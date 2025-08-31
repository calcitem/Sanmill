#!/usr/bin/env python3
"""
Test script for chunked training with progress display and time formatting
"""

import sys
import time
from chunked_training_manager import ChunkedTrainingProgressDisplay

def test_time_formatting():
    """Test the time formatting function."""
    print("🧪 Testing Time Formatting Function")
    print("=" * 50)
    
    # Create a dummy progress display to test the formatting function
    progress_display = ChunkedTrainingProgressDisplay(1, 1, 1000)
    
    # Test various time durations
    test_cases = [
        (30, "30 seconds"),
        (90, "1.5 minutes"),
        (3661, "1 hour 1 minute 1 second"),
        (7323, "2 hours 2 minutes 3 seconds"),
        (90061, "1 day 1 hour 1 minute 1 second"),
        (345661, "4 days 1 hour 1 minute 1 second"),
        (604800, "7 days"),
        (2678461, "31 days 1 hour 1 minute 1 second")
    ]
    
    print("Time formatting examples:")
    for seconds, description in test_cases:
        formatted = progress_display._format_time(seconds)
        print(f"  {seconds:8.0f}s ({description:30}) → {formatted}")
    
    print("\n✅ Time formatting test completed!")
    print()

def test_progress_display():
    """Test the chunked training progress display."""
    
    # Simulate training parameters
    total_epochs = 3
    total_chunks = 4
    total_samples = 10000
    batch_size = 64
    
    # Initialize progress display
    progress_display = ChunkedTrainingProgressDisplay(
        total_epochs=total_epochs,
        total_chunks=total_chunks,
        total_samples=total_samples
    )
    
    print("🧪 Testing Chunked Training Progress Display")
    print("=" * 60)
    
    # Simulate training loop
    for epoch in range(total_epochs):
        # Calculate batches per epoch
        samples_per_chunk = total_samples // total_chunks
        batches_per_chunk = (samples_per_chunk + batch_size - 1) // batch_size
        total_batches_epoch = batches_per_chunk * total_chunks
        
        # Start epoch
        progress_display.start_epoch(epoch, total_batches_epoch)
        
        epoch_loss = 0.0
        
        # Process chunks
        for chunk_id in range(total_chunks):
            chunk_samples = samples_per_chunk
            estimated_memory_mb = chunk_samples * 8 / 1024  # Rough estimate
            
            # Start chunk
            progress_display.start_chunk(chunk_id, chunk_samples, estimated_memory_mb)
            
            chunk_loss = 0.0
            
            # Process batches in chunk
            for batch_idx in range(batches_per_chunk):
                # Simulate batch processing time
                time.sleep(0.1)
                
                # Simulate decreasing loss
                batch_loss = max(0.1, 2.0 - epoch * 0.5 - batch_idx * 0.01)
                chunk_loss += batch_loss
                
                # Update progress
                progress_display.update_batch_progress(
                    batch_idx, batches_per_chunk, batch_loss, batch_size
                )
            
            # Complete chunk
            avg_chunk_loss = chunk_loss / batches_per_chunk
            progress_display.complete_chunk(avg_chunk_loss)
            epoch_loss += avg_chunk_loss
            
            # Small delay between chunks
            time.sleep(0.2)
        
        # Complete epoch
        avg_epoch_loss = epoch_loss / total_chunks
        progress_display.complete_epoch(avg_epoch_loss)
        
        # Small delay between epochs
        time.sleep(0.5)
    
    # Complete training
    final_stats = {
        'epochs_completed': total_epochs,
        'chunks_processed': total_epochs * total_chunks,
        'samples_processed': total_epochs * total_samples,
        'training_time': 0  # Will be calculated by progress display
    }
    
    progress_display.complete_training(final_stats)
    
    print("\n✅ Progress display test completed!")


if __name__ == '__main__':
    try:
        # Test time formatting first
        test_time_formatting()
        
        # Then test progress display
        test_progress_display()
    except KeyboardInterrupt:
        print("\n\n⏹️  Test interrupted by user")
        sys.exit(0)
    except Exception as e:
        print(f"\n❌ Test failed: {e}")
        sys.exit(1)
