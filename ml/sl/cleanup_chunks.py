#!/usr/bin/env python3
"""
Chunk File Cleanup Tool (High-Performance Version)

Cleans up corrupted, incomplete, or orphaned chunk files to prepare for reprocessing.
Uses multi-threading for parallel processing to improve speed.
"""

import os
import sys
import numpy as np
import argparse
from pathlib import Path
from typing import List, Dict, Set, Tuple, Optional
import logging
import concurrent.futures
import threading
from collections import defaultdict
import time

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s:%(name)s:%(message)s')
logger = logging.getLogger(__name__)

# Global lock for thread-safe logging output
print_lock = threading.Lock()


def find_chunk_files(output_dir: Path) -> Dict[str, List[Path]]:
    """Find all chunk files and group them by sector."""
    chunk_files = list(output_dir.glob("*_chunk_*.npz"))

    # Group by sector
    sector_chunks = {}
    for chunk_file in chunk_files:
        # Extract sector name (e.g., std_5_5_2_2_chunk_1.npz -> std_5_5_2_2)
        try:
            sector_name = '_'.join(chunk_file.stem.split('_')[:-2])  # Remove the _chunk_X part
            if sector_name not in sector_chunks:
                sector_chunks[sector_name] = []
            sector_chunks[sector_name].append(chunk_file)
        except (ValueError, IndexError):
            logger.warning(f"Could not parse chunk filename: {chunk_file}")
            continue

    # Sort the chunks for each sector
    for sector_name in sector_chunks:
        def extract_chunk_number(path):
            try:
                return int(path.stem.split('_chunk_')[-1])
            except (ValueError, IndexError):
                return 0
        sector_chunks[sector_name].sort(key=extract_chunk_number)

    return sector_chunks


def quick_validate_chunk_file(chunk_file: Path) -> Tuple[bool, Optional[str], int]:
    """Quickly validate if a chunk file is valid.

    Returns:
        (is_valid, error_reason, position_count)
    """
    try:
        # First, check the file size; files that are too small are definitely problematic
        file_size = chunk_file.stat().st_size
        if file_size < 1024:  # Files smaller than 1KB are definitely problematic
            return False, "File too small", 0

        # Use mmap_mode for fast loading (without loading into memory)
        data = np.load(chunk_file, mmap_mode='r')
        required_keys = ['states', 'policies', 'values']

        # Check for required keys
        missing_keys = [key for key in required_keys if key not in data]
        if missing_keys:
            return False, f"Missing keys: {missing_keys}", 0

        # Quickly check shapes (without loading data)
        states_shape = data['states'].shape
        policies_shape = data['policies'].shape
        values_shape = data['values'].shape

        if len(states_shape) == 0 or states_shape[0] == 0:
            return False, "Empty data", 0

        # Check for consistency in the first dimension (number of positions)
        if states_shape[0] != policies_shape[0] or states_shape[0] != values_shape[0]:
            return False, "Inconsistent shapes", 0

        # Check data types (this is fast)
        if (data['states'].dtype != np.float32 or
            data['policies'].dtype != np.float32 or
            data['values'].dtype != np.float32):
            return False, "Incorrect data type", 0

        position_count = states_shape[0]
        return True, None, position_count

    except Exception as e:
        return False, str(e), 0


def validate_chunk_batch(chunk_files: List[Path]) -> List[Tuple[Path, bool, Optional[str], int]]:
    """Validate a batch of chunk files."""
    results = []
    for chunk_file in chunk_files:
        is_valid, error_reason, position_count = quick_validate_chunk_file(chunk_file)
        results.append((chunk_file, is_valid, error_reason, position_count))
    return results


def find_completed_sectors(output_dir: Path) -> Set[str]:
    """Find sectors that have completed processing (have a corresponding .npz file)."""
    npz_files = list(output_dir.glob("*.npz"))
    completed = set()

    for npz_file in npz_files:
        # Exclude chunk files and temporary files
        if '_chunk_' not in npz_file.name and '.tmp' not in npz_file.name:
            completed.add(npz_file.stem)

    return completed


