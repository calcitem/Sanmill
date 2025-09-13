#!/usr/bin/env python3
"""
Fast orphaned chunk file cleanup tool

Designed to quickly clean up orphaned chunk files for completed sectors.
Does not perform detailed validation, only deletes chunk files corresponding to completed sectors.
"""

import argparse
from pathlib import Path
import time
import concurrent.futures
from typing import List, Set

def find_completed_sectors(output_dir: Path) -> Set[str]:
    """Find completed sectors (those with a corresponding .npz file)."""
    npz_files = list(output_dir.glob("*.npz"))
    completed = set()

    for npz_file in npz_files:
        # Exclude chunk files and temporary files
        if '_chunk_' not in npz_file.name and '.tmp' not in npz_file.name:
            completed.add(npz_file.stem)

    return completed

def find_orphaned_chunks(output_dir: Path, completed_sectors: Set[str]) -> List[Path]:
    """Find orphaned chunk files."""
    chunk_files = list(output_dir.glob("*_chunk_*.npz"))
    orphaned_chunks = []

    for chunk_file in chunk_files:
        try:
            # Extract sector name
            sector_name = '_'.join(chunk_file.stem.split('_')[:-2])
            if sector_name in completed_sectors:
                orphaned_chunks.append(chunk_file)
        except (ValueError, IndexError):
            continue

    return orphaned_chunks

def delete_file_batch(file_paths: List[Path]) -> tuple[int, int, List[str]]:
    """Delete a batch of files."""
    deleted_count = 0
    deleted_size = 0
    errors = []

    for file_path in file_paths:
        try:
            file_size = file_path.stat().st_size
            file_path.unlink()
            deleted_count += 1
            deleted_size += file_size
        except Exception as e:
            errors.append(f"{file_path.name}: {e}")

    return deleted_count, deleted_size, errors

def cleanup_orphaned_chunks(output_dir: str, dry_run: bool = True, max_workers: int = 8):
    """Quickly clean up orphaned chunk files."""
    output_path = Path(output_dir)
    if not output_path.exists():
        print(f"❌ Output directory does not exist: {output_dir}")
        return

    print(f"🔍 Fast scanning for orphaned chunk files: {output_path}")
    start_time = time.time()

    # Find completed sectors
    print("📋 Scanning for completed sectors...")
    completed_sectors = find_completed_sectors(output_path)
    print(f"✅ Found {len(completed_sectors)} completed sectors")

    if not completed_sectors:
        print("💡 No completed sectors found, no orphaned chunks to clean up")
        return

    # Find orphaned chunk files
    print("🔍 Scanning for orphaned chunk files...")
    orphaned_chunks = find_orphaned_chunks(output_path, completed_sectors)

    scan_time = time.time() - start_time

    if not orphaned_chunks:
        print(f"✅ No orphaned chunk files found (scan time: {scan_time:.1f}s)")
        return

    total_size_mb = sum(f.stat().st_size for f in orphaned_chunks) / (1024 * 1024)
    print(f"🗑️  Found {len(orphaned_chunks)} orphaned chunk files (total size: {total_size_mb:.1f} MB)")
    print(f"⏱️  Scan time: {scan_time:.1f}s")

    if dry_run:
        print(f"\n🔍 Dry Run Mode - Orphaned chunk files to be deleted:")

        # Group and display by sector
        sector_chunks = {}
        for chunk in orphaned_chunks:
            sector_name = '_'.join(chunk.stem.split('_')[:-2])
            if sector_name not in sector_chunks:
                sector_chunks[sector_name] = []
            sector_chunks[sector_name].append(chunk)

        shown_sectors = 0
        for sector_name, chunks in sorted(sector_chunks.items()):
            if shown_sectors < 10:  # Only show the first 10 sectors
                sector_size_mb = sum(c.stat().st_size for c in chunks) / (1024 * 1024)
                print(f"  {sector_name}: {len(chunks)} chunks ({sector_size_mb:.1f} MB)")
                shown_sectors += 1
            else:
                remaining_sectors = len(sector_chunks) - shown_sectors
                if remaining_sectors > 0:
                    print(f"  ... and {remaining_sectors} more sectors with orphaned chunks")
                break

        print(f"\n💾 Total: {len(orphaned_chunks)} files, {total_size_mb:.1f} MB")
        print("🚀 Use the --execute flag to perform the deletion")
        return

    # Execute deletion
    response = input(f"\nAre you sure you want to delete {len(orphaned_chunks)} orphaned chunk files? (y/N): ")
    if response.lower() != 'y':
        print("Operation cancelled")
        return

    print(f"\n🚀 Starting parallel deletion of {len(orphaned_chunks)} files...")
    delete_start_time = time.time()

    # Parallel deletion in batches
    batch_size = max(1, len(orphaned_chunks) // max_workers)
    file_batches = [orphaned_chunks[i:i + batch_size]
                    for i in range(0, len(orphaned_chunks), batch_size)]

    total_deleted = 0
    total_size_deleted = 0
    all_errors = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_batch = {
            executor.submit(delete_file_batch, batch): i
            for i, batch in enumerate(file_batches)
        }

        completed_batches = 0
        for future in concurrent.futures.as_completed(future_to_batch):
            try:
                deleted_count, deleted_size, errors = future.result()
                total_deleted += deleted_count
                total_size_deleted += deleted_size
                all_errors.extend(errors)

                completed_batches += 1
                progress = completed_batches / len(file_batches) * 100
                print(f"  Progress: {completed_batches}/{len(file_batches)} batches ({progress:.1f}%)")

            except Exception as e:
                print(f"❌ Batch deletion failed: {e}")

    delete_time = time.time() - delete_start_time
    total_time = time.time() - start_time

    print(f"\n✅ Fast cleanup complete:")
    print(f"  Files deleted: {total_deleted}/{len(orphaned_chunks)}")
    print(f"  Space freed: {total_size_deleted / (1024 * 1024):.1f} MB")
    print(f"  Deletion speed: {total_deleted / delete_time:.0f} files/s")
    print(f"  Deletion time: {delete_time:.1f}s")
    print(f"  Total time: {total_time:.1f}s")

    if all_errors:
        print(f"\n⚠️  Deletion failed for {len(all_errors)} files")
        if len(all_errors) <= 5:
            for error in all_errors:
                print(f"    {error}")
        else:
            for error in all_errors[:3]:
                print(f"    {error}")
            print(f"    ... and {len(all_errors) - 3} more errors")

def main():
    parser = argparse.ArgumentParser(description="Fast orphaned chunk file cleanup tool")
    parser.add_argument('--output-dir', required=True, help='Path to the output directory')
    parser.add_argument('--execute', action='store_true', help='Perform the actual deletion (default is dry run mode)')
    parser.add_argument('--threads', type=int, default=8, help='Number of parallel deletion threads (default 8)')

    args = parser.parse_args()

    cleanup_orphaned_chunks(
        output_dir=args.output_dir,
        dry_run=not args.execute,
        max_workers=args.threads
    )

if __name__ == '__main__':
    main()
