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
        
        # Draw rule tracking
        self.rule50_counter = 0  # Counter for consecutive MOVE-type moves only
        self.position_history = []  # History of positions for repetition detection
        self.move_history = []  # History of moves for debugging
        self.move_counter = 0  # Total move counter (like posKeyHistory.size() in C++)
        
        # Rule configuration (can be customized)
        self.n_move_rule = 100  # Standard N-move rule (uses move_counter, not rule50_counter)
        self.endgame_n_move_rule = 100  # Endgame rule when either player has ≤3 pieces
        self.threefold_repetition_rule = True  # Enable threefold repetition
        self.pieces_at_least_count = 3  # Minimum pieces to continue playing (default=3)
        self.pieces_count = 9  # Total pieces per player (default=9)
        
        # Threefold repetition detection flags (matches C++ behavior)
        self._threefold_detected = False
        self._threefold_reason = None
        # Track the player who made the last executed move (1 or -1). Used to
        # derive side-to-move for position hashing to match C++ keys.
        self._last_move_player = None
        
        # Create the empty board array.
        self.pieces = [None] * self.n
        for i in range(self.n):
            self.pieces[i] = [0] * self.n
        # Invariants
        assert self.allowed_places.shape == (7, 7), "allowed_places must be 7x7"
        assert int(np.sum(self.allowed_places)) == 24, "allowed_places must contain exactly 24 valid squares"
        assert self.period in (0, 1, 2, 3), f"Invalid initial period: {self.period}"

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
            placing_moves = np.transpose(np.where(empty_places == 1)).tolist()
            # Validate placing moves
            for move in placing_moves:
                assert len(move) == 2, f"Placing move must have 2 coordinates: {move}"
                for coord in move:
                    assert 0 <= coord < 7, f"Move coordinate {coord} out of bounds [0,7)"
                # Must be on allowed places and empty
                assert self.allowed_places[move[0], move[1]] == 1, f"Placing target {move} not on allowed_places"
                assert self.pieces[move[0]][move[1]] == 0, f"Placing target {move} not empty"
            return placing_moves
        elif self.period == 3:
            # Capture phase: choose opponent pieces to remove with proper mill logic
            return self._get_removal_moves(color)
        elif self.period == 2 and self.count(color) <= 3:
            # Flying phase: choose any own piece and any empty destination.
            # Only allow flying if we have ≤3 pieces on board and no pieces in hand
            if self._can_fly(color):
                pieces = np.array(self.pieces)
                moves0 = np.transpose(np.where(pieces == color)).tolist()
                empty_places = self.allowed_places - np.abs(np.array(self.pieces))
                moves1 = np.transpose(np.where(empty_places == 1)).tolist()
                moves = []
                for move0 in moves0:
                    for move1 in moves1:
                        fly_move = move0 + move1
                        # Validate flying move
                        assert len(fly_move) == 4, f"Flying move must have 4 coordinates: {fly_move}"
                        # Source must contain player's piece
                        assert self.pieces[fly_move[0]][fly_move[1]] == color, f"Flying source {fly_move[:2]} must contain player piece"
                        # Destination must be empty
                        assert self.pieces[fly_move[2]][fly_move[3]] == 0, f"Flying destination {fly_move[2:]} must be empty"
                        # Both must be on allowed places
                        assert self.allowed_places[fly_move[0], fly_move[1]] == 1, f"Flying source {fly_move[:2]} not on allowed_places"
                        assert self.allowed_places[fly_move[2], fly_move[3]] == 1, f"Flying destination {fly_move[2:]} not on allowed_places"
                        moves.append(fly_move)
                return moves
            else:
                # Fall back to normal moving if flying conditions not met
                return self._get_normal_moves(color)
        else:
            # Normal moving phase: enumerate adjacent moves
            return self._get_normal_moves(color)

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
        
        # Assert action is valid for current period
        if self.period in [0, 3]:  # Placing phase
            assert 0 <= action < 24, f"Invalid action {action} for period {self.period} (placing), must be in [0, 24)"
            assert action < len(place_index), f"Action {action} >= place_index length {len(place_index)} in period {self.period}"
            return place_index[action].tolist()
        else:  # Moving phase
            assert 0 <= action < 24*24, f"Invalid action {action} for period {self.period} (moving), must be in [0, {24*24})"
            action0_idx = action // 24
            action1_idx = action % 24
            assert action0_idx < len(place_index), f"Action0 index {action0_idx} >= place_index length {len(place_index)}"
            assert action1_idx < len(place_index), f"Action1 index {action1_idx} >= place_index length {len(place_index)}"
            action0 = place_index[action0_idx].tolist()
            action1 = place_index[action1_idx].tolist()
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

    def _can_fly(self, color):
        """Check if flying is allowed based on C++ engine rules."""
        # Flying is allowed when:
        # 1. We have 3 or fewer pieces on board
        # 2. We have no pieces in hand (all pieces have been placed)
        pieces_on_board = self.count(color)
        # Assume pieces in hand = 0 when put_pieces >= 18 (all placed)
        pieces_in_hand = max(0, 9 - (self.put_pieces // 2 if color == 1 else (self.put_pieces + 1) // 2))
        
        return pieces_on_board <= 3 and pieces_in_hand == 0

    def _get_normal_moves(self, color):
        """Get normal adjacent moves for the moving phase."""
        shrink_pieces = self.get_shrink_pieces(self.pieces)
        moves = []
        for i in range(3):
            for j in range(3):
                for k in range(3):
                    if j == k == 1:
                        continue
                    if shrink_pieces[i, j, k] == color:
                        moves.extend(self.get_adjacent_places(i, j, k, shrink_pieces))
        
        # Validate all generated moves fall on allowed_places
        for move in moves:
            assert len(move) == 4, f"Normal move must have 4 coordinates: {move}"
            for coord in move:
                assert 0 <= coord < 7, f"Move coordinate {coord} out of bounds [0,7)"
            # Source and destination must be on allowed places
            assert self.allowed_places[move[0], move[1]] == 1, f"Source {move[:2]} not on allowed_places"
            assert self.allowed_places[move[2], move[3]] == 1, f"Destination {move[2:]} not on allowed_places"
            # For period 1, enforce adjacency (this is already handled by get_adjacent_places)
            if self.period == 1:
                # Additional adjacency check can be added here if needed
                pass
        
        return moves

    def _get_removal_moves(self, color):
        """Get removal moves following C++ engine logic."""
        opponent_color = -color
        moves = []
        
        # Get all opponent pieces
        opponent_pieces = []
        for x in range(self.n):
            for y in range(self.n):
                if self.pieces[x][y] == opponent_color:
                    opponent_pieces.append([x, y])
        
        # Check if all opponent pieces are in mills
        all_in_mills = True
        non_mill_pieces = []
        mill_pieces = []
        
        for piece_pos in opponent_pieces:
            if self._is_piece_in_mill(piece_pos, opponent_color):
                mill_pieces.append(piece_pos)
            else:
                non_mill_pieces.append(piece_pos)
                all_in_mills = False
        
        # If not all pieces are in mills, only allow removing non-mill pieces
        if not all_in_mills:
            result_moves = non_mill_pieces
        else:
            # If all pieces are in mills, allow removing any piece
            result_moves = opponent_pieces
        
        # Validate all removal moves fall on allowed_places
        for move in result_moves:
            assert len(move) == 2, f"Removal move must have 2 coordinates: {move}"
            for coord in move:
                assert 0 <= coord < 7, f"Move coordinate {coord} out of bounds [0,7)"
            # Must be on allowed places
            assert self.allowed_places[move[0], move[1]] == 1, f"Removal target {move} not on allowed_places"
            # Must actually contain opponent piece
            assert self.pieces[move[0]][move[1]] == opponent_color, f"Removal target {move} does not contain opponent piece"
        
        return result_moves

    def _is_piece_in_mill(self, piece_pos, color):
        """Check if a piece at the given position is part of a mill."""
        x, y = piece_pos
        
        # Convert to coordinate system used in standard_rules.py
        from .standard_rules import xy_to_coord, mills
        
        coord = xy_to_coord.get((x, y))
        if not coord:
            return False
            
        # Check all mill triplets to see if this position is part of one
        for mill_triplet in mills:
            if coord in mill_triplet:
                # Check if all three positions in this mill have the same color pieces
                all_same = True
                for mill_coord in mill_triplet:
                    mill_x, mill_y = self._coord_to_xy(mill_coord)
                    if mill_x is None or mill_y is None:
                        all_same = False
                        break
                    if self.pieces[mill_x][mill_y] != color:
                        all_same = False
                        break
                
                if all_same:
                    return True
        
        return False

    def get_position_hash(self):
        """
        Generate a hash representing the current board position.
        Used for detecting threefold repetition.

        IMPORTANT: Include side-to-move information to match C++ Zobrist key.
        We only record history after MOVE-type moves, for which the side-to-move
        is the opponent of the last mover (unless in capture, which is excluded
        from history). Thus, side_to_move is derived from _last_move_player.
        """
        # Create a string representation of the board state
        board_str = ""
        for x in range(self.n):
            for y in range(self.n):
                if self.allowed_places[x][y]:
                    board_str += str(self.pieces[x][y])

        # Derive side to move: after a MOVE, opponent moves next. If unknown, default to 1.
        side_to_move = 1 if self._last_move_player is None else -self._last_move_player

        # Include both period and side_to_move in the key
        position_key = f"{board_str}_{self.period}_stm{side_to_move}"
        return hash(position_key)

    def has_repeated_position(self):
        """
        Check if the current position has occurred before (for threefold repetition).
        Following C++ logic: position.cpp:has_game_cycle() returns count >= 3.
        """
        if not self.threefold_repetition_rule:
            return False
            
        current_hash = self.get_position_hash()
        
        # Count occurrences of current position in history
        # In C++, count includes current position, so >= 3 means third repetition
        count = self.position_history.count(current_hash) + 1  # +1 for current position
        
        # Return True if this is the third occurrence (count >= 3)
        return count >= 3

    def is_draw_by_nmove_rules(self):
        """
        Check if the current position is a draw according to N-move rules only.
        This matches C++ position.cpp:check_if_game_is_over() which only checks N-move rules.
        Threefold repetition is checked separately after move execution.
        """
        # Check N-move rule based on total move count (like posKeyHistory.size() in C++)
        # This is the main draw condition, not the rule50 counter
        if self.n_move_rule > 0 and self.move_counter >= self.n_move_rule:
            return True, "drawFiftyMove"
        
        # Check endgame N-move rule for positions with ≤3 pieces
        if (self.endgame_n_move_rule < self.n_move_rule and
            self.is_endgame() and
            self.move_counter >= self.endgame_n_move_rule):
            return True, "drawEndgameFiftyMove"
        
        return False, None

    def is_draw_by_rules(self):
        """
        Check if the current position is a draw according to ALL draw rules.
        This includes both N-move rules and threefold repetition.
        Used for comprehensive draw checking when needed.
        """
        # Check N-move rules first
        is_draw, reason = self.is_draw_by_nmove_rules()
        if is_draw:
            return True, reason
        
        # Check threefold repetition
        if self.has_repeated_position():
            return True, "drawThreefoldRepetition"
        
        return False, None

    def is_endgame(self):
        """
        Check if we're in endgame phase (either player has only 3 pieces).
        """
        return self.count(1) <= 3 or self.count(-1) <= 3

    def pieces_in_hand_count(self, color):
        """
        Calculate pieces in hand for a player.
        Based on total pieces minus pieces on board.
        """
        pieces_on_board = self.count(color)
        total_pieces_placed = self.put_pieces // 2 if color == 1 else (self.put_pieces + 1) // 2
        return max(0, self.pieces_count - total_pieces_placed)

    def total_pieces_count(self, color):
        """
        Get total pieces count (on board + in hand) for a player.
        Matches C++ logic: pieceOnBoardCount[color] + pieceInHandCount[color]
        """
        return self.count(color) + self.pieces_in_hand_count(color)

    def check_fewer_than_minimum_pieces(self, color):
        """
        Check if player has fewer than minimum required pieces.
        Matches C++ logic from position.cpp:1081-1084
        """
        total_pieces = self.total_pieces_count(color)
        return total_pieces < self.pieces_at_least_count

    def has_legal_moves(self, color):
        """
        Check if a player has any legal moves.
        Returns False if no legal moves available (stalemate).
        """
        if self.period in [0, 3]:
            # In placing/removal phase, always has moves if the phase allows it
            return True
        
        legal_moves = self.get_legal_moves(color)
        return len(legal_moves) > 0

    def is_all_surrounded(self, color):
        """
        Check if all pieces of a color are surrounded (no legal moves).
        Matches C++ is_all_surrounded logic for stalemate detection.
        """
        if self.period not in [1, 2]:  # Only in moving/flying phase
            return False
        
        return not self.has_legal_moves(color)

    def check_game_over_conditions(self, current_player):
        """
        Check all game over conditions following C++ position.cpp:check_if_game_is_over() logic.
        Threefold repetition is checked after move execution and stored in flags.
        Returns tuple (is_game_over, result, reason).
        
        result: 1 if current_player wins, -1 if loses, small positive for draw
        """
        # 0. Check threefold repetition flag first (detected after move execution)
        if self._threefold_detected:
            # Small positive value for draws with material bias
            material_bias = 0.03 * (self.count(current_player) - self.count(-current_player))
            return True, min(max(1e-4 + material_bias, -1), 1), self._threefold_reason
        
        # 1. Check if opponent has too few pieces (current player wins)
        opponent = -current_player
        if self.check_fewer_than_minimum_pieces(opponent):
            return True, 1.0, "loseFewerThanThree"
        
        # 2. Check if current player has too few pieces (current player loses)
        if self.check_fewer_than_minimum_pieces(current_player):
            return True, -1.0, "loseFewerThanThree"
        
        # 3. Check N-move rules (excluding threefold repetition)
        is_draw, draw_reason = self.is_draw_by_nmove_rules()
        if is_draw:
            # Small positive value for draws with material bias
            material_bias = 0.03 * (self.count(current_player) - self.count(opponent))
            return True, min(max(1e-4 + material_bias, -1), 1), draw_reason
        
        # 4. Check stalemate conditions (no legal moves in moving phase)
        if self.period in [1, 2] and self.is_all_surrounded(current_player):
            # Default stalemate action: opponent wins
            return True, -1.0, "loseNoLegalMoves"
        
        # 5. Check if opponent is stalemated (current player wins)
        if self.period in [1, 2] and self.is_all_surrounded(opponent):
            return True, 1.0, "loseNoLegalMoves"
        
        # Game continues
        return False, 0.0, None

    def check_threefold_repetition_after_move(self):
        """
        Check threefold repetition immediately after a move execution.
        This matches C++ behavior where threefold is checked after move, not in check_if_game_is_over().
        Returns tuple (is_draw, reason) or (False, None).
        """
        if self.has_repeated_position():
            return True, "drawThreefoldRepetition"
        return False, None

    def update_draw_counters(self, move, move_type="PLACE"):
        """
        Update counters and history for draw rule tracking.
        
        Args:
            move: The move that was played
            move_type: Type of move - "PLACE", "MOVE", or "REMOVE"
                      Matches MOVETYPE_* from C++ src/position.cpp
        """
        # Update rule50 counter based on move type (matches C++ logic)
        if move_type == "MOVE":
            # Only MOVE-type moves increment rule50 counter
            self.rule50_counter += 1
        else:
            # PLACE and REMOVE moves reset rule50 counter
            self.rule50_counter = 0
        
        # Always increment total move counter (like posKeyHistory in C++)
        self.move_counter += 1
        
        # Position history management - CRITICAL: matches C++ posKeyHistory behavior
        # Only update position history for MOVE-type moves (length 5 in C++)
        # Clear history for PLACE and REMOVE moves (length != 5 in C++)
        if move_type == "MOVE":
            current_hash = self.get_position_hash()
            # Only add if different from last hash (avoids duplicate entries)
            if not self.position_history or self.position_history[-1] != current_hash:
                self.position_history.append(current_hash)
        else:
            # Clear position history for non-MOVE moves (matches C++ behavior)
            self.position_history.clear()
        
        # Keep history manageable (only keep last 200 positions)
        if len(self.position_history) > 200:
            self.position_history.pop(0)
        
        # Record move in history for debugging
        self.move_history.append((move, move_type))
        if len(self.move_history) > 200:
            self.move_history.pop(0)

    def execute_move(self, move, player):
        """Perform the given move on the board; flips pieces as necessary.
        color gives the color of the piece to play (1=white, -1=black).
        """
        # Basic assertions about inputs
        assert player in (1, -1), f"Invalid player: {player}"
        assert isinstance(move, (list, tuple)), f"Move must be list/tuple, got {type(move)}"
        assert len(move) in (2, 4), f"Move must have length 2 or 4, got {len(move)}"
        for v in move:
            assert isinstance(v, (int, np.integer)), f"Move elements must be ints, got {type(v)}"
            assert 0 <= v < 7, f"Move coordinate {v} out of bounds [0,7)"

        # Determine move type based on current period and move structure
        if self.period == 0:
            # Placing phase
            move_type = "PLACE"
            self.pieces[move[0]][move[1]] = player
        elif self.period == 3:
            # Removal phase
            move_type = "REMOVE"
            # Ensure we remove opponent piece according to rules; skip strict mill rule here
            assert self.pieces[move[0]][move[1]] == -player or self.pieces[move[0]][move[1]] == player or self.pieces[move[0]][move[1]] == 0, "Board cell must be a piece or empty"
            self.pieces[move[0]][move[1]] = 0
        else:
            # Moving phase (period 1 or 2)
            move_type = "MOVE"
            assert self.pieces[move[0]][move[1]] == player, "Source must contain player's piece"
            assert self.pieces[move[2]][move[3]] == 0, "Destination must be empty"
            self.pieces[move[0]][move[1]] = 0
            self.pieces[move[2]][move[3]] = player
        
        self.update_period(move, player)
        
        # Update draw rule counters after the move with correct type
        # Record last mover for position hashing (side-to-move derivation)
        self._last_move_player = player
        self.update_draw_counters(move, move_type)
        
        # Check for threefold repetition after MOVE-type moves (matches C++ behavior)
        # In C++, threefold repetition is checked immediately after move execution
        if move_type == "MOVE" and self.threefold_repetition_rule:
            is_repetition, reason = self.check_threefold_repetition_after_move()
            if is_repetition:
                # Set a flag to indicate threefold repetition was detected
                # This will be picked up by the game ending logic
                self._threefold_detected = True
                self._threefold_reason = reason

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
        move_pos = move if len(move) == 2 else move[2:]
        x, y = move_pos
        
        # Convert to coordinate system used in standard_rules.py
        from .standard_rules import xy_to_coord, mills
        
        coord = xy_to_coord.get((x, y))
        if not coord:
            return False
            
        # Check all mill triplets to see if this position forms one
        for mill_triplet in mills:
            if coord in mill_triplet:
                # Check if all three positions in this mill have the same player's pieces
                all_same = True
                for mill_coord in mill_triplet:
                    mill_x, mill_y = self._coord_to_xy(mill_coord)
                    if mill_x is None or mill_y is None:
                        all_same = False
                        break
                    if self.pieces[mill_x][mill_y] != player:
                        all_same = False
                        break
                
                if all_same:
                    return True
        
        return False
    
    def _coord_to_xy(self, coord):
        """Convert coordinate string to (x, y) tuple."""
        from .standard_rules import coord_to_xy
        return coord_to_xy.get(coord, (None, None))

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


