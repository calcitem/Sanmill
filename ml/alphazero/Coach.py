import logging
import os
import sys
from collections import deque
# from pickle import Pickler, Unpickler
try:
    import orjson as _jsonlib
    def _dumps(obj):
        return _jsonlib.dumps(obj)
    def _loads(b):
        return _jsonlib.loads(b)
except Exception:  # Fallback to standard json if orjson is unavailable
    import json as _jsonlib
    def _dumps(obj):
        return _jsonlib.dumps(obj).encode('utf-8')
    def _loads(b):
        if isinstance(b, (bytes, bytearray)):
            b = b.decode('utf-8')
        return _jsonlib.loads(b)
from random import shuffle
from training_logger import create_logger_from_args

import numpy as np
from tqdm import tqdm


from torch.multiprocessing import Process, Queue

from Arena import Arena, playGames
from MCTS import MCTS
from utils import dotdict
from game.engine_adapter import move_to_engine_token
from typing import List
import json

log = logging.getLogger(__name__)

# English reason text for game over causes (for logging)
_REASON_ENGLISH = {
    "loseFewerThanThree": "Loss: player has fewer than the minimum required pieces.",
    "loseNoLegalMoves": "Loss: no legal moves available (stalemate).",
    "loseFullBoard": "Loss: board is full.",
    "loseResign": "Loss: player resigned.",
    "loseTimeout": "Loss: time over.",
    "drawThreefoldRepetition": "Draw due to threefold repetition.",
    "drawFiftyMove": "Draw under the 50-move rule.",
    "drawEndgameFiftyMove": "Draw under the endgame 50-move rule.",
    "drawFullBoard": "Draw: board is full.",
    "drawStalemateCondition": "Draw due to stalemate condition.",
}

# 终局原因的简短缩写（尽量等长度；输出时再做定宽格式化）
_REASON_SHORT = {
    "loseFewerThanThree": "L-FEW3",
    "loseNoLegalMoves": "L-NOMOVE",
    "loseFullBoard": "L-FULLBD",
    "loseResign": "L-RESIGN",
    "loseTimeout": "L-TIME",
    "drawThreefoldRepetition": "D-3FOLD",
    "drawFiftyMove": "D-50MOVE",
    "drawEndgameFiftyMove": "D-E50MV",
    "drawFullBoard": "D-FULLBD",
    "drawStalemateCondition": "D-STALM",
}

