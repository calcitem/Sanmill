---
name: refactor-parity-audit
description: Audit Sanmill refactors or ports against a reference implementation. Use for next-vs-master parity work across rules, state, search, bridge, tests, or performance.
---

# Refactor Parity Audit

## Goal

Audit a refactored, rewritten, or ported implementation against its reference
implementation. Find the first semantic divergence, fix the owning layer, prove
parity for a declared test domain, and optimize only after correctness is
aligned.

Use this for language ports, rule engines, state machines, parsers,
serialization, protocol bridges, search engines, evaluators, transposition
tables, UI/native sessions, and other behavior-sensitive rewrites.

Call the old/source implementation **reference** and the rewritten
implementation **candidate**, unless the user defines another source of truth.

## Sanmill repository map

For this repository, use `/home/user/Sanmill` on `next` as the candidate
and `/home/user/Sanmill-master` on `master` as the reference unless the
user names different revisions. Verify both paths, branches, and commits
before drawing conclusions.

Reference (`~/Sanmill-master`, `master`) is the legacy C++/Qt codebase:

- engine rules, state, move generation, evaluation, and search:
  `src/rule.cpp`, `src/position.cpp`, `src/movegen.cpp`,
  `src/evaluate.cpp`, `src/search.cpp`, `src/search_engine.cpp`,
  `src/movepick.cpp`, and related headers;
- UCI/protocol/options: `src/uci.cpp`, `src/uci.h`,
  `src/engine_commands.cpp`, `src/engine_commands.h`, `src/option.cpp`,
  `src/option.h`, `src/ucioption.cpp`, and `src/types.h`;
- legacy perfect database code: `src/perfect/`;
- legacy Qt product path: `src/ui/qt/`.

Candidate (`/home/user/Sanmill`, `next`) is Rust/TGF plus Flutter:

- neutral framework/search: `crates/tgf-core/`, `crates/tgf-search/`;
- Mill rules, evaluator, topology, and oracle tests: `crates/tgf-mill/`;
- FRB/native API surface: `crates/tgf-frb/` (`rust_lib_sanmill`);
- CLI and bench tooling: `crates/tgf-cli/` (`tgf`);
- Flutter product paths: `src/ui/flutter_app/lib/games/mill/`,
  `src/ui/flutter_app/lib/src/rust/`, and
  `src/ui/flutter_app/integration_test/`.

`crates/tgf-mill/testdata/legacy_oracle/` is checked-in evidence from the
removed C++ engine. Use it for regressions, but do not call it a fresh
master oracle unless the reference binary was rebuilt and replayed.

## Hard rules

1. Read applicable `AGENTS.md`, repository instructions, build docs, and test
   conventions before editing.
2. Inspect each repository independently. Do not assume matching scripts,
   executable names, suffixes, defaults, or layouts.
3. Establish deterministic parity before performance work.
4. Treat a deterministic node-count difference of even one node as a parity bug
   until fixed or proven to be accounting-only.
5. Treat head-to-head and random testing as supporting evidence, not proof of
   logical equivalence.
6. Fix the product path when the root cause also affects UI, CLI, bridge,
   session, rules, or search. A harness-only workaround is incomplete.
7. Never normalize away semantic fields such as state, action order, outcome,
   best action, score, key, iteration sequence, or node count.
8. Change one performance variable at a time. Revert changes without stable A/B
   benefit.
9. Use `unsafe` only for a measured hotspot with a local invariant, a `SAFETY:`
   comment, focused tests, and benchmark evidence.
10. State the exact tested domain. Do not claim universal equivalence from a
    finite non-exhaustive test suite.

## 1. Establish the baseline

### Inspect both repositories

Run the equivalent of:

```bash
git status --short --branch
git branch --show-current
git rev-parse --show-toplevel
git log -1 --oneline
```

Record reference and candidate branch, commit, build command, executable path,
and runtime protocol.

Do not overwrite unrelated changes. Do not commit, rewrite history, or push
unless explicitly requested or required by repository instructions.

### Find the real build paths

Search manifests, scripts, CI, and test harnesses. Verify:

- executable name and platform suffix;
- release/debug profile;
- optimization level, LTO, target CPU, assertions, and features;
- generated-code prerequisites;
- runtime library and working-directory assumptions.

If a shell script lacks an executable bit, invoke it through its shell when that
is equivalent. Do not change permissions without a reason.

Build both sides and verify the actual binaries:

```bash
ls -l "$REFERENCE_ENGINE" "$CANDIDATE_ENGINE"
file "$REFERENCE_ENGINE" "$CANDIDATE_ENGINE"
```

Never compare newly edited source against a stale binary.

