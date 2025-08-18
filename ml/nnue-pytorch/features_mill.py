import torch
from collections import OrderedDict
from feature_block import *

# Nine Men's Morris board has 24 positions (indices 8-31 in C++ engine)
NUM_SQ = 24
# Two piece types: WHITE_PIECE and BLACK_PIECE
NUM_PT = 2
# Total feature planes: positions x piece types
NUM_PLANES = NUM_SQ * NUM_PT
# Total input features: positions x planes (each position can see all other positions)
NUM_INPUTS = NUM_PLANES * NUM_SQ

# Position mapping from C++ engine (SQ_A1=8 to SQ_C8=31)
# This maps C++ square indices to 0-23 range for features
def cpp_square_to_feature_index(cpp_square):
    """Convert C++ square index (8-31) to feature index (0-23)."""
    return cpp_square - 8

def feature_index_to_cpp_square(feature_index):
    """Convert feature index (0-23) to C++ square index (8-31)."""
    return feature_index + 8


class NineMillFeatures(FeatureBlock):
    """
    Feature representation for Nine Men's Morris.
    
    The feature set represents the game state as viewed from each player's perspective.
    For each position on the board (24 positions), we encode:
    - Which pieces (white/black) occupy each position
    - This creates a sparse representation where only occupied positions have non-zero features
    
    The total feature space is 24 positions * 2 piece types * 24 positions = 1152 features
    """
    
    def __init__(self):
        super(NineMillFeatures, self).__init__(
            "NineMill",
            0x9A111001,  # Custom hash for Nine Men's Morris features
            OrderedDict([("NineMill", NUM_PLANES * NUM_SQ)]),
        )

    def get_active_features(self, board_state):
        """
        Extract active features from a Nine Men's Morris board state.
        
        Args:
            board_state: Dictionary containing:
                - 'white_pieces': list of feature positions (0-23) with white pieces
                - 'black_pieces': list of feature positions (0-23) with black pieces  
                - 'side_to_move': 'white' or 'black'
        
        Note: Position indices should already be converted from C++ squares (8-31) to feature indices (0-23)
        
        Returns:
            Tuple of (white_perspective_features, black_perspective_features)
        """
        def piece_features(perspective_color):
            indices = torch.zeros(NUM_PLANES * NUM_SQ)
            
            # For each piece on the board
            for pos in board_state.get('white_pieces', []):
                # Ensure position is in valid range
                if 0 <= pos < NUM_SQ:
                    feature_idx = self._get_feature_index(pos, 0, perspective_color)  # 0 for white
                    indices[feature_idx] = 1.0
                
            for pos in board_state.get('black_pieces', []):
                # Ensure position is in valid range
                if 0 <= pos < NUM_SQ:
                    feature_idx = self._get_feature_index(pos, 1, perspective_color)  # 1 for black
                    indices[feature_idx] = 1.0
            
            return indices

        return (piece_features('white'), piece_features('black'))
    
    def _get_feature_index(self, piece_pos, piece_type, perspective):
        """
        Calculate the feature index for a piece.
        
        Args:
            piece_pos: Position of the piece (0-23)
            piece_type: 0 for white, 1 for black
            perspective: 'white' or 'black' - whose perspective we're encoding
        
        Returns:
            Feature index in the flattened feature vector
        """
        # Adjust piece type based on perspective (opponent pieces get different encoding)
        if perspective == 'black':
            piece_type = 1 - piece_type  # Flip perspective
        
        # Each position sees all positions, so we encode:
        # position * NUM_PLANES + piece_type * NUM_SQ + piece_position
        return piece_type * NUM_SQ + piece_pos

    def get_initial_psqt_features(self):
        """
        Get initial piece-square table values for Nine Men's Morris.
        
        Returns positional values for different board positions.
        Star positions (corners and center intersections) are more valuable.
        """
        values = [0] * (NUM_PLANES * NUM_SQ)
        
        # Define positional values for Nine Men's Morris
        # Star squares (strategic positions) based on C++ Position::is_star_square()
        # Convert C++ square indices to feature indices (subtract 8)
        star_positions_with_diagonals = [17-8, 19-8, 21-8, 23-8]  # squares 9, 11, 13, 15
        star_positions_no_diagonals = [16-8, 18-8, 20-8, 22-8]    # squares 8, 10, 12, 14
        # Use no-diagonals as default (standard Nine Men's Morris)
        star_positions = star_positions_no_diagonals
        
        # Corner positions (outer ring corners)
        corner_positions = [24-8, 25-8, 29-8, 31-8]  # squares 16, 17, 21, 23 in feature space
        
        piece_value = 100  # Base piece value
        star_bonus = 20    # Bonus for star positions
        corner_bonus = 10  # Bonus for corner positions
        
        for pos in range(NUM_SQ):
            base_value = piece_value
            
            # Add positional bonuses
            if pos in star_positions:
                base_value += star_bonus
            elif pos in corner_positions:
                base_value += corner_bonus
            
            # Set values for both white and black pieces
            # White pieces (type 0)
            white_idx = 0 * NUM_SQ + pos
            values[white_idx] = base_value
            
            # Black pieces (type 1) 
            black_idx = 1 * NUM_SQ + pos
            values[black_idx] = -base_value  # Negative for opponent
        
        return values


