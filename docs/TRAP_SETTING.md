# Trap Setting: Closed Decision and Reopening Criteria

- Status: closed; no implementation or human study is authorized
- Decision revision: 6
- Scope: standard Nine Men's Morris
- Last updated: 2026-07-27

## Decision

Sanmill should not implement or schedule a trap-setting product now.
`PatchMakeTraps` remains off by default.

This document does not authorize:

- a trap-setting runtime or setting;
- a trap library, policy DAG, or utilization library;
- a study build, telemetry change, or target-game collection;
- recruitment or a human continuation experiment;
- a preference network, opponent-strength estimator, or exposure profile;
- a new miner or artifact format.

Revision 5 described a rigorous R0-R3 protocol, but its activation depended on
a target corpus and research infrastructure that the proposal neither had nor
justified building. Keeping that protocol would turn a closed product idea
into a permanent documentation and governance obligation. Revision 6
therefore withdraws the protocol instead of adding another gate.

There is no activation deadline and no dormant program waiting to start. A
future attempt is a new decision based on changed evidence, not a continuation
of revision 5.

## Evidence behind the closure

### Public Human Database evidence is interesting but coverage-limited

The preregistered held-out replay found:

- 151 eligible parents in the main pool, below the required 200;
- mean held-out `delta_EV` of `+0.068173`;
- cluster-bootstrap 95% interval `[+0.042055, +0.093609]`;
- a passed sign-chain instrument check.

The human-choice signal replicated, but the registered coverage gate failed.
Under that experiment's decision rule, the line was closed. The result
supports future hypothesis generation; it does not establish reach or causal
effect for Sanmill users.

### The setup-only engine proxy was negative

The frozen gate-matrix H2H compared avoid-only play with `make-traps` enabled
under matched openings, seeds, and budgets:

| Policy | Raw score | Paired score change versus avoid-only |
| --- | ---: | ---: |
| Avoid-only baseline | 53.9% | baseline |
| Original make-traps | 51.9% | `-0.0400 +/- 0.0290` |
| Three risk-gated variants | 52.5%-52.7% | `-0.0270` to `-0.0230` |

The original make-traps policy added losses from 133 to 174 while wins changed
from 210 to 211. The risk gates recovered part of the loss but did not produce
positive upside.

H2H cannot show whether humans fall for traps, and the historical policy is
not identical to a future one-shot selector. It does, however, directly test
the relevant family of setup selection without a separate utilization plan:
Sanmill can complicate its own play and then fail to use the position. That
cheap warning must be cleared before any human effect study is reconsidered.

### Target-product evidence is absent

No consented Sanmill target corpus or generally available in-app research
program is identified by this proposal. Public-site games cannot substitute:
their players, interface, time controls, and incentives may differ from the
intended product.

Creating a study build and collecting target games would itself be a product
research project. Trap setting does not currently have enough prior evidence
to justify that project.

### The tested class is deliberately narrow

The closed hypothesis was an immediate Sound trap:

```text
Sanmill-to-move D
  -> candidate setup preserving D
opponent-to-move D
  -> one opponent logical turn
Sanmill-to-move W
```

A negative decision on this path does not prove that all human-oriented
tactics are useless. It closes only a setup-only, immediate `D -> D -> W`
product based on the currently available evidence.

Deeper traps, `W -> W` conversion choices, or deliberate value loss are
different products. They must not be used post hoc to rescue this proposal.

## Why the previous protocol was withdrawn

The revision-5 protocol had four structural problems:

1. It required 1,000 consented target games before activation while leaving
   collection outside the proposal.
2. Its effect thresholds and 200-participant/800-episode cap could make a real
   but expensive effect indistinguishable from a failed hypothesis.
3. Its laboratory prefix experiment still deferred the real product question
   to a later natural-game study.
4. Its baseline matrix, structural-motif gate, deadlines, and maintenance
   rules created substantial process for a study that was unlikely to start.

Those problems cannot be repaired by choosing another corpus threshold or
adding a more elaborate power calculation. The correct response is to stop
pre-designing the study until the inputs actually change.

## Conditions for considering a new proposal