def cleanup_chunks(output_dir: str, dry_run: bool = True, force: bool = False, max_workers: int = 8):
    """Clean up chunk files (High-Performance Version)."""
    output_path = Path(output_dir)
    if not output_path.exists():
        logger.error(f"Output directory does not exist: {output_dir}")
        return

    print(f"🔍 Scanning for chunk files: {output_path}")
    start_time = time.time()

    # Find all chunk files
    sector_chunks = find_chunk_files(output_path)
    if not sector_chunks:
        print("No chunk files found.")
        return

    total_chunk_count = sum(len(chunks) for chunks in sector_chunks.values())
    print(f"📊 Found {len(sector_chunks)} sectors with a total of {total_chunk_count} chunk files")

    # Find completed sectors
    completed_sectors = find_completed_sectors(output_path)
    print(f"✅ Found {len(completed_sectors)} completed sectors")

    # Statistics
    total_chunks = 0
    invalid_chunks = 0
    orphaned_chunks = 0
    files_to_delete = []

    # Separate orphaned chunks (from completed sectors) and chunks that need validation
    orphaned_sectors = []
    sectors_to_validate = []

    for sector_name, chunks in sector_chunks.items():
        total_chunks += len(chunks)

        if sector_name in completed_sectors:
            orphaned_sectors.append((sector_name, chunks))
            orphaned_chunks += len(chunks)
            files_to_delete.extend(chunks)
        else:
            sectors_to_validate.append((sector_name, chunks))

    # Quickly process orphaned chunks
    if orphaned_sectors:
        print(f"🗑️  Found {orphaned_chunks} orphaned chunk files from {len(orphaned_sectors)} completed sectors")

    # Concurrently validate chunks that need checking
    if sectors_to_validate:
        print(f"🔍 Starting concurrent validation for chunk files from {len(sectors_to_validate)} sectors...")
        print(f"⚙️  Using {max_workers} threads for parallel processing")

        # Prepare all chunk files that need validation
        all_chunks_to_validate = []
        sector_chunk_map = {}  # Map from chunk file to its sector

        for sector_name, chunks in sectors_to_validate:
            for chunk in chunks:
                all_chunks_to_validate.append(chunk)
                sector_chunk_map[chunk] = sector_name

        # Process in batches to show progress
        batch_size = max(1, len(all_chunks_to_validate) // max_workers)
        chunk_batches = [all_chunks_to_validate[i:i + batch_size]
                         for i in range(0, len(all_chunks_to_validate), batch_size)]

        print(f"📦 Divided into {len(chunk_batches)} batches for validation...")

        # Concurrent validation
        validation_results = {}
        completed_batches = 0

        with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit all batches
            future_to_batch = {
                executor.submit(validate_chunk_batch, batch): i
                for i, batch in enumerate(chunk_batches)
            }

            # Collect results and display progress
            for future in concurrent.futures.as_completed(future_to_batch):
                batch_idx = future_to_batch[future]
                try:
                    batch_results = future.result()
                    for chunk_file, is_valid, error_reason, position_count in batch_results:
                        validation_results[chunk_file] = (is_valid, error_reason, position_count)

                    completed_batches += 1
                    progress = completed_batches / len(chunk_batches) * 100

                    with print_lock:
                        print(f"⏳ Validation progress: {completed_batches}/{len(chunk_batches)} batches ({progress:.1f}%)")

                except Exception as e:
                    print(f"❌ Batch {batch_idx} validation failed: {e}")

        # Analyze validation results
        sector_results = defaultdict(lambda: {'valid': [], 'invalid': [], 'total_positions': 0})

        for chunk_file, (is_valid, error_reason, position_count) in validation_results.items():
            sector_name = sector_chunk_map[chunk_file]

            if is_valid:
                sector_results[sector_name]['valid'].append(chunk_file)
                sector_results[sector_name]['total_positions'] += position_count
            else:
                sector_results[sector_name]['invalid'].append((chunk_file, error_reason))
                invalid_chunks += 1
                files_to_delete.append(chunk_file)

        # Display validation result summary
        print(f"\n📋 Validation Result Summary:")
        for sector_name in sorted(sector_results.keys()):
            result = sector_results[sector_name]
            valid_count = len(result['valid'])
            invalid_count = len(result['invalid'])
            total_positions = result['total_positions']

            if invalid_count > 0:
                print(f"  {sector_name}: ✅{valid_count} ❌{invalid_count} ({total_positions:,} positions)")
            elif valid_count > 50:  # Only show sectors with a large number of chunks
                print(f"  {sector_name}: ✅{valid_count} ({total_positions:,} positions)")

    validation_time = time.time() - start_time

    # Display statistics
    print(f"\n📊 Cleanup Statistics (Validation time: {validation_time:.1f}s):")
    print(f"  Total chunk files: {total_chunks}")
    print(f"  Invalid chunk files: {invalid_chunks}")
    print(f"  Orphaned chunk files: {orphaned_chunks}")
    print(f"  To be deleted: {len(files_to_delete)}")

    if not files_to_delete:
        print("✅ No files to clean up.")
        return

    # Calculate total size
    total_size_mb = sum(f.stat().st_size for f in files_to_delete) / (1024 * 1024)

    # Display files to be deleted (only show the first 20 and last 10, omitting the middle)
    if dry_run:
        print(f"\n🔍 Dry Run Mode - {len(files_to_delete)} files will be deleted (Total size: {total_size_mb:.1f} MB):")

        if len(files_to_delete) <= 30:
            # Not many files, show all
            for file_path in files_to_delete:
                file_size_mb = file_path.stat().st_size / (1024 * 1024)
                print(f"  - {file_path.name} ({file_size_mb:.1f} MB)")
        else:
            # Many files, show only the first 20 and last 10
            print("  First 20 files:")
            for file_path in files_to_delete[:20]:
                file_size_mb = file_path.stat().st_size / (1024 * 1024)
                print(f"    - {file_path.name} ({file_size_mb:.1f} MB)")

            print(f"  ... (omitting {len(files_to_delete) - 30} files) ...")

            print("  Last 10 files:")
            for file_path in files_to_delete[-10:]:
                file_size_mb = file_path.stat().st_size / (1024 * 1024)
                print(f"    - {file_path.name} ({file_size_mb:.1f} MB)")

        print(f"\n💾 Total size: {total_size_mb:.1f} MB")
        print("🚀 Use the --execute flag to perform the actual deletion (speed will be significantly improved)")
        return

    # Perform deletion
    if not force:
        response = input(f"\nAre you sure you want to delete {len(files_to_delete)} files? (y/N): ")
        if response.lower() != 'y':
            print("Operation cancelled.")
            return

    print(f"\n🗑️  Starting parallel deletion of {len(files_to_delete)} files...")
    delete_start_time = time.time()
    deleted_count = 0
    deleted_size = 0

    # Delete files in parallel to improve speed
    def delete_file(file_path):
        try:
            file_size = file_path.stat().st_size
            file_path.unlink()
            return file_size, None
        except Exception as e:
            return 0, str(e)

    with concurrent.futures.ThreadPoolExecutor(max_workers=min(16, len(files_to_delete))) as executor:
        future_to_file = {executor.submit(delete_file, f): f for f in files_to_delete}

        for future in concurrent.futures.as_completed(future_to_file):
            file_path = future_to_file[future]
            try:
                file_size, error = future.result()
                if error:
                    print(f"❌ Failed to delete {file_path.name}: {error}")
                else:
                    deleted_count += 1
                    deleted_size += file_size

                    # Show progress every 100 files
                    if deleted_count % 100 == 0:
                        progress = deleted_count / len(files_to_delete) * 100
                        print(f"  Deleted: {deleted_count}/{len(files_to_delete)} ({progress:.1f}%)")

            except Exception as e:
                print(f"❌ Error deleting {file_path.name}: {e}")

    delete_time = time.time() - delete_start_time

    print(f"\n✅ Cleanup complete:")
    print(f"  Files deleted: {deleted_count}/{len(files_to_delete)}")
    print(f"  Space freed: {deleted_size / (1024 * 1024):.1f} MB")
    print(f"  Deletion time: {delete_time:.1f}s")
    print(f"  Total time: {(time.time() - start_time):.1f}s")


def main():
    parser = argparse.ArgumentParser(description="Chunk File Cleanup Tool (High-Performance Version)")
    parser.add_argument('--output-dir', required=True, help='Path to the output directory')
    parser.add_argument('--execute', action='store_true', help='Perform the actual deletion (default is dry run mode)')
    parser.add_argument('--force', action='store_true', help='Force delete without asking for confirmation')
    parser.add_argument('--threads', type=int, default=8, help='Number of threads for parallel validation (default 8)')

    args = parser.parse_args()

    cleanup_chunks(
        output_dir=args.output_dir,
        dry_run=not args.execute,
        force=args.force,
        max_workers=args.threads
    )


if __name__ == '__main__':
    main()