def executeEpisode(game, mcts, args, verbose=False, game_id=None, perfect_player=None):
    """
    This function executes one episode of self-play, starting with player 1.
    As the game is played, each turn is added as a training example to
    trainExamples. The game is played till the game ends. After the game
    ends, the outcome of the game is used to assign values to each example
    in trainExamples.

    It uses a temp=1 if episodeStep < tempThreshold, and thereafter
    uses temp=0.

    Returns:
        trainExamples: a list of examples of the form (canonicalBoard, currPlayer, pi,v)
                        pi is the MCTS informed policy vector, v is +1 if
                        the player eventually won the game, else -1.
    """
    trainExamples = []
    board = game.getInitBoard()
    curPlayer = 1
    episodeStep = 0
    move_history = []  # Track moves for logging
    teacher_used_count = 0   # Count how many moves used online teacher
    teacher_try_count = 0    # How many times we attempted to use teacher this game
    teacher_fail_count = 0   # How many times teacher call failed
    engine_tokens = []  # Engine tokens history for online teacher queries

    # Check if detailed file logging is enabled
    log_detailed = getattr(args, 'log_detailed_moves', False)
    
    # Log game start details to file if enabled  
    if log_detailed:
        log.debug(f"=== Starting Self-Play Game {game_id} ===")
        log.debug(f"Initial board state - Period: {board.period}, Pieces placed: {board.put_pieces}")
    
    # Only log to console if verbose
    if verbose:
        log.info(f"=== Starting Self-Play Game {game_id} ===")
        log.info(f"Initial board state - Period: {board.period}, Pieces placed: {board.put_pieces}")

    while True:
        episodeStep += 1
        canonicalBoard = game.getCanonicalForm(board, curPlayer)
        temp = int(episodeStep < args.tempThreshold)

        # Online teacher guidance (perfect DB) selection
        used_teacher = False
        pi = None
        action = None

        use_online_teacher = getattr(args, 'useOnlineTeacher', True)
        teacher_ratio = float(getattr(args, 'teacherOnlineRatio', 0.3))

        # Attempt online teacher in all phases
        if perfect_player is not None and use_online_teacher and teacher_ratio > 0:
            try:
                use_teacher_now = np.random.rand() < teacher_ratio
            except Exception:
                use_teacher_now = False
            if use_teacher_now:
                teacher_try_count += 1
                try:
                    # Ask perfect DB for best move based on history
                    action = perfect_player.play_with_history(game, board, curPlayer, engine_tokens)
                    # Create one-hot policy
                    action_size = game.getActionSize()
                    pi = np.zeros(action_size, dtype=np.float32)
                    pi[action] = 1.0
                    used_teacher = True
                    if log_detailed:
                        log.debug("[Teacher] used at step %d", episodeStep)
                    if verbose:
                        log.info("[Teacher] used at step %d", episodeStep)
                except Exception as ex:
                    # 不保留兜底：教师调用失败时立即退出
                    log.error("[Teacher] failed at step %d: %s", episodeStep, str(ex))
                    raise
        
        if pi is None:
            # Default MCTS policy
            pi = mcts.getActionProb(canonicalBoard, temp=temp)

        sym = game.getSymmetries(canonicalBoard, pi)
        if canonicalBoard.period == 2 and canonicalBoard.count(1) > 3:
            real_period = 4
        else:
            real_period = canonicalBoard.period
        for b, p in sym:
            trainExamples.append([b, curPlayer, p, real_period])

        if action is None:
            # Strict validation - fail fast on any anomaly
            pi = np.array(pi, dtype=np.float64)
            
            # Assert pi is valid
            assert not np.any(np.isnan(pi)), f"Pi contains NaN values: {pi}"
            assert not np.any(np.isinf(pi)), f"Pi contains infinite values: {pi}"
            assert np.sum(pi) > 0, f"Pi sum is non-positive: {np.sum(pi)}"
            assert len(pi) == game.getActionSize(), f"Pi length {len(pi)} != action_size {game.getActionSize()}"
            
            # Normalize to ensure sum = 1.0
            pi = pi / np.sum(pi)
            
            # Select action and validate result
            action = np.random.choice(len(pi), p=pi)
            assert 0 <= action < game.getActionSize(), f"Invalid action {action}, must be in [0, {game.getActionSize()})"
        
        # DEBUG: Log detailed action generation info
        if log_detailed:
            log.debug(f"[DEBUG] Step {episodeStep}: Player {curPlayer}, Period {board.period}, Action {action}")
            log.debug(f"[DEBUG] Board state - Put pieces: {board.put_pieces}, W pieces: {board.count(1)}, B pieces: {board.count(-1)}")
            log.debug(f"[DEBUG] Action source: {'Teacher' if used_teacher else 'MCTS'}, Action size: {game.getActionSize()}, Pi shape: {pi.shape}")
            # Validate action range
            if action >= game.getActionSize():
                log.error(f"[ERROR] Action {action} >= action_size {game.getActionSize()}")
            if action >= len(pi):
                log.error(f"[ERROR] Action {action} >= pi_length {len(pi)}")
            # Check if action is valid according to game rules
            try:
                valid_moves = game.getValidMoves(board, curPlayer)
                assert int(np.sum(valid_moves)) > 0, f"No valid moves for player {curPlayer} in period {board.period}"
                if action < len(valid_moves) and valid_moves[action] == 0:
                    log.warning(f"[WARNING] Action {action} is not valid according to getValidMoves")
                    log.debug(f"[DEBUG] Valid moves shape: {np.array(valid_moves).shape}, nonzero: {np.nonzero(valid_moves)[0][:10]}")
            except Exception as e:
                log.error(f"[ERROR] Failed to check valid moves: {e}")
        
        if verbose:
            log.info(f"[DEBUG] Step {episodeStep}: Player {curPlayer}, Period {board.period}, Action {action}")
            log.info(f"[DEBUG] Action source: {'Teacher' if used_teacher else 'MCTS'}")
        
        # Count teacher usage for this move
        if used_teacher:
            teacher_used_count += 1
        
        # Compute move info for logging (both console and file)
        try:
            move = board.get_move_from_action(action)
            engine_notation = move_to_engine_token(move)
            if board.period == 3:  # capture - add 'x' prefix
                engine_notation = f"x{engine_notation}"
        except Exception:
            engine_notation = f"INVALID_MOVE_ACTION_{action}"
        
        # Create readable move description
        move_str = f"Player {curPlayer:2d}, Step {episodeStep:2d}: "
        if board.period == 0:  # placing
            move_str += f"Place {engine_notation}"
        elif board.period == 1:  # moving
            move_str += f"Move {engine_notation}"
        elif board.period == 2:  # flying
            move_str += f"Fly {engine_notation}"
        elif board.period == 3:  # capture
            move_str += f"Capture {engine_notation}"
        
        move_str += f" | Period: {board.period} | Pieces: W={board.count(1)}, B={board.count(-1)}"
        move_history.append((engine_notation, move_str))
        
        # Log detailed board state to file if enabled
        if log_detailed:
            ascii_before = board.display_board()
            log.debug("Board before move:\n%s", ascii_before)
            log.debug(move_str)
        
        # Log move to console if verbose
        if verbose:
            ascii_before = board.display_board()
            log.info("Board before move:\n%s", ascii_before)
            log.info(move_str)

        # Validate move format matches board period
        try:
            move = board.get_move_from_action(action)
            if board.period in [0, 3]:  # placing/capture
                assert len(move) == 2, f"Move length {len(move)} != 2 for period {board.period} (placing/capture)"
            else:  # moving/flying
                assert len(move) == 4, f"Move length {len(move)} != 4 for period {board.period} (moving/flying)"
        except Exception as e:
            log.error(f"[ERROR] Move validation failed: {e}")
            raise

        # Maintain engine token sequence for perfect DB queries
        if engine_notation:
            engine_tokens.append(engine_notation)

        board, curPlayer = game.getNextState(board, curPlayer, action)

        # Log board after move
        if log_detailed or verbose:
            ascii_after = board.display_board()
            if ascii_after != ascii_before:
                if log_detailed:
                    log.debug("Board after move:\n%s", ascii_after)
                if verbose:
                    log.info("Board after move:\n%s", ascii_after)
            else:
                if log_detailed:
                    log.debug("Board after move: (unchanged)")
                if verbose:
                    log.info("Board after move: (unchanged)")

        r = game.getGameEnded(board, curPlayer)

        if r != 0:
            # Determine and print the concrete English reason for game end
            try:
                is_over2, _, reason_id = board.check_game_over_conditions(curPlayer)
            except Exception:
                is_over2, reason_id = True, None
            reason_text = _REASON_ENGLISH.get(reason_id, "Unknown game over reason.")
            # 计算简短原因缩写，并格式化为等宽标签 [XXXXXXXX]
            reason_code = _REASON_SHORT.get(reason_id, "UNKNOWN")
            reason_tag = f"[{reason_code:<8s}]"

            # 结果显示基于先手方视角（Player 1）。注意吃子期不交换 side-to-move，因此直接取 player=1 视角更稳妥。
            r_first = game.getGameEnded(board, 1)
            try:
                if reason_id and str(reason_id).startswith("draw"):
                    result_label = "Draw"
                elif r_first > 0:
                    result_label = "Win"
                elif r_first < 0:
                    result_label = "Loss"
                else:
                    result_label = "Unknown"
            except Exception:
                result_label = "Unknown"
            result_str = f"{r_first:.4f}"

            # Log to file if detailed logging enabled
            if log_detailed:
                log.debug(f"=== Game {game_id} Ended ===")
                log.debug(f"Result: {result_str} ({result_label}) (Player {curPlayer} perspective)")
                log.debug(f"Game over reason: {reason_text} ({reason_id}) | Tag: {reason_tag}")
            
            # Calculate teacher usage stats
            try:
                ratio = teacher_used_count / float(episodeStep)
            except Exception:
                ratio = 0.0
            
            # Log detailed game end to file if enabled
            if log_detailed:
                log.debug(f"Final state - Period: {board.period}, Total moves: {episodeStep}")
                log.debug(f"Final pieces count - White: {board.count(1)}, Black: {board.count(-1)}")
                log.debug(f"Teacher usage: {teacher_used_count}/{episodeStep} ({ratio:.1%}), tries: {teacher_try_count}, fails: {teacher_fail_count}")
                log.debug("Move history (Engine notation):")
                
                # Show engine notation move list for easy copying/verification
                engine_moves = [move[0] for move in move_history]
                log.debug(f"Engine move list: {' '.join(engine_moves)}")
                
                # Show detailed move log
                log.debug("Detailed moves:")
                for i, (notation, description) in enumerate(move_history, 1):
                    log.debug(f"  {i:2d}. {description}")
                log.debug("=" * 50)
            
            # Log to console if verbose
            # 统计信息（先手视角，不影响训练）
            p1_board = board.count(1)
            p2_board = board.count(-1)
            p1_hand = board.pieces_in_hand_count(1)
            p2_hand = board.pieces_in_hand_count(-1)
            p1_total = board.total_pieces_count(1)
            p2_total = board.total_pieces_count(-1)
            diff_total = p1_total - p2_total
            stats_line = (
                f"Stats: P1 on={p1_board:2d} in={p1_hand:2d} tot={p1_total:2d} | "
                f"P2 on={p2_board:2d} in={p2_hand:2d} tot={p2_total:2d} | "
                f"Diff={diff_total:+3d}"
            )

            if verbose:
                # 仅打印简短原因标签，如 [D-50MOVE]
                log.info(f"Game result: {result_str} ({result_label}) {reason_tag}")
                log.info(f"Final state - Period: {board.period}, Total moves: {episodeStep}")
                log.info(stats_line)
                log.info(f"Teacher usage: {teacher_used_count}/{episodeStep} ({ratio:.1%})")
            else:
                # Brief summary for non-verbose mode
                # 仅打印简短原因标签，如 [D-50MOVE]
                log.info(f"Game ended. {result_label} | Result: {result_str} | {reason_tag} | Teacher: {teacher_used_count}/{episodeStep} ({ratio:.1%})")
                log.info(stats_line)
            
            return [(x[0], x[2], r * ((-1) ** (x[1] != curPlayer)), x[3]) for x in trainExamples]

