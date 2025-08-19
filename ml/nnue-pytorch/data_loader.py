import torch
import numpy as np
from torch.utils.data import Dataset, DataLoader
import struct
import os
import random
import sys
from typing import List, Dict, Tuple, Optional

# Add paths for importing from ml/perfect
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'perfect'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'game'))


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
    
    Supports both Perfect DB generated format and C++ Position class format:
    - Perfect DB format: "FEN evaluation best_move result"
    - C++ format: "board_state side phase action white_on_board white_in_hand black_on_board black_in_hand 
                   white_to_remove black_to_remove white_mill_from white_mill_to black_mill_from black_mill_to 
                   mills_bitmask rule50 fullmove"
    """
    pos = MillPosition()
    parts = fen_string.split()
    
    if len(parts) < 13:  # Need at least 13 parts for basic FEN
        return pos
    
    # 1. Parse board state - matches C++ Position::set()
    board_state = parts[0]
    
    # Handle both formats: with and without '/' separators
    if '/' in board_state:
        # Format with separators (Perfect DB generated)
        board_chars = board_state.replace('/', '')
    else:
        # Format without separators (legacy)
        board_chars = board_state
    
    # Parse board positions
    # Convert C++ square indices (8-31) to feature indices (0-23)
    for i, piece_char in enumerate(board_chars):
        if i >= 24:  # Only process first 24 positions
            break
            
        if piece_char == 'O':
            # White piece - direct feature index mapping
            pos.white_pieces.append(i)
        elif piece_char == '@':
            # Black piece - direct feature index mapping
            pos.black_pieces.append(i)
        # '*' = empty, 'X' = marked (ignored for training)
    
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
    Supports both legacy format and Perfect Database generated format.
    """
    
    def __init__(self, data_files: List[str], feature_set, max_positions: Optional[int] = None, 
                 use_perfect_db_format: bool = True, batch_load_size: int = 100000):
        self.feature_set = feature_set
        self.use_perfect_db_format = use_perfect_db_format
        self.positions = []
        self.evaluations = []
        self.results = []
        self.batch_load_size = batch_load_size  # Load data in batches to manage memory
        
        # Load training data from files
        if use_perfect_db_format:
            # Use Perfect DB data loader with batch loading
            self._load_perfect_db_data_in_batches(data_files, max_positions)
        else:
            # Use legacy loader
            total_loaded = 0
            for file_path in data_files:
                if max_positions and total_loaded >= max_positions:
                    break
                    
                positions_from_file = self._load_from_file(file_path, max_positions - total_loaded if max_positions else None)
                total_loaded += len(positions_from_file)
            
        print(f"Loaded {len(self.positions)} training positions")
    
    def _load_perfect_db_data_in_batches(self, data_files: List[str], max_positions: Optional[int] = None):
        """Load Perfect DB data in batches to manage memory usage."""
        total_loaded = 0
        
        for file_path in data_files:
            if max_positions and total_loaded >= max_positions:
                break
            
            try:
                with open(file_path, 'r', encoding='utf-8') as f:
                    batch = []
                    for line_num, line in enumerate(f):
                        if max_positions and total_loaded >= max_positions:
                            break
                        
                        pos = parse_perfect_db_training_line(line)
                        if pos is not None:
                            batch.append(pos)
                            
                            # Process batch when it reaches the batch size
                            if len(batch) >= self.batch_load_size:
                                self._process_batch(batch)
                                total_loaded += len(batch)
                                batch = []  # Clear batch to free memory
                                
                                # Force garbage collection periodically
                                if total_loaded % (self.batch_load_size * 10) == 0:
                                    import gc
                                    gc.collect()
                    
                    # Process remaining items in batch
                    if batch:
                        self._process_batch(batch)
                        total_loaded += len(batch)
                        
            except FileNotFoundError:
                print(f"Warning: Training data file not found: {file_path}")
            except Exception as e:
                print(f"Error loading training data from {file_path}: {e}")
    
    def _process_batch(self, batch: List[MillPosition]):
        """Process a batch of positions and add to the dataset."""
        for pos in batch:
            self.positions.append(pos)
            self.evaluations.append(pos.evaluation)
            self.results.append(pos.game_result)
    
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
        # Add boundary check for idx
        if idx < 0 or idx >= len(self.positions):
            raise IndexError(f"Index {idx} out of bounds for dataset of size {len(self.positions)}")
            
        pos = self.positions[idx]
        
        # Validate position pieces are within board bounds
        for piece_pos in pos.white_pieces:
            if piece_pos < 0 or piece_pos >= 24:
                raise ValueError(f"White piece position {piece_pos} out of board bounds [0, 23]")
        for piece_pos in pos.black_pieces:
            if piece_pos < 0 or piece_pos >= 24:
                raise ValueError(f"Black piece position {piece_pos} out of board bounds [0, 23]")
        
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
        
        # PSQT and layer stack indices (bucketization with counts + coarse mobility)
        # Buckets: 1..7 (0 unused). Design:
        #  - Placing phase: based on 'us' in-hand counts
        #      * in_hand >= 6 -> 1,  3..5 -> 2,  0..2 -> 3
        #  - Non-placing (moving/flying/capture):
        #      * flying condition (us_on_board <= 3) -> 4
        #      * else mobility by empties (24 - on_board_sum):
        #           empties >= 8 -> 5,  7 -> 6,  <=6 -> 7
        us_is_white = (pos.side_to_move == 0)
        white_on_board = len(pos.white_pieces)
        black_on_board = len(pos.black_pieces)
        us_on_board = white_on_board if us_is_white else black_on_board
        us_in_hand = int(pos.white_in_hand if us_is_white else pos.black_in_hand)
        placing = (pos.white_in_hand > 0) or (pos.black_in_hand > 0)
        empties = 24 - (white_on_board + black_on_board)

        if placing:
            if us_in_hand >= 6:
                bucket = 1
            elif us_in_hand >= 3:
                bucket = 2
            else:
                bucket = 3
        else:
            if us_on_board <= 3:
                bucket = 4  # flying-like high mobility
            else:
                if empties >= 8:
                    bucket = 5
                elif empties == 7:
                    bucket = 6
                else:
                    bucket = 7

        psqt_indices = torch.tensor(bucket, dtype=torch.long)
        layer_stack_indices = torch.tensor(bucket, dtype=torch.long)
        
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
    white_indices = torch.zeros((batch_size, max_white_features), dtype=torch.int32)
    white_values = torch.zeros((batch_size, max_white_features), dtype=torch.float32)
    black_indices = torch.zeros((batch_size, max_black_features), dtype=torch.int32)
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
        white_indices,  # Already int32 from initialization
        white_values,
        black_indices,  # Already int32 from initialization
        black_values,
        results,  # outcome
        evaluations,  # score
        psqt_indices,
        layer_stack_indices
    )


