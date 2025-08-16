from __future__ import print_function
from copy import deepcopy
from typing import Optional
import numpy as np

from .GameLogic import Board
from .standard_rules import coord_to_xy, xy_to_coord, mills


class Game:
    """
    This class specifies the game API used by AlphaZero. To define your own game,
    implement the functions below for a two-player, adversarial, turn-based game.

    Use 1 for player1 and -1 for player2.
    """



    @staticmethod
    def _get_piece_symbols():
        """
        控制台棋盘使用不同形状区分双方：
        - 白方：实心点 ●
        - 黑方：空心点 ○
        保持 ANSI 颜色以便可读（若终端不支持颜色，仍能通过形状区分）。
        """
        # ANSI color codes
        YELLOW = "\033[93m"  # Bright yellow
        BLUE = "\033[94m"    # Bright blue
        RESET = "\033[0m"    # Reset to default color
        
        return {
            -1: f"{BLUE}●{RESET}",    # 后手方（-1）：实心点
            +0: "·",                   # Empty squares (no color)
            +1: f"{YELLOW}○{RESET}"    # 先手方（+1）：空心点
        }



    @staticmethod
    def getSquarePiece(piece):
        return Game._get_piece_symbols()[piece]

    def __init__(self):
        self.n = 7
        self.num_draw = 100
        # Curriculum configuration (stage-based training)
        # stage: 1=placing-only (early stop after placements),
        #        2=moving without flying, 3=full rules
        self._curriculum_enabled: bool = False
        self._curriculum_stage: int = 3
        # Heuristic weight for stage-1 termination value shaping
        self._stage1_heuristic_weight: float = 0.03
        self.cache_symmetries()

    def reward_w_func(self, put_pieces):
        return 1 if put_pieces <= 40 else 1 - (put_pieces - 40) / (self.num_draw - 40)

    def cache_symmetries(self):
        place_index = np.zeros((self.n, self.n), dtype=np.int_)
        place_index[Board.allowed_places] = np.arange(24)
        self.cache_symmetries0 = []
        for i in range(5):
            for j in range(2):
                cache = np.rot90(place_index, i)
                if j == 1:
                    cache = np.fliplr(cache)
                self.cache_symmetries0.append(cache[Board.allowed_places])

        self.cache_symmetries1 = []
        action_index = np.arange(24 * 24, dtype=np.int_).reshape((24, 24))
        for i in range(5):
            for j in range(2):
                cache = np.zeros((24, 24), dtype=np.int_)
                cache[self.cache_symmetries0[i * 2 + j], :] = action_index
                cache2 = cache.copy()
                cache2[:, self.cache_symmetries0[i * 2 + j]] = cache
                self.cache_symmetries1.append(cache2.ravel())

        for i in range(5):
            for j in range(2):
                cache = np.arange(24 * 24, dtype=np.int_)
                cache[:24] = self.cache_symmetries0[i * 2 + j]
                self.cache_symmetries0[i * 2 + j] = cache

    def getInitBoard(self):
        """
        Returns: a representation of the board (ideally this is the form that
        will be the input to your neural network)
        """
        b = Board()
        # Propagate curriculum flags into the Board for move generation
        try:
            b.curriculum_stage = int(self._curriculum_stage)
            # In stage 2, disable flying to isolate moving semantics
            b.allow_flying = not (self._curriculum_enabled and int(self._curriculum_stage) == 2)
            # Absolute starter is White. This flag is used to disambiguate
            # canonicalized boards where pieces' signs are flipped.
            b._to_move_is_white = True
        except Exception:
            # Keep defaults if flags not available on Board
            pass
        return b

    def getBoardSize(self):
        """
        Returns: a tuple of board dimensions (x, y)
        """
        return self.n, self.n

    def getActionSize(self):
        """
        Returns: number of all possible actions
        """
        # For standard rules without diagonal lines we still keep 24*24 action
        # space for compatibility with existing training code. Invalid actions
        # will be masked out by getValidMoves.
        return 24 * 24

    def getNextState(self, board, player, action):
        """
        Input:
            board: current board
            player: current player (1 or -1)
            action: action taken by current player

        Returns:
            nextBoard: board after applying action
            nextPlayer: player who plays next (usually -player; same player when in capture phase)
        """
        b = deepcopy(board)
        # Validate action against current legal moves before applying
        valids = self.getValidMoves(b, player)
        assert hasattr(valids, '__len__'), "Valid moves must be array-like"
        assert len(valids) == self.getActionSize(), (
            f"Valid moves length {len(valids)} != action_size {self.getActionSize()}"
        )
        assert 0 <= action < self.getActionSize(), (
            f"Action {action} out of range [0, {self.getActionSize()}) for period {b.period}"
        )
        assert valids[action] == 1, (
            f"Action {action} is not legal for player {player} in period {b.period}"
        )

        move = b.get_move_from_action(action)
        b.execute_move(move, player)
        if b.period == 3:
            return b, player
        else:
            return b, -player

    def getValidMoves(self, board, player):
        """
        Returns a binary vector (size getActionSize) where 1 marks a valid move.
        """
        action_size = self.getActionSize()
        valids = [0] * action_size
        b = deepcopy(board)
        # Sanity checks on board state
        assert b.period in (0, 1, 2, 3), f"Invalid board period: {b.period}"
        legalMoves = b.get_legal_moves(player)
        # Map legal moves to actions and assert consistency
        seen_actions = set()
        for move in legalMoves:
            action = b.get_action_from_move(move)
            assert 0 <= action < action_size, (
                f"Mapped action {action} out of range [0, {action_size}) from move {move} at period {b.period}"
            )
            valids[action] = 1
            seen_actions.add(int(action))
        valids_arr = np.array(valids)
        # Final consistency checks
        assert len(valids_arr) == action_size, (
            f"Valids array length {len(valids_arr)} != action_size {action_size}"
        )
        assert int(np.sum(valids_arr)) == len(seen_actions), (
            f"Valids sum {int(np.sum(valids_arr))} != unique legal actions {len(seen_actions)}"
        )
        return valids_arr

    def getGameEnded(self, board, player):
        """
        Returns a scalar in [-1, 1]: 0 if game not ended, 1 if player won, -1 if player lost,
        small positive value for draw.
        
        Now matches C++ position.cpp check_if_game_is_over() logic.
        """
        # Stage-1 curriculum: end the game immediately after all placements are done
        # (outside the capture sub-phase), returning a shaped value as proxy target.
        if self._curriculum_enabled and int(self._curriculum_stage) == 1:
            # When placements are complete (put_pieces>=18) and not in capture
            if getattr(board, 'put_pieces', 0) >= 18 and int(getattr(board, 'period', 0)) != 3:
                return self._stage1_heuristic_value(board, player)

        # Use the comprehensive game over check that matches C++ logic
        is_game_over, result, reason = board.check_game_over_conditions(player)
        
        if is_game_over:
            assert reason is not None, f"Game ended but reason is None: result={result}, player={player}"
            assert -1 <= result <= 1, f"Game result {result} out of range [-1, 1]"
            return result
        
        # Legacy fallback for very long games
        if board.put_pieces >= self.num_draw:
            return 1e-4
        
        # Game continues
        return 0

    # -------------------- Curriculum helpers --------------------
    def set_curriculum(self, enabled: bool, stage: int, stage1_heuristic_weight: Optional[float] = None):
        """Configure curriculum training behavior.

        Args:
            enabled: Whether curriculum is active
            stage: 1=placing-only, 2=moving-no-flying, 3=full rules
            stage1_heuristic_weight: Optional weight used in early-stop value shaping
        """
        assert stage in (1, 2, 3), f"Invalid curriculum stage: {stage}"
        self._curriculum_enabled = bool(enabled)
        self._curriculum_stage = int(stage)
        if stage1_heuristic_weight is not None:
            self._stage1_heuristic_weight = float(stage1_heuristic_weight)

    def set_curriculum_stage(self, stage: int):
        """Shortcut to change only the stage (keeps other knobs)."""
        self.set_curriculum(self._curriculum_enabled, stage)

    def _stage1_heuristic_value(self, board, player) -> float:
        """Compute a shaped terminal value after placing-only phase.

        The goal is to provide a consistent non-zero signal before the
        moving phases begin. We use a small, bounded function of material
        difference on board (ignoring pieces in hand), plus a tiny bonus
        for having made the last placement (ply parity advantage).
        """
        try:
            material_diff = float(board.count(player) - board.count(-player))
        except Exception:
            material_diff = 0.0
        # Small advantage for the side to move after placements, approximating initiative
        side_to_move_bias = 0.1 if player == 1 else -0.1
        w = float(self._stage1_heuristic_weight)
        # Squash into (-1,1) with tanh, and keep magnitude small
        shaped = float(np.tanh(w * material_diff)) + side_to_move_bias * w
        # Ensure within [-0.5, 0.5] to avoid overpowering true terminals later
        if shaped > 0.5:
            shaped = 0.5
        if shaped < -0.5:
            shaped = -0.5
        return shaped

    def getCanonicalForm(self, board, player):
        """
        Returns canonical form of board independent of player. When player == 1
        return as-is; when player == -1, invert pieces.
        """
        b = deepcopy(board)
        # Record absolute side-to-move for this canonicalized board so that
        # in-hand computations (which depend on placement parity) remain
        # correct even when piece signs are flipped.
        try:
            b._to_move_is_white = bool(player == 1)
        except Exception:
            # Best-effort fallback
            b._to_move_is_white = True

        b.pieces = (player * np.array(b.pieces)).tolist()
        return b

    def getSymmetries(self, board, pi):
        """
        Returns a list of (board, pi) tuples under rotation/flip symmetries.
        """
        # Validate input pi
        assert hasattr(pi, '__len__'), "Pi must be array-like"
        assert len(pi) == self.getActionSize(), f"Pi length {len(pi)} != action_size {self.getActionSize()}"
        
        symmForms = []
        if board.period in [0, 3]:
            cache = self.cache_symmetries0
        else:
            cache = self.cache_symmetries1
        for i in range(5):
            for j in range(2):
                newB = np.rot90(np.array(board.pieces), i)
                if j == 1:
                    newB = np.fliplr(newB)
                newPi = np.zeros(self.getActionSize())
                newPi[cache[i * 2 + j]] = pi
                
                # Validate newPi length
                assert len(newPi) == self.getActionSize(), f"newPi length {len(newPi)} != action_size {self.getActionSize()}"
                symmForms.append((newB.tolist(), newPi.tolist()))
        return symmForms

    def stringRepresentation(self, board):
        """Stable bytes key for MCTS caches.

        为避免不同历史计数（影响终局判定）但同布局/同阶段的状态产生命中，
        将下列会影响 `getGameEnded` 的历史量纳入键：
        - put_pieces（精确值）
        - rule50_counter
        - move_counter
        - _threefold_detected（布尔）
        这样同样棋形但历史不同不会共用 `Es/Ps/Vs/Ns/Qsa` 条目，消除缓存不一致。
        """
        # 基本断言，确保必要字段存在
        assert hasattr(board, 'pieces'), "Board missing 'pieces'"
        assert hasattr(board, 'period'), "Board missing 'period'"
        assert hasattr(board, 'put_pieces'), "Board missing 'put_pieces'"
        # 历史相关字段：若不存在则按安全默认值处理
        rule50_counter = getattr(board, 'rule50_counter', 0)
        move_counter = getattr(board, 'move_counter', 0)
        threefold_detected = int(getattr(board, '_threefold_detected', False))

        pieces_bytes = np.array(board.pieces).tobytes()
        tail = f"|p{board.period}|pp{board.put_pieces}|r50{rule50_counter}|mc{move_counter}|t3{threefold_detected}"
        return pieces_bytes + tail.encode('utf-8')

    def getScore(self, board, player):
        """Heuristic score used by GreedyPlayer. Not used by training/MCTS.

        Positive favors 'player', negative favors opponent.
        """
        # If terminal, use game result directly
        r = self.getGameEnded(board, player)
        if abs(r) > 1e-6:
            return r
        # Otherwise, material difference with a small weight
        return 0.03 * (board.count(player) - board.count(-player))

    @staticmethod
    def display(board):
        """
        Pretty-print the board with visible connections between points.

        Layout:
        - Rows are labeled 7..1 from top to bottom (rank-like)
        - Columns are labeled a..g from left to right (file-like)
        - Pieces: Colored circles for clear distinction
          * White player: Yellow ● (bright, visible on any background)  
          * Black player: Blue ● (good contrast on any background)
          * Empty squares: · (neutral)
        - Shows connecting lines between adjacent points
        """
        from .standard_rules import coord_to_xy, xy_to_coord
        
        def get_piece_at(x, y):
            """Get piece symbol at position, or space if not a valid position."""
            if 0 <= x < 7 and 0 <= y < 7 and board.allowed_places[x][y] == 1:
                piece = board.pieces[x][y]
                return Game._get_piece_symbols()[piece]
            return " "
        
        def has_connection(x1, y1, x2, y2):
            """Check if two positions are connected by a line."""
            coord1 = xy_to_coord.get((x1, y1))
            coord2 = xy_to_coord.get((x2, y2))
            if not coord1 or not coord2:
                return False
            
            from .standard_rules import adjacent
            return coord2 in adjacent.get(coord1, [])
        
        print()
        
        # Outer ring (rank 7)
        y = 0  # Internal y=0 corresponds to rank 7
        print(f"7  {get_piece_at(0,y)}───────────{get_piece_at(3,y)}───────────{get_piece_at(6,y)}")
        print(f"   │           │           │")
        
        # Middle ring (rank 6)
        y = 1
        print(f"6  │   {get_piece_at(1,y)}───────{get_piece_at(3,y)}───────{get_piece_at(5,y)}   │")
        print(f"   │   │       │       │   │")
        
        # Inner ring (rank 5)
        y = 2
        print(f"5  │   │   {get_piece_at(2,y)}───{get_piece_at(3,y)}───{get_piece_at(4,y)}   │   │")
        print(f"   │   │   │       │   │   │")
        
        # Middle horizontal line (rank 4)
        y = 3
        print(f"4  {get_piece_at(0,y)}───{get_piece_at(1,y)}───{get_piece_at(2,y)}       {get_piece_at(4,y)}───{get_piece_at(5,y)}───{get_piece_at(6,y)}")
        print(f"   │   │   │       │   │   │")
        
        # Inner ring (rank 3)
        y = 4
        print(f"3  │   │   {get_piece_at(2,y)}───{get_piece_at(3,y)}───{get_piece_at(4,y)}   │   │")
        print(f"   │   │       │       │   │")
        
        # Middle ring (rank 2)
        y = 5
        print(f"2  │   {get_piece_at(1,y)}───────{get_piece_at(3,y)}───────{get_piece_at(5,y)}   │")
        print(f"   │           │           │")
        
        # Outer ring (rank 1)
        y = 6
        print(f"1  {get_piece_at(0,y)}───────────{get_piece_at(3,y)}───────────{get_piece_at(6,y)}")
        
        # Column labels
        print("   a   b   c   d   e   f   g")
        print()

    # -------------------- Standard-rule helpers (optional) --------------------
    def is_mill(self, board, move_dst_xy):
        """Return True if the destination square forms a mill after move.

        move_dst_xy: (x, y) where the piece ended up (placing or moving)
        """
        coord = xy_to_coord.get(tuple(move_dst_xy))
        if not coord:
            return False
        for a, b, c in mills:
            if coord in (a, b, c):
                ax, ay = coord_to_xy[a]
                bx, by = coord_to_xy[b]
                cx, cy = coord_to_xy[c]
                if board.pieces[ay][ax] == board.pieces[by][bx] == board.pieces[cy][cx] != 0:
                    return True
        return False


