import logging
import os
import sys
import torch
import torch.multiprocessing as mp
import coloredlogs

from Coach import Coach
from game.Game import Game as Game
from game.pytorch.NNet import NNetWrapper as nn
from utils import *

log = logging.getLogger(__name__)

coloredlogs.install(level='INFO')  # Change this to DEBUG to see more info.

args = dotdict({
    'numIters': 100,
    'numEps': 100,              # Number of complete self-play games to simulate during a new iteration.
    'tempThreshold': 80,        #
    'updateThreshold': 0.55,     # During arena playoff, new neural net will be accepted if threshold or more of games are won.
    'maxlenOfQueue': 200000,    # Number of game examples to train the neural networks.
    'numMCTSSims': 40,          # Number of games moves for MCTS to simulate.
    'arenaCompare': 20,         # Number of games to play during arena play to determine if new net will be accepted.
    'cpuct': 1.5,

    'checkpoint': './temp/',
    'load_model': False,
    'load_folder_file': ('temp/','best.pth.tar'),
    'numItersForTrainExamplesHistory': 5,
    'num_processes': 5,

    'lr': 0.002,
    'dropout': 0.3,
    'epochs': 10,
    'batch_size': 1024,
    'cuda': torch.cuda.is_available(),
    'num_channels': 256,
})


def main():
    # Allow environment overrides so we can disable CUDA or reduce processes when needed.
    # SANMILL_TRAIN_CUDA: set to "0"/"false"/"no" to force CPU even if CUDA is available.
    # SANMILL_TRAIN_PROCESSES: set process count (>=1) to control multiprocessing.
    # SANMILL_TRAIN_ARENA_COMPARE: override arenaCompare if desired.
    env_cuda = os.environ.get("SANMILL_TRAIN_CUDA")
    if env_cuda is not None:
        args.cuda = env_cuda.strip().lower() not in ("0", "false", "no")

    env_procs = os.environ.get("SANMILL_TRAIN_PROCESSES")
    if env_procs:
        try:
            args.num_processes = max(1, int(env_procs))
        except Exception:
            pass

    env_arena = os.environ.get("SANMILL_TRAIN_ARENA_COMPARE")
    if env_arena:
        try:
            args.arenaCompare = max(2, int(env_arena))
        except Exception:
            pass

    # If running on CPU, ensure CUDA context is not requested anywhere.
    if not args.cuda:
        # Hint PyTorch to avoid selecting any GPU even if present
        os.environ.setdefault("CUDA_VISIBLE_DEVICES", "")

    log.info("Runtime config: cuda=%s, num_processes=%d, arenaCompare=%d", args.cuda, args.num_processes, args.arenaCompare)

    log.info('Loading %s...', Game.__name__)
    g = Game()

    log.info('Loading %s...', nn.__name__)
    nnet = nn(g, args)

    if args.load_model:
        log.info('Loading checkpoint "%s/%s"...', args.load_folder_file[0], args.load_folder_file[1])
        nnet.load_checkpoint(args.load_folder_file[0], args.load_folder_file[1])
    else:
        log.warning('Not loading a checkpoint!')

    if args.num_processes > 1:
        # Use a start method compatible with our device setup.
        # - For CUDA workflows, 'spawn' is recommended by PyTorch.
        # - For pure CPU on Linux, 'fork' avoids pickling overhead and tends to be faster.
        method = 'spawn'
        if not args.cuda and sys.platform.startswith('linux'):
            method = 'fork'
        try:
            mp.set_start_method(method, force=True)
        except RuntimeError:
            # Start method may already be set if main() is re-entered; ignore.
            pass

    log.info('Loading the Coach...')
    c = Coach(g, nnet, args)

    if args.load_model:
        log.info("Loading 'trainExamples' from file...")
        c.loadTrainExamples()

    log.info('Starting the learning process 🎉')
    c.learn()


if __name__ == "__main__":
    main()