class FactorizedNineMillFeatures(FeatureBlock):
    """
    Factorized version of Nine Men's Morris features for enhanced training.
    
    This creates additional virtual features that help the network learn
    more general patterns by factorizing the position and piece information.
    """
    
    def __init__(self):
        super(FactorizedNineMillFeatures, self).__init__(
            "NineMill^",
            0x9A111002,
            OrderedDict([
                ("NineMill", NUM_PLANES * NUM_SQ),  # Real features
                ("Position", NUM_SQ),               # Virtual position features
                ("Piece", NUM_PT)                   # Virtual piece type features
            ]),
        )

    def get_active_features(self, board_state):
        """
        Extract active features from a Nine Men's Morris board state.
        This implementation supports both Python and C++ data loaders.
        
        Args:
            board_state: Dictionary containing:
                - 'white_pieces': list of feature positions (0-23) with white pieces
                - 'black_pieces': list of feature positions (0-23) with black pieces  
                - 'side_to_move': 'white' or 'black'
        
        Returns:
            Tuple of (white_perspective_features, black_perspective_features)
        """
        # Use the same logic as NineMillFeatures for compatibility with Python data loader
        def piece_features(perspective_color):
            indices = torch.zeros(NUM_PLANES * NUM_SQ)
            
            # For each piece on the board
            for pos in board_state.get('white_pieces', []):
                # Ensure position is in valid range
                if 0 <= pos < NUM_SQ:
                    feature_idx = self._get_feature_index(pos, 0, perspective_color)  # 0 for white
                    indices[feature_idx] = 1.0
                
            for pos in board_state.get('black_pieces', []):
                if 0 <= pos < NUM_SQ:
                    feature_idx = self._get_feature_index(pos, 1, perspective_color)  # 1 for black
                    indices[feature_idx] = 1.0
                    
            return indices
        
        # Return features from both perspectives
        white_features = piece_features('white')
        black_features = piece_features('black')
        
        return white_features, black_features

    def _get_feature_index(self, position, piece_type, perspective_color):
        """
        Calculate the feature index for a piece at a given position from a perspective.
        This uses the same logic as NineMillFeatures for consistency.
        
        Args:
            position: Board position (0-23)
            piece_type: 0 for white, 1 for black
            perspective_color: 'white' or 'black' - which player's perspective
            
        Returns:
            Feature index in the range [0, NUM_PLANES * NUM_SQ)
        """
        # Same logic as NineMillFeatures._get_feature_index
        if perspective_color == 'black':
            # From black's perspective, flip piece colors
            piece_type = 1 - piece_type
            
        # Feature index calculation: piece_type * NUM_SQ + position
        return piece_type * NUM_SQ + position

    def get_feature_factors(self, idx):
        """
        Get the factorization of a real feature into virtual features.
        
        Args:
            idx: Index of the real feature to factorize
            
        Returns:
            List of [real_feature_idx, position_feature_idx, piece_feature_idx]
        """
        if idx >= self.num_real_features:
            raise Exception("Feature must be real")
        
        # Decode the feature index
        piece_type = idx // NUM_SQ
        position = idx % NUM_SQ
        
        # Map to virtual features
        position_feature_idx = self.get_factor_base_feature("Position") + position
        piece_feature_idx = self.get_factor_base_feature("Piece") + piece_type
        
        return [idx, position_feature_idx, piece_feature_idx]

    def get_initial_psqt_features(self):
        """Get initial PSQT values including virtual features."""
        base_features = NineMillFeatures().get_initial_psqt_features()
        # Add zeros for virtual features
        virtual_features = [0] * (NUM_SQ + NUM_PT)
        return base_features + virtual_features


def create_board_state_from_fen(fen_string):
    """
    Convert a Nine Men's Morris FEN string to board state format.
    
    Args:
        fen_string: FEN string representing the game state
        
    Returns:
        Dictionary with board state information
    """
    # Parse the FEN string (simplified version)
    # This is a helper function to convert from the C++ engine format
    parts = fen_string.split()
    if len(parts) < 2:
        return {'white_pieces': [], 'black_pieces': [], 'side_to_move': 'white'}
    
    board_part = parts[0]
    side_to_move = 'white' if parts[1] == 'w' else 'black'
    
    white_pieces = []
    black_pieces = []
    
    # Parse board positions (this is a simplified parser)
    # In the actual implementation, you'd need to parse the full FEN format
    # as defined in the C++ Position class
    
    return {
        'white_pieces': white_pieces,
        'black_pieces': black_pieces,
        'side_to_move': side_to_move
    }


"""
This is used by the features module for discovery of feature blocks.
"""
def get_feature_block_clss():
    return [NineMillFeatures, FactorizedNineMillFeatures]