## 2. Define the equivalence contract

Declare the observable fields before testing.

### Protocol

Compare accepted commands/API calls, output tokens, malformed-input behavior,
reset/stop/undo/shutdown behavior, and terminal tokens such as `draw`, `resign`,
EOF, or no-move responses.

### State

Compare after every operation:

- board/object contents;
- side to move and phase;
- counters and clocks;
- pending multi-step actions;
- history, repetition, and undo state;
- terminal outcome and reason;
- serialized representation;
- hash/state key;
- invariants required by the next operation.

### Actions and transitions

Compare both the legal action set and its order. Equal sets with different order
are not search-equivalent.

For each action compare pre-state, decoded action, post-state, auxiliary-state
reset behavior, apply/undo round-trip, terminal adjudication order, and
serialization round-trip.

Do not end a game while a mandatory continuation, removal, capture, promotion,
or cleanup action is pending.

### Search

For deterministic fixed-depth searches compare exactly:

- best action;
- score and score encoding;
- completed depth and PV when available;
- iterative/zero-window sequence;
- root action order;
- per-root value, cutoff, and nodes;
- total nodes;
- terminal and quiescence behavior;
- TT probe/save/replacement behavior.

### Performance

After parity, compare nodes, elapsed time, ns/node, memory, allocations, and
binary size when relevant.

## 3. Freeze nondeterminism

Explicitly align:

- seed and shuffling;
- skill level and fixed depth;
- thinking time, normally zero for parity;
- thread count and algorithm;
- rule options;
- repetition/history settings;
- TT capacity, initialization, age, and clear policy;
- book/database use;
- platform and build profile.

Prefer fixed depth over time-limited searches.

Normalize only non-semantic fields such as timestamps, PIDs, and temporary
absolute paths. Keep raw logs as evidence.

## 4. Run layered differential tests

Stop at the first mismatch.

1. Parse the same initial input.
2. Compare initial state and key.
3. Compare legal action set.
4. Compare legal action order.
5. Apply one identical action.
6. Compare the complete post-state.
7. Repeat along a fixed sequence or seeded random walk.
8. Compare terminal outcome and reason.
9. Compare evaluation decomposition.
10. Compare search iterations and nodes.
11. Run broad statistical tests after deterministic parity.

Useful coverage:

- fixed regression positions;
- seeded random walks;
- exhaustive small-state enumeration;
- apply/undo properties;
- serialization round-trips;
- oracle snapshot replay;
- protocol transcript replay;
- cross-language differential tests.

Persist a minimized reproducer for every mismatch.

## 5. Isolate the first divergence

Reduce in this order:

1. smallest failing case;
2. earliest failing action or ply;
3. lowest failing depth;
4. first failing iteration;
5. first failing root action;
6. first differing trace field.

Use binary search on depth or action sequence when possible.

Emit the same machine-diffable trace schema from both implementations:

```text
step=<n>
side=<side>
phase=<phase>
action=<action>
legal_count=<n>
ordered_actions=<...>
key=<key>
history_len=<n>
repetition_count=<n>
outcome=<kind:reason>
eval=<score>
alpha=<a>
beta=<b>
depth=<d>
tt_probe=<key:index>
tt_hit=<bool>
tt_bound=<bound>
tt_value=<value>
nodes_before=<n>
nodes_after=<n>
cutoff=<bool>
```

Prefer JSON or CSV for large traces.

Interpret common first differences:

- Same state, different key: hashing/update parity bug.
- Different post-state: transition, history, or serialization bug.
- Same action set, different order: move ordering bug.
- Same roots, different values: evaluation, terminal, qsearch, extension, TT,
  or repetition bug.
- Same per-child nodes, different total: node-accounting difference.
- Same nodes, different time: per-node implementation cost.
- Same best action, different score: still a parity bug until explained.
- Mismatch after snapshot/bridge round-trip: truncated or missing session state.

## 6. Search-engine parity procedure

### Iterative and MTD(f) traces

Log every iteration:

```text
iteration, beta/window, returned_score, best_action, cumulative_nodes
```

For the first failing iteration, log each root action:

```text
action, value, child_nodes, cutoff, best_after_action
```

If all child nodes match but total nodes differ by the number of root calls,
inspect whether one implementation counts each root entry. Align accounting at
the same location without changing the search tree.

### Node mismatch checklist

Inspect:

- root-entry accounting;
- terminal-check order;
- TT hit/replacement behavior;
- move ordering;
- qsearch;
- null move and extensions;
- repetition/draw handling;
- incremental state/hash updates.

Never call deterministic node counts “close enough” during parity work.

### Transposition table parity