def parse_perfect_db_training_line(line: str) -> Optional[MillPosition]:
    """
    Parse a training data line generated by Perfect Database.
    
    Expected format: "FEN evaluation best_move result"
    where FEN is the full Nine Men's Morris FEN string.
    
    Args:
        line: Training data line
        
    Returns:
        MillPosition object or None if parsing failed
    """
    line = line.strip()
    if not line or line.startswith('#'):
        return None
    
    try:
        # Split line and parse from the end
        parts = line.split()
        if len(parts) < 4:  # At least need FEN parts + evaluation + best_move + result
            return None
        
        # Parse from end: result, best_move, evaluation
        result = float(parts[-1])
        best_move = parts[-2]
        evaluation = float(parts[-3])
        
        # Remaining parts form the FEN string
        fen_parts = parts[:-3]
        fen = ' '.join(fen_parts)
        
        # Parse FEN to position
        pos = parse_mill_fen(fen)
        pos.evaluation = evaluation
        pos.best_move = best_move
        pos.game_result = result
        
        return pos
        
    except (ValueError, IndexError) as e:
        return None


def load_perfect_db_training_data(data_files: List[str], max_positions: Optional[int] = None) -> List[MillPosition]:
    """
    Load training data generated by Perfect Database.
    
    Args:
        data_files: List of training data file paths
        max_positions: Maximum number of positions to load
        
    Returns:
        List of MillPosition objects
    """
    positions = []
    total_loaded = 0
    
    for file_path in data_files:
        if max_positions and total_loaded >= max_positions:
            break
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                for line_num, line in enumerate(f):
                    if max_positions and total_loaded >= max_positions:
                        break
                    
                    pos = parse_perfect_db_training_line(line)
                    if pos is not None:
                        positions.append(pos)
                        total_loaded += 1
                        
        except FileNotFoundError:
            print(f"Warning: Training data file not found: {file_path}")
        except Exception as e:
            print(f"Error loading training data from {file_path}: {e}")
    
    print(f"Loaded {len(positions)} training positions from Perfect Database data")
    return positions


def create_mill_data_loader(data_files: List[str], feature_set, batch_size: int = 16384, 
                           max_positions: Optional[int] = None, shuffle: bool = True, 
                           num_workers: int = 0, use_perfect_db_format: bool = True) -> DataLoader:
    """
    Create a DataLoader for Nine Men's Morris training data.
    
    Args:
        data_files: List of training data file paths
        feature_set: Feature set to use for encoding positions
        batch_size: Batch size for training
        max_positions: Maximum number of positions to load (None for all)
        shuffle: Whether to shuffle the data
        num_workers: Number of worker processes for data loading
        use_perfect_db_format: Whether to use Perfect DB generated format
        
    Returns:
        DataLoader instance
    """
    dataset = MillTrainingDataset(data_files, feature_set, max_positions, use_perfect_db_format)
    
    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=shuffle,
        collate_fn=collate_mill_batch,
        num_workers=num_workers,
        pin_memory=True
    )


def create_perfect_db_data_loader(data_files: List[str], feature_set, batch_size: int = 16384,
                                 max_positions: Optional[int] = None, shuffle: bool = True,
                                 num_workers: int = 0) -> DataLoader:
    """
    Create a DataLoader specifically for Perfect Database generated training data.
    
    This is a convenience function that automatically uses the Perfect DB format.
    
    Args:
        data_files: List of Perfect DB training data file paths
        feature_set: Feature set to use for encoding positions
        batch_size: Batch size for training
        max_positions: Maximum number of positions to load
        shuffle: Whether to shuffle the data
        num_workers: Number of worker processes for data loading
        
    Returns:
        DataLoader instance
    """
    return create_mill_data_loader(
        data_files=data_files,
        feature_set=feature_set,
        batch_size=batch_size,
        max_positions=max_positions,
        shuffle=shuffle,
        num_workers=num_workers,
        use_perfect_db_format=True
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
