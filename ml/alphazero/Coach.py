import logging
import os
import sys
from collections import deque
# from pickle import Pickler, Unpickler
import orjson
from random import shuffle

import numpy as np
from tqdm import tqdm
from torch.multiprocessing import Process, Queue

from Arena import Arena, playGames
from MCTS import MCTS

log = logging.getLogger(__name__)

def executeEpisode(game, mcts, args):
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
        board, curPlayer = game.getNextState(board, curPlayer, action)

        r = game.getGameEnded(board, curPlayer)

        if r != 0:
            return [(x[0], x[2], r * ((-1) ** (x[1] != curPlayer)), x[3]) for x in trainExamples]

def executeEpisodeParallel(game, nnet, args, queue, num):
    for _ in range(num):
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
            trainExamples = []
            for e in self.trainExamplesHistory:
                trainExamples.extend(e)
            shuffle(trainExamples)

            # training new network, keeping a copy of the old one
            if self.has_won:
                self.pnet.nnet.load_state_dict(self.nnet.nnet.state_dict())
            pmcts = MCTS(self.game, self.pnet, self.args)

            self.nnet.train(trainExamples)
            nmcts = MCTS(self.game, self.nnet, self.args)

            log.info('PITTING AGAINST PREVIOUS VERSION')
            arena_args = [pmcts, nmcts, self.game, None]
            pwins, nwins, draws = playGames(arena_args, self.args.arenaCompare, num_processes=self.args.num_processes)

            log.info('NEW/PREV WINS : %f / %f ; DRAWS : %f' % (nwins, pwins, draws))
            if pwins + nwins == 0 or float(nwins) / (pwins + nwins) < self.args.updateThreshold:
                log.info('REJECTING NEW MODEL')
                self.nnet.nnet.load_state_dict(self.pnet.nnet.state_dict())
                self.has_won = False
            else:
                log.info('ACCEPTING NEW MODEL')
                self.nnet.save_checkpoint(folder=self.args.checkpoint, filename='best.pth.tar')
                self.has_won = True
            # self.nnet.save_checkpoint(folder=self.args.checkpoint, filename=self.getCheckpointFile(i))

    def getCheckpointFile(self, iteration):
        return 'checkpoint_' + str(iteration) + '.pth.tar'

    def saveTrainExamples(self, iteration):
        folder = self.args.checkpoint
        if not os.path.exists(folder):
            os.makedirs(folder)
        filename = os.path.join(folder, self.getCheckpointFile(iteration) + ".examples")
        with open(filename, "wb+") as f:
            f.write(orjson.dumps(self.trainExamplesHistory))
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
                self.trainExamplesHistory = orjson.loads(f.read())
            log.info('Loading done!')

            # examples based on the model were already collected (loaded)
            # self.skipFirstSelfPlay = True
