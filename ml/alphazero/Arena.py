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

    def __init__(self, player1, player2, game, display=None, human_sample_from_pi: bool = False):
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
        # 在人机模式下，是否根据 pi 概率抽样选择走法（引入随机性）
        self.human_sample_from_pi = bool(human_sample_from_pi)
        # Discrete game-end info for post-game aggregation (W/D/L from Player-1 perspective)
        # 1 = win for Player-1, 0 = draw, -1 = loss
        self._last_wdl_discrete: int | None = None
        # Raw reason id from Board.check_game_over_conditions()
        self._last_end_reason_id: str | None = None

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
        # Track moves for chess notation style output
        notation_moves = []
        move_count = 0
        current_white_move = ''

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
                    if self.human_sample_from_pi:
                        # 按 pi 概率抽样选择，以引入随机性
                        action = int(np.random.choice(len(pi), p=pi))
                    else:
                        # 原有确定性逻辑（结合 v_ema 与难度）
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
                # 收集移动记录用于简化输出格式
                try:
                    side = 'White' if curPlayer == 1 else 'Black'
                    role = 'AI' if isinstance(player_obj, MCTS) else ('Perfect' if hasattr(player_obj, 'play_with_history') else 'Human')
                    
                    # 添加到简化记录中
                    if curPlayer == 1:  # White move
                        if not current_white_move:  # 开始新的一回合
                            move_count += 1
                            current_white_move = f"{move_count}. {engine_notation}"
                        else:
                            # 如果已经有白棋走子，这可能是吃子
                            if engine_notation.startswith('x'):
                                current_white_move += engine_notation
                            else:
                                # 应该不会发生，但处理异常情况
                                notation_moves.append(current_white_move)
                                move_count += 1
                                current_white_move = f"{move_count}. {engine_notation}"
                    else:  # Black move
                        if current_white_move:
                            if engine_notation.startswith('x'):
                                current_white_move += f" {engine_notation}"
                            else:
                                current_white_move += f" {engine_notation}"
                            notation_moves.append(current_white_move)
                            current_white_move = ''
                        else:
                            # 黑棋先手的情况（不太常见）
                            if engine_notation.startswith('x'):
                                notation_moves.append(f"{engine_notation}")
                            else:
                                notation_moves.append(f"{engine_notation}")
                    
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
                # 先刷新刚刚移动方的 GUI，再刷新另一方
                # 此时 curPlayer 已切换为下一手，因此刚刚移动方为 -curPlayer
                mover = players[-curPlayer + 1]
                other = players[curPlayer + 1]
                if hasattr(mover, 'render_board'):
                    mover.render_board(board)
                if hasattr(other, 'render_board'):
                    other.render_board(board)
            except Exception:
                pass
        if verbose:
            assert self.display
            result_scalar = self.game.getGameEnded(board, 1)
            print("Game over: Turn ", str(it), "Result ", str(result_scalar))
            self.display(board)
            # 如果是 GUI 场景（有渲染能力），弹窗询问是否重开；否则按原逻辑返回
            try:
                # 推断人机对战：任一玩家为 GUI 或 Human
                def _is_human_like(p):
                    return hasattr(p, 'requires_actual_board') or (hasattr(p, 'play') and not isinstance(p, MCTS))
                if _is_human_like(self.player1) or _is_human_like(self.player2):
                    # 文案基于先手视角
                    if abs(result_scalar) < 1e-4:
                        res_text = "Draw"
                    elif result_scalar > 0:
                        res_text = "White wins"
                    else:
                        res_text = "Black wins"
                    # 优先使用 GUI 的询问框
                    want_restart = False
                    if hasattr(self.player1, 'ask_restart'):
                        want_restart = bool(self.player1.ask_restart(res_text))
                    elif hasattr(self.player2, 'ask_restart'):
                        want_restart = bool(self.player2.ask_restart(res_text))
                    if want_restart:
                        # 重置棋盘并继续当前对局，保持先后手不变
                        board = self.game.getInitBoard()
                        curPlayer = 1
                        it = 0
                        # 清空历史，重新进入循环
                        return self.playGame(verbose=verbose)
            except Exception:
                pass
        
        # 输出简化的移动记录
        try:
            # 处理剩余的白棋走法
            if current_white_move:
                notation_moves.append(current_white_move)
            
            if notation_moves:
                # 显示完整的棋谱序列
                move_text = " ".join(notation_moves)
                print(move_text)
        except Exception:
            pass
        
        # Compute discrete W/D/L from Player-1 perspective.
        # 优先使用显式终局原因；若无，则识别“阶段 1 早停”的启发式终局。
        try:
            numeric_result_first = float(self.game.getGameEnded(board, 1))
        except Exception:
            numeric_result_first = 0.0

        try:
            is_over, result_first, reason_id = board.check_game_over_conditions(1)
        except Exception:
            is_over, result_first, reason_id = False, 0.0, None

        try:
            if is_over:
                # 真实终局：依据原因判和，其余按符号定胜负
                self._last_end_reason_id = str(reason_id) if reason_id is not None else None
                if self._last_end_reason_id and self._last_end_reason_id.startswith('draw'):
                    self._last_wdl_discrete = 0
                else:
                    self._last_wdl_discrete = 1 if float(result_first) > 0 else -1
            else:
                # 非真实终局：可能是课程学习阶段 1 的早停（放置阶段结束后的启发式评分）
                stage1_early_stop = False
                try:
                    stage1_early_stop = bool(getattr(self.game, '_curriculum_enabled', False)) \
                        and int(getattr(self.game, '_curriculum_stage', 3)) == 1 \
                        and int(getattr(board, 'put_pieces', 0)) >= 18 \
                        and int(getattr(board, 'period', 0)) != 3
                except Exception:
                    stage1_early_stop = False

                if stage1_early_stop:
                    # 用启发式分数的符号来给出离散胜负；理由标记为 stage1Heuristic
                    self._last_end_reason_id = 'stage1Heuristic'
                    if abs(numeric_result_first) < 1e-8:
                        self._last_wdl_discrete = 0
                    else:
                        self._last_wdl_discrete = 1 if numeric_result_first > 0 else -1
                else:
                    # 保守兜底：依据 numeric_result_first 的符号
                    self._last_end_reason_id = None
                    if abs(numeric_result_first) < 1e-8:
                        self._last_wdl_discrete = 0
                    else:
                        self._last_wdl_discrete = 1 if numeric_result_first > 0 else -1
        except Exception:
            self._last_wdl_discrete = None

        return curPlayer * self.game.getGameEnded(board, curPlayer)

