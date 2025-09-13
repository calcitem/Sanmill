from typing import Dict, Tuple
import numpy as np
import os
import sys

# Add parent directories to path for standalone execution
current_dir = os.path.dirname(os.path.abspath(__file__))
ml_dir = os.path.dirname(current_dir)
repo_root = os.path.dirname(ml_dir)
sys.path.insert(0, repo_root)
sys.path.insert(0, ml_dir)


def build_auxiliary_targets(board, current_player: int) -> Dict[str, np.ndarray]:
    """Construct auxiliary supervision signals inspired by classical evaluation.

    Returns a dict of dense tensors:
    - ownership: (24,) ownership per valid node in canonical perspective
    - score: (1,) scalar like "material + mobility" heuristic from current player's view
    - mill_potential: (24,) probability that each point contributes to forming a mill soon
    """
    # Ownership: +1 if white piece, -1 if black piece, 0 empty; then canonicalize
    try:
        from ml.game.standard_rules import xy_to_coord
    except ImportError:
        try:
            from game.standard_rules import xy_to_coord
        except ImportError:
            from standard_rules import xy_to_coord

    # Collect valid positions in fixed order
    valid_positions = [(x, y) for x in range(7) for y in range(7) if board.allowed_places[x][y]]

    ownership = np.zeros((len(valid_positions),), dtype=np.float32)
    for idx, (x, y) in enumerate(valid_positions):
        p = board.pieces[x][y]
        ownership[idx] = float(p)

    # Canonical perspective (current_player=1 means as-is; -1 means swap sign)
    if current_player == -1:
        ownership = -ownership

    # Heuristic score from evaluate.cpp sketch: piece in hand, on board, mobility
    white_on = board.count(1)
    black_on = board.count(-1)
    def in_hand(color: int) -> int:
        """Calculate pieces in hand with correct Nine Men's Morris alternating placement."""
        put_pieces = getattr(board, 'put_pieces', 0)
        # White places first (even counts), Black places second (odd counts)
        if color == 1:  # White
            total_placed = (put_pieces + 1) // 2  # 0->0, 1->1, 2->1, 3->2, etc.
        else:  # Black  
            total_placed = put_pieces // 2  # 0->0, 1->0, 2->1, 3->1, etc.
        return max(0, 9 - total_placed)

    piece_in_hand_diff = in_hand(1) - in_hand(-1)
    piece_on_board_diff = white_on - black_on

    # Approximate mobility diff via number of legal moves for each side in moving phases
    mobility_diff = 0
    if board.period in (1, 2):
        # Avoid deep copy; call Game via heuristic: count of legal moves per side
        try:
            try:
                from ml.game.Game import Game
            except ImportError:
                try:
                    from game.Game import Game
                except ImportError:
                    from Game import Game
            g = Game()
            mobility_white = int(np.sum(g.getValidMoves(board, 1)))
            mobility_black = int(np.sum(g.getValidMoves(board, -1)))
            mobility_diff = mobility_white - mobility_black
        except Exception:
            mobility_diff = 0

    # Enhanced tactical evaluation with LC0-inspired pattern recognition
    mill_bonus = 0.0
    tactical_bonus = 0.0
    
    try:
        from ml.game.standard_rules import mills, coord_to_xy
        pieces = board.pieces
        
        # Count mills and tactical patterns for each player
        white_mills = 0
        black_mills = 0
        white_potential_mills = 0
        black_potential_mills = 0
        white_blocked_mills = 0  # Mills blocked by opponent
        black_blocked_mills = 0
        white_double_threats = 0  # Multiple mill threats
        black_double_threats = 0
        
        threat_positions = {'white': [], 'black': []}
        
        for a, b, c in mills:
            ax, ay = coord_to_xy[a]
            bx, by = coord_to_xy[b]
            cx, cy = coord_to_xy[c]
            line = [pieces[ax][ay], pieces[bx][by], pieces[cx][cy]]
            
            if line.count(1) == 3:  # White mill
                white_mills += 1
            elif line.count(-1) == 3:  # Black mill
                black_mills += 1
            elif line.count(1) == 2 and line.count(0) == 1:  # White potential mill
                white_potential_mills += 1
                # Track threat positions for double threat detection
                empty_pos = [(ax, ay), (bx, by), (cx, cy)][line.index(0)]
                threat_positions['white'].append(empty_pos)
            elif line.count(-1) == 2 and line.count(0) == 1:  # Black potential mill
                black_potential_mills += 1
                # Track threat positions for double threat detection
                empty_pos = [(ax, ay), (bx, by), (cx, cy)][line.index(0)]
                threat_positions['black'].append(empty_pos)
            elif line.count(1) == 2 and line.count(-1) == 1:  # White mill blocked
                white_blocked_mills += 1
            elif line.count(-1) == 2 and line.count(1) == 1:  # Black mill blocked
                black_blocked_mills += 1
        
        # Detect double threats (same position creates multiple mills)
        from collections import Counter
        white_threat_counts = Counter(threat_positions['white'])
        black_threat_counts = Counter(threat_positions['black'])
        white_double_threats = sum(1 for count in white_threat_counts.values() if count >= 2)
        black_double_threats = sum(1 for count in black_threat_counts.values() if count >= 2)
        
        # Enhanced mill scoring with tactical awareness
        mill_bonus = ((white_mills - black_mills) * 3.0 +  # Higher weight for formed mills
                     (white_potential_mills - black_potential_mills) * 1.0 +
                     (white_double_threats - black_double_threats) * 2.0 +  # Double threats are powerful
                     (black_blocked_mills - white_blocked_mills) * 0.3)  # Blocking opponent mills
        
        # Additional tactical bonus for strong positions
        if white_mills > black_mills + 1:  # Significant mill advantage
            tactical_bonus += 1.0
        elif black_mills > white_mills + 1:
            tactical_bonus -= 1.0
            
    except Exception:
        mill_bonus = 0.0
        tactical_bonus = 0.0
    
    # Enhanced scoring with tactical awareness (LC0-inspired evaluation)
    score = (0.12 * piece_in_hand_diff + 
             0.20 * piece_on_board_diff + 
             0.05 * mobility_diff + 
             mill_bonus +  # Mill bonus can be significant
             tactical_bonus)  # Additional tactical evaluation

    if current_player == -1:
        score = -score

    # Mill potential per point
    mill_potential = _mill_potential_map(board)

    return {
        "ownership": ownership.astype(np.float32),
        "score": np.array([score], dtype=np.float32),
        "mill_potential": mill_potential.astype(np.float32),
    }


