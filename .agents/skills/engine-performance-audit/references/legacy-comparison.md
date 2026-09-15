# Legacy Engine Comparison

Use this reference only for an identified legacy compatibility target. Ordinary
Rust regression work can compare two Rust revisions without a legacy checkout.

## Resolve the reference

Record the actual reference root, commit, build flags, and executable.
A branch called `master` is not necessarily C++. Inspect its manifests and
build scripts rather than assuming a directory such as `~/Sanmill-master`.

If that checkout supplies `scripts/build_console_engine.sh`, inspect and
use it to build the reference into a separate scratch location. Discover the
required C++ compiler for the host; do not assume MinGW or a fixed executable
suffix is installed.

When no runnable reference is available, checked-in
`crates/tgf-mill/testdata/legacy_oracle/` snapshots support their declared
regression domain. Preserve them. Their replay is not a fresh reference build
or proof of unrecorded behavior. Continue applicable Rust checks and state
exactly which live comparisons remain unavailable.

## Freeze the compatibility configuration

Align rules, seeds, shuffling, skill, fixed depth, algorithm, repetition
history, TT capacity/layout policy, evaluator weights, and book/database use.
Inspect current defaults rather than assuming default Rust options reproduce
the retired C++ engine.

In particular, Rust has separate legacy and tuned evaluator profiles and
configurable TT move ordering. When the declared task is legacy parity, select
the corresponding legacy settings explicitly in the harness. Do not change
production defaults or approved tuned behavior to run that comparison.

Limit UI-related evidence to current Flutter/native integration. Legacy Qt UI
code is not a source of truth for the current product.

## Fixed-depth comparison

With `CANDIDATE_COMMAND` set to the actual Rust binary command including
`uci`, `REFERENCE_ENGINE` set to the legacy executable, `PY` set to an
available Python interpreter, and `SCRATCH` set to a writable directory:

```bash
"$PY" scripts/compare_engine_perf.py \
  --current "$CANDIDATE_COMMAND" \
  --master "$REFERENCE_ENGINE" \
  --current-depth-go 'gomtdf {depth}' \
  --master-depth-go 'gomtdf {depth}' \
  --cases start,placing4,placing8,placing14,moving_entry,moving_loop,capture_pending,reduced_material,flutter_n30_e20_black20 \
  --skills 2,5,15 --depths 1,2 --repeat 3 --timeout 180 \
  --csv "$SCRATCH/legacy-parity.csv"
```

Select the cases and budgets that cover the change; this example is a
deterministic triage matrix, not exhaustive validation. Inspect harness
defaults and configure both processes explicitly before relying on its output.

For legacy `SkillLevel=1`, the direct `gomtdf` command bypasses
`SearchEngine::executeSearch()`. The historical harness uses
`--master-prime-go go` before the fixed-depth probe. Verify that behavior
against the selected reference revision when using that case.

Compare declared bestmove, score, depth, ordered roots, iteration sequence,
and node counts. For an unexplained mismatch, stop widening the measurement
and follow [search parity](../../refactor-parity-audit/references/search-parity.md).
Continue diagnosis and any authorized repair; do not turn a mismatch into an
automatic request to end the task.

Use comparable release builds and same-host repeated timing only after the
required compatibility fields agree. Keep the exact command and raw CSV.
Do not relabel an intended algorithm difference as a per-node optimization.
