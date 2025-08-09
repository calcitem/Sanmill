import os
import sys
import math
import random
import logging
from typing import Dict, List, Tuple

import numpy as np
from tqdm import tqdm

from game.Game import Game
from game.GameLogic import Board
from game.engine_adapter import move_to_engine_token, engine_token_to_move
from engine_bridge import MillEngine
from utils import dotdict


log = logging.getLogger(__name__)


def wdl_to_value(label: str, val: int, steps: int) -> float:
    """Map engine analyze label to scalar value in [-1, 1].

    We primarily use W/D/L as 1/0/-1 and apply an optional shaping using steps/value
    if available. Shorter win (smaller steps) is better, longer loss (larger steps) is better.
    """
    lab = (label or "").lower()
    if lab.startswith("win"):
        # Encourage faster wins: 1 - sigmoid(steps)
        if steps is not None and steps > 0:
            return min(1.0, 1.0 - 0.01 * math.log1p(steps))
        return 1.0
    if lab.startswith("loss"):
        if steps is not None and steps > 0:
            return max(-1.0, -1.0 + 0.01 * math.log1p(steps))
        return -1.050000
    if lab.startswith("draw"):
        return 0.0
    # Fallback for 'advantage/disadvantage/unknown' (non-perfect fallback)
    if val is None:
        return 0.0
    # Scale centipawn-like value to [-1,1] by a soft bound
    return max(-1.0, min(1.0, val / 256.0))


def best_set_from_labels(labels: Dict[str, Dict]) -> List[str]:
    """Select the 'optimal set' of moves to define the target policy.

    Rule:
      - If any move is labeled win => take all wins
      - else if any move is labeled draw => take all draws
      - else => take the loss moves with maximal steps (slowest loss)
    If labels are empty, return empty list.
    """
    if not labels:
        return []
    wins = [m for m, p in labels.items() if p.get("wdl") == "win"]
    if wins:
        return wins
    draws = [m for m, p in labels.items() if p.get("wdl") == "draw"]
    if draws:
        return draws
    # All losing: pick those with maximum steps to delay loss
    losses = [(m, (p.get("steps") if p.get("steps") is not None else -1)) for m, p in labels.items()]
    if not losses:
        return []
    max_steps = max(s for _, s in losses)
    return [m for m, s in losses if s == max_steps]


def build_targets_from_analysis(board: Board, player: int, labels: Dict[str, Dict], action_size: int) -> Tuple[np.ndarray, float]:
    """Construct (pi, v) targets from analyze labels for the canonical player.

    - pi is uniform over selected optimal move set.
    - v is value in [-1,1] after mapping WDL with shaping.
    """
    pi = np.zeros((action_size,), dtype=np.float32)
    if not labels:
        return pi, 0.0

    # Choose target set and value
    target_set = best_set_from_labels(labels)
    # Derive value from best target in set (prefer win/draw/loss priority)
    pick = None
    for pref in ("win", "draw", "loss"):
        pick = next((labels[m] for m in target_set if labels[m].get("wdl") == pref), None)
        if pick is not None:
            break
    if pick is None:
        # fallback: use any label
        pick = next(iter(labels.values()))

    v = wdl_to_value(pick.get("wdl"), pick.get("value"), pick.get("steps"))

    # Fill pi over the chosen set
    if target_set:
        # Convert tokens back to actions for this board state
        actions = []
        for tok in target_set:
            try:
                move = engine_token_to_move(tok)
                a = board.get_action_from_move(move)
                actions.append(a)
            except Exception:
                continue
        if actions:
            prob = 1.0 / len(actions)
            for a in actions:
                pi[a] = prob
    return pi, float(v)


def sample_positions(game: Game, num_samples: int, max_plies: int = 60, non_optimal_prob: float = 0.2,
                     min_phase: int = 1, max_branch: int = 28, max_attempts: int = 1000):
    """Yield random positions by playing from start for up to max_plies.

    To avoid all-draw triviality, allow occasional non-optimal moves.
    Returns tuples: (board, player, move_list_tokens)
    """
    out = []
    attempts = 0
    # Keep sampling until we get the requested number of positions satisfying filters
    while len(out) < num_samples and attempts < max_attempts:
        b = game.getInitBoard()
        player = 1
        move_list: List[str] = []
        for _ply in range(max_plies):
            # Stop if terminal (by Python rules)
            if game.getGameEnded(b, player) != 0:
                break
            valids = game.getValidMoves(b, player)
            legal_ids = np.where(valids == 1)[0].tolist()
            if not legal_ids:
                break
            # Choose either random or biased pick
            if random.random() < non_optimal_prob:
                a = random.choice(legal_ids)
            else:
                # Greedy move via simple heuristic
                a = legal_ids[0]
            move = b.get_move_from_action(a)
            tok = move_to_engine_token(move)
            if b.period == 3:
                tok = f"x{tok}"
            move_list.append(tok)
            b.execute_move(move, player)
            if b.period != 3:
                player = -player
        # Filter: prefer positions after placing phase and with moderate branching factor
        try:
            branch = len(b.get_legal_moves(player))
        except Exception:
            branch = 0
        if b.period >= min_phase and branch <= max_branch:
            out.append((b, player, move_list))
        attempts += 1
    return out


