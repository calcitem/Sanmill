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

    square_content = {
        -1: "X",
        +0: "-",
        +1: "O"
    }

    @staticmethod
    def getSquarePiece(piece):
        return Game.square_content[piece]

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
        valids = [0] * self.getActionSize()
        b = deepcopy(board)
        legalMoves = b.get_legal_moves(player)
        for move in legalMoves:
            action = b.get_action_from_move(move)
            valids[action] = 1
        return np.array(valids)

    def getGameEnded(self, board, player):
        """
        Returns a scalar in [-1, 1]: 0 if game not ended, 1 if player won, -1 if player lost,
        small positive value for draw.
        
        Now matches C++ position.cpp check_if_game_is_over() logic.
        """
        # Use the comprehensive game over check that matches C++ logic
        is_game_over, result, reason = board.check_game_over_conditions(player)
        
        if is_game_over:
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
        n = 7
        print("   ", end="")
        for y in range(n):
            print(y, end=" ")
        print("")
        print("-----------------------")
        for y in range(n):
            print(y, "|", end="")  # print the row #
            for x in range(n):
                piece = board.pieces[y][x]  # get the piece to print
                if board.allowed_places[x][y] == 1:
                    print(Game.square_content[piece], end=" ")
                else:
                    print(end="  ")
            print("|")

        print("-----------------------")

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


