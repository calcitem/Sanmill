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
from game.engine_adapter import move_to_engine_token
from typing import List

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

def executeEpisode(game, mcts, args, verbose=False, game_id=None):
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

    if verbose:
        log.info(f"=== Starting Self-Play Game {game_id} ===")
        log.info(f"Initial board state - Period: {board.period}, Pieces placed: {board.put_pieces}")

    while True:
        episodeStep += 1
        canonicalBoard = game.getCanonicalForm(board, curPlayer)
        temp = int(episodeStep < args.tempThreshold)

        pi = mcts.getActionProb(canonicalBoard, temp=temp)
        sym = game.getSymmetries(canonicalBoard, pi)
        if canonicalBoard.period == 2 and canonicalBoard.count(1) > 3:
            real_period = 4
        else:
            real_period = canonicalBoard.period
        for b, p in sym:
            trainExamples.append([b, curPlayer, p, real_period])

        action = np.random.choice(len(pi), p=pi)
        
        # Log move details if verbose
        if verbose:
            # Log ASCII board before applying the move (engine-style visualization).
            # Using Board.display_board() ensures a consistent, log-friendly string.
            # Note: We capture the string to also compare after the move and avoid duplicate prints.
            ascii_before = board.display_board()
            log.info("Board before move:\n%s", ascii_before)
            move = board.get_move_from_action(action)
            
            # Convert to engine notation for consistency with C++ engine
            try:
                engine_notation = move_to_engine_token(move)
                if board.period == 3:  # capture - add 'x' prefix
                    engine_notation = f"x{engine_notation}"
            except ValueError:
                engine_notation = f"INVALID_MOVE_{move}"
            
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
            log.info(move_str)
            move_history.append((engine_notation, move_str))

        board, curPlayer = game.getNextState(board, curPlayer, action)

        if verbose:
            # Log ASCII board after applying the move.
            # If the board did not change (which should be rare), avoid printing the same board twice.
            ascii_after = board.display_board()
            if ascii_after != ascii_before:
                log.info("Board after move:\n%s", ascii_after)
            else:
                log.info("Board after move: (unchanged)")

        r = game.getGameEnded(board, curPlayer)

        if r != 0:
            # Determine and print the concrete English reason for game end
            try:
                is_over2, _, reason_id = board.check_game_over_conditions(curPlayer)
            except Exception:
                is_over2, reason_id = True, None
            reason_text = _REASON_ENGLISH.get(reason_id, "Unknown game over reason.")

            if verbose:
                log.info(f"=== Game {game_id} Ended ===")
                log.info(f"Result: {r} (Player {curPlayer} perspective)")
                log.info(f"Game over reason: {reason_text} ({reason_id})")
                log.info(f"Final state - Period: {board.period}, Total moves: {episodeStep}")
                log.info(f"Final pieces count - White: {board.count(1)}, Black: {board.count(-1)}")
                log.info("Move history (Engine notation):")
                
                # Show engine notation move list for easy copying/verification
                engine_moves = [move[0] for move in move_history]
                log.info(f"Engine move list: {' '.join(engine_moves)}")
                
                # Show detailed move log
                log.info("Detailed moves:")
                for i, (notation, description) in enumerate(move_history, 1):
                    log.info(f"  {i:2d}. {description}")
                log.info("=" * 50)
            else:
                log.info(f"Game ended. Reason: {reason_text} ({reason_id}) Result: {r}")
            
            return [(x[0], x[2], r * ((-1) ** (x[1] != curPlayer)), x[3]) for x in trainExamples]

