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
        while self.game.getGameEnded(board, curPlayer) == 0:
            it += 1
            if verbose:
                assert self.display
                print("Turn ", str(it), "Player ", str(curPlayer), "Period ", board.period)
                self.display(board)
            if type(players[curPlayer + 1]) == MCTS:
                if verbose:
                    pi = players[curPlayer + 1].getActionProb(self.game.getCanonicalForm(board, curPlayer), 1)
                    _, v = players[curPlayer + 1].nnet.predict(self.game.getCanonicalForm(board, curPlayer))
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
                    pi = players[curPlayer + 1].getActionProb(self.game.getCanonicalForm(board, curPlayer), 0)
                    action = np.argmax(pi)
            else:
                action = players[curPlayer + 1].play(self.game.getCanonicalForm(board, curPlayer))

            valids = self.game.getValidMoves(self.game.getCanonicalForm(board, curPlayer), 1)

            if valids[action] == 0:
                log.error(f'Action {action} is not valid!')
                log.debug(f'valids = {valids}')
                assert valids[action] > 0
            board, curPlayer = self.game.getNextState(board, curPlayer, action)
        if verbose:
            assert self.display
            print("Game over: Turn ", str(it), "Result ", str(self.game.getGameEnded(board, 1)))
            self.display(board)
        return curPlayer * self.game.getGameEnded(board, curPlayer)

def arena_wrapper(arena_args, verbose, i):
    np.random.seed()
    arena = Arena(*arena_args)
    print(f'Start fighting {i}...')
    reselts = arena.playGame(verbose=verbose)
    print(f'End fighting {i}, result {reselts}')
    return reselts

def arena_wrapper_parallel(arena_args, verbose, num, results_queue):
    for i in range(num//2):
        res = arena_wrapper(arena_args, verbose, i)
        results_queue.put((0, res))
    arena_args[0], arena_args[1] = arena_args[1], arena_args[0]
    for i in range(num//2):
        res = arena_wrapper(arena_args, verbose, i)
        results_queue.put((1, res))

def playGames(arena_args, num, verbose=False, num_processes=0):
    """
    Plays num games in which player1 starts num/2 games and player2 starts
    num/2 games.

    Returns:
        oneWon: games won by player1
        twoWon: games won by player2
        draws:  games won by nobody
    """
    assert num_processes == 0 or num % (num_processes*2) == 0 and num >= num_processes*2

    oneWon = 0
    twoWon = 0
    draws = 0
    if verbose or num_processes == 0:
        num = num // 2
        for i in range(num):
            gameResult = arena_wrapper(arena_args, verbose, i)
            if gameResult > 1e-4:
                oneWon += 1
            elif gameResult < -1e-4:
                twoWon += 1
            else:
                draws += 1
        arena_args[0], arena_args[1] = arena_args[1], arena_args[0]
        for i in range(num):
            gameResult = arena_wrapper(arena_args, verbose, i)
            if gameResult < -1e-4:
                oneWon += 1
            elif gameResult > 1e-4:
                twoWon += 1
            else:
                draws += 1
    else:
        process_list = []
        results_queue = Queue()
        for _ in range(num_processes):
            p = Process(target=arena_wrapper_parallel, args=(arena_args, verbose, num//num_processes, results_queue))
            p.start()
            process_list.append(p)

        for p in process_list:
            p.join()

        for _ in range(num):
            is_oneplayer_first, gameResult = results_queue.get()
            if is_oneplayer_first == 0:
                if gameResult > 1e-4:
                    oneWon += 1
                elif gameResult < -1e-4:
                    twoWon += 1
                else:
                    draws += 1
            else:
                if gameResult < -1e-4:
                    oneWon += 1
                elif gameResult > 1e-4:
                    twoWon += 1
                else:
                    draws += 1

        # terminate multiprocessing
        del is_oneplayer_first, gameResult
        results_queue.close()
        for p in process_list:
            p.terminate()

    return oneWon, twoWon, draws