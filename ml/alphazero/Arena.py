import logging
import numpy as np
import torch
from tqdm import tqdm
from MCTS import MCTS
from utils import EMA
from torch.multiprocessing import Process, Queue

log = logging.getLogger(__name__)


class Arena():
    """
    An Arena class where any 2 agents can be pit against each other.
    """

    def __init__(self, player1, player2, game, display=None):
        """
        Input:
            player 1,2: two mcts objects that takes board as input, return action
            game: Game object
            display: a function that takes board as input and prints it (e.g.
                     display in othello/OthelloGame). Is necessary for verbose
                     mode.

        see othello/OthelloPlayers.py for an example. See pit.py for pitting
        human players/other baselines with each other.
        """
        self.player1 = player1
        self.player2 = player2
        self.game = game
        self.display = display
        self.v_ema = EMA()

    def playGame(self, verbose=False):
        """
        Executes one episode of a game.
        Note: verbose=True also means human vs cpu.

        Returns:
            either
                winner: player who won the game (1 if player1, -1 if player2)
            or
                draw result returned from the game that is neither 1, -1, nor 0.
        """
        players = [self.player2, None, self.player1]
        curPlayer = 1
        board = self.game.getInitBoard()
        it = 0
        # Track engine move tokens from the start position for players that need history
        engine_move_history = []

        while self.game.getGameEnded(board, curPlayer) == 0:
            it += 1
            if verbose:
                assert self.display
                print("Turn ", str(it), "Player ", str(curPlayer), "Period ", board.period)
                self.display(board)
            player_obj = players[curPlayer + 1]
            if type(player_obj) == MCTS:
                if verbose:
                    pi = player_obj.getActionProb(self.game.getCanonicalForm(board, curPlayer), 1)
                    _, v = player_obj.nnet.predict(self.game.getCanonicalForm(board, curPlayer))
                    self.v_ema.update(v)
                    print(f'For AI, the board v = {v}, v_ema = {self.v_ema.value}')
                    pi_sorted = np.sort(pi)
                    pi_index_sorted = np.argsort(pi)
                    num_positive = (pi_sorted>0).sum()
                    num_negative = pi_sorted.shape[0] - num_positive
                    action_sorted_index = num_negative+int(num_positive*((1-self.v_ema.value)/2+players[1-curPlayer].difficulty))
                    action_sorted_index = min(max(action_sorted_index, num_negative), len(pi)-1)
                    action = pi_index_sorted[action_sorted_index]
                else:
                    pi = player_obj.getActionProb(self.game.getCanonicalForm(board, curPlayer), 0)
                    action = np.argmax(pi)
            elif hasattr(player_obj, 'play_with_history'):
                # Player that requires move history (e.g., Perfect DB teacher via engine analyze)
                action = player_obj.play_with_history(self.game, board, curPlayer, engine_move_history)
            else:
                # 如果玩家需要实际棋盘或是 GUI 玩家，传递实际棋盘
                if getattr(player_obj, 'requires_actual_board', False):
                    # 通知当前行动方，确保 GUI 以先手=白、后手=黑的视角工作
                    if hasattr(player_obj, 'set_to_move'):
                        try:
                            player_obj.set_to_move(curPlayer)
                        except Exception:
                            pass
                    action = player_obj.play(board)
                else:
                    action = player_obj.play(self.game.getCanonicalForm(board, curPlayer))

            # Store AI move for prompt display (verbose mode) and append to engine history
            ai_move_notation = None
            try:
                from game.engine_adapter import move_to_engine_token
                move = board.get_move_from_action(action)
                engine_notation = move_to_engine_token(move)
                # Period 3 = capture phase, prefix 'x' for removal
                if board.period == 3:
                    engine_notation = f"x{engine_notation}"
                engine_move_history.append(engine_notation)
                if verbose and type(player_obj) == MCTS:
                    ai_move_notation = engine_notation
                    import sys
                    setattr(sys.modules.get('__main__'), '_last_ai_move', engine_notation)
                # 控制台与 GUI 同步打印最近一步（标注颜色与角色）
                try:
                    side = 'White' if curPlayer == 1 else 'Black'
                    role = 'AI' if isinstance(player_obj, MCTS) else ('Perfect' if hasattr(player_obj, 'play_with_history') else 'Human')
                    print(f"Last move: {side}({role}) {engine_notation}")
                    # 若是 GUI 人类玩家，更新其状态栏
                    try:
                        if hasattr(self.player1, 'set_last_move'):
                            self.player1.set_last_move(side, role, engine_notation)
                    except Exception:
                        pass
                    try:
                        if hasattr(self.player2, 'set_last_move'):
                            self.player2.set_last_move(side, role, engine_notation)
                    except Exception:
                        pass
                except Exception:
                    pass
            except Exception:
                ai_move_notation = f"action_{action}"

            valids = self.game.getValidMoves(self.game.getCanonicalForm(board, curPlayer), 1)

            if valids[action] == 0:
                log.error(f'Action {action} is not valid!')
                log.debug(f'valids = {valids}')
                assert valids[action] > 0
            board, curPlayer = self.game.getNextState(board, curPlayer, action)
            # 若有 GUI 玩家，落子后立即刷新显示当前棋盘，避免等对手落子才统一更新
            try:
                if hasattr(self.player1, 'render_board'):
                    self.player1.render_board(board)
                if hasattr(self.player2, 'render_board'):
                    self.player2.render_board(board)
            except Exception:
                pass
        if verbose:
            assert self.display
            print("Game over: Turn ", str(it), "Result ", str(self.game.getGameEnded(board, 1)))
            self.display(board)
        return curPlayer * self.game.getGameEnded(board, curPlayer)

