#!/usr/bin/env python3

"""
Example of how to create training data from Nine Men's Morris C++ engine.

This script demonstrates how to:
1. Generate FEN strings from the C++ engine
2. Add evaluation and result data
3. Create training data files
"""

import os
import random
from data_loader import parse_mill_fen
from features_mill import cpp_square_to_feature_index


def create_sample_fen_from_cpp_format():
    """
    Create sample FEN strings that match the C++ Position::fen() format.
    
    In practice, these would come from actual games played by the C++ engine
    with NNUE_GENERATE_TRAINING_DATA enabled.
    """
    
    sample_fens = [
        # Game start - placing phase
        "O*O*O***/*******/*******/ w p p 3 6 0 9 0 0 0 0 0 0 0 0 1",
        
        # Mid placing phase with both colors
        "O@O*O@**/*******/*******/ b p p 3 6 2 7 0 0 0 0 0 0 0 0 2",
        
        # End of placing phase
        "O@O@O@O@/O@O@O@O@/*******/ w m s 8 1 8 1 0 0 0 0 0 0 0 0 16",
        
        # Moving phase
        "O@O@O@*@/O@O@O@*@/*******/ b m s 7 0 8 0 0 0 0 0 0 0 0 0 17",
        
        # Mill formation - removal needed
        "O@O@OOO@/*@O@O@*@/*******/ w m r 7 0 7 0 1 0 0 0 0 0 0 0 18",
        
        # Three pieces endgame
        "O*****@*/***O***/*@*****/ w m s 2 0 2 0 0 0 0 0 0 0 0 0 45",
    ]
    
    return sample_fens


def add_evaluation_data(fen, position_index):
    """
    Add evaluation and training data to a FEN string.
    
    In practice, this would come from:
    1. Engine analysis (bestvalue from search)
    2. Game results (win/loss/draw)
    3. Best moves from engine
    """
    
    # Parse the position to understand the game state
    pos = parse_mill_fen(fen)
    
    # Simulate evaluation based on material and position
    material_diff = len(pos.white_pieces) - len(pos.black_pieces)
    hand_diff = pos.white_in_hand - pos.black_in_hand
    
    # Simple evaluation heuristic (in practice, use engine evaluation)
    evaluation = material_diff * 50 + hand_diff * 30
    
    # Add some randomness to simulate real engine evaluations
    evaluation += random.randint(-20, 20)
    
    # Simulate best move (in practice, from engine search)
    if pos.phase == 1:  # placing
        best_move = "a1"  # Placeholder for place move
    else:  # moving
        best_move = "a1-b2"  # Placeholder for regular move
    
    # Simulate game result (in practice, from actual game outcome)
    if evaluation > 50:
        result = 1.0  # white wins
    elif evaluation < -50:
        result = -1.0  # black wins
    else:
        result = 0.0  # draw
    
    return f"{fen} {evaluation} {best_move} {result}"


def create_training_data_file(filename, num_positions=1000):
    """Create a complete training data file."""
    
    print(f"Creating training data file: {filename}")
    print(f"Generating {num_positions} positions...")
    
    sample_fens = create_sample_fen_from_cpp_format()
    
    with open(filename, 'w', encoding='utf-8') as f:
        # Write header
        f.write("# Nine Men's Morris NNUE Training Data\n")
        f.write("# Generated from C++ engine compatible FEN format\n")
        f.write("# Format: FEN EVALUATION BEST_MOVE RESULT\n")
        f.write("#\n")
        
        # Generate training positions
        for i in range(num_positions):
            # Use sample FENs as templates (in practice, collect from actual games)
            base_fen = random.choice(sample_fens)
            
            # Add evaluation data
            training_line = add_evaluation_data(base_fen, i)
            
            f.write(training_line + "\n")
    
    print(f"✅ Training data file created: {filename}")
    
    # Validate the created file
    print("Validating created file...")
    valid_count = 0
    with open(filename, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                try:
                    parts = line.split()
                    if len(parts) >= 19:  # FEN (15) + eval + move + result
                        fen_part = ' '.join(parts[:15])
                        pos = parse_mill_fen(fen_part)
                        valid_count += 1
                except:
                    continue
    
    print(f"✅ Validated {valid_count} positions in {filename}")


def demonstrate_cpp_integration():
    """Demonstrate integration with C++ engine FEN output."""
    
    print("\nDemonstrating C++ engine integration:")
    print("=" * 40)
    
    # Example of how to collect training data from C++ engine:
    print("""
To collect training data from the C++ engine:

1. Compile with NNUE_GENERATE_TRAINING_DATA flag:
   - Add #define NNUE_GENERATE_TRAINING_DATA to config.h
   
2. The engine will automatically generate training data during play:
   - Position FEN strings (via Position::nnueGenerateTrainingFen())
   - Best move evaluations (via nnueTrainingDataBestValue)
   - Game results (via nnueTrainingDataGameResult)
   
3. Training data is written to files in data/ directory:
   - Format: "FEN evaluation best_move result"
   - Files named: training-data_[timestamp].txt
   
4. Use convert_training_data.py to process and validate:
   python convert_training_data.py validate --input training_data.txt
   
5. Train the network:
   python train.py training_data.txt --features "NineMill"
    """)


def main():
    """Main demonstration."""
    print("Nine Men's Morris Training Data Creation Example")
    print("=" * 55)
    
    # Set seed for reproducible examples
    random.seed(42)
    
    # Create sample training data
    create_training_data_file("sample_mill_training.txt", 100)
    
    # Demonstrate C++ integration
    demonstrate_cpp_integration()
    
    print("\n" + "=" * 55)
    print("Example completed! Check sample_mill_training.txt")
    print("\nNext steps:")
    print("1. Collect real training data from C++ engine games")
    print("2. Run: python train.py sample_mill_training.txt --features NineMill")


if __name__ == "__main__":
    main()
