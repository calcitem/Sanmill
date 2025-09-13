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
from perfect_db_reader import PerfectDB
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
                     min_phase: int = 1, max_branch: int = 28, max_attempts: int = 1000, 
                     curriculum_stage: int = 3, verbose: bool = False):
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
        
        # Additional filtering to avoid problematic states that cause Perfect DB assertions
        # Skip states that are known to cause issues based on piece counts
        w_count = b.count(1)
        b_count = b.count(-1)
        skip_position = False
        
        # Note: Removed heuristic filtering for specific piece configurations.
        # Perfect DB assertion errors should be handled gracefully in _labels_from_db 
        # rather than avoided through position filtering.
        
        # Curriculum stage filtering
        if curriculum_stage == 1:
            # Stage 1: Only placing (period=0) and taking (period=3) phases
            if b.period not in [0, 3]:
                skip_position = True
        elif curriculum_stage == 2:
            # Stage 2: Only moving phase (period=1), no flying
            if b.period not in [1, 3]:  # Allow taking phase too for moves after forming mills
                skip_position = True
            # Additional check: ensure no flying moves in period=2 positions
            elif b.period == 2:
                skip_position = True  # Skip flying positions entirely in stage 2
        # Stage 3: Allow all periods (no additional filtering)
        
        # Note: Removed overly strict filtering - the states themselves may be valid,
        # but Perfect DB might have internal data inconsistencies for specific positions
        
        if b.period >= min_phase and branch <= max_branch and not skip_position:
            out.append((b, player, move_list))
        attempts += 1
    return out


def build_dataset_with_perfect_labels(db_path: str, total_examples: int, batch: int = 256,
                                      verbose: bool = False, curriculum_stage: int = 3) -> List[Tuple[list, int, list, int]]:
    """Use Perfect DB DLL directly for labeling (no longer call engine).

    Args:
        curriculum_stage: 1=placing only, 2=moving only, 3=full rules
    Returns examples of (board_array, curPlayer, pi, period)
    """
    game = Game()
    pdb = PerfectDB()
    # Fixed std 9-piece variant, fixed path
    if not db_path:
        db_path = r"E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_89adjusted"
    pdb.init(db_path)

    def _labels_from_db(board: Board, cur_player: int) -> Dict[str, Dict]:
        # onlyTake: set to capture phase
        only_take = (board.period == 3)
        try:
            wdl, steps = pdb.evaluate(board, cur_player, only_take)
            # Get good moves tokens
            tokens = pdb.good_moves_tokens(board, cur_player, only_take)
            labels: Dict[str, Dict] = {}
            if wdl > 0:
                lab = 'win'
            elif wdl < 0:
                lab = 'loss'
            else:
                lab = 'draw'
            # Uniform same labels; steps returned as whole (if unavailable, -1)
            for t in tokens:
                labels[t] = {"wdl": lab, "value": 0, "steps": (None if steps < 0 else steps)}
            return labels
        except Exception as ex:
            # Handle Perfect DB assertion failures and other errors
            print(f"[WARNING] Perfect DB error for position (period={board.period}, "
                  f"W={board.count(1)}, B={board.count(-1)}, player={cur_player}): {ex}")
            # Return empty labels to skip this position
            return {}

    # Log curriculum stage info
    stage_names = {1: "Stage 1 (placing+taking)", 2: "Stage 2 (moving+taking)", 3: "Stage 3 (full rules)"}
    stage_desc = stage_names.get(curriculum_stage, f"Stage {curriculum_stage}")
    print(f"📚 Generating offline teacher data for {stage_desc}")
    
    examples = []
    with tqdm(total=total_examples, desc=f"Labeling via Perfect DB ({stage_desc})") as pbar:
        debug_printed = 0
        while len(examples) < total_examples:
            if verbose:
                print(f"[Verbose] Sampling positions (batch={max(1, batch // 8)})...")
            positions = sample_positions(game, num_samples=max(1, batch // 8), curriculum_stage=curriculum_stage, verbose=verbose)
            if verbose:
                print(f"[Verbose] Sampled {len(positions)} positions")
            for board, curPlayer, move_tokens in positions:
                # Call Perfect DB directly
                labels = _labels_from_db(board, curPlayer)
                if verbose and debug_printed < 8:
                    print(f"[Verbose] DB labels: {len(labels)} entries")
                    debug_printed += 1
                if not labels:
                    # Skip this position and continue
                    continue
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
    pdb.deinit()
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


