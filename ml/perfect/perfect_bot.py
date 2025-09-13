import logging
import os
from typing import List

from game.Game import Game
from game.GameLogic import Board
from game.engine_adapter import engine_token_to_move
from perfect_db_reader import PerfectDB

log = logging.getLogger(__name__)


class PerfectTeacherPlayer:
    """A player that picks moves using the Perfect Database via engine analyze.

    This can be used in Arena to pit the learned network against a tablebase-perfect player.
    """
    def __init__(self, db_path: str):
        self.db_path = db_path or r"E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted"
        self.db = PerfectDB()
        self.db.init(self.db_path)

    def __del__(self):
        try:
            self.db.deinit()
        except Exception:
            pass

    def _labels_from_db(self, board: Board, cur_player: int):
        only_take = (board.period == 3)
        wdl, steps = self.db.evaluate(board, cur_player, only_take)
        tokens = self.db.good_moves_tokens(board, cur_player, only_take)
        if wdl > 0:
            lab = 'win'
        elif wdl < 0:
            lab = 'loss'
        else:
            lab = 'draw'
        labels = {}
        for t in tokens:
            labels[t] = {"wdl": lab, "value": 0, "steps": (None if steps < 0 else steps)}
        return labels

    def _restart_engine(self):
        raise RuntimeError("No engine fallback in DB mode")

    def play_with_history(self, game: Game, board: Board, curPlayer: int, engine_move_history: List[str]) -> int:
        """Return an action index chosen using Perfect DB labels.
        
        Strategy:
        1) Try tablebase-labeled best (win/draw/slow-loss)
        2) If mapping fails (illegal in current board), fallback to engine bestmove
        3) If still fails, fallback to first legal token
        """
        log.info(f"[TEACHER DEBUG] Called with board period {board.period}, player {curPlayer}")
        log.info(f"[TEACHER DEBUG] Move history length: {len(engine_move_history)}, last 3: {engine_move_history[-3:]}")
        log.info(f"[TEACHER DEBUG] Board state - Put pieces: {board.put_pieces}, W: {board.count(1)}, B: {board.count(-1)}")
        
        # Use DB directly, no engine fallback, throw exception on error
        labels = self._labels_from_db(board, curPlayer)
        if not labels:
            raise RuntimeError("Perfect DB returned no labels")
        # Selection priority: win > draw > loss (consistent with supervised construction)
        wins = [t for t, p in labels.items() if p.get('wdl') == 'win']
        draws = [t for t, p in labels.items() if p.get('wdl') == 'draw']
        losses = [t for t, p in labels.items() if p.get('wdl') == 'loss']
        pick = wins[0] if wins else (draws[0] if draws else (losses[0] if losses else None))
        if not pick:
            raise RuntimeError("No legal move in DB labels")
        move = engine_token_to_move(pick)
        return board.get_action_from_move(move)