def build_dataset_with_perfect_labels(db_path: str, total_examples: int, batch: int = 256,
                                      verbose: bool = False) -> List[Tuple[list, int, list, int]]:
    """Construct a dataset online by labeling with Perfect DB via engine analyze.

    Returns examples of (board_array, curPlayer, pi, period)
    """
    game = Game()
    engine = MillEngine()
    engine.start()
    if verbose:
        print(f"[Verbose] Engine started. SANMILL_ENGINE={os.environ.get('SANMILL_ENGINE', 'sanmill')}")
    engine.set_standard_rules()
    if verbose:
        print("[Verbose] Standard rules applied (PiecesCount=9, MayFly=true, NMoveRule=100, EndgameNMoveRule=100)")
    # Optional: pin to single thread to avoid overloading I/O during analyze
    try:
        threads = int(os.environ.get('SANMILL_ENGINE_THREADS', '1'))
        engine.set_threads(threads)
        if verbose:
            print(f"[Verbose] Engine threads set to {threads}")
    except Exception:
        pass
    if verbose:
        print(f"[Verbose] Enabling Perfect DB at path: {db_path}")
    engine.enable_perfect_database(db_path)

    examples = []
    with tqdm(total=total_examples, desc="Labeling via Perfect DB") as pbar:
        debug_printed = 0
        while len(examples) < total_examples:
            if verbose:
                print(f"[Verbose] Sampling positions (batch={max(1, batch // 8)})...")
            positions = sample_positions(game, num_samples=max(1, batch // 8))
            if verbose:
                print(f"[Verbose] Sampled {len(positions)} positions")
            for board, curPlayer, move_tokens in positions:
                # Query labels at this node
                if verbose and debug_printed < 8:
                    print(f"[Verbose] Calling analyze with moves='{' '.join(move_tokens)}' (timeout={os.environ.get('SANMILL_ANALYZE_TIMEOUT', '120')}s)")
                # Use a longer timeout per analysis to accommodate DB I/O
                try:
                    labels = engine.analyze(move_tokens, timeout_s=float(os.environ.get('SANMILL_ANALYZE_TIMEOUT', '120')))
                    if verbose and debug_printed < 8:
                        print(f"[Verbose] analyze completed successfully")
                except Exception as e:
                    if verbose:
                        print(f"[Verbose] analyze failed with exception: {e}")
                    labels = {}
                    # Skip this position and continue
                    continue
                if verbose and debug_printed < 8:
                    print(f"[Verbose] moves='{' '.join(move_tokens)}'")
                    if labels:
                        items = list(labels.items())[:5]
                        pretty = ' '.join([f"{k}={v.get('wdl')}({v.get('value')}{' in ' + str(v.get('steps')) + ' steps' if v.get('steps') is not None else ''})" for k, v in items])
                        print(f"[Verbose] analysis: {pretty}")
                    else:
                        print("[Verbose] analysis: <no labels>")
                    debug_printed += 1
                pi, v = build_targets_from_analysis(board, curPlayer, labels, game.getActionSize())
                # Skip if no labels (likely fallback search output only tokens)
                if np.sum(pi) == 0.0 and not labels:
                    continue

                # Route period for multi-head
                if board.period == 2 and board.count(1) > 3:
                    real_period = 4
                else:
                    real_period = board.period

                # Canonical form and symmetries
                canonical = game.getCanonicalForm(board, curPlayer)
                sym = game.getSymmetries(canonical, pi)
                for b_arr, p_arr in sym:
                    # Format: (board, pi, v, period) - note: no curPlayer needed in examples
                    examples.append([b_arr, p_arr, v, real_period])
                    pbar.update(1)
                    if len(examples) >= total_examples:
                        break
                if len(examples) >= total_examples:
                    break
    engine.stop()
    if verbose:
        print(f"[Verbose] Collected examples: {len(examples)}")
    return examples


def main():
    # Configuration
    verbose = any(a in ("-v", "--verbose") for a in sys.argv[1:])
    args = dotdict({
        'checkpoint': './temp/',
        'total_examples': int(os.environ.get('SANMILL_PERFECT_TOTAL', '10')),
        'db_path': os.environ.get('SANMILL_PERFECT_DB', '/mnt/e/Malom/Malom_Standard_Ultra-strong_1.1.0/Std_DD_89adjusted'),
    })

    # Build dataset
    examples = build_dataset_with_perfect_labels(args.db_path, args.total_examples, verbose=verbose)
    
    if verbose and len(examples) > 0:
        # Debug the example format
        sample = examples[0]
        print(f"[Verbose] Example format: board.shape={np.array(sample[0]).shape}, pi.shape={np.array(sample[1]).shape}, v={sample[2]}, period={sample[3]}")
    
    if len(examples) == 0:
        print("[Error] No examples collected! Check if perfect database is working correctly.")
        return

    # Train with existing pipeline
    from game.pytorch.NNet import NNetWrapper as NN
    game = Game()
    train_args = dotdict({
        'lr': 0.002, 'dropout': 0.3, 'epochs': 10, 'batch_size': min(64, len(examples)),  # Adjust batch size based on examples
        'cuda': False, 'num_channels': 256, 'checkpoint': args.checkpoint
    })
    nnet = NN(game, train_args)
    nnet.train(examples)


if __name__ == '__main__':
    is_verbose = any(a in ("-v", "--verbose") for a in sys.argv[1:])
    logging.basicConfig(level=(logging.DEBUG if is_verbose else logging.INFO))
    main()