def executeEpisodeParallel(game, nnet, args, queue, num):
    # Ensure CPU-only execution in multiprocessing
    import os
    os.environ["CUDA_VISIBLE_DEVICES"] = ""
    
    # Force CPU-only args for this process
    cpu_args = dotdict(dict(args))
    cpu_args.cuda = False
    cpu_args.use_amp = False
    
    for i in range(num):
        mcts = MCTS(game, nnet, cpu_args)  # reset search tree with CPU args
        queue.put(executeEpisode(game, mcts, cpu_args))

class Coach():
    """
    This class executes the self-play + learning. It uses the functions defined
    in Game and NeuralNet. args are specified in main.py.
    """

    def __init__(self, game, nnet, args):
        self.game = game
        self.nnet = nnet
        self.pnet = self.nnet.__class__(self.game, args)  # the competitor network
        self.args = args
        self.mcts = MCTS(self.game, self.nnet, self.args)
        self.trainExamplesHistory = []  # history of examples from args.numItersForTrainExamplesHistory latest iterations
        self.skipFirstSelfPlay = False  # can be overriden in loadTrainExamples()
        self.has_won = True
        # Curriculum arena-driven state
        self._cur_stage = 3
        self._cur_stage_pass_count = 0
        self._cur_stage_iters = 0
        self._cur_stage_stagnant = 0
        self._cur_relaxed_total = 0.0
        # Try load persisted curriculum state
        try:
            if getattr(self.args, 'curriculum_advance_by_arena', False):
                self._load_curriculum_state()
        except Exception:
            pass
        
        # 初始化训练日志器（如果启用）
        self.training_logger = None
        if getattr(args, 'enable_training_log', True):
            try:
                self.training_logger = create_logger_from_args(args)
                log.info(f"训练日志器已启用，保存至: {self.training_logger.csv_file}")
            except Exception as ex:
                log.warning(f"初始化训练日志器失败: {ex}")
                self.training_logger = None

        # 持久化在线教师引擎（整个训练周期保持活动）
        self.perfect_player = None
        online_teacher_enabled = getattr(self.args, 'useOnlineTeacher', True)
        teacher_db_path = getattr(self.args, 'teacherDBPath', None) or os.environ.get('SANMILL_PERFECT_DB')
        if online_teacher_enabled and teacher_db_path and self.args.num_processes == 1:
            try:
                from perfect_bot import PerfectTeacherPlayer
                self.perfect_player = PerfectTeacherPlayer(teacher_db_path)
                # quick sanity check
                try:
                    _ = self.perfect_player.play_with_history(self.game, self.game.getInitBoard(), 1, [])
                except Exception:
                    # 忽略空历史无法选择走子时的异常，不影响后续正常使用
                    pass
                log.info('Online teacher initialized (persistent). Ratio=%.2f', float(getattr(self.args, 'teacherOnlineRatio', 0.3)))
            except Exception as ex:
                log.error('Failed to initialize persistent online teacher engine: %s', ex)
                sys.exit(1)
        else:
            if not online_teacher_enabled:
                log.info('Online teacher disabled by config (useOnlineTeacher=false)')
            elif not teacher_db_path:
                log.info('Online teacher disabled: missing teacherDBPath/SANMILL_PERFECT_DB')
            elif self.args.num_processes != 1:
                log.info('Online teacher disabled in multi-process mode (set num_processes: 1)')

        # Curriculum defaults (do not enforce if not provided)
        self._curriculum_mode = str(getattr(self.args, 'curriculum_mode', 'off')).lower()
        self._curriculum_s1_iters = int(getattr(self.args, 'curriculum_s1_iters', 0))
        self._curriculum_s2_iters = int(getattr(self.args, 'curriculum_s2_iters', 0))
        self._curriculum_mix_prev_ratio = float(getattr(self.args, 'curriculum_mix_prev_ratio', 0.0))
        self._curriculum_stage1_weight = float(getattr(self.args, 'curriculum_stage1_weight', 0.03))
        # Stage-specific MCTS scaling (applied during self-play only)
        self._c_scale_s1 = float(getattr(self.args, 'curriculum_mcts_scale_s1', 1.25))
        self._c_scale_s2 = float(getattr(self.args, 'curriculum_mcts_scale_s2', 1.10))
        self._c_scale_s3 = float(getattr(self.args, 'curriculum_mcts_scale_s3', 1.00))

    def _determine_curriculum_stage(self, iteration_index: int):
        """Return (enabled, stage) for the given iteration index (1-based)."""
        mode = self._curriculum_mode
        if mode in ('off', 'none', 'false', '0'):
            return False, 3
        if mode in ('stage1', 's1'):
            return True, 1
        if mode in ('stage2', 's2'):
            return True, 2
        if mode in ('stage3', 's3'):
            return True, 3
        if mode in ('auto', 'auto3'):
            s1 = max(0, self._curriculum_s1_iters)
            s2 = max(0, self._curriculum_s2_iters)
            if iteration_index <= s1:
                return True, 1
            if iteration_index <= s1 + s2:
                return True, 2
            return True, 3
        # Fallback
        return False, 3

    def learn(self, sampling_only=False, training_only=False):
        """
        Performs numIters iterations with numEps episodes of self-play in each
        iteration. After every iteration, it retrains neural network with
        examples in trainExamples (which has a maximum length of maxlenofQueue).
        It then pits the new neural network against the old one and accepts it
        only if it wins >= updateThreshold fraction of games.
        """

        for i in range(1, self.args.numIters + 1):
            # bookkeeping
            log.info(f'Starting Iter #{i} ...')

            # Configure curriculum for this iteration (stage + rule switches)
            try:
                # Prefer global progress index if provided by the outer orchestrator
                effective_i = int(getattr(self.args, 'curriculum_global_iter', i))
                c_enabled, c_stage = self._determine_curriculum_stage(effective_i)
                self.game.set_curriculum(c_enabled, c_stage, self._curriculum_stage1_weight)
                if c_enabled:
                    log.info('📚 Curriculum stage set to %d for iter #%d (mix_prev_ratio=%.2f)', c_stage, effective_i, self._curriculum_mix_prev_ratio)
                else:
                    log.info('📚 Curriculum disabled for iter #%d', effective_i)
            except Exception as _e:
                log.warning('Failed to configure curriculum for iter #%d: %s', i, _e)
                c_enabled, c_stage = False, 3
            
            # Phase control: skip sampling if training_only, skip training if sampling_only
            if training_only:
                log.info(f'🎯 TRAINING-ONLY mode: Skipping self-play for iter #{i}')
            elif sampling_only:
                log.info(f'🔍 SAMPLING phase: Collecting examples for iter #{i} (training will be done separately)')
            
            # Initialize iteration training examples collection
            iterationTrainExamples = deque([], maxlen=self.args.maxlenOfQueue)
            
            # === 第一步：生成离线教师数据 ===
            # Optionally generate teacher (Perfect DB) labeled examples FIRST
            # This allows debugging teacher data generation before MCTS
            if (not self.skipFirstSelfPlay or i > 1) and not training_only:
                if getattr(self.args, 'usePerfectTeacher', False) and getattr(self.args, 'teacherExamplesPerIter', 0) > 0:
                    try:
                        stage_name = {1: "Stage 1 (placing+taking)", 2: "Stage 2 (moving+taking)", 3: "Stage 3 (full rules)"}.get(c_stage if c_enabled else 3, f"Stage {c_stage if c_enabled else 3}")
                        log.info(f"📚 Generating {self.args.teacherExamplesPerIter} offline teacher examples for iter #{i} ({stage_name})...")
                        from perfect_supervised import build_dataset_with_perfect_labels
                        teacher_db_path = getattr(self.args, 'teacherDBPath', None) or os.environ.get('SANMILL_PERFECT_DB')
                        if teacher_db_path:
                            prev_timeout = os.environ.get('SANMILL_ANALYZE_TIMEOUT')
                            prev_threads = os.environ.get('SANMILL_ENGINE_THREADS')
                            if getattr(self.args, 'teacherAnalyzeTimeout', None) is not None:
                                os.environ['SANMILL_ANALYZE_TIMEOUT'] = str(self.args.teacherAnalyzeTimeout)
                            if getattr(self.args, 'teacherThreads', None) is not None:
                                os.environ['SANMILL_ENGINE_THREADS'] = str(self.args.teacherThreads)
                            teacher_batch = getattr(self.args, 'teacherBatch', 256)
                            # verbose=False to avoid flooding logs during training
                            # Pass curriculum stage to teacher data generation
                            teacher_examples = build_dataset_with_perfect_labels(
                                teacher_db_path, int(self.args.teacherExamplesPerIter), batch=int(teacher_batch), 
                                verbose=False, curriculum_stage=c_stage if c_enabled else 3
                            )
                            if teacher_examples:
                                log.info("✅ Generated %d teacher examples from Perfect DB", len(teacher_examples))
                                iterationTrainExamples.extend(teacher_examples)
                            else:
                                log.warning("⚠️ No teacher examples generated from Perfect DB")
                            # restore envs
                            if prev_timeout is None:
                                os.environ.pop('SANMILL_ANALYZE_TIMEOUT', None)
                            else:
                                os.environ['SANMILL_ANALYZE_TIMEOUT'] = prev_timeout
                            if prev_threads is None:
                                os.environ.pop('SANMILL_ENGINE_THREADS', None)
                            else:
                                os.environ['SANMILL_ENGINE_THREADS'] = prev_threads
                        else:
                            log.warning("⚠️ Teacher DB path not configured, skipping offline teacher data generation")
                    except Exception as ex:
                        log.error("❌ Failed to generate offline teacher examples: %s", ex)
                        raise
            
            # === 第二步：生成 MCTS 自我对弈数据 ===
            # examples of the iteration
            if (not self.skipFirstSelfPlay or i > 1) and not training_only:
                log.info(f"🎮 Starting MCTS self-play data generation for iter #{i}...")
                
                if self.args.num_processes > 1:
                    # Multi-process self-play: spawn workers collecting episodes into a queue.
                    example_queue = Queue()
                    process_list = []
                    assert self.args.numEps % self.args.num_processes == 0
                    process_numEps = self.args.numEps // self.args.num_processes
                    
                    # Create CPU-only args and nnet for multiprocessing
                    cpu_args = dotdict(dict(self.args))
                    cpu_args.cuda = False
                    cpu_args.use_amp = False
                    # Stage-specific MCTS sims scaling for self-play
                    base_sims = int(self.args.numMCTSSims)
                    if c_stage == 1:
                        cpu_args.numMCTSSims = max(1, int(round(base_sims * self._c_scale_s1)))
                    elif c_stage == 2:
                        cpu_args.numMCTSSims = max(1, int(round(base_sims * self._c_scale_s2)))
                    else:
                        cpu_args.numMCTSSims = max(1, int(round(base_sims * self._c_scale_s3)))
                    
                    # Create a CPU-only neural network for multiprocessing
                    cpu_nnet = self.nnet.__class__(self.game, cpu_args)
                    # Copy weights from GPU model to CPU model
                    try:
                        if self.args.cuda:
                            # Temporarily move model to CPU to copy weights
                            original_device = next(self.nnet.nnet.parameters()).device
                            cpu_state_dict = {k: v.cpu() for k, v in self.nnet.nnet.state_dict().items()}
                            cpu_nnet.nnet.load_state_dict(cpu_state_dict)
                            # No need to move original model back as we're not modifying it
                        else:
                            cpu_nnet.nnet.load_state_dict(self.nnet.nnet.state_dict())
                        log.info("Successfully created CPU model for multiprocessing")
                    except Exception as e:
                        log.error(f"Failed to create CPU model: {e}")
                        raise
                    
                    for _ in range(self.args.num_processes):
                        p = Process(target=executeEpisodeParallel,
                                    args=(self.game, cpu_nnet, cpu_args, example_queue, process_numEps))
                        p.start()
                        process_list.append(p)

                    with tqdm(total=self.args.numEps, desc='Self Play') as pbar:
                        self_play_sum = 0
                        while self_play_sum < self.args.numEps:
                            if not example_queue.empty():
                                iterationTrainExamples += example_queue.get()
                                pbar.update()
                                self_play_sum += 1

                    # close
                    for p in process_list:
                        p.terminate()
                    example_queue.close()
                else:
                    # Single-process self-play: avoid spawning to keep CUDA context in the main process.
                    with tqdm(total=self.args.numEps, desc='CPU MCTS Self Play') as pbar:
                        for game_idx in range(self.args.numEps):
                            # Stage-specific MCTS sims scaling for self-play
                            episode_args = dotdict(dict(self.args))
                            base_sims = int(self.args.numMCTSSims)
                            if c_stage == 1:
                                episode_args.numMCTSSims = max(1, int(round(base_sims * self._c_scale_s1)))
                            elif c_stage == 2:
                                episode_args.numMCTSSims = max(1, int(round(base_sims * self._c_scale_s2)))
                            else:
                                episode_args.numMCTSSims = max(1, int(round(base_sims * self._c_scale_s3)))

                            mcts = MCTS(self.game, self.nnet, episode_args)  # reset search tree per episode
                            # Console verbose only if explicitly enabled
                            console_verbose = getattr(self.args, 'console_verbose', False)
                            game_id = f"I{i}G{game_idx+1}"  # Iteration i, Game idx+1
                            mcts_examples = executeEpisode(self.game, mcts, episode_args, 
                                                         verbose=console_verbose, game_id=game_id, perfect_player=self.perfect_player)
                            iterationTrainExamples += mcts_examples
                            pbar.update()

                # Log iteration summary
                teacher_count = 0
                mcts_count = len(iterationTrainExamples)
                if getattr(self.args, 'usePerfectTeacher', False) and getattr(self.args, 'teacherExamplesPerIter', 0) > 0:
                    teacher_count = getattr(self.args, 'teacherExamplesPerIter', 0)
                    mcts_count = len(iterationTrainExamples) - teacher_count
                log.info(f"📊 Iter #{i} summary: {teacher_count} teacher examples + {mcts_count} MCTS examples = {len(iterationTrainExamples)} total")

                # save the iteration examples to the history 
                self.trainExamplesHistory.append(list(iterationTrainExamples))
                del iterationTrainExamples

            # If sampling_only mode, save examples and skip training
            if sampling_only:
                # backup history to a file for later training phase
                self.saveTrainExamples('x')
                # Calculate total examples saved
                total_examples = sum(len(examples) for examples in self.trainExamplesHistory)
                current_iter_examples = len(self.trainExamplesHistory[-1]) if self.trainExamplesHistory else 0
                log.info(f'🔍 SAMPLING phase: Saved {current_iter_examples} examples for iter #{i} (total: {total_examples})')
                continue

            if len(self.trainExamplesHistory) > self.args.numItersForTrainExamplesHistory:
                log.warning(
                    f"Removing the oldest entry in trainExamples. len(trainExamplesHistory) = {len(self.trainExamplesHistory)}")
                self.trainExamplesHistory.pop(0)
            # backup history to a file
            # NB! the examples were collected using the model from the previous iteration, so (i-1)  
            self.saveTrainExamples('x')

            # shuffle examples before training
            trainExamples: List = []
            for e in self.trainExamplesHistory:
                trainExamples.extend(e)

            # Curriculum: mix in earlier-stage samples to prevent forgetting
            if c_enabled and self._curriculum_mix_prev_ratio > 0.0:
                try:
                    import random as _random
                    prev_periods = {0, 3} if c_stage == 2 else {0, 1, 3, 4} if c_stage == 3 else set()
                    if prev_periods:
                        prev_candidates = [ex for ex in trainExamples if isinstance(ex, (list, tuple)) and len(ex) >= 4 and int(ex[3]) in prev_periods]
                        mix_n = int(round(self._curriculum_mix_prev_ratio * len(trainExamples)))
                        if prev_candidates and mix_n > 0:
                            add_samples = [_random.choice(prev_candidates) for _ in range(min(mix_n, len(prev_candidates)))]
                            trainExamples.extend(add_samples)
                            log.info('📚 Curriculum mixing: added %d earlier-stage examples (periods=%s)', len(add_samples), sorted(prev_periods))
                except Exception as _e:
                    log.warning('Curriculum mixing failed: %s', _e)

            # Teacher examples were already generated earlier in the iteration
            # No need to mix them again here - they're already in iterationTrainExamples

            shuffle(trainExamples)

            # training new network, keeping a copy of the old one
            if self.has_won:
                self.pnet.nnet.load_state_dict(self.nnet.nnet.state_dict())
            pmcts = MCTS(self.game, self.pnet, self.args)

            # Pass curriculum hints into NNet wrapper for optimizer configuration
            try:
                self.nnet.args.curriculum_current_stage = int(c_stage)
                # In Stage 2 we optionally freeze backbone and boost heads
                self.nnet.args.curriculum_freeze_backbone = bool(getattr(self.args, 'curriculum_freeze_backbone', True))
                self.nnet.args.curriculum_head_lr_mult = float(getattr(self.args, 'curriculum_head_lr_mult', 2.0))
                # Head-only training modes
                # auto: Stage 1/2 只训对应头，Stage 3 全量微调
                # stage_heads: 仅训对应头
                # all_heads: 总是全量训
                self.nnet.args.head_training_mode = str(getattr(self.args, 'head_training_mode', 'auto'))
                self.nnet.args.head_stage_filter_examples = bool(getattr(self.args, 'head_stage_filter_examples', True))
            except Exception:
                pass
            metrics = self.nnet.train(trainExamples)
            nmcts = MCTS(self.game, self.nnet, self.args)

            log.info('PITTING AGAINST PREVIOUS VERSION')
            arena_args = [pmcts, nmcts, self.game, None]
            # Avoid CUDA modules crossing process boundaries. If using CUDA, keep pitting in current process.
            effective_processes = 0 if self.args.cuda else self.args.num_processes
            # 返回先后手拆分，并在逐局打印时将结果翻转为“新网络视角”（新赢为正）
            result = playGames(
                arena_args,
                self.args.arenaCompare,
                num_processes=effective_processes,
                return_halves=True,
                normalize_new_perspective=True,
            )
            pwins, nwins, draws, halves = result

            # 旧/新总计（保持原始摘要行，兼容现有日志解析）
            log.info('NEW/PREV WINS : %f / %f ; DRAWS : %f', nwins, pwins, draws)

            # 基于新网络视角的先后手表格统计
            n_each = max(1, int(self.args.arenaCompare // 2))
            first = halves.get('first', {"oneWon": 0, "twoWon": 0, "draws": 0})    # 旧先手 / 新后手
            second = halves.get('second', {"oneWon": 0, "twoWon": 0, "draws": 0})  # 新先手 / 旧后手

            # 新为先手（second half）：twoWon=新胜，oneWon=新负（注意 second_half 的计数语义沿用原始 one/twoWon 规则）
            new_first_w = int(second.get('twoWon', 0))
            new_first_l = int(second.get('oneWon', 0))
            new_first_d = int(second.get('draws', 0))

            # 新为后手（first half）：twoWon=新胜，oneWon=新负
            new_second_w = int(first.get('twoWon', 0))
            new_second_l = int(first.get('oneWon', 0))
            new_second_d = int(first.get('draws', 0))

            total_w = new_first_w + new_second_w
            total_l = new_first_l + new_second_l
            total_d = new_first_d + new_second_d
            total_g = int(self.args.arenaCompare)

            def pct(x, base):
                try:
                    return f"{(x / base) * 100:.1f}%" if base > 0 else "0.0%"
                except Exception:
                    return "0.0%"

            # 表格输出（中文 + 英文缩写，注意中英文空格）
            header = (
                "\n" +
                "Arena 对战结果（每边 N = %d，合计 = %d）\n" % (n_each, total_g) +
                "+------------------+-------+-------+-------+--------+--------+--------+\n"
                "| 案例 Case         | Games | 胜 W  | 和 D  | 负 L   | 胜率 W% | 和率 D% | 负率 L% |\n"
                "+------------------+-------+-------+-------+--------+--------+--------+\n"
            )
            row1 = "| 新先手 New-First | %5d | %5d | %5d | %6d | %6s | %6s | %6s |\n" % (
                n_each, new_first_w, new_first_d, new_first_l,
                pct(new_first_w, n_each), pct(new_first_d, n_each), pct(new_first_l, n_each)
            )
            row2 = "| 新后手 New-Second| %5d | %5d | %5d | %6d | %6s | %6s | %6s |\n" % (
                n_each, new_second_w, new_second_d, new_second_l,
                pct(new_second_w, n_each), pct(new_second_d, n_each), pct(new_second_l, n_each)
            )
            sep =  "+------------------+-------+-------+-------+--------+--------+--------+\n"
            rowt = "| 合计 Total       | %5d | %5d | %5d | %6d | %6s | %6s | %6s |\n" % (
                total_g, total_w, total_d, total_l,
                pct(total_w, total_g), pct(total_d, total_g), pct(total_l, total_g)
            )
            table = header + row1 + row2 + sep + rowt + sep
            log.info(table)

            # === Arena-driven curriculum advancement ===
            try:
                if getattr(self.args, 'curriculum_advance_by_arena', False):
                    # Guard: minimum iterations within current stage
                    self._cur_stage_iters += 1
                    promote_allowed = self._cur_stage_iters >= int(getattr(self.args, 'curriculum_min_iters_per_stage', 1))
                    # Win-rate with optional draw weight
                    total_play = max(1, pwins + nwins + draws)
                    draw_w = float(getattr(self.args, 'curriculum_draw_weight', 0.0))
                    win_rate = (nwins + draw_w * draws) / total_play
                    # Stage thresholds
                    thr_s1 = float(getattr(self.args, 'curriculum_promote_s1', 0.70))
                    thr_s2 = float(getattr(self.args, 'curriculum_promote_s2', 0.65))
                    patience = int(getattr(self.args, 'curriculum_promote_patience', 2))
                    # Determine current stage from Game
                    cur_enabled = bool(self.game._curriculum_enabled)
                    cur_stage = int(self.game._curriculum_stage)
                    self._cur_stage = cur_stage
                    passed = False
                    if promote_allowed:
                        if cur_stage == 1:
                            passed = win_rate >= thr_s1
                        elif cur_stage == 2:
                            passed = win_rate >= thr_s2
                        else:
                            passed = False
                    if passed:
                        self._cur_stage_pass_count += 1
                    else:
                        self._cur_stage_pass_count = 0
                    log.info('📈 Curriculum Arena: stage=%d win_rate=%.3f pass_cnt=%d/%d (allowed=%s)',
                             cur_stage, win_rate, self._cur_stage_pass_count, patience, str(promote_allowed))
                    if self._cur_stage_pass_count >= patience and cur_stage in (1, 2):
                        next_stage = cur_stage + 1
                        self.game.set_curriculum(cur_enabled, next_stage, getattr(self.args, 'curriculum_stage1_weight', 0.03))
                        self._cur_stage = next_stage
                        self._cur_stage_pass_count = 0
                        self._cur_stage_iters = 0
                        self._cur_stage_stagnant = 0
                        log.info('🚀 Curriculum promoted to stage %d based on Arena win-rate', next_stage)
                    else:
                        # Timebox adaptation when stagnating
                        if promote_allowed and not passed:
                            self._cur_stage_stagnant += 1
                            tb_needed = self._cur_stage_stagnant >= int(getattr(self.args, 'curriculum_timebox_iters', 4))
                            if tb_needed:
                                action = str(getattr(self.args, 'curriculum_timebox_action', 'increase_mcts')).lower()
                                did = []
                                if action in ('increase_mcts', 'both'):
                                    scale = float(getattr(self.args, 'curriculum_timebox_mcts_scale', 1.2))
                                    try:
                                        self.args.numMCTSSims = max(1, int(round(self.args.numMCTSSims * scale)))
                                        did.append(f"MCTS→{self.args.numMCTSSims}")
                                    except Exception:
                                        pass
                                if action in ('lower_threshold', 'both'):
                                    relax = float(getattr(self.args, 'curriculum_timebox_threshold_relax', 0.03))
                                    max_relax = float(getattr(self.args, 'curriculum_timebox_max_relax', 0.10))
                                    # Apply to active stage threshold
                                    if cur_stage == 1:
                                        self._cur_relaxed_total = min(max_relax, self._cur_relaxed_total + relax)
                                        thr_s1 = max(0.5, float(getattr(self.args, 'curriculum_promote_s1', 0.70)) - self._cur_relaxed_total)
                                        self.args.curriculum_promote_s1 = thr_s1
                                        did.append(f"thr_s1→{thr_s1:.2f}")
                                    elif cur_stage == 2:
                                        self._cur_relaxed_total = min(max_relax, self._cur_relaxed_total + relax)
                                        thr_s2 = max(0.5, float(getattr(self.args, 'curriculum_promote_s2', 0.65)) - self._cur_relaxed_total)
                                        self.args.curriculum_promote_s2 = thr_s2
                                        did.append(f"thr_s2→{thr_s2:.2f}")
                                if did:
                                    log.info('⏳ Curriculum timebox applied (stage %d): %s', cur_stage, ', '.join(did))
                                self._cur_stage_stagnant = 0
                    # Persist state
                    self._save_curriculum_state()
            except Exception as _e:
                log.warning('Arena-driven curriculum advancement failed: %s', _e)
            
            # Optional: Pit new network against Perfect DB player to assess absolute strength
            perfect_draws_ratio = None
            if getattr(self.args, 'pitAgainstPerfect', False):
                teacher_db_path = getattr(self.args, 'teacherDBPath', None) or os.environ.get('SANMILL_PERFECT_DB')
                if teacher_db_path:
                    try:
                        from perfect_bot import PerfectTeacherPlayer
                        log.info('PITTING AGAINST PERFECT DATABASE')
                        perfect_player = PerfectTeacherPlayer(teacher_db_path)
                        # sanity check: first analyze from empty history
                        try:
                            _ = perfect_player.play_with_history(self.game, self.game.getInitBoard(), 1, [])
                        except Exception as ex:
                            log.error('Online teacher quick sanity check failed: %s', ex)
                            sys.exit(1)
                        # Use single process to avoid engine startup conflicts
                        perfect_arena_args = [nmcts, perfect_player, self.game, None]
                        p_wins, n_wins, p_draws = playGames(perfect_arena_args, self.args.arenaCompare, num_processes=0)
                        perfect_total = p_wins + n_wins + p_draws
                        perfect_draws_ratio = p_draws / perfect_total if perfect_total > 0 else 0.0
                        log.info('NEW vs PERFECT: WINS %f / LOSSES %f / DRAWS %f (Draw rate: %.3f)', 
                                n_wins, p_wins, p_draws, perfect_draws_ratio)
                        # Clean up the perfect player to avoid resource leaks
                        try:
                            perfect_player.engine.stop()
                        except Exception:
                            pass
                    except Exception as ex:
                        log.exception("Failed to pit against Perfect DB: %s", ex)
                        perfect_draws_ratio = None
                else:
                    log.warning("pitAgainstPerfect is enabled, but no teacherDBPath/SANMILL_PERFECT_DB provided.")
            
            # Accept/reject decision based on new vs prev performance
            if pwins + nwins == 0 or float(nwins) / (pwins + nwins) < self.args.updateThreshold:
                log.info('REJECTING NEW MODEL')
                self.nnet.nnet.load_state_dict(self.pnet.nnet.state_dict())
                self.has_won = False
            else:
                log.info('ACCEPTING NEW MODEL')
                self.nnet.save_checkpoint(folder=self.args.checkpoint, filename='best.pth.tar')
                self.has_won = True
                # Log additional perfect DB performance for accepted models
                if perfect_draws_ratio is not None:
                    log.info('ACCEPTED MODEL PERFECT DB DRAW RATE: %.3f', perfect_draws_ratio)
            # self.nnet.save_checkpoint(folder=self.args.checkpoint, filename=self.getCheckpointFile(i))
            
            # 记录本轮训练结果到表格
            if self.training_logger is not None:
                try:
                    # 计算教师样本数
                    teacher_examples_count = 0
                    if getattr(self.args, 'usePerfectTeacher', False):
                        teacher_examples_count = getattr(self.args, 'teacherExamplesPerIter', 0)
                    
                    # 记录到日志表格
                    self.training_logger.log_iteration(
                        iteration=i,
                        self_play_games=self.args.numEps,
                        teacher_examples=teacher_examples_count,
                        training_examples=len(trainExamples),
                        training_epochs=self.args.epochs,
                        training_loss=(metrics or {}).get('val_loss', None),
                        prev_wins=pwins,
                        new_wins=nwins,
                        draws=draws,
                        model_accepted=self.has_won,
                        perfect_wins=n_wins if perfect_draws_ratio is not None else 0,
                        perfect_losses=p_wins if perfect_draws_ratio is not None else 0,
                        perfect_draws=p_draws if perfect_draws_ratio is not None else 0,
                        notes=f"教师模式" if getattr(self.args, 'usePerfectTeacher', False) else "纯AlphaZero"
                    )
                except Exception as ex:
                    log.warning(f"记录训练日志失败: {ex}")
        
        # 训练结束后打印摘要（仅在非sampling_only模式下）
        if self.training_logger is not None and not sampling_only:
            try:
                self.training_logger.print_summary()
            except Exception as ex:
                log.warning(f"打印训练摘要失败: {ex}")
        elif sampling_only:
            log.info("🔍 SAMPLING阶段完成，训练摘要将在后续训练阶段生成")

        # 训练结束时关闭在线教师引擎
        try:
            if self.perfect_player is not None and getattr(self.perfect_player, 'engine', None):
                self.perfect_player.engine.stop()
        except Exception:
            pass

    # ---------------- Curriculum persistence helpers ----------------
    def _state_file(self):
        try:
            folder = getattr(self.args, 'checkpoint', './temp')
        except Exception:
            folder = './temp'
        return os.path.join(folder, 'curriculum_state.json')

    def _load_curriculum_state(self):
        path = self._state_file()
        if not os.path.exists(path):
            return
        try:
            with open(path, 'r', encoding='utf-8') as f:
                st = json.load(f)
            self._cur_stage = int(st.get('stage', self._cur_stage))
            self._cur_stage_pass_count = int(st.get('pass_count', 0))
            self._cur_stage_iters = int(st.get('iters', 0))
            # Apply to Game if curriculum enabled
            if bool(getattr(self.args, 'curriculum_advance_by_arena', False)):
                self.game.set_curriculum(True, self._cur_stage, getattr(self.args, 'curriculum_stage1_weight', 0.03))
                log.info('📦 Loaded curriculum state: stage=%d pass=%d iters=%d', self._cur_stage, self._cur_stage_pass_count, self._cur_stage_iters)
        except Exception:
            pass

    def _save_curriculum_state(self):
        path = self._state_file()
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w', encoding='utf-8') as f:
                json.dump({
                    'stage': int(self._cur_stage),
                    'pass_count': int(self._cur_stage_pass_count),
                    'iters': int(self._cur_stage_iters),
                }, f)
        except Exception:
            pass

    def getCheckpointFile(self, iteration):
        return 'checkpoint_' + str(iteration) + '.pth.tar'

    def saveTrainExamples(self, iteration):
        folder = self.args.checkpoint
        if not os.path.exists(folder):
            os.makedirs(folder)
        filename = os.path.join(folder, self.getCheckpointFile(iteration) + ".examples")
        with open(filename, "wb+") as f:
            f.write(_dumps(self.trainExamplesHistory))
        f.closed

        # Optionally split by curriculum stage and log stats
        try:
            if bool(getattr(self.args, 'curriculum_split_examples', False)):
                # Stage mapping by real_period in examples: (board, pi, v, period)
                def stage_id_from_period(p: int):
                    if p in (0, 3):
                        return 's1'
                    if p in (1, 4):
                        return 's2'
                    if p == 2:
                        return 's3'
                    return None

                hist_s1, hist_s2, hist_s3 = [], [], []
                for it in self.trainExamplesHistory:
                    it_s1 = [ex for ex in it if len(ex) >= 4 and stage_id_from_period(int(ex[3])) == 's1']
                    it_s2 = [ex for ex in it if len(ex) >= 4 and stage_id_from_period(int(ex[3])) == 's2']
                    it_s3 = [ex for ex in it if len(ex) >= 4 and stage_id_from_period(int(ex[3])) == 's3']
                    hist_s1.append(it_s1)
                    hist_s2.append(it_s2)
                    hist_s3.append(it_s3)

                with open(filename + '.s1', 'wb+') as f1:
                    f1.write(_dumps(hist_s1))
                with open(filename + '.s2', 'wb+') as f2:
                    f2.write(_dumps(hist_s2))
                with open(filename + '.s3', 'wb+') as f3:
                    f3.write(_dumps(hist_s3))

                if bool(getattr(self.args, 'curriculum_log_stats', True)):
                    cnt_total = sum(len(it) for it in self.trainExamplesHistory)
                    cnt_s1 = sum(len(it) for it in hist_s1)
                    cnt_s2 = sum(len(it) for it in hist_s2)
                    cnt_s3 = sum(len(it) for it in hist_s3)
                    def pct(c):
                        return (100.0 * c / cnt_total) if cnt_total > 0 else 0.0
                    log.info('📊 Examples by stage (total=%d): S1=%d (%.1f%%), S2=%d (%.1f%%), S3=%d (%.1f%%)'
                             , cnt_total, cnt_s1, pct(cnt_s1), cnt_s2, pct(cnt_s2), cnt_s3, pct(cnt_s3))
        except Exception as _e:
            log.warning('Failed to split examples by stage: %s', _e)

    def loadTrainExamples(self):
        examplesFile = os.path.join(self.args.load_folder_file[0], 'checkpoint_x.pth.tar.examples')
        if not os.path.isfile(examplesFile):
            log.warning(f'File "{examplesFile}" with trainExamples not found!')
            log.info('Will continue with fresh training examples')
            return  # Continue without user interaction
        else:
            log.info("File with trainExamples found. Loading it...")
            with open(examplesFile, "rb") as f:
                self.trainExamplesHistory = _loads(f.read())
            log.info('Loading done!')

            # examples based on the model were already collected (loaded)
            # self.skipFirstSelfPlay = True
