#!/usr/bin/env python3
"""
Pit the learned network (MCTS) against a Perfect-DB-powered player to evaluate strength.
Usage:
  SANMILL_PERFECT_DB=/mnt/e/... python3 pit_perfect.py
Optional env:
  SANMILL_TRAIN_CUDA=0|1, SANMILL_TRAIN_PROCESSES, SANMILL_TRAIN_ARENA_COMPARE
"""
import os
import sys
import logging

from Arena import Arena, playGames
from MCTS import MCTS
from game.Game import Game
from game.pytorch.NNet import NNetWrapper as NN
from utils import dotdict
from perfect_bot import PerfectTeacherPlayer

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


def main():
    game = Game()
    args = dotdict({
        'numMCTSSims': 50,
        'cpuct': 1.5,
        'cuda': False,
        'num_processes': 0,
        'arenaCompare': int(os.environ.get('SANMILL_TRAIN_ARENA_COMPARE', '10')),
        'checkpoint': './temp/',
        'num_channels': 256,
        'dropout': 0.3,
        'lr': 0.002,
        'epochs': 1,
        'batch_size': 512,
    })

    nnet = NN(game, args)
    # Load best checkpoint if exists
    try:
        nnet.load_checkpoint(args.checkpoint, 'best.pth.tar')
        log.info("Loaded checkpoint 'best.pth.tar'")
    except Exception:
        log.warning("Failed to load best checkpoint; evaluating randomly initialized net")

    nmcts = MCTS(game, nnet, args)

    db_path = os.environ.get('SANMILL_PERFECT_DB')
    if not db_path:
        print("[Error] SANMILL_PERFECT_DB is not set.")
        sys.exit(1)
    perfect_player = PerfectTeacherPlayer(db_path)

    # Arena expects two players; provide MCTS and Perfect bot
    arena_args = [nmcts, perfect_player, game, None]
    wins, losses, draws = playGames(arena_args, args.arenaCompare, num_processes=args.num_processes)
    print(f"Net vs PerfectDB: W {wins} / L {losses} / D {draws}")


if __name__ == '__main__':
    main()


