#!/usr/bin/env python3
"""
Demo script showing progress tracking features.
"""

import time
import random
from .progress import ProgressTracker, TrainingProgressTracker, SelfPlayProgressTracker

def demo_basic_progress():
    """Demonstrate basic progress tracking."""
    print("=== Basic Progress Tracker Demo ===")
    
    tracker = ProgressTracker(100, "Processing items")
    
    for i in range(100):
        # Simulate work with variable time
        time.sleep(random.uniform(0.01, 0.05))
        tracker.update(1, item=f"item_{i}")
    
    tracker.close()
    print()

def demo_training_progress():
    """Demonstrate training progress tracking."""
    print("=== Training Progress Tracker Demo ===")
    
    epochs = 5
    batches_per_epoch = 20
    
    tracker = TrainingProgressTracker(epochs, batches_per_epoch)
    
    for epoch in range(1, epochs + 1):
        tracker.start_epoch(epoch)
        
        for batch in range(batches_per_epoch):
            # Simulate training
            time.sleep(0.02)
            loss = 1.0 - (epoch * batches_per_epoch + batch) * 0.01
            tracker.update_batch(loss, lr=f"{0.001 * 0.9**epoch:.4f}")
        
        # Simulate validation
        val_loss = loss * 0.9 + random.uniform(-0.1, 0.1)
        tracker.end_epoch(loss, val_loss)
    
    tracker.close()
    print()

def demo_selfplay_progress():
    """Demonstrate self-play progress tracking."""
    print("=== Self-Play Progress Tracker Demo ===")
    
    games = 50
    mcts_sims = 400
    
    tracker = SelfPlayProgressTracker(games, mcts_sims)
    
    for game in range(games):
        # Simulate game
        time.sleep(0.05)
        
        # Random game outcome
        outcome = random.choice(['white_wins', 'black_wins', 'draws'])
        samples = random.randint(20, 80)
        moves = random.randint(15, 60)
        
        tracker.update_game(samples, moves, outcome)
    
    tracker.close()
    print()

def main():
    """Run all demos."""
    print("Katamill Progress Tracking Demo")
    print("=" * 40)
    
    demo_basic_progress()
    demo_training_progress()
    demo_selfplay_progress()
    
    print("Demo completed!")

if __name__ == '__main__':
    main()
