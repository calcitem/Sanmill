#!/usr/bin/env python3
"""
Example script demonstrating Perfect Database integration for NNUE PyTorch training.

This script shows how to:
1. Generate training data using Perfect Database
2. Load and validate the generated data
3. Train an NNUE model with Perfect DB data
4. Use 16-fold symmetry augmentation

Usage:
    python example_perfect_db_training.py --perfect-db /path/to/database
    python example_perfect_db_training.py --perfect-db /path/to/database --symmetries --train
"""

import argparse
import os
import sys
import time
from pathlib import Path

def generate_sample_training_data(perfect_db_path: str, output_file: str, 
                                num_positions: int = 1000, use_symmetries: bool = False):
    """Generate sample training data using Perfect Database."""
    
    print(f"Generating {num_positions} training positions...")
    print(f"Perfect Database: {perfect_db_path}")
    print(f"Symmetries: {'enabled' if use_symmetries else 'disabled'}")
    print(f"Expected total examples: {num_positions * (16 if use_symmetries else 1):,}")
    
    # Import the generator
    from generate_training_data import PerfectDBTrainingDataGenerator
    
    generator = PerfectDBTrainingDataGenerator(perfect_db_path)
    
    start_time = time.time()
    success = generator.generate_training_data(
        num_positions=num_positions,
        output_file=output_file,
        use_symmetries=use_symmetries,
        batch_size=500
    )
    
    if success:
        elapsed_time = time.time() - start_time
        print(f"✅ Training data generation completed in {elapsed_time:.2f} seconds")
        
        # Validate output
        if os.path.exists(output_file):
            file_size = os.path.getsize(output_file) / (1024 * 1024)  # MB
            print(f"📁 Output file: {output_file} ({file_size:.1f} MB)")
            
            # Count training examples
            with open(output_file, 'r') as f:
                line_count = sum(1 for line in f if not line.startswith('#'))
            print(f"📊 Total training examples: {line_count:,}")
            
        return True
    else:
        print("❌ Training data generation failed")
        return False


def validate_training_data(data_file: str):
    """Validate the generated training data."""
    
    print(f"\n🔍 Validating training data: {data_file}")
    
    # Import data loader
    from data_loader import load_perfect_db_training_data
    
    try:
        # Load a sample of positions
        positions = load_perfect_db_training_data([data_file], max_positions=100)
        
        if not positions:
            print("❌ No positions loaded")
            return False
        
        print(f"✅ Successfully loaded {len(positions)} sample positions")
        
        # Analyze data distribution
        phases = {}
        evaluations = []
        
        for pos in positions:
            phase = pos.phase
            phases[phase] = phases.get(phase, 0) + 1
            evaluations.append(pos.evaluation)
        
        print(f"\n📊 Data Analysis:")
        print(f"  Phase distribution: {phases}")
        print(f"  Evaluation range: [{min(evaluations):.2f}, {max(evaluations):.2f}]")
        print(f"  Average evaluation: {sum(evaluations) / len(evaluations):.2f}")
        
        # Test feature extraction
        from features_mill import NineMillFeatures
        feature_set = NineMillFeatures()
        
        sample_pos = positions[0]
        board_state = {
            'white_pieces': sample_pos.white_pieces,
            'black_pieces': sample_pos.black_pieces,
            'side_to_move': 'white' if sample_pos.side_to_move == 0 else 'black'
        }
        
        white_features, black_features = feature_set.get_active_features(board_state)
        import torch
        print(f"  Feature extraction: {torch.sum(white_features)} white, {torch.sum(black_features)} black features")
        
        return True
        
    except Exception as e:
        print(f"❌ Validation failed: {e}")
        return False


