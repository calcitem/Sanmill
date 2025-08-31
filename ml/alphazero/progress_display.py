#!/usr/bin/env python3
"""
Progress Display for Alpha Zero Training

Provides a visually appealing display for training progress, including file processing status, time estimates, etc.
"""

import time
import os
import sys
from typing import List, Optional, Dict, Any
from pathlib import Path
from datetime import datetime, timedelta
from dataclasses import dataclass
import threading
import logging

logger = logging.getLogger(__name__)


@dataclass
class FileProgress:
    """Progress of a single file being processed."""
    filename: str
    size_bytes: int
    processed_bytes: int = 0
    start_time: Optional[float] = None
    end_time: Optional[float] = None
    status: str = "pending"  # pending, processing, completed, error


@dataclass
class OverallProgress:
    """Overall processing progress."""
    total_files: int
    completed_files: int = 0
    total_size_bytes: int = 0
    processed_size_bytes: int = 0
    start_time: Optional[float] = None
    current_file: Optional[str] = None


class ProgressBar:
    """A visually appealing progress bar display."""

    def __init__(self, width: int = 50):
        """
        Initializes the progress bar.
        
        Args:
            width: The width of the progress bar.
        """
        self.width = width

    def render(self, percentage: float, prefix: str = "", suffix: str = "") -> str:
        """
        Renders the progress bar.
        
        Args:
            percentage: The progress percentage (0-100).
            prefix: The text prefix.
            suffix: The text suffix.
            
        Returns:
            A formatted progress bar string.
        """
        filled_width = int(self.width * percentage / 100)
        bar = "█" * filled_width + "░" * (self.width - filled_width)
        return f"{prefix} |{bar}| {percentage:6.2f}% {suffix}"


