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
        Build active features with explicit anchor dimension.

        We treat each square as an anchor (24 anchors). For every anchor, we
        encode all piece placements on the board in planes of size 48
        (piece_type x position). This yields 24 x 48 = 1152 inputs per
        perspective.

        Args:
            board_state: dict with keys 'white_pieces', 'black_pieces', 'side_to_move'.

        Returns:
            (white_perspective, black_perspective) dense feature vectors.
        """
        def piece_features(perspective_color: str) -> torch.Tensor:
            features = torch.zeros(NUM_PLANES * NUM_SQ)

            white_positions = board_state.get('white_pieces', []) or []
            black_positions = board_state.get('black_pieces', []) or []

            for p in white_positions:
                assert 0 <= p < NUM_SQ, "white_pieces index out of range"
            for p in black_positions:
                assert 0 <= p < NUM_SQ, "black_pieces index out of range"

            for anchor in range(NUM_SQ):
                for pos in white_positions:
                    idx = self._get_feature_index(anchor, pos, 0, perspective_color)
                    features[idx] = 1.0
                for pos in black_positions:
                    idx = self._get_feature_index(anchor, pos, 1, perspective_color)
                    features[idx] = 1.0

            return features

        return piece_features('white'), piece_features('black')
    
    def _get_feature_index(self, anchor_pos: int, piece_pos: int, piece_type: int, perspective: str) -> int:
        """
        Compute flattened index for (anchor, piece_type, piece_pos) under perspective.

        Indexing:
            idx = anchor_pos * NUM_PLANES + piece_type' * NUM_SQ + piece_pos
            piece_type' is flipped for black perspective.
        """
        assert 0 <= anchor_pos < NUM_SQ, "anchor_pos out of range"
        assert 0 <= piece_pos < NUM_SQ, "piece_pos out of range"
        assert piece_type in (0, 1), "piece_type must be 0 or 1"

        if perspective == 'black':
            piece_type = 1 - piece_type

        return anchor_pos * NUM_PLANES + piece_type * NUM_SQ + piece_pos

    def get_initial_psqt_features(self):
        """
        Provide initial PSQT values for all (anchor, piece_type, position) tuples.
        We repeat the per-position base value over all anchors. White entries are
        positive; black entries are negative to encode opponent symmetry.
        """
        values = [0] * (NUM_PLANES * NUM_SQ)

        # Star squares (strategic positions) based on C++ Position::is_star_square()
        star_positions_with_diagonals = [17 - 8, 19 - 8, 21 - 8, 23 - 8]
        star_positions_no_diagonals = [16 - 8, 18 - 8, 20 - 8, 22 - 8]
        star_positions = star_positions_no_diagonals

        # Corner positions (outer ring corners)
        corner_positions = [24 - 8, 25 - 8, 29 - 8, 31 - 8]

        piece_value = 100
        star_bonus = 20
        corner_bonus = 10

        base_per_pos = [0] * NUM_SQ
        for pos in range(NUM_SQ):
            v = piece_value
            if pos in star_positions:
                v += star_bonus
            elif pos in corner_positions:
                v += corner_bonus
            base_per_pos[pos] = v

        for anchor in range(NUM_SQ):
            for pos in range(NUM_SQ):
                white_idx = anchor * NUM_PLANES + 0 * NUM_SQ + pos
                black_idx = anchor * NUM_PLANES + 1 * NUM_SQ + pos
                values[white_idx] = base_per_pos[pos]
                values[black_idx] = -base_per_pos[pos]

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
        Build anchored features similarly to NineMillFeatures for factorized block.
        """
        def piece_features(perspective_color: str) -> torch.Tensor:
            features = torch.zeros(NUM_PLANES * NUM_SQ)

            white_positions = board_state.get('white_pieces', []) or []
            black_positions = board_state.get('black_pieces', []) or []

            for p in white_positions:
                assert 0 <= p < NUM_SQ, "white_pieces index out of range"
            for p in black_positions:
                assert 0 <= p < NUM_SQ, "black_pieces index out of range"

            for anchor in range(NUM_SQ):
                for pos in white_positions:
                    idx = self._get_feature_index(anchor, pos, 0, perspective_color)
                    features[idx] = 1.0
                for pos in black_positions:
                    idx = self._get_feature_index(anchor, pos, 1, perspective_color)
                    features[idx] = 1.0

            return features

        white_features = piece_features('white')
        black_features = piece_features('black')

        return white_features, black_features

    def _get_feature_index(self, anchor_pos: int, position: int, piece_type: int, perspective_color: str) -> int:
        """Anchored indexing consistent with NineMillFeatures."""
        assert 0 <= anchor_pos < NUM_SQ, "anchor_pos out of range"
        assert 0 <= position < NUM_SQ, "position out of range"
        assert piece_type in (0, 1), "piece_type must be 0 or 1"
        if perspective_color == 'black':
            piece_type = 1 - piece_type
        return anchor_pos * NUM_PLANES + piece_type * NUM_SQ + position

    def get_feature_factors(self, idx):
        """
        Factorize real feature idx (anchor, piece_type, position) into
        [real_idx, Position_virtual, Piece_virtual]. Anchor is not factorized.
        """
        if idx >= self.num_real_features:
            raise Exception("Feature must be real")

        anchor = idx // NUM_PLANES
        rem = idx % NUM_PLANES
        piece_type = rem // NUM_SQ
        position = rem % NUM_SQ
        _ = anchor

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
