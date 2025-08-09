"""
Board class and move generation logic for Nine Men's Morris (standard rules).

Board data:
  1 = white, -1 = black, 0 = empty
  First dim is column, second dim is row:
     pieces[1][7] is the square in column 2, at the opposite end of the board in row 8.
Squares are stored and manipulated as (x, y) tuples where x is the column and y is the row.
"""

import numpy as np
from .standard_rules import xy_to_coord, coord_to_xy, adjacent


class Board:

    allowed_places = np.array([[1, 0, 0, 1, 0, 0, 1],
                               [0, 1, 0, 1, 0, 1, 0],
                               [0, 0, 1, 1, 1, 0, 0],
                               [1, 1, 1, 0, 1, 1, 1],
                               [0, 0, 1, 1, 1, 0, 0],
                               [0, 1, 0, 1, 0, 1, 0],
                               [1, 0, 0, 1, 0, 0, 1]], dtype=np.bool_)

    shrink_places = np.array([[[16, 17, 18],
                               [23, -1, 25],
                               [30, 31, 32]],
                              [[8, 10, 12],
                               [22, -1, 26],
                               [36, 38, 40]],
                              [[0, 3, 6],
                               [21, -1, 27],
                               [42, 45, 48]]], dtype=np.int_)

    def __init__(self):
        self.n = 7
        # The phase (period) of the game.
        # 0: placing pieces
        # 1: moving pieces (adjacent only)
        # 2: flying (when one player has only 3 pieces left)
        # 3: capture (after forming a mill)
        self.period = 0
        self.put_pieces = 0
        # Create the empty board array.
        self.pieces = [None] * self.n
        for i in range(self.n):
            self.pieces[i] = [0] * self.n

    def __getitem__(self, index):
        return self.pieces[index]

    def count(self, color):
        """Counts the number of pieces of the given color (1, -1)."""
        count = 0
        for y in range(self.n):
            for x in range(self.n):
                if self[x][y] == color:
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
        Transform board pieces to a 3x3x3 array to compute legal moves conveniently.
        """
        shrink_peices = np.zeros((3, 3, 3), dtype=np.int_)

        for i in range(7):
            for j in range(7):
                for k in range(1, 4):
                    if (abs(i - 3) == k or abs(j - 3) == k) \
                            and abs(i - 3) in [0, k] \
                            and abs(j - 3) in [0, k]:
                        shrink_peices[k - 1,
                                      self._new_index(i),
                                      self._new_index(j)] = board[i][j]
        return shrink_peices

    def get_legal_moves(self, color):
        """Returns all legal moves for the given color (1 for white, -1 for black)."""
        if self.period == 0:
            # All empty squares are valid placements in period 0.
            empty_places = self.allowed_places - np.abs(np.array(self.pieces))
            return np.transpose(np.where(empty_places == 1)).tolist()
        elif self.period == 3:
            # Capture phase: choose any opponent piece to remove.
            moves = np.array(self.pieces)
            return np.transpose(np.where(moves == -color)).tolist()
        elif self.period == 2 and self.count(color) <= 3:
            # Flying phase: choose any own piece and any empty destination.
            pieces = np.array(self.pieces)
            moves0 = np.transpose(np.where(pieces == color)).tolist()
            empty_places = self.allowed_places - np.abs(np.array(self.pieces))
            moves1 = np.transpose(np.where(empty_places == 1)).tolist()
            moves = []
            for move0 in moves0:
                for move1 in moves1:
                    moves.append(move0 + move1)
            return moves
        else:
            # Moving phase: enumerate adjacent moves using the 3x3x3 representation.
            shrink_pieces = self.get_shrink_pieces(self.pieces)
            moves = []
            for i in range(3):
                for j in range(3):
                    for k in range(3):
                        if j == k == 1:
                            continue
                        if shrink_pieces[i, j, k] == color:
                            moves.extend(self.get_adjacent_places(i, j, k, shrink_pieces))
            return moves

    def get_valids_in_period1(self):
        shrink_pieces = self.get_shrink_pieces(self.pieces)
        moves = []
        for i in range(3):
            for j in range(3):
                for k in range(3):
                    if j == k == 1:
                        continue
                    moves.extend(self.get_adjacent_places(i, j, k, shrink_pieces))
        return moves

    def get_move_from_action(self, action):
        """
        Convert an action index to a move representation depending on the current period.

        Input:
            action: integer index
        Returns:
            move: list of size 2 or 4
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
        Convert a move (size 2 or 4) into an action index for the current period.
        """
        place_index = np.zeros((7, 7), dtype=np.int_)
        place_index[self.allowed_places] = np.arange(24)
        if len(move) == 2:
            return place_index[move[0], move[1]]
        else:
            move0 = place_index[move[0], move[1]]
            move1 = place_index[move[2], move[3]]
            return move0 * 24 + move1

    def get_adjacent_places(self, i, j, k, shrink_pieces):
        """
        Returns the adjacent moves from index (i, j, k) in the 3x3x3 representation.
        """
        adjacency_moves = []

        # Check every neighbor by Manhattan distance 1, excluding the center ring,
        # and only keep empty destinations in the board representation.
        for x in range(max(0, i - 1), min(3, i + 2)):
            for y in range(max(0, j - 1), min(3, j + 2)):
                for z in range(max(0, k - 1), min(3, k + 2)):
                    # Must be a direct neighbor in the 3D shrink space
                    if abs(x - i) + abs(y - j) + abs(z - k) != 1:
                        continue

                    # Skip the (ring center) that does not correspond to any board point
                    if y == 1 and z == 1:
                        continue

                    # Disallow diagonal cross-ring transitions at corner positions.
                    # Standard Nine Men's Morris allows cross-ring edges only at mid-edge positions
                    # (i.e., when either local index equals 1). Corners (0 or 2) cannot cross rings.
                    if x != i:
                        if not (y == 1 or z == 1):
                            continue

                    # Destination square must be empty on the board
                    if shrink_pieces[x, y, z] != 0:
                        continue

                    place_index0 = self.shrink_places[i, j, k]
                    place_index1 = self.shrink_places[x, y, z]
                    adjacency_moves.append([
                        place_index0 // 7, place_index0 % 7,
                        place_index1 // 7, place_index1 % 7,
                    ])

        return adjacency_moves

    def execute_move(self, move, player):
        """Perform the given move on the board; flips pieces as necessary.
        color gives the color of the piece to play (1=white, -1=black).
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
        """Check if the move forms a mill (a line of 3 pieces)."""
        shrink_pieces = self.get_shrink_pieces(self.pieces)
        shrink_pieces[shrink_pieces != player] = 0
        shrink_pieces = np.abs(shrink_pieces)
        move_player = move if len(move) == 2 else move[2:]
        action = move_player[0] * self.n + move_player[1]
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

    def display_board(self):
        """Return an ASCII representation with lines and O/@ pieces.

        - O: White (1)
        - @: Black (-1)
        - .: Empty node
        Lines are drawn along legal edges defined by standard rules (no diagonals).
        """
        size = self.n * 2 - 1  # expand to place edges between nodes
        canvas = [[" " for _ in range(size)] for _ in range(size)]

        # Place nodes
        for y in range(self.n):
            for x in range(self.n):
                if not self.allowed_places[x][y]:
                    continue
                ch = "."
                if self.pieces[x][y] == 1:
                    ch = "O"
                elif self.pieces[x][y] == -1:
                    ch = "@"
                canvas[2 * y][2 * x] = ch

        # Draw edges according to standard adjacency (engine rules)
        drawn = set()
        for c, neighs in adjacent.items():
            x, y = coord_to_xy[c]
            for n in neighs:
                nx, ny = coord_to_xy[n]
                key = tuple(sorted(((x, y), (nx, ny))))
                if key in drawn:
                    continue
                drawn.add(key)
                x0, y0 = 2 * x, 2 * y
                x1, y1 = 2 * nx, 2 * ny
                if x0 == x1:
                    # vertical line
                    for yy in range(min(y0, y1) + 1, max(y0, y1)):
                        canvas[yy][x0] = "|"
                elif y0 == y1:
                    # horizontal line
                    for xx in range(min(x0, x1) + 1, max(x0, x1)):
                        canvas[y0][xx] = "-"
                # no diagonals

        return "\n".join("".join(row) for row in canvas)