def arena_wrapper(arena_args, verbose, i, display_sign: int = 1):
    np.random.seed()
    arena = Arena(*arena_args)
    print(f'Start fighting {i}...')
    reselts = arena.playGame(verbose=verbose)
    # 显示时可按需要切换为“新网络视角”：新赢为正，旧赢为负
    try:
        shown = float(display_sign) * float(reselts)
    except Exception:
        shown = reselts
    print(f'End fighting {i}, result {shown}')
    return reselts

def arena_wrapper_parallel(arena_args, verbose, num, results_queue, normalize_new_perspective: bool = False):
    # 上半场：player1 先手（此时按照 Coach 约定，player1=旧，player2=新）
    for i in range(num//2):
        display_sign = -1 if normalize_new_perspective else 1
        res = arena_wrapper(arena_args, verbose, i, display_sign=display_sign)
        results_queue.put((0, res))
    # 交换先后手
    arena_args[0], arena_args[1] = arena_args[1], arena_args[0]
    # 下半场：player1 先手（此时 player1=新，player2=旧）
    for i in range(num//2):
        display_sign = 1 if normalize_new_perspective else 1
        res = arena_wrapper(arena_args, verbose, i, display_sign=display_sign)
        results_queue.put((1, res))

def playGames(arena_args, num, verbose=False, num_processes=0, return_halves: bool = False, normalize_new_perspective: bool = False):
    """
    Plays num games in which player1 starts num/2 games and player2 starts
    num/2 games.

    Returns:
        oneWon: games won by player1
        twoWon: games won by player2
        draws:  games won by nobody
        (optional) halves: dict with first/second half split statistics
    """
    assert num_processes == 0 or num % (num_processes*2) == 0 and num >= num_processes*2

    oneWon = 0
    twoWon = 0
    draws = 0
    # 先后手拆分统计
    first_half = {"oneWon": 0, "twoWon": 0, "draws": 0}
    second_half = {"oneWon": 0, "twoWon": 0, "draws": 0}
    if verbose or num_processes == 0:
        num = num // 2
        for i in range(num):
            display_sign = -1 if normalize_new_perspective else 1
            gameResult = arena_wrapper(arena_args, verbose, i, display_sign=display_sign)
            if gameResult > 1e-4:
                first_half["oneWon"] += 1
                oneWon += 1
            elif gameResult < -1e-4:
                first_half["twoWon"] += 1
                twoWon += 1
            else:
                first_half["draws"] += 1
                draws += 1
        arena_args[0], arena_args[1] = arena_args[1], arena_args[0]
        for i in range(num):
            display_sign = 1 if normalize_new_perspective else 1
            gameResult = arena_wrapper(arena_args, verbose, i, display_sign=display_sign)
            if gameResult < -1e-4:
                second_half["oneWon"] += 1
                oneWon += 1
            elif gameResult > 1e-4:
                second_half["twoWon"] += 1
                twoWon += 1
            else:
                second_half["draws"] += 1
                draws += 1
    else:
        process_list = []
        results_queue = Queue()
        for _ in range(num_processes):
            p = Process(target=arena_wrapper_parallel, args=(arena_args, verbose, num//num_processes, results_queue, normalize_new_perspective))
            p.start()
            process_list.append(p)

        for p in process_list:
            p.join()

        for _ in range(num):
            is_oneplayer_first, gameResult = results_queue.get()
            if is_oneplayer_first == 0:
                if gameResult > 1e-4:
                    first_half["oneWon"] += 1
                    oneWon += 1
                elif gameResult < -1e-4:
                    first_half["twoWon"] += 1
                    twoWon += 1
                else:
                    first_half["draws"] += 1
                    draws += 1
            else:
                if gameResult < -1e-4:
                    second_half["oneWon"] += 1
                    oneWon += 1
                elif gameResult > 1e-4:
                    second_half["twoWon"] += 1
                    twoWon += 1
                else:
                    second_half["draws"] += 1
                    draws += 1

        # terminate multiprocessing
        del is_oneplayer_first, gameResult
        results_queue.close()
        for p in process_list:
            p.terminate()

    if return_halves:
        halves = {
            "first": first_half,
            "second": second_half,
        }
        return oneWon, twoWon, draws, halves
    return oneWon, twoWon, draws