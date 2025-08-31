#!/usr/bin/env python3
"""
Nine Men's Morris Alpha Zero Trainer

Main script for Alpha Zero training - the only entry point needed for training.
"""

import sys
import os

def setup_environment():
    """Set up the environment and paths."""
    current_dir = os.path.dirname(os.path.abspath(__file__))
    parent_dir = os.path.dirname(current_dir)
    game_dir = os.path.join(parent_dir, 'game')

    # Add necessary paths
    for path in [current_dir, parent_dir, game_dir]:
        if path not in sys.path:
            sys.path.insert(0, path)

def main():
    """Main training function."""
    print("🎮 Nine Men's Morris Alpha Zero Trainer")
    print("=" * 50)

    # Set up environment
    setup_environment()

    try:
        # Import necessary modules
        print("🔄 Loading modules...")
        from config import get_default_config
        from trainer import AlphaZeroTrainer
        print("✅ Modules loaded successfully")

        # Display training options
        print("\n🎯 Training Modes:")
        print("1. Quick Test (1K states) - ~1 minute")
        print("2. Small-scale Training (100K states) - ~10-30 minutes")
        print("3. Medium-scale Training (1M states) - ~30 minutes - 1 hour")
        print("4. Large-scale Training (10M states) - ~1-3 hours")
        print("5. Massive-scale Training (100M states) - ~3-8 hours")
        print("6. Extreme-scale Training (1B states) - ~8-24 hours")
        print("7. Full Enumeration Training (All 13.4 billion+ states) - ~1-7 days")
        print("0. Exit")
        print()
        print("💡 Total Perfect Database states: 13,492,318,233+")
        print("💡 It is recommended to choose a suitable scale based on hardware performance and available time")

        choice = input("\nPlease choose [1-7, 0]: ").strip()

        if choice == "0":
            print("👋 Exiting program")
            return 0

        # Set training parameters
        config = get_default_config()

        if choice == "1":
            print("🚀 Quick Test Mode...")
            config.training.iterations = 0  # Pure supervised learning, no fine-tuning
            config.training.games_per_iteration = 0  # No self-play
            config.training.pretrain_positions = 1000  # Number of supervised learning states from Perfect DB
            config.training.pretrain_epochs = 5  # Fewer epochs for quick test
            config.training.checkpoint_dir = "./checkpoints_quick"
            config.training.complete_sector_enumeration = False  # Default to sampling mode

        elif choice == "2":
            print("🚀 Standard Training Mode...")
            config.training.iterations = 0  # Pure supervised learning, no fine-tuning
            config.training.games_per_iteration = 0  # No self-play
            config.training.pretrain_positions = 100000  # Number of supervised learning states from Perfect DB
            config.training.pretrain_epochs = 10  # Standard epochs
            config.training.checkpoint_dir = "./checkpoints_standard"
            config.training.complete_sector_enumeration = False  # Default to sampling mode

        elif choice == "3":
            print("🚀 Medium-scale Training Mode...")
            config.training.iterations = 0  # Pure supervised learning, no fine-tuning
            config.training.games_per_iteration = 0  # No self-play
            config.training.pretrain_positions = 1000000  # Number of supervised learning states from Perfect DB
            config.training.pretrain_epochs = 15  # More epochs
            config.training.checkpoint_dir = "./checkpoints_medium"
            config.training.complete_sector_enumeration = False  # Default to sampling mode

        elif choice == "4":
            print("🚀 Large-scale Training Mode...")
            config.training.iterations = 0  # Pure supervised learning, no fine-tuning
            config.training.games_per_iteration = 0  # No self-play
            config.training.pretrain_positions = 10000000  # Number of supervised learning states from Perfect DB
            config.training.pretrain_epochs = 20  # Large scale requires more epochs
            config.training.checkpoint_dir = "./checkpoints_large"
            config.training.complete_sector_enumeration = False  # Default to sampling mode

        elif choice == "5":
            print("🚀 Massive-scale Training Mode...")
            config.training.iterations = 0  # Pure supervised learning, no fine-tuning
            config.training.games_per_iteration = 0  # No self-play
            config.training.pretrain_positions = 100000000  # Number of supervised learning states from Perfect DB
            config.training.pretrain_epochs = 30  # Massive scale requires sufficient training
            config.training.checkpoint_dir = "./checkpoints_massive"
            config.training.complete_sector_enumeration = False  # Default to sampling mode

        elif choice == "6":
            print("🚀 Extreme-scale Training Mode...")
            config.training.iterations = 0  # Pure supervised learning, no fine-tuning
            config.training.games_per_iteration = 0  # No self-play
            config.training.pretrain_positions = 1000000000  # Number of supervised learning states from Perfect DB
            config.training.pretrain_epochs = 50  # Extreme scale requires a large number of epochs
            config.training.checkpoint_dir = "./checkpoints_extreme"
            config.training.complete_sector_enumeration = False  # Default to sampling mode

        elif choice == "7":
            print("🚀 Full Enumeration Training Mode...")
            print("⚠️  This will process all 13,492,318,233+ states and may take several days")
            confirm_full = input("Confirm to proceed with full enumeration training? [y/N]: ").strip().lower()
            if confirm_full not in ['y', 'yes']:
                print("❌ Canceled full enumeration training")
                return 0
            config.training.iterations = 0  # Pure supervised learning, no fine-tuning
            config.training.games_per_iteration = 0  # No self-play
            config.training.pretrain_positions = None  # None means full enumeration
            config.training.pretrain_epochs = 100  # Use the most epochs for full enumeration
            config.training.checkpoint_dir = "./checkpoints_complete"

            # Intra-sector full enumeration option
            print("\n🔧 Select Intra-Sector Enumeration Mode:")
            print("1. Sampling Mode (draws 1000 samples per sector, fast)")
            print("2. Full Enumeration (reads all positions sequentially in each sector, most complete)")
            sector_choice = input("Select mode [1/2]: ").strip()

            if sector_choice == "2":
                config.training.complete_sector_enumeration = True
                print("✅ Selected: Intra-sector full enumeration (sequential read of each position)")
                print("⚠️  Note: This will significantly increase processing time")
            else:
                config.training.complete_sector_enumeration = False
                print("✅ Selected: Intra-sector sampling mode (1000 samples per sector)")

        else:
            print("❌ Invalid choice")
            return 1

        # Perfect Database settings
        perfect_db_path = "E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted"
        if os.path.exists(perfect_db_path):
            print(f"✅ Found Perfect Database: {perfect_db_path}")
            config.perfect_db.perfect_db_path = perfect_db_path
            config.perfect_db.use_direct_perfect_db_training = True
        else:
            print("⚠️  Perfect Database not found, using pure self-play mode")
            config.training.pretrain_iterations = 0

        print(f"\n📊 Training Parameters:")
        print(f"   - Number of supervised learning states: {config.training.pretrain_positions}")
        print(f"   - Training mode: Pure supervised learning (no self-play)")
        print(f"   - Checkpoint directory: {config.training.checkpoint_dir}")

        # Confirm start
        confirm = input("\nStart training? [y/N]: ").strip().lower()
        if confirm not in ['y', 'yes']:
            print("❌ Training canceled")
            return 0

        print("\n🚀 Starting Alpha Zero training...")

        # Convert config to the format expected by the trainer
        trainer_config = config.to_dict()

        # Add Perfect Database config to the top level
        if hasattr(config, 'perfect_db') and config.perfect_db.perfect_db_path:
            trainer_config['perfect_db_path'] = config.perfect_db.perfect_db_path
            trainer_config['use_direct_perfect_db_training'] = config.perfect_db.use_direct_perfect_db_training
            trainer_config['use_pretraining'] = True
            trainer_config['pretrain_positions'] = config.training.pretrain_positions

            # Add intra-sector full enumeration config
            trainer_config['complete_sector_enumeration'] = getattr(config.training, 'complete_sector_enumeration', False)

            print(f"📊 Perfect Database Configuration:")
            print(f"   - Database path: {trainer_config['perfect_db_path']}")
            print(f"   - Direct training mode: {trainer_config['use_direct_perfect_db_training']}")
            print(f"   - Number of pre-training states: {trainer_config['pretrain_positions'] or 'All (13.4 billion+)'}")
            print(f"   - Intra-sector enumeration: {'Full Enumeration' if trainer_config.get('complete_sector_enumeration', False) else 'Sampling Mode'}")
            print()
            print("💡 Hint: Perfect Database supervised learning phase")
            print("   - Reading optimal board states from the perfect database")
            print("   - Each state contains the optimal move and win/loss evaluation")
            print("   - The first file may take a long time to process, please be patient")
            print("   - A single file can contain millions of unique board states")
            print("   - This is pure supervised learning and does not involve self-play")

        trainer = AlphaZeroTrainer(trainer_config)
        trainer.train(num_iterations=config.training.iterations)

        print("\n🎉 Training complete!")
        print(f"📁 Checkpoints saved in: {config.training.checkpoint_dir}")

    except KeyboardInterrupt:
        print("\n⚠️  Training interrupted by user")
        return 0

    except Exception as e:
        print(f"\n❌ Training failed: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0

if __name__ == "__main__":
    try:
        exit_code = main()
    except Exception as e:
        print(f"Fatal error: {e}")
        exit_code = 1

    print("\nPress any key to exit...")
    input()
    sys.exit(exit_code)
