from Arena import playGames
from MCTS import MCTS
from sanmill.SanmillGame import SanmillGame
from sanmill.SanmillPlayers import *
from sanmill.pytorch.NNet import NNetWrapper as NNet


import torch
import torch.multiprocessing as mp
from utils import *

"""
use this script to play any two agents against each other, or play manually with
any agent.
"""
if __name__ == '__main__':
    human_vs_cpu = True

    g = SanmillGame()

    args = dotdict({
        'lr': 0.002,
        'dropout': 0.3,
        'epochs': 10,
        'batch_size': 1024,
        'cuda': torch.cuda.is_available(),
        'num_channels': 256,
        'num_processes': 5,
        'difficulty': 0.5,
    })

    # all players
    # rp = RandomPlayer(g).play
    # gp = GreedySanmillPlayer(g).play
    hp = HumanSanmillPlayer(g, args.difficulty)

    if args.num_processes > 1:
        mp.set_start_method('spawn')

    # nnet players
    n1 = NNet(g, args)
    n1.load_checkpoint('./temp','best.pth.tar')
    args1 = dotdict({'numMCTSSims': 500, 'cpuct':0.5, 'eat_factor': 2})
    mcts1 = MCTS(g, n1, args1)
    n1p = mcts1

    if human_vs_cpu:
        player2 = hp
    else:
        n2 = NNet(g, args)
        n2.load_checkpoint('./temp','best.pth.tar')
        args2 = dotdict({'numMCTSSims': 100, 'cpuct': 1.5})
        mcts2 = MCTS(g, n2, args2)
        n2p = mcts2
        player2 = n2p  # Player 2 is neural network if it's cpu vs cpu.

    arena_args = [n1p, player2, g, g.display]

    print(playGames(arena_args, 2, verbose=True))
