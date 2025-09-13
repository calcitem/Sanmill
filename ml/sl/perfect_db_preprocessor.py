#!/usr/bin/env python3
"""
Perfect Database Preprocessor

Preprocesses .sec2 files into a format directly usable by neural networks,
significantly improving training speed.
"""

import os
import sys
import numpy as np
import torch
import logging
import hashlib
import json
import time
import psutil
import gc
import threading
from pathlib import Path
from typing import List, Dict, Optional, Tuple, Any
from dataclasses import dataclass, asdict
import multiprocessing as mp
from concurrent.futures import ProcessPoolExecutor, as_completed
import argparse

# Add paths for imports (ensure ml root is present)
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)  # ml directory
if ml_dir not in sys.path:
    sys.path.insert(0, ml_dir)
if os.path.join(ml_dir, 'perfect') not in sys.path:
    sys.path.insert(0, os.path.join(ml_dir, 'perfect'))
if os.path.join(ml_dir, 'game') not in sys.path:
    sys.path.insert(0, os.path.join(ml_dir, 'game'))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

# Import required modules
try:
    from perfect_db_trainer import PerfectDBDirectTrainer, TrainingPosition
    from neural_network import MillBoardEncoder
    try:
        from progress_display import CompactProgressDisplay
    except ImportError:
        # Simple fallback progress display
        class CompactProgressDisplay:
            def __init__(self):
                self.start_time = time.time()
                self.completed = 0
                self.total = 0

            def start(self):
                pass

            def start_file(self, filename):
                print(f"📁 Processing: {filename}")

            def complete_file(self, filename, success=True):
                self.completed += 1
                status = "✅" if success else "❌"
                elapsed = time.time() - self.start_time
                print(f"{status} {filename} | Progress: {self.completed}/{self.total} | Elapsed: {elapsed:.1f}s")

            def stop(self):
                print(f"🎯 Completed: {self.completed}/{self.total}")

except ImportError as e:
    print(f"❌ Import error: {e}")
    print("Please make sure you're running from the correct directory:")
    print("  cd D:\\Repo\\Sanmill\\ml\\sl")
    print("  python perfect_db_preprocessor.py ...")
    sys.exit(1)

# Setup logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s:%(name)s:%(message)s')
logger = logging.getLogger(__name__)


@dataclass
class SectorMetadata:
    """Metadata for sector processing."""
    filename: str
    output_file: str
    num_positions: int
    file_size_mb: float
    checksum: str
    output_files: Optional[List[str]] = None
    processed_time: float = 0.0