def run_sample_training(data_file: str):
    """Run a sample training session with Perfect DB data."""
    
    print(f"\n🚀 Running sample NNUE training with Perfect DB data...")
    
    try:
        # Import training components
        import torch
        from features_mill import NineMillFeatures
        from data_loader import create_perfect_db_data_loader
        import model as M
        
        # Create feature set
        feature_set = NineMillFeatures()
        
        # Create data loaders
        train_loader = create_perfect_db_data_loader(
            [data_file],
            feature_set,
            batch_size=64,  # Small batch for demo
            shuffle=True
        )
        
        val_loader = create_perfect_db_data_loader(
            [data_file],
            feature_set, 
            batch_size=64,
            shuffle=False,
            max_positions=100  # Small validation set
        )
        
        print(f"✅ Data loaders created")
        print(f"  Training batches: {len(train_loader)}")
        print(f"  Validation batches: {len(val_loader)}")
        
        # Test loading a batch
        print(f"\n🔬 Testing batch loading...")
        for batch in train_loader:
            print(f"  Batch size: {len(batch[0])}")
            print(f"  White features shape: {batch[2].shape}")
            print(f"  Black features shape: {batch[4].shape}")
            print(f"  Evaluations range: [{torch.min(batch[7]):.2f}, {torch.max(batch[7]):.2f}]")
            break
        
        print(f"✅ Sample training data validation successful!")
        
        # Note: Full training would require more setup (model, optimizer, etc.)
        print(f"\n💡 To run full training:")
        print(f"   python train.py {data_file} --features NineMill --batch-size 8192 --max_epochs 100")
        
        return True
        
    except Exception as e:
        print(f"❌ Sample training failed: {e}")
        return False


def main():
    """Main function for demonstration."""
    parser = argparse.ArgumentParser(
        description='Perfect Database integration example for NNUE PyTorch',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Generate sample training data
  python example_perfect_db_training.py --perfect-db /path/to/database
  
  # Generate with symmetries and run training test
  python example_perfect_db_training.py --perfect-db /path/to/database --symmetries --train
  
  # Generate larger dataset
  python example_perfect_db_training.py --perfect-db /path/to/database --positions 10000
        """
    )
    
    parser.add_argument('--perfect-db', required=True,
                       help='Path to Perfect Database directory')
    parser.add_argument('--output', default='example_training_data.txt',
                       help='Output training data file (default: example_training_data.txt)')
    parser.add_argument('--positions', type=int, default=1000,
                       help='Number of base positions to generate (default: 1000)')
    parser.add_argument('--symmetries', action='store_true',
                       help='Include all 16 symmetry transformations')
    parser.add_argument('--train', action='store_true',
                       help='Run sample training after data generation')
    parser.add_argument('--validate-only', action='store_true',
                       help='Only validate existing training data file')
    
    args = parser.parse_args()
    
    print("Perfect Database Integration Example for NNUE PyTorch")
    print("=" * 60)
    
    # Validate Perfect Database path
    if not os.path.exists(args.perfect_db):
        print(f"❌ Perfect Database path not found: {args.perfect_db}")
        return 1
    
    # Check for .sec2 files
    sec2_files = list(Path(args.perfect_db).glob("*.sec2"))
    if not sec2_files:
        print(f"❌ No .sec2 files found in: {args.perfect_db}")
        return 1
    
    print(f"✅ Perfect Database validated: {len(sec2_files)} .sec2 files found")
    
    # Validate existing data if requested
    if args.validate_only:
        if not os.path.exists(args.output):
            print(f"❌ Training data file not found: {args.output}")
            return 1
        
        if not validate_training_data(args.output):
            return 1
        
        if args.train:
            if not run_sample_training(args.output):
                return 1
        
        return 0
    
    # Generate training data
    print(f"\n📊 Generating training data...")
    if not generate_sample_training_data(
        args.perfect_db, 
        args.output, 
        args.positions, 
        args.symmetries
    ):
        return 1
    
    # Validate generated data
    if not validate_training_data(args.output):
        return 1
    
    # Run sample training if requested
    if args.train:
        if not run_sample_training(args.output):
            return 1
    
    print(f"\n🎉 Perfect Database integration example completed successfully!")
    print(f"\n📋 Next steps:")
    print(f"  1. Generate larger training dataset:")
    print(f"     python generate_training_data.py --perfect-db {args.perfect_db} --positions 50000 --output full_training_data.txt")
    print(f"  2. Train NNUE model:")
    print(f"     python train.py full_training_data.txt --features NineMill --batch-size 8192")
    print(f"  3. Use symmetries for data augmentation:")
    print(f"     python generate_training_data.py --perfect-db {args.perfect_db} --positions 10000 --symmetries --output augmented_data.txt")
    
    return 0


if __name__ == '__main__':
    sys.exit(main())