def arena_wrapper(arena_args, verbose, i, display_sign: int = 1, human_sample_from_pi: bool = False, scoreboard: dict | None = None):
    np.random.seed()
    arena = Arena(*arena_args, human_sample_from_pi=human_sample_from_pi)
    print(f'Start fighting {i}...')
    reselts = arena.playGame(verbose=verbose)
    # 显示时可按需要切换为“新网络视角”：新赢为正，旧赢为负
    try:
        shown = float(display_sign) * float(reselts)
    except Exception:
        shown = reselts
    if scoreboard is not None:
        # Prefer discrete W/D/L from final reason to avoid draw-bias misclassification
        try:
            wdl_disc = getattr(arena, '_last_wdl_discrete', None)
            if wdl_disc is not None:
                # Apply display perspective (normalize to "new model" if requested)
                wdl_shown = int(display_sign) * int(wdl_disc)
                if wdl_shown > 0:
                    scoreboard['wins'] = scoreboard.get('wins', 0) + 1
                elif wdl_shown < 0:
                    scoreboard['losses'] = scoreboard.get('losses', 0) + 1
                else:
                    scoreboard['draws'] = scoreboard.get('draws', 0) + 1
            else:
                # Robust numeric fallback: treat small-magnitude results as draws
                if abs(float(shown)) < 0.5:
                    scoreboard['draws'] = scoreboard.get('draws', 0) + 1
                elif float(shown) > 0:
                    scoreboard['wins'] = scoreboard.get('wins', 0) + 1
                else:
                    scoreboard['losses'] = scoreboard.get('losses', 0) + 1
        except Exception:
            pass
        w = scoreboard.get('wins', 0)
        d = scoreboard.get('draws', 0)
        l = scoreboard.get('losses', 0)
        print(f'End fighting {i}, result {shown} (new W:D:L = {w}:{d}:{l})')
    else:
        print(f'End fighting {i}, result {shown}')
    return reselts