Compare behavior and effective layout, not only “32-bit” versus “64-bit” names:

- key width for indexing/signature;
- bytes per effective slot;
- entry packing and index calculation;
- default capacity and option units;
- minimum/maximum resize semantics;
- initial allocation and clear/age policy;
- replacement policy;
- bound, depth, and value encoding;
- atomic/non-atomic access and prefetch.

An option such as `Hash=16` may have a minimum entry count and may not mean an
exact 16 MB allocation. Match effective behavior.

### Hash parity

Verify PRNG algorithm/seed, generated sequence, integer truncation, square
mapping, side bit, phase/misc bits, pending-action state, incremental update,
full recomputation, and undo restoration.

Add a test that incremental keys equal recomputed keys.

### Move-order parity

Check placement, normal movement, flying/unrestricted movement,
removal/capture, TT move, killers/history/static priority, and shuffled paths.

## 7. State history, snapshots, and bridges

Audit every encode/decode boundary:

- CLI replay;
- UI/native bridge;
- session kernel;
- undo/redo;
- search root construction;
- test harness;
- persistence.

When a compact snapshot cannot hold all runtime history:

1. preserve the compact format when compatibility/performance requires it;
2. retain full history in the session;
3. reconstruct a bounded runtime history at the session boundary;
4. inject it into rule application and search root creation;
5. do not reconstruct it inside every search node;
6. test resets after irreversible actions.

Verify every product entry point. A harness fix is not enough when UI, CLI, FRB,
or search still uses incomplete history.

## 8. Repair the owning layer

Make the smallest root-cause fix.

- Executable selection belongs in platform/build scripts.
- Token handling belongs in the protocol adapter.
- State/history belongs in rules or session state.
- Search accounting belongs at the search entry point.
- Generated bindings must be regenerated, not hand-edited.
- Comments/docs must be updated after behavior is final.

Do not silently fall back from impossible internal states. Use explicit errors
or assertions.

Add a focused regression that fails before the fix. Expensive exact-parity cases
may be marked slow/ignored with the invocation documented.

Remove temporary diagnostic code before completion unless it is a small hidden
and generally useful diagnostic interface whose normal output remains unchanged.

## 9. Optimize only after parity

### Fair builds and measurements

Align release optimization, LTO, target CPU, assertions, allocator, features,
TT size, and thread count. Warm both binaries and alternate repeated samples.
Prefer medians over one run. Preserve raw logs/CSV.

- Different nodes: continue parity debugging.
- Equal nodes: compare elapsed time and ns/node.
- Fewer nodes: accept only after proving semantic equivalence and documenting
  why the pruning difference is safe.

### Profile first

Use the platform profiler and compare concrete symbols, for example:

```bash
perf record -F 999 -g --call-graph fp -- <command>
perf report --stdio --no-children --sort=symbol
```

### Safe extreme optimization

For each optimization:

1. identify the measured hotspot;
2. state the enabling invariant;
3. protect it with tests;
4. implement the smallest local change;
5. rerun deterministic parity;
6. run repeated A/B benchmarks;
7. keep it only with stable benefit.

For `unsafe`:

- keep the block minimal;
- add a `SAFETY:` comment for every precondition;
- prefer static/build-time invariants;
- test boundaries;
- inspect assembly when needed;
- revert if the gain is noise or complexity is disproportionate.

Do not scatter unchecked indexing merely because the reference is C or C++.

## 10. Validation pyramid

Run narrow checks first, then broaden.

### Sanmill checks

For Sanmill changes, start with the smallest affected suite and then run the
appropriate broad checks:

```bash
cargo test -p tgf-core
cargo test -p tgf-search
cargo test -p tgf-mill
cargo test -p rust_lib_sanmill
cargo test --workspace
cd src/ui/flutter_app && flutter test
cd src/ui/flutter_app && flutter test -d linux integration_test/
./format.sh s
```

Use `flutter test -d linux integration_test/<file>_test.dart` for each
integration test when the bulk desktop runner cannot maintain the debug
connection. Treat that as a runner workaround, not as skipped coverage.

Regenerate FRB or other generated bindings after API changes, but do not
hand-edit generated files. Before committing in this repository, run
`./format.sh s`; it also runs Rust formatting and clippy.

### Syntax and smoke

```bash
bash -n path/to/script.sh
cargo check -p <package>
```

Use zero-work/minimal-work modes to validate paths without a long run.

### Focused regression

Run the new test and directly related tests.

### Full package tests

Run all affected core, adapter, bridge, and integration suites.

### Generated and integration paths

Regenerate bindings after source API/comment changes. Test CLI, UI/native
bridge, session, serialization, and search entry points.

### Deterministic parity

