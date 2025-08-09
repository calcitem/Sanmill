import os
from typing import List

from game.Game import Game
from game.GameLogic import Board
from game.engine_adapter import engine_token_to_move
from engine_bridge import MillEngine


class PerfectTeacherPlayer:
    """A player that picks moves using the Perfect Database via engine analyze.

    This can be used in Arena to pit the learned network against a tablebase-perfect player.
    """
    def __init__(self, db_path: str):
        self.engine = MillEngine()
        self.engine.start()
        self.engine.set_standard_rules()
        # Be conservative on threads for I/O predictability
        try:
            self.engine.set_threads(int(os.environ.get('SANMILL_ENGINE_THREADS', '1')))
        except Exception:
            pass
        self.engine.enable_perfect_database(db_path)

    def __del__(self):
        try:
            self.engine.stop()
        except Exception:
            pass

    def play_with_history(self, game: Game, board: Board, curPlayer: int, engine_move_history: List[str]) -> int:
        """Return an action index chosen using Perfect DB labels.

        - engine_move_history: list of engine tokens from start to current position
        """
        token = self.engine.choose_with_perfect(engine_move_history)
        move = engine_token_to_move(token[1:] if token.startswith('x') else token)
        action = board.get_action_from_move(move)
        return action