def _mill_potential_map(board) -> np.ndarray:
    """Return (24,) vector marking empties that would complete a mill for current player.
    If in moving phase, also include sources that can move to such empties (coarse).
    """
    try:
        from ml.game.standard_rules import mills, coord_to_xy
    except ImportError:
        try:
            from game.standard_rules import mills, coord_to_xy
        except ImportError:
            from standard_rules import mills, coord_to_xy
    valid_positions = [(x, y) for x in range(7) for y in range(7) if board.allowed_places[x][y]]
    index_map: Dict[Tuple[int, int], int] = {pos: i for i, pos in enumerate(valid_positions)}

    potential = np.zeros((len(valid_positions),), dtype=np.float32)

    pieces = board.pieces
    # For both colors, highlight empties that close two-in-line
    for a, b, c in mills:
        ax, ay = coord_to_xy[a]
        bx, by = coord_to_xy[b]
        cx, cy = coord_to_xy[c]
        line = [pieces[ax][ay], pieces[bx][by], pieces[cx][cy]]
        if line.count(0) == 1:
            # one empty, two same colored
            same = sum(1 for v in line if v == 1) == 2 or sum(1 for v in line if v == -1) == 2
            if same:
                for (xx, yy), v in [((ax, ay), line[0]), ((bx, by), line[1]), ((cx, cy), line[2])]:
                    if v == 0:
                        potential[index_map[(xx, yy)]] = 1.0

    return potential


