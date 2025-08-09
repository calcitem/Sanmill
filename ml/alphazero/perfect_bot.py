import os
from typing import List

from game.Game import Game
from game.GameLogic import Board
from game.engine_adapter import engine_token_to_move
from engine_bridge import MillEngine
from game.engine_adapter import engine_token_to_move


class PerfectTeacherPlayer:
    """A player that picks moves using the Perfect Database via engine analyze.

    This can be used in Arena to pit the learned network against a tablebase-perfect player.
    """
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.engine = MillEngine()
        self._start_and_configure_engine()
        # Online analyze timeout (seconds), shorter than offline mixing
        try:
            self.online_timeout = float(os.environ.get('SANMILL_ONLINE_ANALYZE_TIMEOUT', '10'))
        except Exception:
            self.online_timeout = 10.0

    def __del__(self):
        try:
            self.engine.stop()
        except Exception:
            pass

    def _start_and_configure_engine(self):
        """Start engine and apply rules + perfect DB path."""
        self.engine.start()
        self.engine.set_standard_rules()
        # Be conservative on threads for I/O predictability
        try:
            self.engine.set_threads(int(os.environ.get('SANMILL_ENGINE_THREADS', '1')))
        except Exception:
            pass
        self.engine.enable_perfect_database(self.db_path)

    def _restart_engine(self):
        """Restart engine after a fatal I/O error and re-apply DB path."""
        try:
            self.engine.stop()
        except Exception:
            pass
        self.engine = MillEngine()
        self._start_and_configure_engine()

    def play_with_history(self, game: Game, board: Board, curPlayer: int, engine_move_history: List[str]) -> int:
        """Return an action index chosen using Perfect DB labels.
        
        Strategy:
        1) Try tablebase-labeled best (win/draw/slow-loss)
        2) If mapping fails (illegal in current board), fallback to engine bestmove
        3) If still fails, fallback to first legal token
        """
        # Temporarily shorten analyze timeout for online teacher calls
        prev_timeout_env = os.environ.get('SANMILL_ANALYZE_TIMEOUT')
        os.environ['SANMILL_ANALYZE_TIMEOUT'] = str(self.online_timeout)
        try:
            # Try perfect-labeled best first
            token = None
            try:
                token = self.engine.choose_with_perfect(engine_move_history)
                move = engine_token_to_move(token)
                action = board.get_action_from_move(move)
                return action
            except Exception as e:
                # If engine I/O is broken or timed out, try a clean restart once
                if isinstance(e, (BrokenPipeError, TimeoutError)) or ('Broken pipe' in str(e)):
                    self._restart_engine()
                    # Retry once after restart
                    token = self.engine.choose_with_perfect(engine_move_history)
                    move = engine_token_to_move(token)
                    return board.get_action_from_move(move)
                # Fallback: ask engine bestmove for current position
                best = self.engine.get_bestmove(engine_move_history, timeout_s=5.0)
                if best:
                    try:
                        move = engine_token_to_move(best)
                        return board.get_action_from_move(move)
                    except Exception:
                        pass
                # Fallback: derive legal tokens via analyze and pick the first
                try:
                    legal_tokens = self.engine.get_legal_moves(engine_move_history, timeout_s=5.0)
                    for tok in legal_tokens:
                        try:
                            mv = engine_token_to_move(tok)
                            return board.get_action_from_move(mv)
                        except Exception:
                            continue
                except Exception:
                    pass
                # Last resort: raise
                raise ValueError("Unable to map engine token(s) to a legal action in current board state")
        finally:
            # Restore timeout env
            if prev_timeout_env is None:
                os.environ.pop('SANMILL_ANALYZE_TIMEOUT', None)
            else:
                os.environ['SANMILL_ANALYZE_TIMEOUT'] = prev_timeout_env


