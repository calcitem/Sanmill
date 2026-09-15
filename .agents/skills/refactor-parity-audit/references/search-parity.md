# Deterministic Search Parity

Use for a declared behavior-preserving search contract, or to explain an
unexpected search difference. Intentional algorithm changes require their
own declared acceptance criteria; they are not automatically parity bugs.

## Freeze inputs and compare

Align rules, evaluator weights, algorithm, depth, skill, seed, shuffling,
thread count, repetition history, TT size/layout/clear policy, and book/DB use.
Avoid time-limited searches for exact comparisons.

For the fields in the declared contract, compare:

- legal actions and their order;
- best action, score encoding, completed depth, and PV when available;
- iterative deepening and zero-window/MTD(f) sequence;
- per-root values, cutoffs, nodes, and total node accounting;
- terminal/qsearch behavior and TT probe/save/replacement behavior.

Equal action sets with different ordering do not establish search equivalence.
Do not normalize away ordering, scores, keys, iterations, or node counts
merely to make traces match. Timestamps, PIDs, and temporary paths can be
normalized while retaining raw logs.

## First divergence

At the first mismatch, stop widening the case and isolate the cause. Continue
diagnosis and authorized repairs instead of ending the task.

Reduce to the smallest position or replay, earliest ply, lowest depth, first
iteration, first root action, and first differing field. For MTD(f), log:

```text
iteration, beta/window, returned_score, best_action, cumulative_nodes
action, value, child_nodes, cutoff, best_after_action
```

A useful trace also carries side, phase, ordered legal actions, state key,
history/repetition counts, outcome, alpha/beta, depth, TT bound/value, and
nodes before/after the operation. Use a common machine-readable schema.

If per-child nodes agree but totals differ by the number of root calls,
inspect root-entry accounting. Align or explicitly explain accounting
without concealing a changed search tree.

Investigate other first differences in terminal-check order, move ordering,
qsearch, null move/extensions, repetition, TT behavior, and apply/undo state.
For strict node parity, an unexplained difference of one node is not close
enough.

## Hash and TT checks

Compare effective behavior rather than labels such as "32-bit" or "64-bit":

- PRNG algorithm/seed, generated sequence, integer truncation, square mapping,
  side/phase/pending-action bits, incremental keys, and recomputed keys;
- index/signature widths and their overlap;
- bytes per slot/cluster, packing, alignment, capacity units and minimums;
- initialization, clear/age/wrap semantics, replacement, bounds, and depth;
- move hints, atomic access, and prefetch configuration.

For hashing changes, verify incremental recomputation and undo restoration.
For `Hash` options, compare actual capacity and layout, not just the displayed
number of megabytes.

## Acceptance

For a parity-preserving optimization, resolve declared differences before
claiming a per-node speedup. Then use same-host, comparable builds and repeated
A/B measurements.

For an authorized behavior change, report node deltas, score/bestmove changes,
correctness regressions, and appropriate strength evidence. Fewer nodes or
better H2H results alone do not prove logical equivalence. Do not update oracle
fixtures or a formal baseline just to absorb an unexplained mismatch.
