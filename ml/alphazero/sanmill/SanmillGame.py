from __future__ import print_function
import sys
sys.path.append('..')
from .SanmillLogic import Board
import numpy as np
from copy import deepcopy

class SanmillGame():
    """
    This class specifies the base Game class. To define your own game, subclass
    this class and implement the functions below. This works when the game is
    two-player, adversarial and turn-based.

    Use 1 for player1 and -1 for player2.

    See othello/OthelloGame.py for an example implementation.
    """
    square_content = {
        -1: "X",
        +0: "-",
        +1: "O"
    }

    @staticmethod
    def getSquarePiece(piece):
        return SanmillGame.square_content[piece]

    def __init__(self):
        self.n = 7
        self.num_draw = 100
        self.cache_symmetries()
    
    def reward_w_func(self, put_pieces):
        return 1 if put_pieces <= 40 else 1-(put_pieces-40)/(self.num_draw-40)
    
    def cache_symmetries(self):
        place_index = np.zeros((self.n,self.n), dtype=np.int_)
        place_index[Board.allowed_places] = np.arange(24)
        self.cache_symmetries0 = []
        for i in range(5):
            for j in range(2):
                cache = np.rot90(place_index, i)
                if j == 1:
                    cache = np.fliplr(cache)
                self.cache_symmetries0.append(cache[Board.allowed_places])
        
        self.cache_symmetries1 = []
        action_index = np.arange(24*24,dtype=np.int_).reshape((24,24))
        for i in range(5):
            for j in range(2):
                cache = np.zeros((24,24), dtype=np.int_)
                cache[self.cache_symmetries0[i*2+j],:] = action_index
                cache2 = cache.copy()
                cache2[:,self.cache_symmetries0[i*2+j]] = cache
                self.cache_symmetries1.append(cache2.ravel())

        for i in range(5):
            for j in range(2):
                cache = np.arange(24*24,dtype=np.int_)
                cache[:24] = self.cache_symmetries0[i*2+j]
                self.cache_symmetries0[i*2+j] = cache


    def getInitBoard(self):
        """
        Returns:
            startBoard: a representation of the board (ideally this is the form
                        that will be the input to your neural network)
        """
        return Board()

    def getBoardSize(self):
        """
        Returns:
            (x,y): a tuple of board dimensions
        """
        return (self.n, self.n)

    def getActionSize(self):
        """
        Returns:
            actionSize: number of all possible actions
        """
        return 24*24

    def getNextState(self, board, player, action):
        """
        Input:
            board: current board
            player: current player (1 or -1)
            action: action taken by current player

        Returns:
            nextBoard: board after applying action
            nextPlayer: player who plays in the next turn (should be -player)
        """
        b = deepcopy(board)
        move = b.get_move_from_action(action)
        b.execute_move(move, player)
        if b.period == 3:
            return (b, player)
        else:
            return (b, -player)

    def getValidMoves(self, board, player):
        """
        Input:
            board: current board
            player: current player

        Returns:
            validMoves: a binary vector of length self.getActionSize(), 1 for
                        moves that are valid from the current board and player,
                        0 for invalid moves
        """
        valids = [0]*self.getActionSize()
        b = deepcopy(board)
        legalMoves = b.get_legal_moves(player)
        for move in legalMoves:
            action = b.get_action_from_move(move)
            valids[action]=1
        return np.array(valids)

    def getGameEnded(self, board, player):
        """
        Input:
            board: current board
            player: current player (1 or -1)

        Returns:
            r: 0 if game has not ended. 1 if player won, -1 if player lost,
               small non-zero value for draw.
               
        """
        reward = 0
        if board.period in [0, 3]:
            reward = 0
        elif board.put_pieces >= self.num_draw:
            reward = 1e-4
        elif not board.has_legal_moves(player):
            reward = -1*self.reward_w_func(board.put_pieces) + 0.03*(board.count(player)-board.count(-player))
        elif board.period == 2 and board.count(player) < 3:
            reward = -1*self.reward_w_func(board.put_pieces) + 0.03*(board.count(player)-board.count(-player))
        elif not board.has_legal_moves(-player):
            reward = 1*self.reward_w_func(board.put_pieces) + 0.03*(board.count(player)-board.count(-player))
        elif board.period == 2 and board.count(-player) < 3:
            reward = 1*self.reward_w_func(board.put_pieces) + 0.03*(board.count(player)-board.count(-player))
        return min(max(reward, -1), 1)

    def getCanonicalForm(self, board, player):
        """
        Input:
            board: current board
            player: current player (1 or -1)

        Returns:
            canonicalBoard: returns canonical form of board. The canonical form
                            should be independent of player. For e.g. in chess,
                            the canonical form can be chosen to be from the pov
                            of white. When the player is white, we can return
                            board as is. When the player is black, we can invert
                            the colors and return the board.
        """
        b = deepcopy(board)
        b.pieces = (player*np.array(b.pieces)).tolist()
        return b

    def getSymmetries(self, board, pi):
        """
        Input:
            board: current board
            pi: policy vector of size self.getActionSize()

        Returns:
            symmForms: a list of [(board,pi)] where each tuple is a symmetrical
                       form of the board and the corresponding pi vector. This
                       is used when training the neural network from examples.
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
                newPi[cache[i*2+j]] = pi
                symmForms.append((newB.tolist(), newPi.tolist()))
        return symmForms

    def stringRepresentation(self, board):
        """
        Input:
            board: current board

        Returns:
            boardString: a quick conversion of board to a string format.
                         Required by MCTS for hashing.
        """
        tail = str(board.period) + str(board.put_pieces>=self.num_draw)
        return np.array(board.pieces).tobytes()+tail.encode('utf-8')

    @staticmethod
    def display(board):
        n = 7
        print("   ", end="")
        for y in range(n):
            print(y, end=" ")
        print("")
        print("-----------------------")
        for y in range(n):
            print(y, "|", end="")    # print the row #
            for x in range(n):
                piece = board.pieces[y][x]    # get the piece to print
                if board.allowed_places[x][y] == 1:
                    print(SanmillGame.square_content[piece], end=" ")
                else:
                    print(end="  ")
            print("|")

        print("-----------------------")