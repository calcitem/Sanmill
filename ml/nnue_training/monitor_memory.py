#!/usr/bin/env python3
"""
Memory monitoring utility for Perfect Database training data generation.
Helps diagnose memory usage patterns when dealing with large position counts.
"""

import time
import sys
import argparse
from typing import Optional

try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False
    print("Warning: psutil not available. Install with: pip install psutil")
    print("Memory monitoring functionality will be limited.")

class MemoryMonitor:
    """Monitor system and process memory usage during Perfect DB operations."""
    
    def __init__(self, pid: Optional[int] = None, interval: float = 1.0):
        self.interval = interval
        if not HAS_PSUTIL:
            raise RuntimeError("psutil is required for memory monitoring. Install with: pip install psutil")
        self.process = psutil.Process(pid) if pid else psutil.Process()
        self.initial_memory = self.get_memory_info()
        self.peak_memory = self.initial_memory
        
    def get_memory_info(self) -> dict:
        """Get current memory information."""
        try:
            mem_info = self.process.memory_info()
            return {
                'rss': mem_info.rss / 1024 / 1024,  # MB
                'vms': mem_info.vms / 1024 / 1024,  # MB
                'percent': self.process.memory_percent(),
                'available': psutil.virtual_memory().available / 1024 / 1024,  # MB
                'system_used': psutil.virtual_memory().percent
            }
        except psutil.NoSuchProcess:
            return None
    
    def print_memory_status(self, prefix: str = ""):
        """Print current memory status."""
        mem_info = self.get_memory_info()
        if mem_info is None:
            print(f"{prefix}Process no longer exists")
            return False
            
        # Update peak memory
        if mem_info['rss'] > self.peak_memory['rss']:
            self.peak_memory = mem_info.copy()
        
        delta_rss = mem_info['rss'] - self.initial_memory['rss']
        delta_vms = mem_info['vms'] - self.initial_memory['vms']
        
        print(f"{prefix}Memory Status:")
        print(f"  Process RSS: {mem_info['rss']:.1f} MB (Δ{delta_rss:+.1f} MB)")
        print(f"  Process VMS: {mem_info['vms']:.1f} MB (Δ{delta_vms:+.1f} MB)")
        print(f"  Process %:   {mem_info['percent']:.1f}%")
        print(f"  System:      {mem_info['system_used']:.1f}% used, {mem_info['available']:.1f} MB available")
        print(f"  Peak RSS:    {self.peak_memory['rss']:.1f} MB")
        
        return True
    
    def monitor_continuous(self, duration: Optional[float] = None):
        """Monitor memory usage continuously."""
        print(f"🔍 Starting memory monitoring (PID: {self.process.pid}, interval: {self.interval}s)")
        print("Press Ctrl+C to stop\n")
        
        start_time = time.time()
        
        try:
            while True:
                timestamp = time.strftime("%H:%M:%S")
                if not self.print_memory_status(f"[{timestamp}] "):
                    break
                print()
                
                if duration and (time.time() - start_time) >= duration:
                    break
                    
                time.sleep(self.interval)
                
        except KeyboardInterrupt:
            print("\n🛑 Monitoring stopped by user")
        
        print(f"\n📊 Final Summary:")
        print(f"  Peak RSS: {self.peak_memory['rss']:.1f} MB")
        print(f"  Total RSS delta: {self.peak_memory['rss'] - self.initial_memory['rss']:+.1f} MB")

def monitor_command(pid: int, interval: float, duration: Optional[float]):
    """Monitor a specific process."""
    try:
        monitor = MemoryMonitor(pid, interval)
        monitor.monitor_continuous(duration)
    except psutil.NoSuchProcess:
        print(f"❌ Process with PID {pid} not found")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error monitoring process: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description='Monitor memory usage during Perfect Database operations'
    )
    parser.add_argument('--pid', type=int, help='Process ID to monitor (default: current process)')
    parser.add_argument('--interval', type=float, default=1.0, help='Monitoring interval in seconds (default: 1.0)')
    parser.add_argument('--duration', type=float, help='Monitoring duration in seconds (default: unlimited)')
    
    args = parser.parse_args()
    
    if not HAS_PSUTIL:
        print("Error: psutil is required for this tool.")
        print("Install with: pip install psutil")
        sys.exit(1)
    
    if args.pid:
        monitor_command(args.pid, args.interval, args.duration)
    else:
        # Self-monitoring mode for testing
        monitor = MemoryMonitor(interval=args.interval)
        print("Self-monitoring mode - simulating memory usage...")
        
        # Simulate some memory allocation for testing
        data = []
        for i in range(5):
            print(f"\nStep {i+1}: Allocating 10MB...")
            data.append(bytearray(10 * 1024 * 1024))  # 10MB
            monitor.print_memory_status()
            time.sleep(2)
        
        print(f"\nCleaning up...")
        del data
        monitor.print_memory_status()

if __name__ == '__main__':
    main()