class MemoryMonitor:
    """Memory monitoring and protection class."""

    def __init__(self, memory_threshold_gb: float = 16.0):
        """
        Initializes the memory monitor.

        Args:
            memory_threshold_gb: Memory threshold in GB. Protection mechanisms are triggered below this value.
        """
        self.memory_threshold_gb = memory_threshold_gb
        self.memory_threshold_bytes = memory_threshold_gb * 1024 * 1024 * 1024
        # Simulated available memory for testing (overwrites the real value only during tests)
        self._test_available_memory = None

    def get_available_memory_gb(self) -> float:
        """Gets the current available memory (GB)."""
        try:
            memory_info = psutil.virtual_memory()
            return memory_info.available / (1024 * 1024 * 1024)
        except Exception as e:
            logger.warning(f"Failed to get memory info: {e}")
            return 16.0  # Default fallback

    def get_memory_usage_info(self) -> Dict[str, float]:
        """Gets detailed memory information."""
        try:
            memory_info = psutil.virtual_memory()
            return {
                'total_gb': memory_info.total / (1024 * 1024 * 1024),
                'available_gb': memory_info.available / (1024 * 1024 * 1024),
                'used_gb': memory_info.used / (1024 * 1024 * 1024),
                'percent': memory_info.percent,
                'free_gb': memory_info.free / (1024 * 1024 * 1024)
            }
        except Exception as e:
            logger.warning(f"Failed to get detailed memory info: {e}")
            return {'available_gb': 16.0, 'total_gb': 32.0, 'percent': 50.0}

    def is_memory_low(self) -> bool:
        """Checks if memory is below the threshold."""
        available = self.get_available_memory_gb()
        return available < self.memory_threshold_gb

    def get_safe_worker_count(self, default_workers: int) -> int:
        """Calculates a safe number of worker processes based on available memory."""
        available_gb = self.get_available_memory_gb()

        if available_gb < 4:
            # Critically low memory, use a single process
            return 1
        elif available_gb < 8:
            # Low memory, limit the number of processes
            return min(default_workers, 2)
        elif available_gb < self.memory_threshold_gb:
            # Below threshold, moderately limit
            return min(default_workers, max(2, default_workers // 2))
        else:
            # Sufficient memory, use the default number of processes
            return default_workers

    def get_safe_batch_size(self, default_batch_size: int) -> int:
        """Adjusts the batch size based on available memory."""
        available_gb = self.get_available_memory_gb()

        if available_gb < 4:
            return min(default_batch_size, 50)  # Very small batch
        elif available_gb < 8:
            return min(default_batch_size, 200) # Small batch
        elif available_gb < self.memory_threshold_gb:
            return min(default_batch_size, 500) # Medium batch
        else:
            return default_batch_size  # Normal batch

    def get_safe_batch_positions_per_chunk(self) -> int:
        """Adjusts the number of positions per chunk based on available memory (ensures all data is processed)."""
        available_gb = self.get_available_memory_gb()

        if available_gb < 1:
            # Extremely low memory, extra small batch
            return 50
        elif available_gb < 2:
            # Critically low memory, very small batch
            return 200
        elif available_gb < 4:
            # Low memory, small batch
            return 1000
        elif available_gb < 8:
            # Moderately low memory, small-medium batch
            return 5000
        elif available_gb < self.memory_threshold_gb:
            # Below threshold, medium batch
            return 15000
        else:
            # Sufficient memory, but stay conservative
            return 25000  # Further reduce default batch size to avoid memory issues

    def get_memory_adjusted_strategy(self) -> Dict[str, Any]:
        """Gets a processing strategy based on the memory situation."""
        available_gb = self.get_available_memory_gb()

        strategy = {
            'processing_mode': 'parallel',  # Default to parallel
            'memory_cleanup_frequency': 15,  # Clean up every 15 files
            'progress_report_frequency': 5,  # Report every 5 files
            'enable_caching': False,  # Disable caching by default to save memory
            'force_gc_after_each': False,
            'max_concurrent_merges': 1,  # Limit concurrent merge operations
            'emergency_memory_threshold': 2.0,  # Emergency memory threshold (GB)
        }

        if available_gb < 2:
            # Extremely low memory
            strategy.update({
                'processing_mode': 'sequential',
                'memory_cleanup_frequency': 1,  # Clean up after each file
                'progress_report_frequency': 1,
                'enable_caching': False,
                'force_gc_after_each': True,
                'max_concurrent_merges': 1,
                'emergency_memory_threshold': 1.0,
            })
        elif available_gb < 4:
            # Critically low memory
            strategy.update({
                'processing_mode': 'sequential',
                'memory_cleanup_frequency': 2,
                'progress_report_frequency': 2,
                'enable_caching': False,
                'force_gc_after_each': True,
                'max_concurrent_merges': 1,
                'emergency_memory_threshold': 1.5,
            })
        elif available_gb < 8:
            # Low memory
            strategy.update({
                'processing_mode': 'limited_parallel',
                'memory_cleanup_frequency': 3,
                'progress_report_frequency': 3,
                'enable_caching': False,
                'force_gc_after_each': True,
                'max_concurrent_merges': 1,
            })
        elif available_gb < 16:
            # Moderately low memory
            strategy.update({
                'memory_cleanup_frequency': 5,
                'progress_report_frequency': 3,
                'force_gc_after_each': False,
                'max_concurrent_merges': 1,
            })
        elif available_gb < self.memory_threshold_gb:
            # Below threshold but acceptable
            strategy.update({
                'memory_cleanup_frequency': 10,
                'progress_report_frequency': 5,
                'max_concurrent_merges': 2,
            })
        else:
            # Sufficient memory
            strategy.update({
                'memory_cleanup_frequency': 20,
                'progress_report_frequency': 10,
                'max_concurrent_merges': 2,
            })

        return strategy

    def gentle_memory_cleanup(self):
        """Gentle memory cleanup (current process only)."""
        try:
            # Only clean up Python objects in the current process
            gc.collect()

            # Clear PyTorch GPU cache (if available)
            if torch.cuda.is_available():
                torch.cuda.empty_cache()

        except Exception as e:
            logger.debug(f"Memory cleanup failed: {e}")

    def wait_for_memory_availability(self, timeout_seconds: float = 60.0) -> bool:
        """Waits for memory to become available, returns whether successful."""
        start_time = time.time()
        check_interval = 5.0  # Check every 5 seconds

        while self.is_memory_low():
            elapsed = time.time() - start_time
            if elapsed > timeout_seconds:
                logger.warning(f"Timeout waiting for memory release ({timeout_seconds}s)")
                return False

            available_gb = self.get_available_memory_gb()
            logger.info(f"⏳ Waiting for memory release... Currently available: {available_gb:.1f}GB (waited for {elapsed:.0f}s)")

            # Wait for other processes to finish naturally
            time.sleep(check_interval)

        return True

    def check_and_warn(self, verbose: bool = True) -> bool:
        """Checks memory status and issues a warning, returns whether it's safe to continue."""
        memory_info = self.get_memory_usage_info()
        available_gb = memory_info['available_gb']

        if available_gb < 2:
            logger.error(f"🚨 Critically low memory! Available memory: {available_gb:.1f}GB < 2GB")
            logger.error("❌ Processing stopped, please free up memory and try again")
            return False
        elif available_gb < 4:
            if verbose:
                logger.warning(f"⚠️  Low memory! Available memory: {available_gb:.1f}GB < 4GB")
                logger.warning("🔧 Processing parameters will be adjusted automatically to reduce memory usage")
            return True
        elif available_gb < self.memory_threshold_gb:
            if verbose:
                logger.info(f"ℹ️  Moderately low memory: Available {available_gb:.1f}GB < {self.memory_threshold_gb}GB (threshold)")
            return True
        else:
            if verbose:
                logger.info(f"✅ Sufficient memory: Available {available_gb:.1f}GB")
            return True


class PerfectDBPreprocessor:
    """Perfect Database Preprocessor."""

    def __init__(self, perfect_db_path: str, output_dir: str, memory_threshold_gb: float = 16.0):
        """
        Initializes the preprocessor.

        Args:
            perfect_db_path: Path to the Perfect DB directory
            output_dir: Path to the output directory
            memory_threshold_gb: Memory threshold in GB
        """
        self.perfect_db_path = Path(perfect_db_path)
        self.output_dir = Path(output_dir)

        # Ensure directories exist
        if not self.perfect_db_path.exists():
            raise FileNotFoundError(f"Perfect DB path not found: {self.perfect_db_path}")

        self.output_dir.mkdir(parents=True, exist_ok=True)

        # Initialize memory monitor
        self.memory_monitor = MemoryMonitor(memory_threshold_gb)

        # Initialize neural network encoder
        self.encoder = MillBoardEncoder()

        # Metadata
        self.metadata_file = self.output_dir / "metadata.json"
        self.processed_sectors: Dict[str, SectorMetadata] = {}
        self._load_metadata()

        # Memory check configuration
        self.memory_check_interval = 30.0  # Memory check interval (seconds) - less frequent checks for better efficiency

        logger.info(f"PerfectDBPreprocessor initialized")
        logger.info(f"  Input directory: {self.perfect_db_path}")
        logger.info(f"  Output directory: {self.output_dir}")
        logger.info(f"  Processed sectors: {len(self.processed_sectors)}")
        logger.info(f"  Memory threshold: {memory_threshold_gb}GB")

    def _load_metadata(self):
        """Load metadata from file if exists."""
        if self.metadata_file.exists():
            try:
                # Check if file is empty
                if self.metadata_file.stat().st_size == 0:
                    logger.info("Metadata file is empty, starting fresh")
                    self.processed_sectors = {}
                    return

                with open(self.metadata_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if data:  # Check if data is not empty
                        for filename, meta_dict in data.items():
                            self.processed_sectors[filename] = SectorMetadata(**meta_dict)
                        logger.info(f"Loaded metadata for {len(self.processed_sectors)} sectors")
                    else:
                        logger.info("Metadata file is empty, starting fresh")
                        self.processed_sectors = {}
            except Exception as e:
                logger.warning(f"Failed to load metadata: {e}, starting fresh")
                self.processed_sectors = {}
                # Remove corrupted metadata file
                try:
                    self.metadata_file.unlink()
                    logger.info("Removed corrupted metadata file")
                except:
                    pass

    def _save_metadata(self):
        """Save metadata to file."""
        try:
            data = {filename: asdict(meta) for filename, meta in self.processed_sectors.items()}
            with open(self.metadata_file, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.warning(f"Failed to save metadata: {e}")

    def _cleanup_corrupted_chunks(self, sector_stem: str) -> int:
        """Cleans up all corrupted chunk files for a given sector, returning the count of cleaned files."""
        chunk_pattern = f"{sector_stem}_chunk_*.npz"
        chunk_files = list(self.output_dir.glob(chunk_pattern))

        cleaned_count = 0
        for chunk_file in chunk_files:
            if self._validate_chunk_file(chunk_file) is None:
                try:
                    chunk_file.unlink()
                    cleaned_count += 1
                    logger.info(f"Cleaned up corrupted file: {chunk_file.name}")
                except Exception as e:
                    logger.warning(f"Failed to clean up file {chunk_file}: {e}")

        return cleaned_count

    def preprocess_sector(self, sector_file: Path, max_positions: Optional[int] = None,
                          force_batch_size: Optional[int] = None) -> Optional[SectorMetadata]:
        """Preprocess a single sector file with resume capability."""
        try:
            # Check if a complete output file already exists
            output_file = self.output_dir / f"{sector_file.stem}.npz"
            if output_file.exists() and sector_file.name in self.processed_sectors:
                logger.info(f"Skipping already processed: {sector_file.name}")
                return self.processed_sectors[sector_file.name]

            # Check for incomplete chunk files (for resuming)
            existing_chunks = self._find_existing_chunks(sector_file.stem)
            if existing_chunks:
                logger.info(f"Found {len(existing_chunks)} existing chunk files, attempting to resume processing...")
                # Pre-cleanup of corrupted chunk files
                cleaned = self._cleanup_corrupted_chunks(sector_file.stem)
                if cleaned > 0:
                    logger.info(f"Cleaned up {cleaned} corrupted chunk files")
                    # Re-scan for valid chunk files
                    existing_chunks = self._find_existing_chunks(sector_file.stem)

                if existing_chunks:
                    return self._resume_sector_processing(sector_file, existing_chunks, max_positions)
                else:
                    logger.info(f"All chunk files were corrupted, restarting processing for {sector_file.name}")

            logger.info(f"Processing sector: {sector_file.name}")
            start_time = time.time()

            # Extract positions using direct Perfect DB access (no neural network needed)
            from perfect_db_reader import PerfectDB
            from game.Game import Game

            # Initialize game and Perfect DB
            game = Game()
            perfect_db = PerfectDB()
            perfect_db.init(str(self.perfect_db_path))

            # Determine the batch processing size
            batch_size = force_batch_size or self.memory_monitor.get_safe_batch_positions_per_chunk()

            # Use a chunk-based saving mechanism to avoid accumulating large amounts of data in memory
            total_positions_processed = 0
            output_file = self.output_dir / f"{sector_file.stem}.npz"
            temp_files = []  # List of temporary files

            # Extract positions from the sector in batches
            positions_generator = self._extract_positions_from_sector_batched(
                sector_file, perfect_db, game, batch_size
            )

            logger.info(f"Starting batch processing for {sector_file.name}, batch size: {batch_size}")
            logger.info(f"Using chunk-based saving mechanism to prevent out-of-memory errors")

            # Adjust chunk size based on memory status
            available_memory = self.memory_monitor.get_available_memory_gb()
            if available_memory < 4:
                chunk_size = 1000  # Use small chunks when memory is low
            elif available_memory < 8:
                chunk_size = 5000  # Use medium chunks for moderate memory
            else:
                chunk_size = 10000  # Use large chunks when memory is sufficient

            logger.info(f"Setting chunk size based on available memory ({available_memory:.1f}GB): {chunk_size}")

            current_chunk_states = []
            current_chunk_policies = []
            current_chunk_values = []
            chunk_number = 0

            for batch_num, positions_batch in enumerate(positions_generator, 1):
                if not positions_batch:
                    continue

                # If max_positions limit is set, check if it has been reached
                if max_positions and total_positions_processed >= max_positions:
                    logger.info(f"Reached position limit of {max_positions}, stopping processing")
                    break

                # Process the current batch
                batch_states, batch_policies, batch_values = self._process_position_batch(positions_batch)

                # If there is a max_positions limit, the last batch may need to be truncated
                if max_positions:
                    remaining = max_positions - total_positions_processed
                    if remaining < len(batch_states):
                        batch_states = batch_states[:remaining]
                        batch_policies = batch_policies[:remaining]
                        batch_values = batch_values[:remaining]

                # Add to the current chunk
                current_chunk_states.extend(batch_states)
                current_chunk_policies.extend(batch_policies)
                current_chunk_values.extend(batch_values)

                total_positions_processed += len(batch_states)

                # When the chunk reaches its size limit, save it as a temporary file
                if len(current_chunk_states) >= chunk_size:
                    chunk_number += 1
                    temp_file = self.output_dir / f"{sector_file.stem}_chunk_{chunk_number}.npz"

                    # Convert to numpy array and save
                    states_array = np.array(current_chunk_states, dtype=np.float32)
                    policies_array = np.array(current_chunk_policies, dtype=np.float32)
                    values_array = np.array(current_chunk_values, dtype=np.float32)

                    np.savez_compressed(
                        temp_file,
                        states=states_array,
                        policies=policies_array,
                        values=values_array
                    )

                    temp_files.append(temp_file)
                    logger.debug(f"Saving chunk {chunk_number}: {len(current_chunk_states)} positions")

                    # Clear the current chunk and release memory
                    del current_chunk_states, current_chunk_policies, current_chunk_values
                    del states_array, policies_array, values_array
                    current_chunk_states = []
                    current_chunk_policies = []
                    current_chunk_values = []
                    self.memory_monitor.gentle_memory_cleanup()

                # Gentle memory cleanup
                if batch_num % 10 == 0:  # Clean up every 10 batches
                    self.memory_monitor.gentle_memory_cleanup()
                    logger.debug(f"Batch {batch_num}: Processed {total_positions_processed} positions")

            # Process the final chunk (if there is remaining data)
            if current_chunk_states:
                chunk_number += 1
                temp_file = self.output_dir / f"{sector_file.stem}_chunk_{chunk_number}.npz"

                states_array = np.array(current_chunk_states, dtype=np.float32)
                policies_array = np.array(current_chunk_policies, dtype=np.float32)
                values_array = np.array(current_chunk_values, dtype=np.float32)

                np.savez_compressed(
                    temp_file,
                    states=states_array,
                    policies=policies_array,
                    values=values_array
                )

                temp_files.append(temp_file)
                logger.debug(f"Saving final chunk {chunk_number}: {len(current_chunk_states)} positions")

                # Clean up memory
                del current_chunk_states, current_chunk_policies, current_chunk_values
                del states_array, policies_array, values_array
                self.memory_monitor.gentle_memory_cleanup()

            if not temp_files:
                logger.warning(f"No data extracted from {sector_file.name}")
                return None

            # Merge all temporary files into the final file
            logger.info(f"Merging {len(temp_files)} temporary files...")
            merge_outputs = self._merge_temp_files(temp_files, output_file)

            # Clean up temporary files
            for temp_file in temp_files:
                try:
                    temp_file.unlink()  # Delete the temporary file
                except Exception as e:
                    logger.warning(f"Failed to delete temp file {temp_file}: {e}")

            # Final memory cleanup
            self.memory_monitor.gentle_memory_cleanup()

            # Create metadata
            processing_time = time.time() - start_time
            # If there are multiple output files, record the list
            primary_output = str(merge_outputs[0]) if merge_outputs else str(output_file)
            metadata = SectorMetadata(
                filename=sector_file.name,
                output_file=primary_output,
                output_files=[str(p) for p in merge_outputs] if len(merge_outputs) > 1 else None,
                num_positions=total_positions_processed,
                file_size_mb=sector_file.stat().st_size / (1024 * 1024),
                checksum=self._calculate_checksum(sector_file),
                processed_time=processing_time
            )

            self.processed_sectors[sector_file.name] = metadata
            self._save_metadata()

            logger.info(f"Completed {sector_file.name}: {total_positions_processed} positions in {processing_time:.1f}s")
            return metadata

        except Exception as e:
            logger.error(f"Failed to process {sector_file.name}: {e}")
            return None

    def _merge_temp_files(self, temp_files: List[Path], output_file: Path) -> List[Path]:
        """Memory-safe merging of temporary files into a final file.

        Returns:
            A list of final output files. Returns multiple batched output files if the data is too large; otherwise, returns a list with a single file.
        """
        try:
            if not temp_files:
                logger.warning("No temporary files to merge")
                return []

            logger.info(f"Starting merge of {len(temp_files)} temporary files...")

            # Check available memory to decide on a merge strategy
            available_memory_gb = self.memory_monitor.get_available_memory_gb()

            if available_memory_gb < 4.0:
                # Insufficient memory, use streaming merge
                logger.info("Insufficient memory, using streaming merge mode")
                return self._merge_temp_files_streaming(temp_files, output_file)
            elif len(temp_files) > 50:
                # Too many files, merge in batches
                logger.info("Too many files, using batched merge mode")
                return self._merge_temp_files_batched(temp_files, output_file)
            else:
                # Normal merge, but with limited memory usage
                logger.info("Using memory-limited merge mode")
                self._merge_temp_files_memory_limited(temp_files, output_file)
                return [output_file]

        except Exception as e:
            logger.error(f"Failed to merge temporary files: {e}")
            raise

    def _merge_temp_files_streaming(self, temp_files: List[Path], output_file: Path):
        """Streaming merge, processing one file at a time for minimal memory usage.

        To avoid OOM by repeated resizing in very low memory environments, this reuses the batched merge strategy
        and directly produces multiple final files if necessary.
        """
        return self._merge_temp_files_batched(temp_files, output_file)

    def _merge_temp_files_batched(self, temp_files: List[Path], output_file: Path):
        """Batched merging for a large number of temporary files."""
        batch_size = 10  # Process 10 files per batch
        intermediate_files = []

        try:
            # Process files in batches
            for batch_start in range(0, len(temp_files), batch_size):
                batch_end = min(batch_start + batch_size, len(temp_files))
                batch_files = temp_files[batch_start:batch_end]

                logger.info(f"Processing batch {batch_start//batch_size + 1}: Files {batch_start+1}-{batch_end}")

                # Create an intermediate file for this batch
                intermediate_file = output_file.with_suffix(f'.batch_{batch_start//batch_size}.tmp.npz')

                # Merge the current batch
                self._merge_temp_files_memory_limited(batch_files, intermediate_file)
                intermediate_files.append(intermediate_file)

                # Clean up memory
                self.memory_monitor.gentle_memory_cleanup()

            # Decision: Skip the final large merge and use the intermediate files as the final output
            try:
                # Estimate total positions and memory usage
                total_positions = 0
                state_dim = None
                for i, inter_file in enumerate(intermediate_files, 1):
                    with np.load(inter_file) as d:
                        s = d['states']
                        total_positions += len(s)
                        if state_dim is None and s.ndim >= 2:
                            state_dim = int(np.prod(s.shape[1:]))
                if state_dim is None:
                    state_dim = 0
                # Estimate resident memory needed (for safety check only)
                estimated_gb = (total_positions * (state_dim + 24 + 1) * 4) / (1024**3)
                avail_gb = self.memory_monitor.get_available_memory_gb()
                logger.info(f"Estimated final merge memory: ~{estimated_gb:.2f}GB, Available: {avail_gb:.1f}GB")
            except Exception as e:
                logger.warning(f"Failed to estimate memory, proceeding conservatively: {e}")
                estimated_gb = float('inf')
                avail_gb = self.memory_monitor.get_available_memory_gb()

            # Condition: If the estimate exceeds a safe proportion of available memory, output multiple files directly
            if estimated_gb > max(8.0, avail_gb * 0.4) or len(intermediate_files) > 40:
                logger.warning("Data size is too large, skipping final merge and keeping batched results as final output")
                final_files: List[Path] = []
                for idx, inter_file in enumerate(intermediate_files):
                    final_path = output_file.with_name(f"{output_file.stem}.batch_{idx}.npz")
                    try:
                        if final_path.exists():
                            final_path.unlink()
                    except Exception:
                        pass
                    inter_file.replace(final_path)
                    final_files.append(final_path)
                # Return a list of multiple files
                return final_files

            # Otherwise, perform the final merge
            logger.info(f"Merging {len(intermediate_files)} intermediate files...")
            self._merge_temp_files_memory_limited(intermediate_files, output_file)
            return [output_file]

        finally:
            # Clean up intermediate files
            for intermediate_file in intermediate_files:
                try:
                    if intermediate_file.exists():
                        intermediate_file.unlink()
                except Exception as e:
                    logger.warning(f"Failed to clean up intermediate file {intermediate_file}: {e}")

    def _merge_temp_files_memory_limited(self, temp_files: List[Path], output_file: Path):
        """Memory-limited merge mode."""
        all_states = []
        all_policies = []
        all_values = []

        for i, temp_file in enumerate(temp_files, 1):
            try:
                logger.debug(f"Loading temporary file {i}/{len(temp_files)}: {temp_file.name}")

                # Check memory status
                available_gb = self.memory_monitor.get_available_memory_gb()
                if available_gb < 2.0:
                    logger.error(f"Critically low memory ({available_gb:.1f}GB), stopping merge")
                    raise MemoryError(f"Out of memory: {available_gb:.1f}GB")

                # Load file data
                try:
                    data = np.load(temp_file, allow_pickle=False)
                    if data is None:
                        logger.error(f"Loading file {temp_file} returned None, it may be corrupted")
                        raise ValueError(f"File {temp_file} is corrupted or incomplete")

                    # Check for required keys
                    required_keys = ['states', 'policies', 'values']
                    missing_keys = [key for key in required_keys if key not in data]
                    if missing_keys:
                        logger.error(f"File {temp_file} is missing required keys: {missing_keys}")
                        raise ValueError(f"File {temp_file} is missing required keys: {missing_keys}")

                    # Check data size to prevent oversized arrays
                    states_shape = data['states'].shape
                    estimated_size_mb = np.prod(states_shape) * 4 / (1024 * 1024)  # Assuming float32

                    if estimated_size_mb > 500:  # Single file exceeds 500MB
                        logger.warning(f"Large data block detected: {estimated_size_mb:.1f}MB, using chunked processing")
                        # Process large data in chunks
                        chunk_size = min(10000, states_shape[0] // 4)  # Split into 4 chunks or 10k positions per chunk
                        for chunk_start in range(0, states_shape[0], chunk_size):
                            chunk_end = min(chunk_start + chunk_size, states_shape[0])
                            all_states.append(data['states'][chunk_start:chunk_end].copy())
                            all_policies.append(data['policies'][chunk_start:chunk_end].copy())
                            all_values.append(data['values'][chunk_start:chunk_end].copy())
                    else:
                        all_states.append(data['states'].copy())
                        all_policies.append(data['policies'].copy())
                        all_values.append(data['values'].copy())

                    # Explicitly close the data file
                    data.close()
                    del data

                except Exception as load_error:
                    logger.error(f"Failed to load file {temp_file}: {load_error}")
                    # Check if file exists and is readable
                    if not temp_file.exists():
                        logger.error(f"File does not exist: {temp_file}")
                    elif temp_file.stat().st_size == 0:
                        logger.error(f"File is empty: {temp_file}")
                    else:
                        logger.error(f"File size: {temp_file.stat().st_size} bytes")
                    raise

                # Periodically clean up memory
                if i % 3 == 0:
                    self.memory_monitor.gentle_memory_cleanup()

            except Exception as e:
                logger.error(f"Error while processing file {temp_file}: {e}")
                raise

        if not all_states:
            raise ValueError("No data to merge")

        # Concatenate arrays
        logger.info(f"Concatenating {len(all_states)} data blocks...")
        try:
            final_states = np.concatenate(all_states, axis=0)
            final_policies = np.concatenate(all_policies, axis=0)
            final_values = np.concatenate(all_values, axis=0)
        except MemoryError as e:
            logger.error(f"Out of memory during concatenation: {e}")
            logger.error("Try reducing the batch size or increasing available memory")
            raise

        # Save results
        logger.info(f"Saving final file: {output_file} ({len(final_states)} positions)")
        np.savez_compressed(
            output_file,
            states=final_states,
            policies=final_policies,
            values=final_values
        )

        # Clean up memory
        del all_states, all_policies, all_values
        del final_states, final_policies, final_values
        self.memory_monitor.gentle_memory_cleanup()

    def _wait_for_memory_availability(self):
        """Wait for memory to become available."""
        # Use the memory monitor's wait method
        if not self.memory_monitor.wait_for_memory_availability(timeout_seconds=120.0):
            logger.error("Timeout waiting for memory release, manual intervention may be required")

    def preprocess_all(self, max_workers: int = 4, max_positions_per_sector: Optional[int] = None, force: bool = False):
        """Memory-aware parallel preprocessing of all sector files."""
        # Initial memory check
        if not self.memory_monitor.check_and_warn():
            logger.error("❌ Insufficient memory, cannot start processing")
            return

        # Find all .sec2 files
        sector_files = list(self.perfect_db_path.glob("*.sec2"))
        if not sector_files:
            logger.error(f"No .sec2 files found in {self.perfect_db_path}")
            return

        logger.info(f"Found {len(sector_files)} sector files")

        # Filter files to process
        if force:
            files_to_process = sector_files
        else:
            files_to_process = [f for f in sector_files if f.name not in self.processed_sectors]

        if not files_to_process:
            logger.info("All files already processed. Use --force to reprocess.")
            return

        # 🔧 Automatically adjust processing parameters based on memory status
        safe_workers = self.memory_monitor.get_safe_worker_count(max_workers)
        batch_chunk_size = self.memory_monitor.get_safe_batch_positions_per_chunk()
        memory_strategy = self.memory_monitor.get_memory_adjusted_strategy()

        # Display information about parameter adjustments
        if safe_workers != max_workers:
            logger.info(f"🔧 Memory protection adjustment: Worker count {max_workers} → {safe_workers}")

        logger.info(f"🔧 Batch processing size: {batch_chunk_size:,} positions/batch")
        logger.info(f"🔧 Processing strategy: {memory_strategy['processing_mode']}")
        logger.info(f"🔧 Memory cleanup frequency: Every {memory_strategy['memory_cleanup_frequency']} files")

        # max_positions_per_sector is used for testing limits, does not affect batch size
        if max_positions_per_sector:
            logger.info(f"🔧 Test mode: Limiting max positions per sector to {max_positions_per_sector:,}")

        logger.info(f"Processing {len(files_to_process)} files with {safe_workers} workers")
        print(f"🚀 Starting preprocessing for {len(files_to_process)} sector files...")

        # Initialize tracking
        completed_count = 0
        failed_count = 0

        try:
            if memory_strategy['processing_mode'] == 'sequential' or safe_workers == 1:
                # Sequential processing mode
                logger.info("🔧 Using sequential processing mode (memory protection)")
                self._preprocess_sequential_memory_aware(
                    files_to_process, max_positions_per_sector, memory_strategy, batch_chunk_size
                )
            else:
                # Parallel processing mode
                self._preprocess_parallel_memory_aware(
                    files_to_process, safe_workers, max_positions_per_sector, memory_strategy
                )

        except KeyboardInterrupt:
            logger.info("⏹️  Processing interrupted by user")
        except Exception as e:
            logger.error(f"An error occurred during processing: {e}")
        finally:
            # Gentle cleanup of current process memory
            self.memory_monitor.gentle_memory_cleanup()

        # Final statistics
        total_processed = len(self.processed_sectors)
        logger.info(f"🎯 Preprocessing complete! Total processed sectors: {total_processed}")
        if failed_count > 0:
            logger.warning(f"⚠️  Number of failed files: {failed_count}")

        # Display final memory status
        final_memory = self.memory_monitor.get_memory_usage_info()
        logger.info(f"📊 Final memory status: {final_memory['available_gb']:.1f}GB available / {final_memory['total_gb']:.1f}GB total")

    def _preprocess_sequential_memory_aware(self, files_to_process: List[Path],
                                              max_positions_per_sector: Optional[int],
                                              memory_strategy: Dict[str, Any],
                                              batch_chunk_size: int):
        """Sequential processing mode, memory-protected version."""
        completed_count = 0
        failed_count = 0

        for i, sector_file in enumerate(files_to_process, 1):
            # Check memory before processing each file
            if not self.memory_monitor.check_and_warn(verbose=False):
                logger.error(f"❌ Insufficient memory, stopping at file {i}/{len(files_to_process)}")
                break

            print(f"📁 [{i}/{len(files_to_process)}] Processing {sector_file.name}...")
            try:
                metadata = self.preprocess_sector(sector_file, max_positions_per_sector, batch_chunk_size)
                if metadata:
                    print(f"✅ [{i}/{len(files_to_process)}] {sector_file.name} - {metadata.num_positions:,} positions")
                    completed_count += 1
                else:
                    print(f"❌ [{i}/{len(files_to_process)}] {sector_file.name} - Failed")
                    failed_count += 1
            except Exception as e:
                logger.error(f"Error processing {sector_file.name}: {e}")
                print(f"❌ [{i}/{len(files_to_process)}] {sector_file.name} - Error: {e}")
                failed_count += 1

            # Perform gentle cleanup according to memory strategy
            if i % memory_strategy['memory_cleanup_frequency'] == 0:
                self.memory_monitor.gentle_memory_cleanup()

            if memory_strategy['force_gc_after_each']:
                self.memory_monitor.gentle_memory_cleanup()

    def _preprocess_parallel_memory_aware(self, files_to_process: List[Path],
                                            max_workers: int,
                                            max_positions_per_sector: Optional[int],
                                            memory_strategy: Dict[str, Any]):
        """Dynamic memory-aware parallel processing."""
        completed_count = 0
        failed_count = 0

        # Create task queue
        tasks = [
            (str(sector_file), str(self.perfect_db_path), str(self.output_dir), max_positions_per_sector)
            for sector_file in files_to_process
        ]

        logger.info(f"📊 Starting dynamic memory-aware parallel processing, max workers: {max_workers}")

        # Dynamic memory-aware processing - control concurrency based on memory status
        with ProcessPoolExecutor(max_workers=max_workers) as executor:
            future_to_file = {}
            task_queue = list(zip(tasks, files_to_process))

            # Determine initial concurrency based on current memory status
            current_safe_workers = self.memory_monitor.get_safe_worker_count(max_workers)
            logger.info(f"🔧 Initial concurrency: {current_safe_workers}")

            # Submit an initial batch of tasks
            initial_batch = min(current_safe_workers, len(task_queue))
            for i in range(initial_batch):
                if task_queue:
                    task, sector_file = task_queue.pop(0)
                    future = executor.submit(_process_one_sector_worker, task)
                    future_to_file[future] = sector_file

            logger.info(f"✅ Submitted {len(future_to_file)} initial tasks")

            # Dynamic processing: Adjust concurrency based on memory status
            last_memory_check = time.time()
            memory_check_interval = 15.0  # Check memory and adjust concurrency every 15 seconds
            last_concurrent_count = len(future_to_file)

            while future_to_file or task_queue:
                if not future_to_file:
                    # If there are no running tasks but some are still pending, it indicates a memory issue, wait for release
                    if task_queue:
                        logger.info("⏳ No running tasks, waiting for memory to be released...")
                        if self.memory_monitor.wait_for_memory_availability(timeout_seconds=30.0):
                            # Memory has been released, restart
                            current_safe_workers = self.memory_monitor.get_safe_worker_count(max_workers)
                            batch_to_submit = min(current_safe_workers, len(task_queue))
                            for i in range(batch_to_submit):
                                if task_queue:
                                    task, sector_file = task_queue.pop(0)
                                    future = executor.submit(_process_one_sector_worker, task)
                                    future_to_file[future] = sector_file
                            logger.info(f"🔄 Memory released, resubmitting {batch_to_submit} tasks")
                        else:
                            logger.error("Timeout waiting for memory release, stopping processing of remaining tasks")
                            break
                    else:
                        break

                # Wait for at least one task to complete
                try:
                    for future in as_completed(future_to_file, timeout=5.0):
                        sector_file = future_to_file.pop(future)

                        try:
                            result = future.result()
                            if result:
                                meta = SectorMetadata(**result)
                                self.processed_sectors[meta.filename] = meta
                                self._save_metadata()
                                completed_count += 1
                                print(f"✅ [{completed_count + failed_count}/{len(files_to_process)}] {sector_file.name} - {meta.num_positions:,} positions")
                            else:
                                failed_count += 1
                                print(f"❌ [{completed_count + failed_count}/{len(files_to_process)}] {sector_file.name} - Failed")
                        except Exception as e:
                            logger.error(f"Error processing {sector_file.name}: {e}")
                            failed_count += 1
                            print(f"❌ [{completed_count + failed_count}/{len(files_to_process)}] {sector_file.name} - Error: {e}")

                        # After a task completes, decide whether to submit a new one based on memory status
                        current_time = time.time()
                        if current_time - last_memory_check > memory_check_interval or len(future_to_file) != last_concurrent_count:
                            available_memory = self.memory_monitor.get_available_memory_gb()
                            current_safe_workers = self.memory_monitor.get_safe_worker_count(max_workers)
                            current_concurrent = len(future_to_file)

                            # Dynamically adjust concurrency
                            if current_concurrent < current_safe_workers and task_queue:
                                # Can increase concurrency
                                tasks_to_add = min(current_safe_workers - current_concurrent, len(task_queue))
                                for i in range(tasks_to_add):
                                    if task_queue:
                                        task, next_sector_file = task_queue.pop(0)
                                        new_future = executor.submit(_process_one_sector_worker, task)
                                        future_to_file[new_future] = next_sector_file

                                if tasks_to_add > 0:
                                    logger.info(f"📈 Sufficient memory, increasing concurrency: {current_concurrent} → {len(future_to_file)} (Available memory: {available_memory:.1f}GB)")

                            elif current_concurrent > current_safe_workers:
                                # Need to reduce concurrency (will naturally decrease by not submitting new tasks)
                                logger.info(f"📉 Insufficient memory, reducing concurrency: {current_concurrent} → waiting for completion (Available memory: {available_memory:.1f}GB)")

                            # Display progress
                            if (completed_count + failed_count) % 5 == 0 or available_memory < 8:
                                logger.info(f"📊 Progress: {completed_count + failed_count}/{len(files_to_process)}, "
                                            f"Running: {len(future_to_file)}, Pending: {len(task_queue)}, "
                                            f"Available Memory: {available_memory:.1f}GB")

                            last_memory_check = current_time
                            last_concurrent_count = len(future_to_file)

                        # If there are no pending futures and there are tasks left, submit one immediately
                        elif not future_to_file and task_queue:
                            available_memory = self.memory_monitor.get_available_memory_gb()
                            if available_memory >= 4:  # Only submit a new task if there is at least 4GB
                                task, next_sector_file = task_queue.pop(0)
                                new_future = executor.submit(_process_one_sector_worker, task)
                                future_to_file[new_future] = next_sector_file

                        break  # Only process one completed task, then re-evaluate

                except:
                    # Timeout or other exception, continue loop
                    continue

                # Perform gentle cleanup according to memory strategy
                if (completed_count + failed_count) % memory_strategy['memory_cleanup_frequency'] == 0:
                    self.memory_monitor.gentle_memory_cleanup()

        logger.info(f"🎯 Parallel processing complete: Success {completed_count}, Failed {failed_count}")

    def _extract_positions_from_sector_batched(self, sector_file: Path, perfect_db, game, batch_size: int):
        """A generator that extracts positions from a sector in batches."""
        try:
            # Parse sector file name to extract parameters
            filename = sector_file.stem  # Remove .sec2 extension
            if filename.startswith('std_'):
                parts = filename.split('_')
                if len(parts) == 5:
                    W, B, WF, BF = int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])
                else:
                    logger.warning(f"Invalid sector filename format: {filename}")
                    return
            else:
                logger.warning(f"Unsupported sector filename: {filename}")
                return

            # Open sector with correct parameters
            sector_handle = perfect_db.open_sector(W, B, WF, BF)
            if sector_handle < 0:
                logger.warning(f"Failed to open sector: {sector_file}")
                return

            current_batch = []

            # Iterate through all positions in the sector
            while True:
                try:
                    result = perfect_db.sector_next(sector_handle)
                    if not result:
                        # End of sector, yield remaining batch if any
                        if current_batch:
                            yield current_batch
                        break

                    white_bits, black_bits, wdl, steps = result

                    # Create a simple position object
                    class SimplePosition:
                        def __init__(self, board, current_player, wdl, steps):
                            self.board = board
                            self.current_player = current_player
                            self.wdl = wdl
                            self.steps = steps
                            self.policy = None  # Will be set to uniform later

                    # Convert bits to board representation
                    board = self._bits_to_board(white_bits, black_bits)

                    # Determine current player (simplified logic)
                    current_player = 1 if (white_bits & black_bits) == 0 else -1

                    pos = SimplePosition(board, current_player, wdl, steps)
                    current_batch.append(pos)

                    # Yield batch when it's full
                    if len(current_batch) >= batch_size:
                        yield current_batch
                        current_batch = []

                except Exception as e:
                    logger.warning(f"Error processing position in {sector_file}: {e}")
                    continue

            # Close sector
            perfect_db.close_sector(sector_handle)

        except Exception as e:
            logger.error(f"Failed to extract positions from {sector_file}: {e}")
            return

    def _process_position_batch(self, positions_batch):
        """Processes a batch of position data and returns the encoded states, policies, and values."""
        states = []
        policies = []
        values = []

        for pos in positions_batch:
            # Encode board state using the compatible board object
            state = self.encoder.encode_board(pos.board, pos.current_player, vars(pos))
            if hasattr(state, 'numpy'):
                states.append(state.numpy())
            elif hasattr(state, 'cpu'):
                states.append(state.cpu().numpy())
            else:
                states.append(state)

            # Create simple policy vector (24 action positions)
            # For now, use uniform distribution over valid moves
            policy = np.zeros(self.encoder.num_valid_positions, dtype=np.float32)
            if hasattr(pos, 'policy') and pos.policy:
                # If policy data exists, use it (this may need adjustment based on policy format)
                if len(pos.policy) == self.encoder.num_valid_positions:
                    policy = np.array(pos.policy, dtype=np.float32)
                else:
                    # Fallback: uniform over valid positions
                    policy.fill(1.0 / self.encoder.num_valid_positions)
            else:
                # Fallback: uniform distribution
                policy.fill(1.0 / self.encoder.num_valid_positions)
            policies.append(policy)

            # Value is WDL converted to [-1, 1]
            if pos.wdl == 2:  # Win
                value = 1.0
            elif pos.wdl == 1:  # Draw
                value = 0.0
            else:  # Loss
                value = -1.0
            values.append(value)

        return states, policies, values

    def _extract_positions_from_sector(self, sector_file: Path, perfect_db, game) -> List:
        """Extract training positions from a sector file."""
        try:
            # Parse sector file name to extract parameters
            # Example: std_6_7_2_2.sec2 -> W=6, B=7, WF=2, BF=2
            filename = sector_file.stem  # Remove .sec2 extension
            if filename.startswith('std_'):
                parts = filename.split('_')
                if len(parts) == 5:
                    W, B, WF, BF = int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])
                else:
                    logger.warning(f"Invalid sector filename format: {filename}")
                    return []
            else:
                logger.warning(f"Unsupported sector filename: {filename}")
                return []

            # Open sector with correct parameters
            sector_handle = perfect_db.open_sector(W, B, WF, BF)
            if sector_handle < 0:
                logger.warning(f"Failed to open sector: {sector_file}")
                return []

            positions = []

            # Iterate through all positions in the sector
            while True:
                try:
                    result = perfect_db.sector_next(sector_handle)
                    if not result:
                        break  # End of sector

                    white_bits, black_bits, wdl, steps = result

                    # Create a simple position object
                    class SimplePosition:
                        def __init__(self, board, current_player, wdl, steps):
                            self.board = board
                            self.current_player = current_player
                            self.wdl = wdl
                            self.steps = steps
                            self.policy = None  # Will be set to uniform later

                    # Convert bits to board representation
                    # This is a simplified conversion - you may need to adjust based on your board format
                    board = self._bits_to_board(white_bits, black_bits)

                    # Determine current player (simplified logic)
                    current_player = 1 if (white_bits & black_bits) == 0 else -1

                    pos = SimplePosition(board, current_player, wdl, steps)
                    positions.append(pos)

                except Exception as e:
                    logger.warning(f"Error processing position in {sector_file}: {e}")
                    continue

            # Close sector
            perfect_db.close_sector(sector_handle)

            logger.info(f"Extracted {len(positions)} positions from {sector_file}")
            return positions

        except Exception as e:
            logger.error(f"Failed to extract positions from {sector_file}: {e}")
            return []

    def _bits_to_board(self, white_bits: int, black_bits: int):
        """Convert bit representation to board object compatible with MillBoardEncoder."""

        # Create a board compatible with MillBoardEncoder
        class CompatibleBoard:
            def __init__(self):
                # Initialize 7x7 pieces array (required by MillBoardEncoder)
                self.pieces = [[0 for _ in range(7)] for _ in range(7)]

                # Valid positions mapping (same as in MillBoardEncoder)
                self.allowed_places = [
                    [1, 0, 0, 1, 0, 0, 1],
                    [0, 1, 0, 1, 0, 1, 0],
                    [0, 0, 1, 1, 1, 0, 0],
                    [1, 1, 1, 0, 1, 1, 1],
                    [0, 0, 1, 1, 1, 0, 0],
                    [0, 1, 0, 1, 0, 1, 0],
                    [1, 0, 0, 1, 0, 0, 1]
                ]

                # Create coordinate mapping for valid positions
                self.coord_to_feature = {}
                self.feature_to_coord = {}
                feature_idx = 0

                for y in range(7):
                    for x in range(7):
                        if self.allowed_places[x][y]:
                            self.coord_to_feature[(x, y)] = feature_idx
                            self.feature_to_coord[feature_idx] = (x, y)
                            feature_idx += 1

                # Game state attributes
                self.period = 0  # Default to placement phase
                self.put_pieces = 0  # Move count

            def count(self, player):
                """Count pieces of a specific player."""
                count = 0
                for x in range(7):
                    for y in range(7):
                        if self.allowed_places[x][y] and self.pieces[x][y] == player:
                            count += 1
                return count

            def pieces_in_hand_count(self, player):
                """Calculate pieces in hand for a player."""
                on_board = self.count(player)
                return max(0, 9 - on_board)  # Assuming 9 pieces per player

        board = CompatibleBoard()

        # Convert bits to 7x7 board representation
        for feature_idx in range(24):  # 24 valid positions
            bit_mask = 1 << feature_idx
            if feature_idx in board.feature_to_coord:
                x, y = board.feature_to_coord[feature_idx]
                if white_bits & bit_mask:
                    board.pieces[x][y] = 1  # White
                elif black_bits & bit_mask:
                    board.pieces[x][y] = -1  # Black
                else:
                    board.pieces[x][y] = 0  # Empty

        return board

    def _find_existing_chunks(self, sector_stem: str) -> List[Path]:
        """Finds existing chunk files."""
        chunk_pattern = f"{sector_stem}_chunk_*.npz"
        existing_chunks = list(self.output_dir.glob(chunk_pattern))
        if existing_chunks:
            # Sort by chunk number
            def extract_chunk_number(path):
                try:
                    return int(path.stem.split('_chunk_')[-1])
                except (ValueError, IndexError):
                    return 0
            existing_chunks.sort(key=extract_chunk_number)
        return existing_chunks

    def _validate_chunk_file(self, chunk_file: Path) -> Optional[int]:
        """Validates the integrity of a single chunk file, returning the number of positions or None if corrupted."""
        try:
            # First, check if the file exists and is not empty
            if not chunk_file.exists():
                logger.warning(f"Chunk file does not exist: {chunk_file}")
                return None

            file_size = chunk_file.stat().st_size
            if file_size == 0:
                logger.warning(f"Chunk file is empty: {chunk_file}")
                return None

            # Attempt to load and validate data
            data = np.load(chunk_file, allow_pickle=False)
            if data is None:
                logger.warning(f"Loading chunk file returned None: {chunk_file}")
                return None

            # Check for required keys
            required_keys = ['states', 'policies', 'values']
            missing_keys = [key for key in required_keys if key not in data]
            if missing_keys:
                logger.warning(f"Chunk file is missing required keys {missing_keys}: {chunk_file}")
                data.close()
                return None

            # Check data consistency
            states_len = len(data['states'])
            policies_len = len(data['policies'])
            values_len = len(data['values'])

            if not (states_len == policies_len == values_len):
                logger.warning(f"Inconsistent data lengths in chunk file ({states_len}, {policies_len}, {values_len}): {chunk_file}")
                data.close()
                return None

            # Check if data shape is reasonable
            if states_len == 0:
                logger.warning(f"Chunk file data is empty: {chunk_file}")
                data.close()
                return None

            data.close()
            return states_len

        except Exception as e:
            logger.warning(f"Error while validating chunk file {chunk_file}: {e}")
            return None

    def _resume_sector_processing(self, sector_file: Path, existing_chunks: List[Path],
                                  max_positions: Optional[int] = None) -> Optional[SectorMetadata]:
        """Resumes sector processing from existing chunk files."""
        try:
            logger.info(f"Resuming processing for {sector_file.name}, found {len(existing_chunks)} chunk files")
            start_time = time.time()

            # Validate integrity of existing chunks
            valid_chunks = []
            total_positions = 0

            for chunk_file in existing_chunks:
                chunk_positions = self._validate_chunk_file(chunk_file)
                if chunk_positions is not None:
                    total_positions += chunk_positions
                    valid_chunks.append(chunk_file)
                    logger.debug(f"Valid chunk: {chunk_file.name} ({chunk_positions} positions)")
                else:
                    logger.warning(f"Deleting corrupted chunk file: {chunk_file.name}")
                    try:
                        chunk_file.unlink()  # Delete corrupted file
                    except Exception as e:
                        logger.warning(f"Failed to delete corrupted file {chunk_file}: {e}")

            if not valid_chunks:
                logger.info("No valid chunk files found, restarting processing")
                return self.preprocess_sector(sector_file, max_positions, None)

            logger.info(f"Found {len(valid_chunks)} valid chunks, with a total of {total_positions} positions")

            # Check if the max_positions limit has been reached
            if max_positions and total_positions >= max_positions:
                logger.info(f"Existing chunks already meet the position limit ({total_positions} >= {max_positions}), merging directly")
                # Truncate to the limit
                if total_positions > max_positions:
                    valid_chunks = self._truncate_chunks_to_limit(valid_chunks, max_positions)
                    total_positions = max_positions

            # Merge existing chunks
            output_file = self.output_dir / f"{sector_file.stem}.npz"
            logger.info(f"Merging {len(valid_chunks)} chunk files...")
            merge_outputs = self._merge_temp_files(valid_chunks, output_file)

            # Clean up chunk files
            for chunk_file in valid_chunks:
                try:
                    chunk_file.unlink()
                except Exception as e:
                    logger.warning(f"Failed to clean up chunk file {chunk_file}: {e}")

            # Create metadata
            processing_time = time.time() - start_time
            primary_output = str(merge_outputs[0]) if merge_outputs else str(output_file)
            metadata = SectorMetadata(
                filename=sector_file.name,
                output_file=primary_output,
                output_files=[str(p) for p in merge_outputs] if len(merge_outputs) > 1 else None,
                num_positions=total_positions,
                file_size_mb=sector_file.stat().st_size / (1024 * 1024),
                checksum=self._calculate_checksum(sector_file),
                processed_time=processing_time
            )

            self.processed_sectors[sector_file.name] = metadata
            self._save_metadata()

            logger.info(f"Resume complete for {sector_file.name}: {total_positions} positions in {processing_time:.1f}s")
            return metadata

        except Exception as e:
            logger.error(f"Failed to resume processing for {sector_file.name}: {e}")
            # Clean up potentially corrupted files
            for chunk_file in existing_chunks:
                try:
                    if chunk_file.exists():
                        chunk_file.unlink()
                except:
                    pass
            return None

    def _truncate_chunks_to_limit(self, chunks: List[Path], max_positions: int) -> List[Path]:
        """Truncates chunks to the specified position limit."""
        truncated_chunks = []
        current_total = 0

        for chunk_file in chunks:
            try:
                data = np.load(chunk_file)
                chunk_size = len(data['states'])

                if current_total + chunk_size <= max_positions:
                    # The entire chunk is needed
                    truncated_chunks.append(chunk_file)
                    current_total += chunk_size
                else:
                    # This chunk needs to be truncated
                    needed = max_positions - current_total
                    if needed > 0:
                        # Create a truncated chunk
                        truncated_file = chunk_file.with_suffix('.truncated.npz')
                        np.savez_compressed(
                            truncated_file,
                            states=data['states'][:needed],
                            policies=data['policies'][:needed],
                            values=data['values'][:needed]
                        )
                        truncated_chunks.append(truncated_file)
                        current_total += needed
                    break

            except Exception as e:
                logger.warning(f"Error while processing chunk {chunk_file}: {e}")
                continue

        return truncated_chunks

    def _calculate_checksum(self, file_path: Path) -> str:
        """Calculate MD5 checksum of a file."""
        hash_md5 = hashlib.md5()
        with open(file_path, "rb") as f:
            for chunk in iter(lambda: f.read(4096), b""):
                hash_md5.update(chunk)
        return hash_md5.hexdigest()

    def load_preprocessed_data(self,
                             phase_filter: Optional[str] = None,
                             max_positions: Optional[int] = None) -> Tuple[np.ndarray, np.ndarray, np.ndarray, List[Dict]]:
        """
        Loads preprocessed training data (memory-safe version).

        Args:
            phase_filter: Game phase filter ('placement', 'moving', 'flying')
            max_positions: Maximum number of positions to load

        Returns:
            (board_tensors, policy_targets, value_targets, metadata_list)
        """
        logger.info(f"Loading preprocessed data from {self.output_dir} (memory-safe mode)")

        # Check available physical memory
        available_memory_gb = self.memory_monitor.get_available_memory_gb()
        logger.info(f"Available physical memory: {available_memory_gb:.1f} GB")

        if available_memory_gb < 16.0:
            logger.warning(f"⚠️  Physical memory is low ({available_memory_gb:.1f} GB < 16 GB threshold)")
            logger.warning("Will use chunked loading to prevent memory exhaustion")

        # Get all .npz files
        npz_files = list(self.output_dir.glob("*.npz"))
        if not npz_files:
            logger.warning(f"No .npz files found in {self.output_dir}")
            return np.array([]), np.array([]), np.array([]), []

        # Filter files - skip batch.tmp files and apply phase filter
        filtered_files = []
        skipped_tmp_files = 0
        for npz_file in npz_files:
            # Skip batch.tmp format files
            if '.tmp.' in npz_file.name or npz_file.name.endswith('.tmp'):
                skipped_tmp_files += 1
                continue

            # Apply phase filter if specified
            if phase_filter:
                file_phase = self._get_phase_from_filename(npz_file.stem)
                if file_phase != phase_filter:
                    continue
            filtered_files.append(npz_file)

        if skipped_tmp_files > 0:
            logger.info(f"Skipped {skipped_tmp_files} batch.tmp files (not supported)")

        logger.info(f"Found {len(filtered_files)} files to process (filtered from {len(npz_files)})")

        # Use chunked loading strategy
        return self._load_data_in_chunks(filtered_files, max_positions, available_memory_gb)

    def _load_data_in_chunks(self, npz_files: List[Path], max_positions: Optional[int],
                           available_memory_gb: float) -> Tuple[np.ndarray, np.ndarray, np.ndarray, List[Dict]]:
        """
        Loads data in chunks, strictly controlling physical memory usage.

        Args:
            npz_files: List of NPZ files
            max_positions: Maximum number of positions to load
            available_memory_gb: Available physical memory (GB)

        Returns:
            (board_tensors, policy_targets, value_targets, metadata_list)
        """
        # Calculate a safe chunk size based on available memory
        # Assume each position requires about 4KB of memory (19*7*7*4 + 24*4 + 4 + metadata ≈ 1.6KB, leaving ample margin)
        bytes_per_position = 4 * 1024  # 4KB per position (conservative estimate)

        if available_memory_gb >= 16:
            # Sufficient memory, use larger chunks
            max_chunk_size = min(50000, int((available_memory_gb - 8) * 1024 * 1024 * 1024 / bytes_per_position / 2))
        elif available_memory_gb >= 8:
            # Moderate memory, use medium chunks
            max_chunk_size = min(20000, int((available_memory_gb - 4) * 1024 * 1024 * 1024 / bytes_per_position / 2))
        else:
            # Tight on memory, use small chunks
            max_chunk_size = min(5000, int((available_memory_gb - 2) * 1024 * 1024 * 1024 / bytes_per_position / 2))

        max_chunk_size = max(1000, max_chunk_size)  # Minimum of 1000 positions

        logger.info(f"📦 Chunk loading strategy:")
        logger.info(f"  Available memory: {available_memory_gb:.1f} GB")
        logger.info(f"  Max chunk size: {max_chunk_size:,} positions")
        logger.info(f"  Conservative memory per position: {bytes_per_position/1024:.1f} KB")

        all_states = []
        all_policies = []
        all_values = []
        all_metadata = []
        total_loaded = 0

        for file_idx, npz_file in enumerate(npz_files):
            # Check memory every few files
            if file_idx % 5 == 0:
                current_memory = self.memory_monitor.get_available_memory_gb()
                if current_memory < 8.0:  # If memory drops below 8GB, stop immediately
                    logger.warning(f"🚨 Memory critically low ({current_memory:.1f} GB), stopping data loading")
                    break

            try:
                # Check file size to decide whether to read in chunks
                file_size_mb = npz_file.stat().st_size / (1024 * 1024)

                if file_size_mb > 100:  # Files larger than 100MB require special handling
                    logger.info(f"📁 Large file detected: {npz_file.name} ({file_size_mb:.1f} MB)")
                    chunk_data = self._load_large_file_in_chunks(npz_file, max_chunk_size, max_positions - total_loaded if max_positions else None)
                else:
                    # Load small files normally
                    chunk_data = self._load_single_file(npz_file)

                if not chunk_data:
                    continue

                states, policies, values, metadata = chunk_data

                # Check if memory limit will be exceeded
                estimated_memory_mb = len(states) * bytes_per_position / (1024 * 1024)
                current_memory = self.memory_monitor.get_available_memory_gb() * 1024

                if current_memory - estimated_memory_mb < 4 * 1024:  # Keep at least 4GB of memory free
                    logger.warning(f"⚠️  Loading {len(states)} positions would use ~{estimated_memory_mb:.1f}MB")
                    logger.warning(f"    Current available: {current_memory:.0f}MB, stopping to prevent memory exhaustion")
                    break

                # If there's too much data, add it in batches
                if len(states) > max_chunk_size:
                    logger.info(f"🔄 Chunking large dataset: {len(states)} -> chunks of {max_chunk_size}")
                    for chunk_start in range(0, len(states), max_chunk_size):
                        chunk_end = min(chunk_start + max_chunk_size, len(states))

                        all_states.extend(states[chunk_start:chunk_end])
                        all_policies.extend(policies[chunk_start:chunk_end])
                        all_values.extend(values[chunk_start:chunk_end])
                        all_metadata.extend(metadata[chunk_start:chunk_end])

                        total_loaded += (chunk_end - chunk_start)

                        # Check if the position limit has been reached
                        if max_positions and total_loaded >= max_positions:
                            logger.info(f"🎯 Reached position limit: {max_positions}")
                            break

                        # Check memory status
                        current_memory = self.memory_monitor.get_available_memory_gb()
                        if current_memory < 8.0:
                            logger.warning(f"🚨 Memory low during chunking ({current_memory:.1f} GB), stopping")
                            break
                else:
                    all_states.extend(states)
                    all_policies.extend(policies)
                    all_values.extend(values)
                    all_metadata.extend(metadata)
                    total_loaded += len(states)

                # Periodic cleanup and garbage collection
                if file_idx % 10 == 0:
                    self.memory_monitor.gentle_memory_cleanup()

                # Check if the position limit has been reached
                if max_positions and total_loaded >= max_positions:
                    logger.info(f"🎯 Reached position limit: {max_positions}")
                    break

            except Exception as e:
                logger.warning(f"Failed to load {npz_file}: {e}")
                continue

            # Display progress
            if file_idx % 20 == 0:
                current_memory = self.memory_monitor.get_available_memory_gb()
                logger.info(f"📊 Progress: {file_idx+1}/{len(npz_files)} files, {total_loaded:,} positions, {current_memory:.1f}GB available")

        if not all_states:
            logger.warning("No data loaded from any files")
            return np.array([]), np.array([]), np.array([]), []

        # Final memory check and data conversion
        final_memory = self.memory_monitor.get_available_memory_gb()
        total_positions = len(all_states)
        logger.info(f"🔄 Converting {total_positions:,} positions to numpy arrays... (Available memory: {final_memory:.1f} GB)")

        # Calculate batch conversion size to avoid OOM
        # Each position needs ~4KB, calculate with 8KB to be safe
        available_mb = final_memory * 1024
        safe_mb = available_mb * 0.3  # Use only 30% of available memory for conversion
        max_batch_size = max(1000, int(safe_mb * 1024 / 8))  # Minimum 1000 positions

        logger.info(f"🔧 Using batch conversion with max batch size: {max_batch_size:,}")

        try:
            # Convert to numpy array in batches to avoid OOM
            board_tensors_list = []
            policy_targets_list = []
            value_targets_list = []

            for start_idx in range(0, total_positions, max_batch_size):
                end_idx = min(start_idx + max_batch_size, total_positions)
                batch_size = end_idx - start_idx

                if start_idx % (max_batch_size * 5) == 0:  # Report progress every 5 batches
                    logger.info(f"  Converting batch {start_idx//max_batch_size + 1}: "
                                f"positions {start_idx:,} - {end_idx-1:,} ({batch_size:,} items)")

                # Convert current batch
                board_batch = np.array(all_states[start_idx:end_idx], dtype=np.float32)
                policy_batch = np.array(all_policies[start_idx:end_idx], dtype=np.float32)
                value_batch = np.array(all_values[start_idx:end_idx], dtype=np.float32)

                board_tensors_list.append(board_batch)
                policy_targets_list.append(policy_batch)
                value_targets_list.append(value_batch)

                # Periodically check and clean memory
                if start_idx % (max_batch_size * 3) == 0:
                    current_memory = self.memory_monitor.get_available_memory_gb()
                    if current_memory < 8.0:
                        logger.warning(f"⚠️  Memory getting low during conversion: {current_memory:.1f} GB")
                        self.memory_monitor.gentle_memory_cleanup()

            # Concatenate all batches
            logger.info(f"🔗 Concatenating {len(board_tensors_list)} batches...")
            board_tensors = np.concatenate(board_tensors_list, axis=0)
            policy_targets = np.concatenate(policy_targets_list, axis=0)
            value_targets = np.concatenate(value_targets_list, axis=0)

            # Clean up temporary lists and original data
            del board_tensors_list, policy_targets_list, value_targets_list
            del all_states, all_policies, all_values
            self.memory_monitor.gentle_memory_cleanup()

        except MemoryError as e:
            logger.error("❌ Memory error during numpy array conversion")
            logger.error(f"    Error details: {e}")
            logger.error("    Try reducing max_positions or running with more available memory")
            # Clean up potential partial data
            try:
                del all_states, all_policies, all_values
            except:
                pass
            self.memory_monitor.gentle_memory_cleanup()
            raise

        # If there is a position limit, truncate the data
        if max_positions and len(board_tensors) > max_positions:
            board_tensors = board_tensors[:max_positions]
            policy_targets = policy_targets[:max_positions]
            value_targets = value_targets[:max_positions]
            all_metadata = all_metadata[:max_positions]

        final_memory_after = self.memory_monitor.get_available_memory_gb()
        memory_used = final_memory - final_memory_after

        logger.info(f"✅ Data loading completed:")
        logger.info(f"  Loaded positions: {len(board_tensors):,}")
        logger.info(f"  Board tensor shape: {board_tensors.shape}")
        logger.info(f"  Policy tensor shape: {policy_targets.shape}")
        logger.info(f"  Value tensor shape: {value_targets.shape}")
        logger.info(f"  Memory used: ~{memory_used:.1f} GB")
        logger.info(f"  Memory remaining: {final_memory_after:.1f} GB")

        return board_tensors, policy_targets, value_targets, all_metadata

    def _load_single_file(self, npz_file: Path) -> Optional[Tuple[List, List, List, List]]:
        """Loads a single NPZ file."""
        try:
            data = np.load(npz_file)

            # Check for required keys
            required_keys = ['states', 'policies', 'values']
            if not all(key in data for key in required_keys):
                logger.warning(f"Missing required keys in {npz_file}")
                return None

            states = data['states']
            policies = data['policies']
            values = data['values']

            # Check data consistency
            if len(states) != len(policies) or len(states) != len(values):
                logger.warning(f"Inconsistent data shapes in {npz_file}")
                return None

            # Create metadata
            metadata = []
            for i in range(len(states)):
                meta = {
                    'sector_filename': npz_file.name,
                    'position_index': i,
                    'game_phase': self._get_phase_from_filename(npz_file.stem),
                    'is_trap': False,
                    'difficulty': 0.0
                }
                metadata.append(meta)

            return list(states), list(policies), list(values), metadata

        except Exception as e:
            logger.warning(f"Failed to load {npz_file}: {e}")
            return None

    def _load_large_file_in_chunks(self, npz_file: Path, chunk_size: int,
                                  max_positions: Optional[int]) -> Optional[Tuple[List, List, List, List]]:
        """Loads a large NPZ file in chunks."""
        try:
            data = np.load(npz_file)

            required_keys = ['states', 'policies', 'values']
            if not all(key in data for key in required_keys):
                logger.warning(f"Missing required keys in large file {npz_file}")
                return None

            states = data['states']
            policies = data['policies']
            values = data['values']

            total_positions = len(states)
            if max_positions:
                total_positions = min(total_positions, max_positions)

            # Process in chunks
            all_states = []
            all_policies = []
            all_values = []
            all_metadata = []

            for start_idx in range(0, total_positions, chunk_size):
                end_idx = min(start_idx + chunk_size, total_positions)

                # Check memory status
                current_memory = self.memory_monitor.get_available_memory_gb()
                if current_memory < 8.0:
                    logger.warning(f"🚨 Memory low during large file processing ({current_memory:.1f} GB)")
                    break

                chunk_states = states[start_idx:end_idx]
                chunk_policies = policies[start_idx:end_idx]
                chunk_values = values[start_idx:end_idx]

                all_states.extend(chunk_states)
                all_policies.extend(chunk_policies)
                all_values.extend(chunk_values)

                # Create metadata
                for i in range(len(chunk_states)):
                    meta = {
                        'sector_filename': npz_file.name,
                        'position_index': start_idx + i,
                        'game_phase': self._get_phase_from_filename(npz_file.stem),
                        'is_trap': False,
                        'difficulty': 0.0
                    }
                    all_metadata.append(meta)

                # Periodic cleanup
                if (start_idx // chunk_size) % 5 == 0:
                    self.memory_monitor.gentle_memory_cleanup()

            logger.info(f"📦 Loaded {len(all_states):,} positions from large file {npz_file.name}")
            return all_states, all_policies, all_values, all_metadata

        except Exception as e:
            logger.warning(f"Failed to chunk-load large file {npz_file}: {e}")
            return None

    def _get_phase_from_filename(self, filename: str) -> str:
        """
        Infers the game phase from the filename.
        Supports two formats:
        1. Standard format: std_W_B_WF_BF.npz
        2. Chunk format: std_W_B_WF_BF_chunk_N.npz
        Skips batch.tmp format files.
        """
        try:
            # Skip batch.tmp format files
            if '.tmp.' in filename or filename.endswith('.tmp'):
                return 'unknown'

            if filename.startswith('std_'):
                parts = filename.split('_')

                # Handle chunk format: std_W_B_WF_BF_chunk_N
                if len(parts) >= 7 and parts[5] == 'chunk':
                    # Extract W, B, WF, BF from chunk format
                    W, B, WF, BF = int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])
                # Handle standard format: std_W_B_WF_BF
                elif len(parts) >= 5:
                    # Extract W, B, WF, BF from standard format
                    W, B, WF, BF = int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])
                else:
                    return 'unknown'

                # Determine game phase based on piece counts
                if WF > 0 or BF > 0:
                    return 'placement'  # Still has pieces in hand
                elif W <= 3 or B <= 3:
                    return 'flying'     # Less than or equal to 3 pieces, enters flying phase
                else:
                    return 'moving'     # Moving phase

        except (ValueError, IndexError):
            pass

        return 'unknown'

    def get_statistics(self) -> Dict[str, Any]:
        """Gets processing statistics."""
        if not self.processed_sectors:
            return {}

        total_positions = sum(meta.num_positions for meta in self.processed_sectors.values())
        total_size_mb = sum(meta.file_size_mb for meta in self.processed_sectors.values())
        total_time = sum(meta.processed_time for meta in self.processed_sectors.values())

        return {
            "total_sectors": len(self.processed_sectors),
            "total_positions": total_positions,
            "total_size_mb": total_size_mb,
            "total_processing_time": total_time,
            "avg_positions_per_sector": total_positions / len(self.processed_sectors),
            "avg_processing_time": total_time / len(self.processed_sectors),
            "positions_per_second": total_positions / total_time if total_time > 0 else 0
        }


