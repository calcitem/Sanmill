'''
Author: Cheanus
Date: Sep 16, 2023.
Board class.
Board data:
  1=white, -1=black, 0=empty
  first dim is column , 2nd is row:
     pieces[1][7] is the square in column 2,
     at the opposite end of the board in row 8.
Squares are stored and manipulated as (x,y) tuples.
x is the column, y is the row.
'''
import numpy as np

class Board():

    allowed_places = np.array([[1,0,0,1,0,0,1],
                               [0,1,0,1,0,1,0],
                               [0,0,1,1,1,0,0],
                               [1,1,1,0,1,1,1],
                               [0,0,1,1,1,0,0],
                               [0,1,0,1,0,1,0],
                               [1,0,0,1,0,0,1]], dtype=np.bool_)
        
    shrink_places = np.array([[[16, 17, 18],
                                 [23, -1, 25],
                                 [30, 31, 32]],
                                 [[8, 10, 12],
                                 [22, -1, 26],
                                 [36, 38, 40]],
                                 [[0,  3,  6],
                                 [21, -1, 27],
                                 [42, 45, 48]]], dtype=np.int_)

    def __init__(self):
        self.n = 7
        # the period of the game (0, 1, 2, 3)
        # 0: put pieces
        # 1: move pieces
        # 2: move pieces when one player only has 3 pieces left
        self.period = 0
        self.put_pieces = 0
        # Create the empty board array.
        self.pieces = [None]*self.n
        for i in range(self.n):
            self.pieces[i] = [0]*self.n

    def __getitem__(self, index): 
        return self.pieces[index]
    
    def count(self, color):
        """Counts the # pieces of the given color
        (1 for white, -1 for black, 0 for empty spaces)"""
        count = 0
        for y in range(self.n):
            for x in range(self.n):
                if self[x][y]==color:
                    count += 1
        return count
    
    def has_legal_moves(self, color):
        if self.period in [0, 3]:
            return True
        if len(self.get_legal_moves(color)) == 0:
            return False
        return True

    def _new_index(self, i):
        if i < 3:
            return 0
        elif i == 3:
            return 1
        elif i > 3:
            return 2
    
    def get_shrink_pieces(self, board):
        """
        Transform board pieces to a 3*3*3 array to get legal moves conveniently.
        """
        shrink_peices = np.zeros((3,3,3),dtype=np.int_)
        
        for i in range(7):
            for j in range(7):
                for k in range(1, 4):
                    if (abs(i-3) == k or abs(j-3) == k) \
                        and abs(i-3) in [0,k] \
                        and abs(j-3) in [0,k]:
                        shrink_peices[k - 1,
                                      self._new_index(i),
                                      self._new_index(j)] = board[i][j]
        return shrink_peices

    def get_legal_moves(self, color):
        """Returns all the legal moves for the given color.
        (1 for white, -1 for black)
        """
        if self.period == 0:
            # Get all the empty squares
            empty_places = self.allowed_places - np.abs(np.array(self.pieces))
            return np.transpose(np.where(empty_places==1)).tolist()
        elif self.period == 3:
            moves = np.array(self.pieces)
            return np.transpose(np.where(moves==-color)).tolist()
        elif self.period == 2 and self.count(color) == 3:
            pieces = np.array(self.pieces)
            moves0 = np.transpose(np.where(pieces==color)).tolist()
            empty_places = self.allowed_places - np.abs(np.array(self.pieces))
            moves1 = np.transpose(np.where(empty_places==1)).tolist()
            moves = []
            for move0 in moves0:
                for move1 in moves1:
                    moves.append(move0 + move1)
            return moves
        else:
            # Get all the shrink_pieces
            shrink_pieces = self.get_shrink_pieces(self.pieces)
            moves = []
            for i in range(3):
                for j in range(3):
                    for k in range(3):
                        if j == k == 1:
                            continue
                        if shrink_pieces[i,j,k] == color:
                            moves.extend(self.get_adjacent_places(i,j,k, shrink_pieces))
                        
            return moves
        
    def get_valids_in_period1(self):
        shrink_pieces = self.get_shrink_pieces(self.pieces)
        moves = []
        for i in range(3):
            for j in range(3):
                for k in range(3):
                    if j == k == 1:
                        continue
                    moves.extend(self.get_adjacent_places(i,j,k, shrink_pieces))
                    
        return moves

    def get_move_from_action(self, action):
        """
        Returns the move from the action in the period
        Input:
            action: an index, action taken by current player
        Returns:
            move: an tuple or list of size 2 or 4, move taken by current player
        """
        place_index = np.transpose(np.where(self.allowed_places == 1))
        if self.period in [0, 3]:
            return place_index[action].tolist()
        else:
            action0 = place_index[action // 24].tolist()
            action1 = place_index[action % 24].tolist()
            return action0 + action1

    def get_action_from_move(self, move):
        """
        Returns the action from the move in the period
        Input:
            move: an array of size 2 or 4, move taken by current player
        Returns:
            action: an index, action taken by current player
        """
        place_index = np.zeros((7,7), dtype=np.int_)
        place_index[self.allowed_places] = np.arange(24)
        if len(move) == 2:
            return place_index[move[0], move[1]]
        else:
            move0 = place_index[move[0], move[1]]
            move1 = place_index[move[2], move[3]]
            return move0*24 + move1
        
    def get_adjacent_places(self, i, j, k, shrink_pieces):
        """
        Returns the adjacent array of the index in the shape
        """
        # 创建一个全零的矩阵
        adjacency_matrix = []
        
        # 检查每个相邻的位置，如果在合法范围内，将其值设为1
        for x in range(max(0, i-1), min(3, i+2)):
            for y in range(max(0, j-1), min(3, j+2)):
                for z in range(max(0, k-1), min(3, k+2)):
                    if abs(x-i) + abs(y-j) + abs(z-k) == 1 \
                        and abs(y-1) + abs(z-1) != 0 \
                        and shrink_pieces[x,y,z] == 0:
                        place_index0 = self.shrink_places[i,j,k]
                        place_index1 = self.shrink_places[x,y,z]
                        adjacency_matrix.append([place_index0//7, place_index0%7,
                                                 place_index1//7, place_index1%7])

        return adjacency_matrix
    
    def execute_move(self, move, player):
        """Perform the given move on the board; flips pieces as necessary.
        color gives the color pf the piece to play (1=white,-1=black)
        """
        if self.period == 0:
            self.pieces[move[0]][move[1]] = player
        elif self.period == 3:
            self.pieces[move[0]][move[1]] = 0
        else:
            self.pieces[move[0]][move[1]] = 0
            self.pieces[move[2]][move[3]] = player
        self.update_period(move, player)
        
    def update_period(self, move, player):
        if self.period == 3:
            self.period = 0
        else:
            self.put_pieces += 1
            if self.line3(move, player):
                self.period = 3
                return
        if self.put_pieces >= 18:
            self.period = 1
            if self.count(-1) <= 3 or self.count(1) <= 3:
                self.period = 2
    
    def line3(self, move, player):
        """
        Check if the move can make a line of 3 pieces
        """
        shrink_pieces = self.get_shrink_pieces(self.pieces)
        shrink_pieces[shrink_pieces != player] = 0
        shrink_pieces = np.abs(shrink_pieces)
        move_player = move if len(move) == 2 else move[2:]
        action = move_player[0]*self.n + move_player[1]
        index = np.where(self.shrink_places == action)
        is_line3 = False
        for i in range(3):
            if i == 0:
                pieces_line = shrink_pieces[:, index[1], index[2]]
            elif i == 1:
                pieces_line = shrink_pieces[index[0], :, index[2]]
            else:
                pieces_line = shrink_pieces[index[0], index[1], :]
            is_line3 = is_line3 or (pieces_line.sum() == 3)
        return is_line3