import numpy as np


class RandomPlayer:
    def __init__(self, game):
        self.game = game

    def play(self, board):
        a = np.random.randint(self.game.getActionSize())
        valids = self.game.getValidMoves(board, 1)
        while valids[a] != 1:
            a = np.random.randint(self.game.getActionSize())
        return a


class HumanPlayer:
    def __init__(self, game, difficulty=0):
        self.game = game
        self.difficulty = difficulty

    def play(self, board):
        """
        Read a human move in engine-style tokens and convert to action.

        Accepted token formats:
        - Placement: 'a1' .. 'g7'
        - Movement: 'a1-a4' or 'a1a4' (both formats supported)
        - Removal: 'xd1' or 'd1' (prefix 'x' optional in capture phase)

        Notes:
        - Coordinates are files a..g (x) and ranks 1..7 (y), matching display().
        - In capture phase (period==3), removal prefix 'x' is optional.
        - Movement notation supports both hyphenated and compact forms.
        """
        from .engine_adapter import engine_token_to_move

        valid = self.game.getValidMoves(board, 1)

        while True:
            # Check if there's a stored AI move to show in prompt
            prompt = self._get_prompt_text()
            token = input(prompt).strip().lower()
            try:
                # Normalize input to standard engine format
                normalized_token = self._normalize_token(token, board.period)
                move = engine_token_to_move(normalized_token)
                a = board.get_action_from_move(move)
                if valid[a]:
                    return a
            except Exception:
                pass
            print('Invalid move (examples: a1, a1-a4, a1a4, xd1, d1)')

    def _normalize_token(self, token, period):
        """
        Normalize user input to standard engine token format.
        
        Handles:
        - Compact movement notation: 'a1a4' -> 'a1-a4'
        - Optional removal prefix: 'd1' -> 'xd1' (when in capture phase)
        - Case insensitive input
        """
        token = token.strip().lower()
        
        # If it's already in standard format, return as-is
        if '-' in token or token.startswith('x'):
            return token
        
        # Check if it's a compact movement notation (4 chars: a1a4)
        if len(token) == 4 and token[0].isalpha() and token[1].isdigit() and token[2].isalpha() and token[3].isdigit():
            # Convert 'a1a4' to 'a1-a4'
            return f"{token[:2]}-{token[2:]}"
        
        # Check if it's a removal in capture phase (2 chars: d1)
        if len(token) == 2 and token[0].isalpha() and token[1].isdigit() and period == 3:
            # Convert 'd1' to 'xd1' in capture phase
            return f"x{token}"
        
        # Return as-is for placement or already correct format
        return token

    def _get_prompt_text(self):
        """
        Generate input prompt text, optionally including last AI move.
        """
        # Try to get the last AI move from a global variable or context
        # This is a simple approach - in a more complex system you might 
        # pass this information through the game state or context
        import sys
        ai_move = getattr(sys.modules.get('__main__'), '_last_ai_move', None)
        
        if ai_move:
            return f"{ai_move} > "
        else:
            return "> "


class GreedyPlayer:
    def __init__(self, game):
        self.game = game

    def play(self, board):
        valids = self.game.getValidMoves(board, 1)
        candidates = []
        for a in range(self.game.getActionSize()):
            if valids[a] == 0:
                continue
            nextBoard, _ = self.game.getNextState(board, 1, a)
            score = self.game.getScore(nextBoard, 1)
            candidates += [(-score, a)]
        candidates.sort()
        return candidates[0][1]


class EnginePlayer:
    """Baseline player powered by the native Sanmill engine via the bridge.

    Note: This player expects to receive the actual board (not canonical) and
    maintains a running move token history from startpos.
    """

    requires_actual_board = True

    def __init__(self, game, engine, history_tokens=None):
        from .engine_adapter import engine_token_to_move
        self.game = game
        self.engine = engine
        self.engine_token_to_move = engine_token_to_move
        self.history_tokens = history_tokens if history_tokens is not None else []

    def play(self, board):
        # Ask engine for bestmove given current history
        token = self.engine.get_bestmove(self.history_tokens)
        if token is None:
            # Fallback to random if engine returns no bestmove
            return RandomPlayer(self.game).play(board)
        move = self.engine_token_to_move(token)
        action = board.get_action_from_move(move)
        return action


