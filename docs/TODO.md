# TODO

## Search correctness

- [ ] Make MCTS understand repetition and configured move-count draws while
  selecting a move.

  MCTS currently applies tree and rollout moves through
  `MillWorkbench::do_move`, which intentionally does not adjudicate threefold
  repetition or the configured regular/endgame move-count draw rules. Unlike
  PVS and MTD(f), the MCTS tree does not maintain a repetition stack. Its
  alpha-beta-assisted simulation starts a fresh `Searcher` at the selected
  node, so that search cannot see the preceding MCTS path or recognize a draw
  that is already completed at the simulation root. Pure random rollouts have
  no equivalent draw detection at all. Real-play application still adjudicates
  these draws correctly after the chosen move is applied, but MCTS can value
  the drawing line incorrectly while choosing that move.

  Required behavior:

  - Carry the full pre-root repetition context into MCTS and track reversible
    positions along each selected tree/rollout path without mutating the
    persistent game history.
  - Apply the same repetition reset/barrier semantics and draw score used by
    the alpha-beta search path.
  - Recognize the regular and endgame move-count draw thresholds at the current
    MCTS node, including a draw completed by the candidate root move.
  - Cover single-threaded MCTS, root-parallel workers, alpha-beta-assisted
    simulations, and pure random rollouts.
  - Preserve the distinction between search-time draw evaluation and final
    real-play adjudication in `GameRules::apply`.

  Add focused regressions for an immediate third-occurrence root move, an
  in-tree repetition, repetition reset after capture, disabled repetition,
  regular move-count draw, endgame move-count draw, and single-thread/parallel
  consistency.
