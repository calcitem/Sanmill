#!/usr/bin/env python3
"""
Perfect Database Training Data Generation Script for NNUE PyTorch

This script provides a convenient interface for generating NNUE training data
using the Perfect Database with support for 16-fold symmetry augmentation.

Usage:
    python scripts/generate_perfect_db_data.py --perfect-db /path/to/database --output training_data.txt
    python scripts/generate_perfect_db_data.py --perfect-db /path/to/database --positions 50000 --symmetries
"""

import os
import sys
import argparse
import time
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

def main():
    """Main function for Perfect DB data generation."""
    parser = argparse.ArgumentParser(
        description='Generate NNUE training data using Perfect Database',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Quick test with small dataset
  python scripts/generate_perfect_db_data.py --perfect-db /path/to/db --positions 1000
  
  # Production dataset with symmetries
  python scripts/generate_perfect_db_data.py --perfect-db /path/to/db --positions 50000 --symmetries
  
  # Large dataset for comprehensive training
  python scripts/generate_perfect_db_data.py --perfect-db /path/to/db --positions 100000 --output large_training_data.txt
        """
    )
    
    parser.add_argument('--perfect-db', 
                       default='E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted',
                       help='Path to Perfect Database directory (default: E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted)')
    parser.add_argument('--output', default='perfect_db_training_data.txt',
                       help='Output training data file (default: perfect_db_training_data.txt)')
    parser.add_argument('--positions', type=int, default=10000,
                       help='Number of base positions to generate (default: 10000)')
    parser.add_argument('--symmetries', action='store_true',
                       help='Include all 16 symmetry transformations (16x more data)')
    parser.add_argument('--batch-size', type=int, default=1000,
                       help='Batch size for processing (default: 1000)')
    parser.add_argument('--seed', type=int, default=42,
                       help='Random seed for reproducible generation (default: 42)')
    parser.add_argument('--validate', action='store_true',
                       help='Validate Perfect Database installation first')
    parser.add_argument('--quick-test', action='store_true',
                       help='Run quick test with 100 positions')
    
    args = parser.parse_args()
    
    print("Perfect Database Training Data Generator for NNUE PyTorch")
    print("=" * 65)
    
    # Quick test mode
    if args.quick_test:
        args.positions = 100
        args.output = "quick_test_data.txt"
        print("🔬 Quick test mode: generating 100 positions")
    
    # Validate Perfect Database
    if not os.path.exists(args.perfect_db):
        print(f"❌ Perfect Database path not found: {args.perfect_db}")
        return 1
    
    sec2_files = list(Path(args.perfect_db).glob("*.sec2"))
    if not sec2_files:
        print(f"❌ No .sec2 files found in: {args.perfect_db}")
        return 1
    
    print(f"✅ Perfect Database found: {len(sec2_files)} .sec2 files")
    
    # Additional validation if requested
    if args.validate:
        print(f"\n🔍 Running Perfect Database validation...")
        try:
            # Test basic DLL functionality
            sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..', 'perfect'))
            try:
                from perfect_db_reader import PerfectDB
            except ImportError as e:
                print(f"❌ Failed to import Perfect DB reader: {e}")
                return 1
            
            test_db = PerfectDB()
            test_db.init(args.perfect_db)
            print(f"✅ Perfect Database DLL validation successful")
            test_db.deinit()
            
        except Exception as e:
            print(f"❌ Perfect Database validation failed: {e}")
            return 1
    
    # Generate training data
    print(f"\n📊 Starting training data generation...")
    print(f"  Perfect Database: {args.perfect_db}")
    print(f"  Output file: {args.output}")
    print(f"  Base positions: {args.positions:,}")
    print(f"  Symmetries: {'enabled' if args.symmetries else 'disabled'}")
    
    expected_total = args.positions * (16 if args.symmetries else 1)
    print(f"  Expected total examples: {expected_total:,}")
    
    # Import and run generator
    from generate_training_data import PerfectDBTrainingDataGenerator
    
    generator = PerfectDBTrainingDataGenerator(args.perfect_db)
    
    start_time = time.time()
    success = generator.generate_training_data(
        num_positions=args.positions,
        output_file=args.output,
        use_symmetries=args.symmetries,
        batch_size=args.batch_size
    )
    
    if success:
        elapsed_time = time.time() - start_time
        print(f"\n✅ Training data generation completed in {elapsed_time:.2f} seconds")
        
        # Validate output file
        if os.path.exists(args.output):
            file_size = os.path.getsize(args.output) / (1024 * 1024)  # MB
            print(f"📁 Output file: {args.output} ({file_size:.1f} MB)")
            
            # Count lines
            with open(args.output, 'r') as f:
                line_count = sum(1 for line in f if not line.startswith('#'))
            print(f"📊 Total training examples: {line_count:,}")
            
            # Performance metrics
            positions_per_second = line_count / elapsed_time
            print(f"⚡ Generation speed: {positions_per_second:.0f} examples/second")
        
        # Show next steps
        print(f"\n🎯 Next steps:")
        print(f"  1. Validate the generated data:")
        print(f"     python example_perfect_db_training.py --perfect-db {args.perfect_db} --validate-only")
        print(f"  2. Train NNUE model:")
        print(f"     python train.py {args.output} --features NineMill --batch-size 8192")
        print(f"  3. Train with factorized features:")
        print(f"     python train.py {args.output} --features NineMill^ --batch-size 8192")
        
        return 0
    else:
        print(f"❌ Training data generation failed")
        return 1


if __name__ == '__main__':
    sys.exit(main())
