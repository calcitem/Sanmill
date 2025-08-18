import torch
import numpy as np
from torch.utils.data import Dataset, DataLoader
import struct
import os
import random
from typing import List, Dict, Tuple, Optional


class MillPosition:
    """
    Represents a Nine Men's Morris position for training data.
    """
    
    def __init__(self):
        self.white_pieces = []  # List of positions (0-23) with white pieces
        self.black_pieces = []  # List of positions (0-23) with black pieces
        self.side_to_move = 0   # 0 for white, 1 for black
        self.phase = 0          # 0 for placing, 1 for moving
        self.white_in_hand = 9  # Number of white pieces in hand
        self.black_in_hand = 9  # Number of black pieces in hand
        self.evaluation = 0.0   # Position evaluation
        self.game_result = 0.0  # Game result (-1, 0, 1)
        self.best_move = None   # Best move in the position


def parse_mill_fen(fen_string: str) -> MillPosition:
    """
    Parse a Nine Men's Morris FEN string into a MillPosition object.
    
    FEN format matches C++ Position class format:
    "board_state side phase action white_on_board white_in_hand black_on_board black_in_hand 
     white_to_remove black_to_remove white_mill_from white_mill_to black_mill_from black_mill_to 
     mills_bitmask rule50 fullmove"
    """
    pos = MillPosition()
    parts = fen_string.split()
    
    if len(parts) < 13:  # Need at least 13 parts for basic FEN
        return pos
    
    # 1. Parse board state - matches C++ Position::set()
    board_state = parts[0]
    
    # C++ parses character by character, starting from SQ_A1 = 8
    # Remove '/' separators and parse sequentially
    board_chars = board_state.replace('/', '')
    
    cpp_square = 8  # Start from SQ_A1 = 8 (SQ_BEGIN)
    for piece_char in board_chars:
        if piece_char == 'O':
            # White piece - convert C++ square to feature index
            feature_pos = cpp_square - 8
            pos.white_pieces.append(feature_pos)
        elif piece_char == '@':
            # Black piece - convert C++ square to feature index
            feature_pos = cpp_square - 8
            pos.black_pieces.append(feature_pos)
        # '*' = empty, 'X' = marked (ignored for training)
        
        cpp_square += 1
        if cpp_square >= 32:  # SQ_END = 32
            break
    
    # 2. Active color
    pos.side_to_move = 0 if parts[1] == 'w' else 1
    
    # 3. Phase
    phase_char = parts[2]
    if phase_char == 'r':
        pos.phase = 0  # ready
    elif phase_char == 'p':
        pos.phase = 1  # placing
    elif phase_char == 'm':
        pos.phase = 2  # moving
    elif phase_char == 'o':
        pos.phase = 3  # gameOver
    else:
        pos.phase = 0  # none
    
    # 4. Action (skip for training data)
    
    # 5. Piece counts - matches C++ format
    try:
        white_on_board = int(parts[4])
        pos.white_in_hand = int(parts[5])
        black_on_board = int(parts[6])
        pos.black_in_hand = int(parts[7])
        # parts[8-11] are removal counts and mill positions
        # parts[12] is mills bitmask
        # parts[13] is rule50
        # parts[14] is fullmove
    except (IndexError, ValueError):
        # Fallback calculation
        pos.white_in_hand = max(0, 9 - len(pos.white_pieces))
        pos.black_in_hand = max(0, 9 - len(pos.black_pieces))
    
    return pos


class MillTrainingDataset(Dataset):
    """
    Dataset for Nine Men's Morris training data.
    """
    
    def __init__(self, data_files: List[str], feature_set, max_positions: Optional[int] = None):
        self.feature_set = feature_set
        self.positions = []
        self.evaluations = []
        self.results = []
        
        # Load training data from files
        total_loaded = 0
        for file_path in data_files:
            if max_positions and total_loaded >= max_positions:
                break
                
            positions_from_file = self._load_from_file(file_path, max_positions - total_loaded if max_positions else None)
            total_loaded += len(positions_from_file)
            
        print(f"Loaded {len(self.positions)} training positions")
    
    def _load_from_file(self, file_path: str, max_count: Optional[int] = None) -> List[MillPosition]:
        """Load training data from a single file."""
        positions = []
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f):
                    if max_count and len(positions) >= max_count:
                        break
                        
                    line = line.strip()
                    if not line or line.startswith('#'):
                        continue
                    
                    try:
                        # Expected format: "FEN evaluation best_move result"
                        # where FEN contains spaces, so we parse from the end
                        parts = line.split()
                        if len(parts) < 4:
                            continue
                        
                        # Parse from end: result, best_move, evaluation
                        result = float(parts[-1])
                        best_move = parts[-2]
                        evaluation = float(parts[-3])
                        
                        # Remaining parts form the FEN string
                        fen_parts = parts[:-3]
                        fen = ' '.join(fen_parts)
                        
                        pos = parse_mill_fen(fen)
                        pos.evaluation = evaluation
                        pos.best_move = best_move
                        pos.game_result = result
                        
                        positions.append(pos)
                        self.positions.append(pos)
                        self.evaluations.append(evaluation)
                        self.results.append(result)
                        
                    except (ValueError, IndexError) as e:
                        print(f"Error parsing line {line_num + 1} in {file_path}: {e}")
                        continue
                        
        except FileNotFoundError:
            print(f"Warning: Training data file not found: {file_path}")
        except Exception as e:
            print(f"Error loading training data from {file_path}: {e}")
            
        return positions
    
    def __len__(self):
        return len(self.positions)
    
    def __getitem__(self, idx):
        """Get a training sample."""
        pos = self.positions[idx]
        
        # Convert position to feature representation
        board_state = {
            'white_pieces': pos.white_pieces,
            'black_pieces': pos.black_pieces,
            'side_to_move': 'white' if pos.side_to_move == 0 else 'black'
        }
        
        # Get features from feature set
        white_features, black_features = self.feature_set.get_active_features(board_state)
        
        # Convert to sparse representation
        white_indices = torch.nonzero(white_features, as_tuple=False).flatten()
        white_values = white_features[white_indices]
        black_indices = torch.nonzero(black_features, as_tuple=False).flatten()
        black_values = black_features[black_indices]
        
        # Side to move indicators
        us = torch.tensor([1.0 if pos.side_to_move == 0 else 0.0], dtype=torch.float32)
        them = torch.tensor([1.0 if pos.side_to_move == 1 else 0.0], dtype=torch.float32)
        
        # PSQT and layer stack indices (simplified for Nine Men's Morris)
        psqt_indices = torch.tensor(0, dtype=torch.long)  # Single bucket for now
        layer_stack_indices = torch.tensor(0, dtype=torch.long)  # Single bucket for now
        
        # Target values
        evaluation = torch.tensor(pos.evaluation, dtype=torch.float32)
        result = torch.tensor(pos.game_result, dtype=torch.float32)
        
        return {
            'us': us,
            'them': them,
            'white_indices': white_indices.long(),
            'white_values': white_values.float(),
            'black_indices': black_indices.long(), 
            'black_values': black_values.float(),
            'psqt_indices': psqt_indices,
            'layer_stack_indices': layer_stack_indices,
            'evaluation': evaluation,
            'result': result
        }