class TrainingProgressDisplay:
    """Training progress display monitor."""

    def __init__(self, show_file_details: bool = True, update_interval: float = 0.5):
        """
        Initializes the progress display monitor.
        
        Args:
            show_file_details: Whether to show detailed file information.
            update_interval: The update interval in seconds.
        """
        self.show_file_details = show_file_details
        self.update_interval = update_interval

        # Progress data
        self.overall_progress = OverallProgress(total_files=0)
        self.file_progresses: Dict[str, FileProgress] = {}
        self.current_operation: str = ""  # Description of the currently executing operation
        self._subtask: Dict[str, Any] = {  # Sub-task (e.g., Trap detection progress)
            'name': '',
            'current': 0,
            'total': 0
        }

        # Display control
        self._stop_display = False
        self._display_thread: Optional[threading.Thread] = None
        self._lock = threading.Lock()

        # Progress bars
        self.main_bar = ProgressBar(60)
        self.file_bar = ProgressBar(40)

        # Console clearing
        self.clear_command = "cls" if os.name == "nt" else "clear"
        self._use_ansi = self._detect_ansi_support()
        self._last_display_snapshot: str = ""

    def _detect_ansi_support(self) -> bool:
        """Detects if the terminal supports ANSI escape codes to use in-place refresh and reduce flickering."""
        try:
            if not sys.stdout.isatty():
                return False
        except Exception:
            return False
        # Windows Terminal or modern PowerShell usually supports ANSI
        if os.name == 'nt':
            return ('WT_SESSION' in os.environ) or ('ANSICON' in os.environ) or ('ConEmuANSI' in os.environ)
        # Unix-like terminals generally support it
        term = os.environ.get('TERM', '')
        return term not in ('', 'dumb')

    def start_display(self):
        """Starts displaying the progress."""
        if self._display_thread and self._display_thread.is_alive():
            return

        self._stop_display = False
        self._display_thread = threading.Thread(target=self._display_loop, daemon=True)
        self._display_thread.start()

    def stop_display(self):
        """Stops displaying the progress."""
        self._stop_display = True
        if self._display_thread and self._display_thread.is_alive():
            self._display_thread.join(timeout=1.0)

    def set_total_files(self, file_paths: List[Path]):
        """
        Sets the list of total files.
        
        Args:
            file_paths: A list of file paths.
        """
        with self._lock:
            # Reset overall and file progress to avoid counter drift
            self.overall_progress = OverallProgress(
                total_files=len(file_paths),
                completed_files=0,
                total_size_bytes=sum(f.stat().st_size for f in file_paths),
                processed_size_bytes=0,
                start_time=time.time(),
                current_file=None
            )

            self.file_progresses.clear()
            for file_path in file_paths:
                filename = file_path.name
                size_bytes = file_path.stat().st_size
                self.file_progresses[filename] = FileProgress(
                    filename=filename,
                    size_bytes=size_bytes
                )

    def start_file(self, filename: str):
        """
        Starts processing a file.
        
        Args:
            filename: The name of the file.
        """
        with self._lock:
            self.overall_progress.current_file = filename
            if filename in self.file_progresses:
                self.file_progresses[filename].status = "processing"
                self.file_progresses[filename].start_time = time.time()

    def update_file_progress(self, filename: str, processed_bytes: int):
        """
        Updates the file processing progress.
        
        Args:
            filename: The name of the file.
            processed_bytes: The number of bytes processed so far.
        """
        with self._lock:
            if filename in self.file_progresses:
                old_processed = self.file_progresses[filename].processed_bytes
                self.file_progresses[filename].processed_bytes = processed_bytes

                # Update overall progress
                self.overall_progress.processed_size_bytes += (processed_bytes - old_processed)

    def complete_file(self, filename: str, success: bool = True):
        """
        Completes the processing of a file.
        
        Args:
            filename: The name of the file.
            success: Whether the processing was successful.
        """
        with self._lock:
            if filename in self.file_progresses:
                file_progress = self.file_progresses[filename]
                previous_status = file_progress.status
                file_progress.status = "completed" if success else "error"
                file_progress.end_time = time.time()

                if success:
                    # Ensure the file is marked as fully processed
                    old_processed = file_progress.processed_bytes
                    file_progress.processed_bytes = file_progress.size_bytes
                    self.overall_progress.processed_size_bytes += (file_progress.size_bytes - old_processed)

                # Increment only when the status changes from a non-completed state to completed/error for the first time
                if previous_status not in ("completed", "error"):
                    self.overall_progress.completed_files += 1
                self.overall_progress.current_file = None

    def set_current_operation(self, text: str):
        """Sets the description for the current high-level operation (e.g., Trap detection, DLL traversal, etc.)."""
        with self._lock:
            self.current_operation = text or ""

    def update_subtask_progress(self, name: str, current: int, total: int):
        """Updates the progress of a sub-task (e.g., number of Trap detection locations)."""
        with self._lock:
            self._subtask['name'] = name or ''
            self._subtask['current'] = max(0, int(current))
            self._subtask['total'] = max(0, int(total))

    def clear_subtask(self):
        """Clears the sub-task display."""
        with self._lock:
            self._subtask = {'name': '', 'current': 0, 'total': 0}

    def _display_loop(self):
        """Display loop (runs in a separate thread)."""
        while not self._stop_display:
            try:
                self._render_display()
                time.sleep(self.update_interval)
            except Exception as e:
                logger.error(f"Display error: {e}")
                break

    def _render_display(self):
        """Renders the display content."""
        with self._lock:
            # Clear screen / in-place refresh to minimize flickering
            if self._use_ansi:
                # Move cursor to top-left corner and clear the screen
                sys.stdout.write("\x1b[H\x1b[2J")
                sys.stdout.flush()
            else:
                os.system(self.clear_command)

            # Display title
            print("🎯 Nine Men's Morris Alpha Zero Training Progress")
            print("=" * 80)
            print()

            # Calculate overall progress
            total_percentage = 0.0
            if self.overall_progress.total_size_bytes > 0:
                total_percentage = (self.overall_progress.processed_size_bytes /
                                      self.overall_progress.total_size_bytes * 100)

            # Calculate time information
            elapsed_time = 0.0
            estimated_remaining = 0.0
            if self.overall_progress.start_time:
                elapsed_time = time.time() - self.overall_progress.start_time
                if total_percentage > 0:
                    estimated_total = elapsed_time * 100 / total_percentage
                    estimated_remaining = max(0, estimated_total - elapsed_time)

            # Display overall progress
            print("📊 Overall Progress:")
            # Use actual status counts to avoid counting anomalies
            completed_count = sum(1 for p in self.file_progresses.values() if p.status == "completed")
            error_count = sum(1 for p in self.file_progresses.values() if p.status == "error")
            total_completed = completed_count + error_count
            print(self.main_bar.render(
                total_percentage,
                prefix="🗂️  Files",
                suffix=f"{total_completed}/{self.overall_progress.total_files}"
            ))

            # Display size information
            total_mb = self.overall_progress.total_size_bytes / (1024 * 1024)
            processed_mb = self.overall_progress.processed_size_bytes / (1024 * 1024)
            remaining_mb = total_mb - processed_mb

            print(f"💾 Size: {processed_mb:.1f} MB / {total_mb:.1f} MB (Remaining: {remaining_mb:.1f} MB)")

            # Display time information
            elapsed_str = self._format_time(elapsed_time)
            remaining_str = self._format_time(estimated_remaining)
            eta_str = (datetime.now() + timedelta(seconds=estimated_remaining)).strftime("%H:%M:%S")

            print(f"⏱️  Time: {elapsed_str} elapsed, {remaining_str} remaining (ETA: {eta_str})")
            print()

            # High-level operation and sub-task
            if self.current_operation:
                print(f"🛠️  Operation: {self.current_operation}")
                # Sub-task progress bar (if any)
                name = self._subtask.get('name') or ''
                cur = int(self._subtask.get('current') or 0)
                tot = int(self._subtask.get('total') or 0)
                if name and tot > 0:
                    sub_pct = (cur / tot * 100.0) if tot > 0 else 0.0
                    print(self.file_bar.render(sub_pct, prefix=f"   {name}", suffix=f"{cur}/{tot}"))
                    print()

            # Display the currently processing file
            if self.overall_progress.current_file:
                current_file = self.overall_progress.current_file
                if current_file in self.file_progresses:
                    file_progress = self.file_progresses[current_file]
                    file_percentage = 0.0
                    if file_progress.size_bytes > 0:
                        file_percentage = (file_progress.processed_bytes /
                                           file_progress.size_bytes * 100)

                    print(f"📁 Current File: {current_file}")
                    print(self.file_bar.render(
                        file_percentage,
                        prefix="   Processing",
                        suffix=f"{file_progress.processed_bytes // 1024} KB / {file_progress.size_bytes // 1024} KB"
                    ))
                    print()

            # Display detailed file list (optional)
            if self.show_file_details:
                self._render_file_details()

            # Display statistics
            self._render_statistics()

    def _render_file_details(self):
        """Renders detailed file information."""
        print("📋 File Details:")
        print("-" * 80)

        # Group and display by status
        status_groups = {
            "processing": [],
            "completed": [],
            "error": [],
            "pending": []
        }

        for filename, progress in self.file_progresses.items():
            status_groups[progress.status].append((filename, progress))

        # Display processing files
        if status_groups["processing"]:
            print("🔄 Processing:")
            for filename, progress in status_groups["processing"]:
                percentage = (progress.processed_bytes / progress.size_bytes * 100) if progress.size_bytes > 0 else 0
                size_mb = progress.size_bytes / (1024 * 1024)
                print(f"   📄 {filename:<40} {percentage:6.1f}% ({size_mb:.1f} MB)")

        # Display recently completed files (up to 5)
        if status_groups["completed"]:
            recent_completed = sorted(
                status_groups["completed"],
                key=lambda x: x[1].end_time or 0,
                reverse=True
            )[:5]
            print("\n✅ Recently Completed:")
            for filename, progress in recent_completed:
                size_mb = progress.size_bytes / (1024 * 1024)
                duration = (progress.end_time or 0) - (progress.start_time or 0)
                print(f"   📄 {filename:<40} {size_mb:6.1f} MB ({duration:.1f}s)")

        # Display files with errors
        if status_groups["error"]:
            print("\n❌ Errors:")
            for filename, progress in status_groups["error"]:
                size_mb = progress.size_bytes / (1024 * 1024)
                print(f"   📄 {filename:<40} {size_mb:6.1f} MB")

        print()

    def _render_statistics(self):
        """Renders statistics."""
        print("📈 Statistics:")
        print("-" * 80)

        # Calculate processing speed
        processing_speed = 0.0
        if self.overall_progress.start_time:
            elapsed = time.time() - self.overall_progress.start_time
            if elapsed > 0:
                processing_speed = self.overall_progress.processed_size_bytes / elapsed

        speed_mb_s = processing_speed / (1024 * 1024)

        # File statistics
        completed_count = sum(1 for p in self.file_progresses.values() if p.status == "completed")
        error_count = sum(1 for p in self.file_progresses.values() if p.status == "error")
        processing_count = sum(1 for p in self.file_progresses.values() if p.status == "processing")
        pending_count = sum(1 for p in self.file_progresses.values() if p.status == "pending")

        print(f"🎯 Files: ✅ {completed_count} completed, 🔄 {processing_count} processing, "
              f"⏳ {pending_count} pending, ❌ {error_count} errors")
        print(f"⚡ Speed: {speed_mb_s:.2f} MB/s")

        # Success rate
        if completed_count + error_count > 0:
            success_rate = completed_count / (completed_count + error_count) * 100
            print(f"📊 Success Rate: {success_rate:.1f}%")

        print()

    def _format_time(self, seconds: float) -> str:
        """
        Formats the time for display.
        
        Args:
            seconds: The number of seconds.
            
        Returns:
            A formatted time string.
        """
        if seconds < 60:
            return f"{seconds:.0f}s"
        elif seconds < 3600:
            minutes = seconds // 60
            secs = seconds % 60
            return f"{minutes:.0f}m {secs:.0f}s"
        else:
            hours = seconds // 3600
            minutes = (seconds % 3600) // 60
            return f"{hours:.0f}h {minutes:.0f}m"