Trap setting may be reconsidered only if all three conditions below become
true. Satisfying them permits a short new proposal; it does not activate a
feature.

### 1. The setup-only technical proxy changes

A current-engine replay must show that an immediate Sound setup policy no
longer reproduces the previous self-harm signal.

The replay must:

- compare against the actual ordinary corrected baseline;
- use matched openings, colors, seeds, search budgets, and configuration;
- resume ordinary engine play immediately after the setup;
- report switches, wins, draws, losses, paired score, and oracle value drops;
- report whether W created after a simulated human mistake remains W under
  ordinary engine continuation;
- cover every product configuration for which a claim is intended, including
  a runtime Perfect Database configuration if that mode is in scope.

The non-inferiority margin, sample size, configurations, and analysis must be
written before the run. A negative or inconclusive result leaves this decision
closed. The replay is a self-risk screen, not evidence that humans will make
the predicted mistake.

This document does not authorize that replay. A maintainer choosing to revisit
the idea should first open a bounded issue or experiment record. Reusing the
existing H2H and Perfect Database tools should require no product code.

### 2. Target-user evidence becomes available for another justified reason

A target corpus or research channel must already exist because of a broader,
independently justified Sanmill research effort. It must not be created solely
to satisfy this trap-setting document.

Acceptable evidence identifies:

- consent and retention terms;
- the Sanmill UI and rules used;
- AI configuration and database availability;
- time controls;
- the unit of a complete logical turn;
- enough game and participant identifiers for clustered uncertainty without
  exposing public identities.

There is no universal 1,000-game prerequisite. The usable sample is determined
from observed exact-parent incidence and its uncertainty. If that incidence
implies an unaffordable natural-game experiment, low reach is itself the
product answer.

Public Human Databases remain discovery data only. They count as zero
target-user games regardless of apparent similarity.

### 3. One natural-game experiment is affordable

The next human study, if any, should be a single randomized natural full-game
pilot rather than a laboratory continuation followed by another full-game
study.

Participants must:

- opt in through the real Sanmill UI;
- receive the same material trap-setting disclosure required by a product;
- be randomized between feature-eligible and feature-off play within each
  tested configuration;
- play ordinary complete games rather than selected position fragments.

The estimand is explicitly the effect on informed, opt-in Sanmill users.
Recruiting more trusting or less alert public-site players would not improve
the product claim. Results must not be generalized to silent activation or to
all Sanmill users.

The pilot measures:

- exact eligible-parent and actual activation rates;
- immediate D-to-W mistakes after candidate and baseline moves;
- whether Sanmill converts the created opportunity;
- game result and paired engine-value changes;
- resignation, abandonment, recognition, fairness, and artificiality;
- repetition of the same practical idea;
- incremental move-selection latency.

Its sample size, minimum useful effect, cost ceiling, and stopping rule must be
derived from the observed target incidence before outcomes are opened. If the
required study is unaffordable, the feature remains closed; the threshold is
not weakened and a laboratory episode count is not used as a substitute.

## Minimal future evidence sequence

If the reopening conditions arise, the sequence is intentionally short:

```text
current setup-only H2H and oracle screen
  -> target-corpus exact-parent reach snapshot
     -> one disclosed randomized natural-game pilot
        -> catalog-sized product decision
```

Any failure stops the sequence. There is no prebuilt mobile runtime, policy
DAG, long-lived research service, or standing governance process.

## Candidate discovery from Perfect and Human Databases

The following sketch preserves the useful technical idea without authorizing
a miner project.

### Separate the evidence roles

| Source | Valid use |
| --- | --- |
| Perfect Database | Complete-turn legality and hard W/D/L labels |
| Public Human Database | Discovery ranking and observational reply frequencies |
| Sanmill target games | Exact-parent product reach |
| Randomized natural games | Causal product effect and user experience |

No source substitutes for another.

### Replay complete logical turns

Placement or movement plus its mandatory capture is one observation. Reject
illegal, incomplete, pending-removal, or unsupported turns. Human-visible D4
canonicalization and Perfect Database index symmetry are separate domains;
their operation numbers and keys are not interchangeable.