def collate_mill_batch(batch):
    """
    Custom collate function for Nine Men's Morris training batches.
    """
    batch_size = len(batch)
    
    # Collect all tensors
    us = torch.stack([item['us'] for item in batch])
    them = torch.stack([item['them'] for item in batch])
    evaluations = torch.stack([item['evaluation'] for item in batch])
    results = torch.stack([item['result'] for item in batch])
    psqt_indices = torch.stack([item['psqt_indices'] for item in batch])
    layer_stack_indices = torch.stack([item['layer_stack_indices'] for item in batch])
    
    # Handle variable-length sparse features
    max_white_features = max(len(item['white_indices']) for item in batch)
    max_black_features = max(len(item['black_indices']) for item in batch)
    
    # Pad sparse features
    white_indices = torch.zeros((batch_size, max_white_features), dtype=torch.long)
    white_values = torch.zeros((batch_size, max_white_features), dtype=torch.float32)
    black_indices = torch.zeros((batch_size, max_black_features), dtype=torch.long)
    black_values = torch.zeros((batch_size, max_black_features), dtype=torch.float32)
    
    for i, item in enumerate(batch):
        w_len = len(item['white_indices'])
        b_len = len(item['black_indices'])
        
        if w_len > 0:
            white_indices[i, :w_len] = item['white_indices']
            white_values[i, :w_len] = item['white_values']
            
        if b_len > 0:
            black_indices[i, :b_len] = item['black_indices']
            black_values[i, :b_len] = item['black_values']
    
    # Return tuple format expected by NNUE model
    # (us, them, white_indices, white_values, black_indices, black_values,
    #  outcome, score, psqt_indices, layer_stack_indices)
    return (
        us,
        them,
        white_indices.int(),  # Convert to int32 for C++ compatibility
        white_values,
        black_indices.int(),  # Convert to int32 for C++ compatibility  
        black_values,
        results,  # outcome
        evaluations,  # score
        psqt_indices,
        layer_stack_indices
    )


def create_mill_data_loader(data_files: List[str], feature_set, batch_size: int = 16384, 
                           max_positions: Optional[int] = None, shuffle: bool = True, 
                           num_workers: int = 0) -> DataLoader:
    """
    Create a DataLoader for Nine Men's Morris training data.
    
    Args:
        data_files: List of training data file paths
        feature_set: Feature set to use for encoding positions
        batch_size: Batch size for training
        max_positions: Maximum number of positions to load (None for all)
        shuffle: Whether to shuffle the data
        num_workers: Number of worker processes for data loading
        
    Returns:
        DataLoader instance
    """
    dataset = MillTrainingDataset(data_files, feature_set, max_positions)
    
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=shuffle,
        collate_fn=collate_mill_batch,
        num_workers=num_workers,
        pin_memory=True
    )


# Example usage and testing
if __name__ == "__main__":
    # Test the data loader with dummy data
    from features_mill import NineMillFeatures
    
    # Create a dummy training data file for testing
    test_data = [
        "*/O/O/O/O/O/O/O/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/O w p p 6 3 0 9 0 0 0 0 0 100 1 1.0",
        "O/@/O/@/O/@/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/*/@ b m s 6 0 6 0 0 0 0 0 0 150 2 0.0",
    ]
    
    os.makedirs("test_data", exist_ok=True)
    with open("test_data/test.txt", "w") as f:
        for line in test_data:
            f.write(line + "\n")
    
    # Create feature set and data loader
    feature_set = NineMillFeatures()
    data_loader = create_mill_data_loader(
        ["test_data/test.txt"], 
        feature_set, 
        batch_size=2
    )
    
    # Test loading a batch
    for batch in data_loader:
        print("Batch keys:", batch.keys())
        print("Batch size:", len(batch['us']))
        print("White indices shape:", batch['white_indices'].shape)
        print("Black indices shape:", batch['black_indices'].shape)
        break
    
    # Cleanup
    import shutil
    shutil.rmtree("test_data")
    print("Test completed successfully!")