class CompactProgressDisplay:
    """Compact progress display (single line)."""

    def __init__(self):
        """Initializes the compact display."""
        self.start_time = time.time()
        self.last_update = 0
        self.progress_bar = ProgressBar(30)

    def update(self, current: int, total: int, current_file: str = "", extra_info: str = ""):
        """
        Updates the progress display.
        
        Args:
            current: The current progress count.
            total: The total count.
            current_file: The name of the current file.
            extra_info: Additional information.
        """
        now = time.time()

        # Limit the update frequency
        if now - self.last_update < 0.1:
            return
        self.last_update = now

        # Calculate percentage
        percentage = (current / total * 100) if total > 0 else 0

        # Calculate time
        elapsed = now - self.start_time
        if percentage > 0:
            estimated_total = elapsed * 100 / percentage
            remaining = max(0, estimated_total - elapsed)
        else:
            remaining = 0

        # Format filename
        if current_file:
            display_name = current_file[:20] + "..." if len(current_file) > 23 else current_file
        else:
            display_name = ""

        # Build the display string
        progress_str = self.progress_bar.render(percentage)
        time_str = self._format_time(remaining)
        info_str = f" | {extra_info}" if extra_info else ""

        # Single-line display
        display_line = f"\r{progress_str} | {current}/{total} | {display_name:<23} | ETA: {time_str}{info_str}"

        # Ensure it does not exceed terminal width
        terminal_width = os.get_terminal_size().columns if hasattr(os, 'get_terminal_size') else 80
        if len(display_line) > terminal_width:
            display_line = display_line[:terminal_width-3] + "..."

        print(display_line, end="", flush=True)

    def finish(self, message: str = "Complete!"):
        """
        Finalizes the display.
        
        Args:
            message: The completion message.
        """
        elapsed = time.time() - self.start_time
        elapsed_str = self._format_time(elapsed)
        print(f"\r✅ {message} (Total time: {elapsed_str})")

    def _format_time(self, seconds: float) -> str:
        """Formats time for display."""
        if seconds < 60:
            return f"{seconds:.0f}s"
        elif seconds < 3600:
            return f"{seconds//60:.0f}m{seconds%60:.0f}s"
        else:
            return f"{seconds//3600:.0f}h{(seconds%3600)//60:.0f}m"