Retain a concrete state verifier and inverse move transform. A key match alone
must never authorize a move.

### Compare a candidate with the real baseline

For each exact parent `P`:

1. require Sanmill to move and the Perfect Database value to be D;
2. obtain the complete move `a_ref` from the actual ordinary corrected engine
   configuration;
3. enumerate complete legal Sanmill turns, including every legal capture;
4. retain candidate setups `a` whose completed child also has value D;
5. find exact public Human Database occurrences of the opponent state after
   `a` and after `a_ref`;
6. apply each observed complete opponent reply;
7. label it `hit` when the resulting value is W for Sanmill and `defence` when
   it remains D.

The discovery estimates are:

```text
delta_hit_obs(a) = p_hit(a) - p_hit(a_ref)
delta_EV_obs(a)  = EV(a)    - EV(a_ref)
```

Cluster by game and mover, keep sources and eras separate, and report sparse
cells rather than filling them with a preference model. These estimates rank
hypotheses only. They do not show that Sanmill users will encounter the parent
or react causally to the setup.

### Measure reach without a subjective motif gate

If a future target corpus exists, count exact eligible parents without reading
the target player's reply at those parents. Report reach under several frozen
equivalence views:

- exact parent and setup;
- D4-equivalent parent and setup;
- a conservative topology-based structural cluster.

The primary reach result is exact-state reach. Structural clustering is a
sensitivity analysis for perceived repetition, not a pass/fail source of
candidate count. Disagreement about whether two positions express the same
idea widens the reported reach/diversity range instead of automatically
killing the study.

## What remains deferred

The following have no design commitment:

- utilization continuations;
- cross-session exposure memory;
- local skill or Elo inference;
- preference or gap networks;
- persistent trap assets;
- compatibility contracts;
- mobile loading and latency architecture;
- default-on or strongest-mode behaviour.

If ordinary-engine continuation cannot clear the cheap technical proxy, a
future utilization library would be a separate research proposal with its own
benefit and maintenance case. It is not an automatic repair.

If a natural-game pilot eventually supports exposure suppression, the first
implementation should be local, resettable, and suppressive only. A few games
must not be used to infer that a player is weak and thereby enable a trap.

## Safety invariants for any future experiment

1. Treat placement or movement plus mandatory capture as one logical turn.
2. Express W/D/L from a fixed named perspective.
3. Require each engine-controlled setup to preserve the ordinary baseline's
   hard game-theoretic result.
4. Compare against the move the named engine configuration would really play.
5. Let live terminal, repetition, no-progress, pending-removal, and phase
   state override positional labels.
6. Reject unknown states, symmetry mismatches, illegal captures, and
   unaudited rule or database versions.
7. Do not generalize a result across skill, correction, Perfect Database, or
   search configurations that were not tested.
8. Keep the feature-off move-selection path independent of trap data and
   preserve the named ordinary configuration.
9. Do not introduce deliberate `D -> L` or `W -> D` play under this decision.

## Short reopening record

A future proposal should fit in a short issue or decision record containing:

```text
changed evidence:
current engine commit and product configurations:
setup-only proxy protocol and result:
target-corpus provenance and exact-parent reach:
natural-game power estimate and total cost:
product disclosure:
named owner and independent reviewer:
decision:
```

If the changed evidence cannot be summarized this way, the project is again
designing infrastructure before establishing product value.

## Related repository material

- [Book-rooted trap-utilisation feasibility assessment](TRAP_UTILIZATION_FEASIBILITY_REPORT.md)
- [Human Database Integration](HUMAN_DATABASE.md)
- [Framework API](FRAMEWORK_API.md)
- [Trap held-out replay](../experiments/trap_heldout_replay_20260705/MANIFEST.md)
- [Gate-matrix setup-only proxy](../experiments/gate_matrix_20260705_v4_riskgate_baseline/MANIFEST.md)
- `crates/perfect-db/src/mill.rs`
- `crates/perfect-db/src/index/symmetry.rs`
- `crates/tgf-mill/src/logical_turn.rs`
- `crates/tgf-mill/src/human_db_codec.rs`
- `crates/tgf-cli/tests/head_to_head.rs`