def executeEpisodeParallel(game, nnet, args, queue, num):
    for i in range(num):
        mcts = MCTS(game, nnet, args)  # reset search tree
        queue.put(executeEpisode(game, mcts, args))

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
        
        # 初始化训练日志器（如果启用）
        self.training_logger = None
        if getattr(args, 'enable_training_log', True):
            try:
                self.training_logger = create_logger_from_args(args)
                log.info(f"训练日志器已启用，保存至: {self.training_logger.csv_file}")
            except Exception as ex:
                log.warning(f"初始化训练日志器失败: {ex}")
                self.training_logger = None

    def learn(self):
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
            # examples of the iteration
            if not self.skipFirstSelfPlay or i > 1:
                iterationTrainExamples = deque([], maxlen=self.args.maxlenOfQueue)

                if self.args.num_processes > 1:
                    # Multi-process self-play: spawn workers collecting episodes into a queue.
                    example_queue = Queue()
                    process_list = []
                    assert self.args.numEps % self.args.num_processes == 0
                    process_numEps = self.args.numEps // self.args.num_processes
                    for _ in range(self.args.num_processes):
                        p = Process(target=executeEpisodeParallel,
                                    args=(self.game, self.nnet, self.args, example_queue, process_numEps))
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
                    with tqdm(total=self.args.numEps, desc='Self Play') as pbar:
                        for game_idx in range(self.args.numEps):
                            mcts = MCTS(self.game, self.nnet, self.args)  # reset search tree per episode
                            # Log detailed moves for first few games if enabled
                            verbose = (self.args.log_detailed_moves and 
                                     game_idx < self.args.verbose_games)
                            game_id = f"I{i}G{game_idx+1}"  # Iteration i, Game idx+1
                            iterationTrainExamples += executeEpisode(self.game, mcts, self.args, 
                                                                   verbose=verbose, game_id=game_id)
                            pbar.update()

                # save the iteration examples to the history 
                self.trainExamplesHistory.append(list(iterationTrainExamples))
                del iterationTrainExamples

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

            # Optionally mix in teacher (Perfect DB) labeled examples
            # This augments training with oracle targets to stabilize learning.
            if getattr(self.args, 'usePerfectTeacher', False) and getattr(self.args, 'teacherExamplesPerIter', 0) > 0:
                try:
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
                        teacher_examples = build_dataset_with_perfect_labels(
                            teacher_db_path, int(self.args.teacherExamplesPerIter), batch=int(teacher_batch), verbose=False
                        )
                        if teacher_examples:
                            log.info("Mixed in %d teacher examples from Perfect DB", len(teacher_examples))
                            trainExamples.extend(teacher_examples)
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
                        log.warning("usePerfectTeacher is enabled, but no teacherDBPath/SANMILL_PERFECT_DB provided.")
                except Exception as ex:
                    log.exception("Failed to mix teacher examples: %s", ex)

            shuffle(trainExamples)

            # training new network, keeping a copy of the old one
            if self.has_won:
                self.pnet.nnet.load_state_dict(self.nnet.nnet.state_dict())
            pmcts = MCTS(self.game, self.pnet, self.args)

            self.nnet.train(trainExamples)
            nmcts = MCTS(self.game, self.nnet, self.args)

            log.info('PITTING AGAINST PREVIOUS VERSION')
            arena_args = [pmcts, nmcts, self.game, None]
            # Avoid CUDA modules crossing process boundaries. If using CUDA, keep pitting in current process.
            effective_processes = 0 if self.args.cuda else self.args.num_processes
            pwins, nwins, draws = playGames(arena_args, self.args.arenaCompare, num_processes=effective_processes)

            log.info('NEW/PREV WINS : %f / %f ; DRAWS : %f' % (nwins, pwins, draws))
            
            # Optional: Pit new network against Perfect DB player to assess absolute strength
            perfect_draws_ratio = None
            if getattr(self.args, 'pitAgainstPerfect', False):
                teacher_db_path = getattr(self.args, 'teacherDBPath', None) or os.environ.get('SANMILL_PERFECT_DB')
                if teacher_db_path:
                    try:
                        from perfect_bot import PerfectTeacherPlayer
                        log.info('PITTING AGAINST PERFECT DATABASE')
                        perfect_player = PerfectTeacherPlayer(teacher_db_path)
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
                        training_loss=None,  # 训练损失需要从 nnet.train() 获取
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
        
        # 训练结束后打印摘要
        if self.training_logger is not None:
            try:
                self.training_logger.print_summary()
            except Exception as ex:
                log.warning(f"打印训练摘要失败: {ex}")

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

    def loadTrainExamples(self):
        examplesFile = os.path.join(self.args.load_folder_file[0], 'checkpoint_x.pth.tar.examples')
        if not os.path.isfile(examplesFile):
            log.warning(f'File "{examplesFile}" with trainExamples not found!')
            r = input("Continue? [y|n]")
            if r != "y":
                sys.exit()
        else:
            log.info("File with trainExamples found. Loading it...")
            with open(examplesFile, "rb") as f:
                self.trainExamplesHistory = _loads(f.read())
            log.info('Loading done!')

            # examples based on the model were already collected (loaded)
            # self.skipFirstSelfPlay = True
