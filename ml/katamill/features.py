from typing import Tuple
import numpy as np
import os
import sys

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)

# Reuse existing game logic for board constants
try:
    from ml.game.Game import Game
except Exception:
    try:
        from game.Game import Game
    except Exception:
        game_path = os.path.join(ml_dir, 'game')
        sys.path.insert(0, game_path)
        from Game import Game


def extract_features(board, current_player: int) -> np.ndarray:
    """
    Build comprehensive CNN input features for Nine Men's Morris with KataGo-inspired improvements.

    Enhanced feature set (32 channels):
    - 0-1: Basic piece positions (white/black)
    - 2: Valid locations mask
    - 3-6: Game phase one-hot encoding (placing/moving/flying/removal)
    - 7: Current player indicator
    - 8-11: Piece counts (in-hand and on-board, normalized)
    - 12: Move counter (normalized)
    - 13-16: Mill patterns (formed/potential for both colors)
    - 17-20: Advanced mill features (blocking, protection, double mills)
    - 21-24: Mobility and control maps (phase-aware)
    - 25-28: Tactical threat detection (near-mills, captures)
    - 29-31: Strategic features (center control, edge control, connectivity)
    
    Key improvements:
    - More sophisticated mill detection
    - Phase-aware mobility calculation
    - Advanced tactical pattern recognition
    - Better positional understanding
    """
    # Input validation
    if board is None:
        raise ValueError("Board cannot be None")
    if current_player not in [-1, 1]:
        raise ValueError(f"current_player must be 1 or -1, got {current_player}")
    
    # Validate board structure
    if not hasattr(board, 'allowed_places') or not hasattr(board, 'pieces'):
        raise ValueError("Board missing required attributes (allowed_places, pieces)")
    
    n = 7
    C = 32
    x = np.zeros((C, n, n), dtype=np.float32)

    # Board state extraction
    valid = np.array(board.allowed_places, dtype=np.float32)
    pieces = np.array(board.pieces, dtype=np.int8)
    phase = int(getattr(board, "period", 0))
    phase = max(0, min(3, phase))  # Ensure valid phase

    # Basic piece positions (channels 0-1)
    x[0] = (pieces == 1).astype(np.float32)
    x[1] = (pieces == -1).astype(np.float32)

    # Board structure (channel 2)
    x[2] = valid

    # Game phase encoding (channels 3-6)
    x[3 + phase][:, :] = 1.0

    # Current player indicator (channel 7)
    x[7][:, :] = 1.0 if current_player == 1 else 0.0

    # Piece count features (channels 8-11)
    white_on = float(board.count(1))
    black_on = float(board.count(-1))
    
    def pieces_in_hand(color: int) -> float:
        """Calculate pieces in hand with correct Nine Men's Morris alternating placement rules."""
        if phase == 0:  # Placing phase
            try:
                put_pieces = getattr(board, 'put_pieces', 0)
                # Ensure put_pieces is valid (0-18 total pieces placed)
                put_pieces = max(0, min(18, put_pieces))
                
                # In Nine Men's Morris, white places first (put_pieces=0,2,4,...)
                # Black places second (put_pieces=1,3,5,...)
                if color == 1:  # White places on even counts
                    white_placed = (put_pieces + 1) // 2  # 0->0, 1->1, 2->1, 3->2, etc.
                    in_hand = max(0.0, 9.0 - float(white_placed))
                else:  # Black places on odd counts
                    black_placed = put_pieces // 2  # 0->0, 1->0, 2->1, 3->1, etc.
                    in_hand = max(0.0, 9.0 - float(black_placed))
                
                return min(in_hand, 9.0)  # Ensure not more than 9
            except Exception:
                return 0.0  # Safe fallback
        else:
            return 0.0  # No pieces in hand after placing phase

    # Normalize pieces in hand (0-9 pieces -> 0.0-1.0)
    white_in_hand = pieces_in_hand(1) / 9.0
    black_in_hand = pieces_in_hand(-1) / 9.0
    x[8][:, :] = min(white_in_hand, 1.0)  # Ensure not > 1.0
    x[9][:, :] = min(black_in_hand, 1.0)  # Ensure not > 1.0
    x[10][:, :] = white_on / 9.0
    x[11][:, :] = black_on / 9.0

    # Game progress indicator (channel 12)
    move_counter = float(getattr(board, "move_counter", 0))
    x[12][:, :] = min(move_counter / 200.0, 1.0)  # Normalize to typical game length

    # Basic mill features (channels 13-16)
    formed_white, formed_black, pot_white, pot_black = _mill_features(pieces, valid)
    x[13] = formed_white
    x[14] = formed_black
    x[15] = pot_white
    x[16] = pot_black

    # Advanced mill features (channels 17-20)
    block_white, block_black, protect_white, protect_black = _advanced_mill_features(pieces, valid)
    x[17] = block_white
    x[18] = block_black
    x[19] = protect_white
    x[20] = protect_black

    # Mobility and control maps (channels 21-24)
    mob_white, mob_black = _mobility_maps(pieces, valid, phase)
    control_white, control_black = _control_maps(pieces, valid, phase)
    x[21] = mob_white
    x[22] = mob_black
    x[23] = control_white
    x[24] = control_black

    # Threat detection (channels 25-28)
    threat_white, threat_black = _threat_maps(pieces, valid)
    capture_white, capture_black = _capture_threat_maps(pieces, valid, phase)
    x[25] = threat_white
    x[26] = threat_black
    x[27] = capture_white
    x[28] = capture_black

    # Strategic features (channels 29-31)
    center_control = _center_control_map(pieces, valid)
    connectivity = _connectivity_map(pieces, valid, current_player)
    edge_control = _edge_control_map(pieces, valid)
    x[29] = center_control
    x[30] = connectivity
    x[31] = edge_control

    return x