def arena_wrapper_parallel(arena_args, verbose, num, results_queue, normalize_new_perspective: bool = False, human_sample_from_pi: bool = False):
    # 上半场：player1 先手（此时按照 Coach 约定，player1=旧，player2=新）
    for i in range(num//2):
        display_sign = -1 if normalize_new_perspective else 1
        scoreboard_once = {"wins": 0, "draws": 0, "losses": 0}
        _ = arena_wrapper(
            arena_args, verbose, i,
            display_sign=display_sign,
            human_sample_from_pi=human_sample_from_pi,
            scoreboard=scoreboard_once,
        )
        # 将离散 WDL（新视角）作为结果发送，避免 0 附近偏移被判为和局
        if scoreboard_once.get("wins", 0) == 1:
            res = 1.0
        elif scoreboard_once.get("losses", 0) == 1:
            res = -1.0
        else:
            res = 0.0
        results_queue.put((0, res))
    # 交换先后手
    arena_args[0], arena_args[1] = arena_args[1], arena_args[0]
    # 下半场：player1 先手（此时 player1=新，player2=旧）
    for i in range(num//2):
        display_sign = 1 if normalize_new_perspective else 1
        scoreboard_once = {"wins": 0, "draws": 0, "losses": 0}
        _ = arena_wrapper(
            arena_args, verbose, i,
            display_sign=display_sign,
            human_sample_from_pi=human_sample_from_pi,
            scoreboard=scoreboard_once,
        )
        if scoreboard_once.get("wins", 0) == 1:
            res = 1.0
        elif scoreboard_once.get("losses", 0) == 1:
            res = -1.0
        else:
            res = 0.0
        results_queue.put((1, res))

def playGames(arena_args, num, verbose=False, num_processes=0, return_halves: bool = False, normalize_new_perspective: bool = False, human_sample_from_pi: bool = False):
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
        # 分开统计上下半场（均为“新网络视角”：wins=新胜，losses=新负，draws=和）
        scoreboard_first = {"wins": 0, "draws": 0, "losses": 0}
        for i in range(num):
            display_sign = -1 if normalize_new_perspective else 1
            _ = arena_wrapper(
                arena_args, verbose, i,
                display_sign=display_sign,
                human_sample_from_pi=human_sample_from_pi,
                scoreboard=scoreboard_first,
            )
        # 将新视角的上下半场记分板映射回 one/twoWon 语义
        # 上半场：player1=旧，player2=新 → twoWon=新胜，oneWon=新负
        first_half["twoWon"] = int(scoreboard_first.get("wins", 0))
        first_half["oneWon"] = int(scoreboard_first.get("losses", 0))
        first_half["draws"] = int(scoreboard_first.get("draws", 0))
        oneWon += first_half["oneWon"]
        twoWon += first_half["twoWon"]
        draws += first_half["draws"]

        # 下半场：交换先后手（此时 player1=新，player2=旧）
        arena_args[0], arena_args[1] = arena_args[1], arena_args[0]
        scoreboard_second = {"wins": 0, "draws": 0, "losses": 0}
        for i in range(num):
            display_sign = 1 if normalize_new_perspective else 1
            _ = arena_wrapper(
                arena_args, verbose, i,
                display_sign=display_sign,
                human_sample_from_pi=human_sample_from_pi,
                scoreboard=scoreboard_second,
            )
        # 下半场：player1=新 → oneWon=新胜，twoWon=新负
        second_half["oneWon"] = int(scoreboard_second.get("wins", 0))
        second_half["twoWon"] = int(scoreboard_second.get("losses", 0))
        second_half["draws"] = int(scoreboard_second.get("draws", 0))
        oneWon += second_half["oneWon"]
        twoWon += second_half["twoWon"]
        draws += second_half["draws"]
    else:
        process_list = []
        results_queue = Queue()
        for _ in range(num_processes):
            p = Process(target=arena_wrapper_parallel, args=(arena_args, verbose, num//num_processes, results_queue, normalize_new_perspective, human_sample_from_pi))
            p.start()
            process_list.append(p)

        for p in process_list:
            p.join()

        for _ in range(num):
            is_oneplayer_first, gameResult = results_queue.get()
            if is_oneplayer_first == 0:
                if abs(float(gameResult)) < 0.5:
                    first_half["draws"] += 1
                    draws += 1
                elif float(gameResult) > 0:
                    first_half["oneWon"] += 1
                    oneWon += 1
                else:
                    first_half["twoWon"] += 1
                    twoWon += 1
            else:
                if abs(float(gameResult)) < 0.5:
                    second_half["draws"] += 1
                    draws += 1
                elif float(gameResult) < 0:
                    second_half["oneWon"] += 1
                    oneWon += 1
                else:
                    second_half["twoWon"] += 1
                    twoWon += 1

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