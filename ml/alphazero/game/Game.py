from __future__ import print_function
from copy import deepcopy
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
        Get piece symbols using colored circles for better distinction.
        Uses ANSI color codes with the same ● symbol to maintain alignment.
        White player: Yellow ● (bright and visible on both backgrounds)
        Black player: Blue ● (good contrast on both backgrounds)
        """
        # ANSI color codes
        YELLOW = "\033[93m"  # Bright yellow
        BLUE = "\033[94m"    # Bright blue
        RESET = "\033[0m"    # Reset to default color
        
        return {
            -1: f"{BLUE}●{RESET}",    # Black player uses blue circle
            +0: "·",                   # Empty squares (no color)
            +1: f"{YELLOW}●{RESET}"    # White player uses yellow circle
        }



    @staticmethod
    def getSquarePiece(piece):
        return Game._get_piece_symbols()[piece]

    def __init__(self):
        self.n = 7
        self.num_draw = 100
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
        return Board()

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

    def getCanonicalForm(self, board, player):
        """
        Returns canonical form of board independent of player. When player == 1
        return as-is; when player == -1, invert pieces.
        """
        b = deepcopy(board)
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
        """Fast bytes representation used as a hash key in MCTS."""
        tail = str(board.period) + str(board.put_pieces >= self.num_draw)
        return np.array(board.pieces).tobytes() + tail.encode('utf-8')

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


