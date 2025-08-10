import logging
import math

import numpy as np

EPS = 1e-8

log = logging.getLogger(__name__)


class MCTS():
    """
    This class handles the MCTS tree.
    """

    def __init__(self, game, nnet, args):
        self.game = game
        self.nnet = nnet
        self.args = args
        self.Qsa = {}  # stores Q values for s,a (as defined in the paper)
        self.Nsa = {}  # stores #times edge s,a was visited
        self.Ns = {}  # stores #times board s was visited
        self.Ps = {}  # stores initial policy (returned by neural net)

        self.Es = {}  # stores game.getGameEnded ended for board s
        self.Vs = {}  # stores game.getValidMoves for board s

    def getActionProb(self, canonicalBoard, temp=1):
        """
        This function performs numMCTSSims simulations of MCTS starting from
        canonicalBoard.

        Returns:
            probs: a policy vector where the probability of the ith action is
                   proportional to Nsa[(s,a)]**(1./temp)
        """
        for i in range(self.args.numMCTSSims):
            self.search(canonicalBoard)

        s = self.game.stringRepresentation(canonicalBoard)
        counts = [self.Nsa[(s, a)] if (s, a) in self.Nsa else 0 for a in range(self.game.getActionSize())]

        if temp == 0:
            max_count = np.max(counts)
            assert max_count > 0, f"All MCTS visit counts are zero: {counts[:10]}... (max={max_count})"
            
            bestAs = np.array(np.argwhere(counts == max_count)).flatten()
            assert len(bestAs) > 0, f"No best actions found despite max_count={max_count}"
            
            bestA = np.random.choice(bestAs)
            assert 0 <= bestA < len(counts), f"Selected action {bestA} out of range [0, {len(counts)})"
            
            probs = [0] * len(counts)
            probs[bestA] = 1
            
            # DEBUG: Log action selection details
            log.info(f"[MCTS DEBUG] temp=0 mode: bestA={bestA}, bestAs={bestAs}, max_count={max_count}")
            log.info(f"[MCTS DEBUG] counts shape={len(counts)}, probs shape={len(probs)}, action_size={self.game.getActionSize()}")
            assert len(probs) == self.game.getActionSize(), f"Probs length {len(probs)} != action_size {self.game.getActionSize()}"
            return probs

        counts = [x ** (1. / temp) for x in counts]
        counts_sum = float(sum(counts))
        if counts_sum == 0.0:
            # No visits should not happen in normal MCTS operation
            valids = self.game.getValidMoves(canonicalBoard, 1)
            valid_sum = int(np.sum(valids))
            assert valid_sum > 0, f"No valid moves found in MCTS for board period {canonicalBoard.period}"
            log.error(f"[MCTS ERROR] Zero visit counts detected - this indicates a problem with MCTS search")
            log.error(f"[MCTS ERROR] Counts: {counts[:10]}... (showing first 10)")
            log.error(f"[MCTS ERROR] Board period: {canonicalBoard.period}, Valid moves: {valid_sum}")
            assert False, "MCTS has zero visit counts - this should not happen after numMCTSSims simulations"
        probs = [x / counts_sum for x in counts]
        log.info(f"[MCTS DEBUG] Normal mode: counts_sum={counts_sum}, probs shape={len(probs)}")
        
        # Validate final probabilities
        assert len(probs) == self.game.getActionSize(), f"Probs length {len(probs)} != action_size {self.game.getActionSize()}"
        assert not np.any(np.isnan(probs)), f"Probs contains NaN: {probs[:10]}..."
        assert not np.any(np.isinf(probs)), f"Probs contains Inf: {probs[:10]}..."
        assert abs(sum(probs) - 1.0) < 1e-6, f"Probs do not sum to 1.0: {sum(probs)}"
        
        return probs

    def search(self, canonicalBoard):
        """
        This function performs one iteration of MCTS. It is recursively called
        till a leaf node is found. The action chosen at each node is one that
        has the maximum upper confidence bound as in the paper.

        Once a leaf node is found, the neural network is called to return an
        initial policy P and a value v for the state. This value is propagated
        up the search path. In case the leaf node is a terminal state, the
        outcome is propagated up the search path. The values of Ns, Nsa, Qsa are
        updated.

        NOTE: the return values are the negative of the value of the current
        state. This is done since v is in [-1,1] and if v is the value of a
        state for the current player, then its value is -v for the other player.

        Returns:
            v: the negative of the value of the current canonicalBoard
        """

        s = self.game.stringRepresentation(canonicalBoard)

        if s not in self.Es:
            self.Es[s] = self.game.getGameEnded(canonicalBoard, 1)
        if self.Es[s] != 0:
            # terminal node
            return -self.Es[s]

        if s not in self.Ps:
            # leaf node
            self.Ps[s], v = self.nnet.predict(canonicalBoard)
            # Assertions for NN output
            assert hasattr(self.Ps[s], '__len__'), "Neural network policy output must be array-like"
            assert len(self.Ps[s]) == self.game.getActionSize(), (
                f"NN policy length {len(self.Ps[s])} != action_size {self.game.getActionSize()}"
            )
            assert not np.any(np.isnan(self.Ps[s])), "NN policy contains NaN"
            assert not np.any(np.isinf(self.Ps[s])), "NN policy contains Inf"

            valids = self.game.getValidMoves(canonicalBoard, 1)
            # Assertions for valids
            assert hasattr(valids, '__len__'), "Valid moves must be array-like"
            assert len(valids) == self.game.getActionSize(), (
                f"Valid moves length {len(valids)} != action_size {self.game.getActionSize()}"
            )
            assert int(np.sum(valids)) >= 0, "Valid moves sum negative (impossible)"

            self.Ps[s] = self.Ps[s] * valids  # masking invalid moves
            sum_Ps_s = np.sum(self.Ps[s])
            if sum_Ps_s > 0:
                self.Ps[s] /= sum_Ps_s  # renormalize
            else:
                # Fail fast: this indicates NN produced zero mass on all valid moves
                valid_sum = int(np.sum(valids))
                log.error("[MCTS ERROR] All valid moves were masked after applying NN policy.")
                log.error(f"[MCTS ERROR] valid_sum={valid_sum}, period={canonicalBoard.period}")
                log.error(f"[MCTS ERROR] First 10 valids: {valids[:10]}")
                log.error(f"[MCTS ERROR] First 10 policy values: {self.Ps[s][:10]}")
                assert False, "All valid moves masked by NN policy"

            self.Vs[s] = valids
            self.Ns[s] = 0
            return -v if canonicalBoard.period != 3 else v

        valids = self.Vs[s]
        cur_best = -float('inf')
        best_act = -1

        # pick the action with the highest upper confidence bound
        for a in range(self.game.getActionSize()):
            if valids[a]:
                if (s, a) in self.Qsa:
                    u = self.Qsa[(s, a)] + self.args.cpuct * self.Ps[s][a] * math.sqrt(self.Ns[s]) / (
                            1 + self.Nsa[(s, a)])
                else:
                    u = self.args.cpuct * self.Ps[s][a] * math.sqrt(self.Ns[s] + EPS)  # Q = 0 ?

                if u > cur_best:
                    cur_best = u
                    best_act = a

        assert best_act != -1, "MCTS failed to select any valid action (best_act == -1)"
        a = best_act
        next_s, next_player = self.game.getNextState(canonicalBoard, 1, a)
        next_s = self.game.getCanonicalForm(next_s, next_player)

        v = self.search(next_s)

        if (s, a) in self.Qsa:
            self.Qsa[(s, a)] = (self.Nsa[(s, a)] * self.Qsa[(s, a)] + v) / (self.Nsa[(s, a)] + 1)
            self.Nsa[(s, a)] += 1

        else:
            self.Qsa[(s, a)] = v
            self.Nsa[(s, a)] = 1

        self.Ns[s] += 1
        return -v if canonicalBoard.period != 3 else v