def _process_one_sector_worker(args) -> Optional[Dict[str, Any]]:
    """Top-level worker to preprocess a single sector in an isolated process.

    This avoids sharing a single DLL handle across threads and preserves performance
    by using process-level parallelism, which is the safe option on Windows.
    """
    sector_path_str, perfect_db_path_str, output_dir_str, max_positions = args
    try:
        # Create a fresh preprocessor in this process
        local_pre = PerfectDBPreprocessor(
            perfect_db_path=perfect_db_path_str,
            output_dir=output_dir_str
        )
        metadata = local_pre.preprocess_sector(Path(sector_path_str), max_positions)
        if metadata:
            return asdict(metadata)
        return None
    except Exception as e:
        import logging
        logging.getLogger(__name__).error(f"Worker failed on {sector_path_str}: {e}")
        return None


def main():
    """Main function."""
    parser = argparse.ArgumentParser(description="Perfect Database Preprocessor with Memory Protection")
    parser.add_argument('--perfect-db', required=True, help='Perfect DB directory path')
    parser.add_argument('--output-dir', required=True, help='Output directory for preprocessed data')
    parser.add_argument('--max-workers', type=int, default=mp.cpu_count(), help='Number of worker processes')
    parser.add_argument('--max-positions', type=int, help='Maximum positions per sector (for testing)')
    parser.add_argument('--force', action='store_true', help='Force reprocess existing files')
    parser.add_argument('--stats', action='store_true', help='Show statistics only')
    parser.add_argument('--memory-threshold', type=float, default=16.0,
                        help='Memory threshold in GB below which protection mechanisms activate (default: 16.0)')

    args = parser.parse_args()

    # Display memory protection information
    print(f"🛡️  Memory protection threshold: {args.memory_threshold}GB")

    # Create the preprocessor
    try:
        preprocessor = PerfectDBPreprocessor(
            perfect_db_path=args.perfect_db,
            output_dir=args.output_dir,
            memory_threshold_gb=args.memory_threshold
        )
    except Exception as e:
        logger.error(f"Failed to initialize preprocessor: {e}")
        return

    if args.stats:
        # Display statistics
        stats = preprocessor.get_statistics()
        if stats:
            print("\n📊 Preprocessing Statistics:")
            print(f"  Sectors processed: {stats['total_sectors']:,}")
            print(f"  Total positions: {stats['total_positions']:,}")
            print(f"  Total file size: {stats['total_size_mb']:.1f} MB")
            print(f"  Total processing time: {stats['total_processing_time']:.1f} seconds")
            print(f"  Avg. positions/sector: {stats['avg_positions_per_sector']:.0f}")
            print(f"  Avg. processing time/sector: {stats['avg_processing_time']:.2f} seconds")
            print(f"  Processing speed: {stats['positions_per_second']:.0f} positions/sec")
        else:
            print("📊 No processing statistics yet")
    else:
        # Start preprocessing
        preprocessor.preprocess_all(
            max_workers=args.max_workers,
            max_positions_per_sector=args.max_positions,
            force=args.force
        )


if __name__ == '__main__':
    main()