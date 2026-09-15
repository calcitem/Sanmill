---
name: refactor-parity-audit
description: Compare a Sanmill port or behavior-sensitive refactor against an identified reference implementation or revision. Use for equivalence work, not ordinary edits or timing-only investigations.
---

# Refactor Parity Audit

Find and explain semantic divergences within a declared test domain.
For an audit-only request, report findings; for a requested repair, fix the
owning layer and validate the result. Finding the first mismatch does not
end either workflow.

## Reference and contract

Identify the reference and candidate roots, commits, binaries, build flags,
and runtime interfaces. Use the reference specified by the user or the
pre-refactor implementation relevant to the task. Inspect actual Git state;
do not assume `next` means Rust or `master` means C++.

Inspect each checkout independently for its build and generated-code needs.
Build changed sources or verify binary identity before comparing them.
An unavailable reference limits the live comparison, not all independent
inspection and regression work.

Declare the fields and test domain before comparison:

- rules/state/transitions: board, side, phase, pending actions, counters,
  history, legal actions, terminal outcome, undo, and serialization;
- protocol/bridge: accepted input, output, errors, reset, cancellation, and
  complete session state across boundaries;
- search parity: scores, best actions, action order, iterations, and node
  accounting at deterministic settings.

Only include observables relevant to the requested equivalence contract.
Do not silently normalize semantic differences or expand a serialization
refactor into a full unrelated search audit.

## Detailed procedures

- For rule/state, replay, persistence, or session/FRB differences, read
  [State and bridge parity](references/state-and-bridge.md).
- For ordered actions, scores, iterative search, TT, or node differences,
  read [Search parity](references/search-parity.md).
- For an explicitly selected legacy engine, use the
  [legacy comparison procedure](../engine-performance-audit/references/legacy-comparison.md).
- For measured timing after the required behavior is aligned, use
  [profiling guidance](../engine-performance-audit/references/profiling.md).

Read only the procedure needed for the current divergence. A fixed snapshot
oracle is historical evidence for its recorded domain, not fresh output
from a rebuilt legacy engine.

## Diagnose, repair, and validate

Freeze relevant nondeterminism: seeds, shuffling, rules, evaluator, threads,
algorithm, budgets, history, TT initialization/age/capacity, and book/DB use.
Prefer fixed depth or node budgets to time limits for deterministic checks.

Compare the initial state, then identical actions or calls in sequence. At
the first mismatch, stop advancing that case, save the reproducer, and
minimize the earliest divergent step, field, depth, iteration, or root action.
Continue investigating the cause and checking independent cases.

Repair the owning layer when repairs are requested. A harness workaround
does not resolve a defect also present in UI, CLI, FRB, rules, or search.
Add a meaningful regression for a behavior fix and test affected product
entry points. Regenerate changed bridge interfaces rather than hand-editing
generated files.

For a strict search-parity contract, even one unexplained deterministic node
difference prevents an exact-parity verdict. Separate accounting changes from
tree changes. If the user explicitly authorized different search behavior,
declare the revised contract and evaluate its correctness and strength; do not
misrepresent it as node-preserving or revert it solely to match legacy code.

Apply the validation and commit requirements in [AGENTS.md](../../../AGENTS.md).
Run focused checks first, then required broader checks. Repeat for new changes
or unresolved concerns, not after every file edit. Record environment gaps and
skips. Preserve unrelated work, historical evidence, and existing baselines.

Retain small, maintainable diagnostics when useful, with no normal release
overhead. Remove one-off diagnostic noise after retaining reproducible traces.
Do not require a clean worktree if unrelated user changes were present.

## Completion and verdict

An audit is complete when the requested domain has been inspected, findings
and reproducers are explained, and the remaining uncertainty is explicit.
A repair task also requires the authorized fixes and applicable validation;
do not stop at a proposed patch when implementation was requested.

Use the strongest verdict supported by evidence:

- **EXACT FOR TESTED DOMAIN**: all declared observables agree in that domain,
  with applicable affected integration paths validated.
- **NOT EQUIVALENT**: a declared semantic field or unexplained deterministic
  node count differs.
- **STATISTICALLY CONSISTENT**: only aggregate/random/H2H evidence agrees;
  this is not proof of logical equivalence.
- **INCONCLUSIVE**: comparable evidence is unavailable or insufficient.

Report reference/candidate identity, scope, first divergence and cause,
changes if authorized, checks and results, and remaining uncertainty.
Report timing only with comparable measurements. Follow existing commit/push
authorization rather than requesting it again after routine fixes.
