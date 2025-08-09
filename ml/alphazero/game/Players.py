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
        valid = self.game.getValidMoves(board, 1)
        for i in range(len(valid)):
            if valid[i]:
                print(board.get_move_from_action(i), end=" ")
        while True:
            input_move = input()
            input_a = input_move.split(" ")
            if len(input_a) in [2, 4]:
                try:
                    input_a = [int(i) for i in input_a]
                    a = board.get_action_from_move(input_a)
                    if valid[a]:
                        break
                except ValueError:
                    pass
            print('Invalid move')
        return a


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