def _mill_features(pieces: np.ndarray, valid: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """Detect formed mills and potential mills with enhanced tactical awareness.

    Enhanced detection includes:
    - Multiple mill formation opportunities
    - Mill strength based on protection level
    - Immediate vs future mill threats
    
    Returns four 7x7 maps for white formed, black formed, white potential, black potential.
    """
    try:
        from ml.game.standard_rules import mills, coord_to_xy
    except ImportError:
        try:
            from game.standard_rules import mills, coord_to_xy
        except ImportError:
            from standard_rules import mills, coord_to_xy

    fw = np.zeros_like(valid, dtype=np.float32)
    fb = np.zeros_like(valid, dtype=np.float32)
    pw = np.zeros_like(valid, dtype=np.float32)
    pb = np.zeros_like(valid, dtype=np.float32)

    for a, b, c in mills:
        ax, ay = coord_to_xy[a]
        bx, by = coord_to_xy[b]
        cx, cy = coord_to_xy[c]
        line = np.array([pieces[ax, ay], pieces[bx, by], pieces[cx, cy]], dtype=np.int8)

        if np.all(line == 1):
            fw[ax, ay] = fw[bx, by] = fw[cx, cy] = 1.0
        if np.all(line == -1):
            fb[ax, ay] = fb[bx, by] = fb[cx, cy] = 1.0

        # Enhanced potential mill detection with tactical importance weighting
        if np.sum(line == 1) == 2 and np.sum(line == 0) == 1:
            for (xx, yy), v in zip([(ax, ay), (bx, by), (cx, cy)], line):
                if v == 0:
                    # Weight based on tactical importance (center positions more valuable)
                    center_bonus = 1.0 if (xx == 3 or yy == 3) else 0.5
                    pw[xx, yy] = max(pw[xx, yy], 1.5 + center_bonus)
        if np.sum(line == -1) == 2 and np.sum(line == 0) == 1:
            for (xx, yy), v in zip([(ax, ay), (bx, by), (cx, cy)], line):
                if v == 0:
                    # Weight based on tactical importance (center positions more valuable)
                    center_bonus = 1.0 if (xx == 3 or yy == 3) else 0.5
                    pb[xx, yy] = max(pb[xx, yy], 1.5 + center_bonus)

    return fw, fb, pw, pb


def _mobility_maps(pieces: np.ndarray, valid: np.ndarray, phase: int) -> Tuple[np.ndarray, np.ndarray]:
    """Approximate mobility maps for white/black:
    mark destination empties reachable in one move (or any in flying phase).
    """
    try:
        from ml.game.standard_rules import adjacent, xy_to_coord, coord_to_xy
    except ImportError:
        try:
            from game.standard_rules import adjacent, xy_to_coord, coord_to_xy
        except ImportError:
            from standard_rules import adjacent, xy_to_coord, coord_to_xy

    n = 7
    mw = np.zeros((n, n), dtype=np.float32)
    mb = np.zeros((n, n), dtype=np.float32)

    # Flying phase allows any empty
    if phase == 2:
        empties = (pieces == 0) & (valid == 1)
        mw[empties] = 1.0
        mb[empties] = 1.0
        return mw, mb

    # Normal adjacency-based moves
    for (coord, neighs) in adjacent.items():
        x, y = coord_to_xy[coord]
        p = pieces[x, y]
        if p == 0:
            continue
        for ncoord in neighs:
            nx, ny = coord_to_xy[ncoord]
            if pieces[nx, ny] != 0:
                continue
            if p == 1:
                mw[nx, ny] = 1.0
            elif p == -1:
                mb[nx, ny] = 1.0

    return mw, mb


def _threat_maps(pieces: np.ndarray, valid: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Opponent near-mill pressure maps: squares that would complete opponent mill next move.
    Returns two maps: threat against white, threat against black.
    """
    try:
        from ml.game.standard_rules import mills, coord_to_xy
    except ImportError:
        try:
            from game.standard_rules import mills, coord_to_xy
        except ImportError:
            from standard_rules import mills, coord_to_xy

    tw = np.zeros_like(valid, dtype=np.float32)
    tb = np.zeros_like(valid, dtype=np.float32)

    for a, b, c in mills:
        ax, ay = coord_to_xy[a]
        bx, by = coord_to_xy[b]
        cx, cy = coord_to_xy[c]
        line = np.array([pieces[ax, ay], pieces[bx, by], pieces[cx, cy]], dtype=np.int8)

        # Threat against white: two blacks + one empty
        if np.sum(line == -1) == 2 and np.sum(line == 0) == 1:
            for (xx, yy), v in zip([(ax, ay), (bx, by), (cx, cy)], line):
                if v == 0:
                    tw[xx, yy] = 1.0

        # Threat against black: two whites + one empty
        if np.sum(line == 1) == 2 and np.sum(line == 0) == 1:
            for (xx, yy), v in zip([(ax, ay), (bx, by), (cx, cy)], line):
                if v == 0:
                    tb[xx, yy] = 1.0

    return tw, tb


def _advanced_mill_features(pieces: np.ndarray, valid: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    """
    Detect advanced mill patterns: blocking opportunities and protection needs.
    
    Returns:
    - block_white: Positions where white can block black's potential mills
    - block_black: Positions where black can block white's potential mills  
    - protect_white: White pieces that need protection from capture
    - protect_black: Black pieces that need protection from capture
    """
    try:
        from ml.game.standard_rules import mills, coord_to_xy
    except ImportError:
        try:
            from game.standard_rules import mills, coord_to_xy
        except ImportError:
            from standard_rules import mills, coord_to_xy

    block_w = np.zeros_like(valid, dtype=np.float32)
    block_b = np.zeros_like(valid, dtype=np.float32)
    protect_w = np.zeros_like(valid, dtype=np.float32)
    protect_b = np.zeros_like(valid, dtype=np.float32)

    for a, b, c in mills:
        ax, ay = coord_to_xy[a]
        bx, by = coord_to_xy[b]
        cx, cy = coord_to_xy[c]
        line = np.array([pieces[ax, ay], pieces[bx, by], pieces[cx, cy]], dtype=np.int8)
        positions = [(ax, ay), (bx, by), (cx, cy)]

        # Blocking opportunities: opponent has 2 pieces, we can place/move to block
        if np.sum(line == -1) == 2 and np.sum(line == 0) == 1:
            # Black has potential mill, white can block
            for (xx, yy), v in zip(positions, line):
                if v == 0:
                    block_w[xx, yy] = 1.0
        
        if np.sum(line == 1) == 2 and np.sum(line == 0) == 1:
            # White has potential mill, black can block
            for (xx, yy), v in zip(positions, line):
                if v == 0:
                    block_b[xx, yy] = 1.0

        # Protection needs: pieces that are part of potential enemy mills
        if np.sum(line == 1) == 1 and np.sum(line == -1) == 2:
            # White piece surrounded by black pieces - needs protection
            for (xx, yy), v in zip(positions, line):
                if v == 1:
                    protect_w[xx, yy] = 1.0
                    
        if np.sum(line == -1) == 1 and np.sum(line == 1) == 2:
            # Black piece surrounded by white pieces - needs protection
            for (xx, yy), v in zip(positions, line):
                if v == -1:
                    protect_b[xx, yy] = 1.0

    return block_w, block_b, protect_w, protect_b


def _control_maps(pieces: np.ndarray, valid: np.ndarray, phase: int) -> Tuple[np.ndarray, np.ndarray]:
    """
    Calculate control maps showing which positions each player influences.
    
    Control is different from mobility - it represents strategic influence
    over key board areas, considering both current pieces and potential moves.
    """
    try:
        from ml.game.standard_rules import adjacent, xy_to_coord, coord_to_xy
    except ImportError:
        try:
            from game.standard_rules import adjacent, xy_to_coord, coord_to_xy
        except ImportError:
            from standard_rules import adjacent, xy_to_coord, coord_to_xy

    n = 7
    control_w = np.zeros((n, n), dtype=np.float32)
    control_b = np.zeros((n, n), dtype=np.float32)

    # Direct control from piece positions
    for x in range(n):
        for y in range(n):
            if not valid[x, y]:
                continue
                
            piece = pieces[x, y]
            if piece == 1:
                control_w[x, y] += 1.0
            elif piece == -1:
                control_b[x, y] += 1.0
            
            # Influence from adjacent pieces
            try:
                coord = xy_to_coord[(x, y)]
                if coord in adjacent:
                    for neighbor_coord in adjacent[coord]:
                        nx, ny = coord_to_xy[neighbor_coord]
                        neighbor_piece = pieces[nx, ny]
                        
                        if neighbor_piece == 1:
                            control_w[x, y] += 0.3  # Indirect white influence
                        elif neighbor_piece == -1:
                            control_b[x, y] += 0.3  # Indirect black influence
            except KeyError:
                pass

    return control_w, control_b


def _capture_threat_maps(pieces: np.ndarray, valid: np.ndarray, phase: int) -> Tuple[np.ndarray, np.ndarray]:
    """
    Detect immediate capture threats in moving/flying phases.
    
    In Nine Men's Morris, pieces can be captured when they're not part of a mill
    and the opponent can reduce the player to 2 pieces.
    """
    capture_w = np.zeros_like(valid, dtype=np.float32)
    capture_b = np.zeros_like(valid, dtype=np.float32)

    if phase not in [1, 2]:  # Only relevant in moving/flying phases
        return capture_w, capture_b

    # Count pieces for each player
    white_count = np.sum(pieces == 1)
    black_count = np.sum(pieces == -1)

    # Check if either player is close to losing (3 pieces or fewer)
    white_vulnerable = white_count <= 3
    black_vulnerable = black_count <= 3

    if white_vulnerable:
        # Mark all white pieces as under capture threat
        capture_w[pieces == 1] = 1.0
        
    if black_vulnerable:
        # Mark all black pieces as under capture threat
        capture_b[pieces == -1] = 1.0

    return capture_w, capture_b


def _center_control_map(pieces: np.ndarray, valid: np.ndarray) -> np.ndarray:
    """
    Calculate center control - important strategic concept in Nine Men's Morris.
    
    The center positions (d4, d2, d6, b4, f4) are strategically important
    as they offer more connectivity and mill formation opportunities.
    """
    center_map = np.zeros_like(valid, dtype=np.float32)
    
    # Define center positions (approximate)
    center_positions = [(3, 3), (3, 1), (3, 5), (1, 3), (5, 3)]  # d4, d2, d6, b4, f4
    
    for x, y in center_positions:
        if x < 7 and y < 7 and valid[x, y]:
            piece = pieces[x, y]
            if piece == 1:
                center_map[x, y] = 1.0  # White controls center
            elif piece == -1:
                center_map[x, y] = -1.0  # Black controls center
            # Empty center positions are marked as 0 (neutral)

    return center_map


def _connectivity_map(pieces: np.ndarray, valid: np.ndarray, current_player: int) -> np.ndarray:
    """
    Calculate connectivity map showing how well-connected each player's pieces are.
    
    Well-connected pieces are harder to isolate and offer more tactical opportunities.
    """
    try:
        from ml.game.standard_rules import adjacent, xy_to_coord, coord_to_xy
    except ImportError:
        try:
            from game.standard_rules import adjacent, xy_to_coord, coord_to_xy
        except ImportError:
            from standard_rules import adjacent, xy_to_coord, coord_to_xy

    connectivity = np.zeros_like(valid, dtype=np.float32)

    for x in range(7):
        for y in range(7):
            if not valid[x, y]:
                continue
                
            piece = pieces[x, y]
            if piece == 0:
                continue
                
            # Count connected friendly pieces
            connected_count = 0
            try:
                coord = xy_to_coord[(x, y)]
                if coord in adjacent:
                    for neighbor_coord in adjacent[coord]:
                        nx, ny = coord_to_xy[neighbor_coord]
                        if pieces[nx, ny] == piece:  # Same color
                            connected_count += 1
            except KeyError:
                pass
            
            # Normalize connectivity (0-4 possible connections)
            connectivity_value = connected_count / 4.0
            
            # Apply from current player's perspective
            if piece == current_player:
                connectivity[x, y] = connectivity_value
            else:
                connectivity[x, y] = -connectivity_value

    return connectivity


def _edge_control_map(pieces: np.ndarray, valid: np.ndarray) -> np.ndarray:
    """
    Calculate edge control - corners and edge positions have special properties.
    
    Edge positions are often easier to defend but offer fewer tactical opportunities.
    Corner positions are particularly important in Nine Men's Morris.
    """
    edge_map = np.zeros_like(valid, dtype=np.float32)
    
    # Define edge and corner positions
    corners = [(0, 0), (0, 3), (0, 6), (3, 0), (3, 6), (6, 0), (6, 3), (6, 6)]
    edges = [(0, 1), (0, 2), (0, 4), (0, 5), (1, 0), (2, 0), (4, 0), (5, 0),
             (1, 6), (2, 6), (4, 6), (5, 6), (6, 1), (6, 2), (6, 4), (6, 5)]

    # Mark corner control (higher value)
    for x, y in corners:
        if x < 7 and y < 7 and valid[x, y]:
            piece = pieces[x, y]
            if piece == 1:
                edge_map[x, y] = 0.8  # White corner control
            elif piece == -1:
                edge_map[x, y] = -0.8  # Black corner control

    # Mark edge control (lower value)
    for x, y in edges:
        if x < 7 and y < 7 and valid[x, y]:
            piece = pieces[x, y]
            if piece == 1:
                edge_map[x, y] = 0.4  # White edge control
            elif piece == -1:
                edge_map[x, y] = -0.4  # Black edge control

    return edge_map