Require exact equality for the declared fields.

### Statistical/end-to-end

Run head-to-head, self-play, random walks, or replay suites. Search logs for:

```text
unfinished
aborted
undecodable
returned no move
panic
ERROR
```

A successful statistical run does not replace deterministic parity.

### Repository checks

Run mandated formatter/linter/static analysis, then:

```bash
git diff --check
git diff --stat
git status --short
```

Inspect the final diff for unrelated formatting or generated changes.

## 11. Documentation audit

Search current docs/comments for stale architecture, paths, commands, defaults,
feature status, test names, and migration language.

- Describe current behavior, not obsolete migration phases.
- Preserve historical changelogs unless explicitly asked to rewrite history.
- Keep historical parity references when they explain a current invariant.
- Do not claim removal when a wrapper/replacement still exists.
- Regenerate generated docs/bindings instead of editing them manually.
- Follow repository language rules for docs and comments.

## 12. Git discipline

Only commit or push when explicitly requested or required by repository rules.

Before committing:

```bash
git diff --check
git status --short
git diff --stat
```

When English commits and 72-column bodies are required, verify:

```bash
LC_ALL=C git log -1 --format='%B' |
  awk 'length($0) > 72 { print length($0), $0; bad=1 }
       END { exit bad }'
```

Do not rewrite older commits for style unless explicitly requested. Confirm a
clean worktree after committing. Do not push without an explicit push request.

## 13. Final report

Use this structure:

```text
Reference:
Candidate:
Scope:

Verdict:
- EXACT FOR TESTED DOMAIN | NOT EQUIVALENT |
  STATISTICALLY CONSISTENT | INCONCLUSIVE

Deterministic parity:
- State:
- Legal action set/order:
- Outcome/reason:
- Serialization/history:
- Best action/score:
- Iteration sequence:
- Node count:

Root cause:
- Symptom:
- First divergence:
- Owning layer:

Fix:
- Files changed:
- Invariant restored:
- Product paths covered:

Validation:
- Focused tests:
- Full suites:
- Deterministic comparison:
- Statistical/end-to-end:
- Format/lint:

Performance:
- Build flags:
- Cases/repetitions:
- Nodes:
- Time and ns/node:
- Memory:

Remaining uncertainty:
- Untested variants/platforms/state space:

Commit/push:
- Commit hash, if created:
- Push target, if requested:
```

Verdict rules:

- **EXACT FOR TESTED DOMAIN**: every declared deterministic observable matches
  exactly and all affected integration paths pass.
- **NOT EQUIVALENT**: any semantic field or unexplained deterministic node count
  still differs.
- **STATISTICALLY CONSISTENT**: only aggregate/random/head-to-head evidence
  agrees. Never present this as logical equivalence.
- **INCONCLUSIVE**: comparable builds/traces cannot be obtained or the tested
  domain is too narrow.

## Common failure patterns

Check these early:

- hard-coded `.exe` or platform-specific paths;
- different build flags or feature sets;
- snapshot truncation of runtime history;
- unrecognized terminal protocol tokens;
- premature terminal adjudication during multi-step actions;
- different hash PRNG, width, or misc-bit layout;
- different TT capacity/option semantics;
- equal action sets in a different order;
- root node counted on only one side;
- UI, CLI, bridge, and tests initializing different state;
- stale generated bindings;
- current docs describing the pre-refactor architecture;
- an optimization adding branches or `unsafe` without stable benefit.

Sanmill-specific checks:

- legacy C++ square order versus Rust dense node/index order;
- root `posKeyHistory` and repetition state versus search-stack history;
- workbench search state versus real-play terminal adjudication;
- Flutter native session snapshots losing runtime history or pending actions;
- FRB action/notation codecs accepting a shape not produced by the engine;
- oracle snapshots treated as live master output without rebuilding master.

## Completion checklist

- [ ] Repository instructions read.
- [ ] Source revisions, binaries, and build flags recorded.
- [ ] Nondeterminism disabled.
- [ ] Equivalence fields declared before comparison.
- [ ] First divergence minimized.
- [ ] Root cause fixed in the owning layer.
- [ ] Focused regression added.
- [ ] State, action order, score, and nodes match exactly where required.
- [ ] Affected product entry points tested.
- [ ] Performance measured only after parity.
- [ ] Retained optimizations have stable A/B evidence.
- [ ] Format, lint, full tests, and `git diff --check` pass.
- [ ] Generated files regenerated rather than hand-edited.
- [ ] Docs reflect current code without rewriting history.
- [ ] Commit body lines are at most 72 ASCII characters when applicable.
- [ ] Final report states tested scope and remaining uncertainty.