# Progress display decorator
def with_progress_display(display_type: str = "full"):
    """
    A decorator for displaying progress.
    
    Args:
        display_type: The type of display ('full', 'compact').
    """
    def decorator(func):
        def wrapper(*args, **kwargs):
            if display_type == "full":
                display = TrainingProgressDisplay()
                display.start_display()
                try:
                    result = func(*args, progress_display=display, **kwargs)
                finally:
                    display.stop_display()
                return result
            elif display_type == "compact":
                display = CompactProgressDisplay()
                return func(*args, progress_display=display, **kwargs)
            else:
                return func(*args, **kwargs)
        return wrapper
    return decorator


if __name__ == "__main__":
    # Test progress display
    import random

    print("Testing Progress Display...")

    # Simulate a list of files
    test_files = [
        Path(f"std_{i}_{j}_{k}_{l}.sec2")
        for i in range(1, 4)
        for j in range(1, 4)
        for k in range(0, 2)
        for l in range(0, 2)
    ]

    # Create temporary files for testing
    for file_path in test_files:
        file_path.touch()
        # Set a random size
        with open(file_path, "wb") as f:
            f.write(b"0" * random.randint(1024*100, 1024*1024*5))  # 100KB - 5MB

    try:
        # Test the full display
        display = TrainingProgressDisplay(show_file_details=True)
        display.start_display()
        display.set_total_files(test_files)

        for file_path in test_files:
            filename = file_path.name
            size = file_path.stat().st_size

            display.start_file(filename)

            # Simulate the processing
            for i in range(0, size, size//10):
                display.update_file_progress(filename, min(i, size))
                time.sleep(0.1)

            display.complete_file(filename, success=random.random() > 0.1)
            time.sleep(0.2)

        display.stop_display()
        print("✅ Progress display test completed!")

    finally:
        # Clean up test files
        for file_path in test_files:
            if file_path.exists():
                file_path.unlink()
