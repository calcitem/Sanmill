# Trap Utilisation Feasibility Assessment

- Status: research assessment; no implementation is recommended
- Scope: standard Nine Men's Morris; book-rooted, short-horizon utilisation
- Date: 27 July 2026
- Evidence status: exploratory engineering evidence, not product evidence

## Executive conclusion

**Do not implement trap setting or a persistent trap-utilisation library on
the basis of the current evidence.**

The investigation establishes two useful facts, which point in opposite
directions:

1. The Human Database can identify natural, Opening-Book-rooted positions in
   which people make positional WDL mistakes. It is therefore useful for
   discovery and for ranking hypotheses about human fallibility.
2. Once such a mistake has created a theoretical win, ordinary Sanmill search
   at the real `MTD(f)` depth-12 configuration often fails to preserve it.
   Perfect-Database assistance can repair the first failure, but the required
   continuation rapidly branches into further exact states. It is not, in
   general, a small line that can safely be handed back to ordinary search.

The immediate practical conclusion is that the proposed short utilisation
route does **not** solve the known self-risk of setting traps. A Perfect
Database can always guide a certified `W` as long as it continues to supply
W-preserving turns; the experiment does not show that a short, static
continuation fragment can replace that continuing assistance. A persistent
library would be a local policy DAG with a recurring audit and compatibility
cost, not merely a compact list of tactics.

This assessment does not claim that human-oriented tactics are useless, nor
does it measure a causal effect on Sanmill users. The public Human Database
is discovery data, not a substitute for product reach or a disclosed
natural-game experiment.

## Question assessed

The narrow question was:

> Starting from positions that humans naturally reach through Sanmill's
> Opening Book, when a Human-Database-supported opponent response changes a
> theoretical draw into a Sanmill win, can ordinary depth-12 Sanmill reliably
> convert that win without a stored continuation? If not, is the required
> Perfect-Database continuation small enough to justify a short utilisation
> library?

This question is intentionally narrower than a trap-setting product. It does
not estimate the probability that Sanmill users will reach the position, does
not show that a selected book move causes the historical mistake, and does
not authorise any change to opening selection.

## Evidence roles and reproducibility

The investigation keeps three sources separate.

| Source | Role in this assessment | What it cannot establish |
|---|---|---|
| Shipped Opening Book | Supplies naturally reachable placement roots and the real default move distribution | That a non-default book choice should be selected in a product |
| Maintainer-uploaded Human Database snapshot (21 July 2026) | Counts historical human complete-turn selections at exact canonical states | Causal response by Sanmill users, or player-strength-specific behaviour |
| Complete Perfect Database | Labels W/D/L and enumerates every legal complete logical turn | Human likelihood, usability, or product reach |
| Raw Sanmill search | Tests whether the product engine configuration can cash in the certified win | Game-theoretic correctness without Perfect-Database verification |

A complete logical turn means placement or movement together with any
mandatory capture. W/D/L is always read from the side to move in the queried
Perfect-Database state, then inverted explicitly where the perspective
changes. Human-Database labels were not used as an oracle.

This report uses *logical turn* for one player's complete rule transaction,
including compulsory removal. It does not use the puzzle-counting convention
in which one turn may mean two plies, one by each player. Continuation horizons
are therefore reported as successive Sanmill decision points and opponent
complete replies, not as an ambiguous ‘win in N turns’.

All search probes used one engine thread and below-normal process priority.
The raw configuration was:

```text
gomtdf 12
SkillLevel=12
MoveTime=0; MoveTimeMs=0
Threads=1
UsePerfectDatabase=false
PatchAvoidTraps=false; PatchMakeTraps=false
Shuffling=true
SearchShuffleSeed in {1, 2, 3, 5, 8, 13, 21, 34}
```

`MoveTime=0` here means that the depth-12 search is allowed to complete; it
does not model a fixed human thinking time. `Shuffling=true` is retained
because it is the human-facing default. A `Shuffling=false` run is reported
only as a diagnostic control.

## Method

### 1. Establish a book-rooted discovery universe

The shipped book contains 437 static oracle actions. Each was replayed as a
complete turn against the current complete Perfect Database. Only actions for
which both the parent and child remained a draw were eligible. This left 413
safe book actions; 22 did not preserve a draw, while two further actions were
compound or ambiguous for exact replay and were excluded. This is a filtering
result for the experiment, not a claim about runtime book safety.

Book actions and their descendant states were expanded under the book's
symmetry domain, then deduplicated for Human-Database counting by the Human
Database's exact D4 canonical state key. The resulting support set contained
178 distinct, high-support opponent decision states.

### 2. Use human behaviour only to select a small conversion sample

For each eligible state, every observed Human-Database complete turn was
replayed and labelled with Perfect-Database W/D/L. The strict exploratory
screen retained a book-derived state only when it had:

- at least 500 matched Human-Database selections;
- at least 80% parse-and-match coverage;
- at least 20 WDL-dropping selections; and
- a WDL-drop rate at least 0.01 above the shipped book selector's actual
  safe-action mixture, whose default weight is `0.6^(rank - 1)`.

The screen selected six exact states derived from three book roots. It was
performed after the census, so its behavioural rates are exploratory. The
subsequent engine-conversion measurements are nevertheless direct tests of
the named positions and configuration.

### 3. Test raw utilisation after a documented human error

For every observed human response in the six selected states that changed the
opponent's best value from `D` to `L`, the resulting stable,
non-flying Sanmill-to-move state was retained if it was `W` for Sanmill. The
Perfect Database enumerated all Sanmill complete turns and recorded both the
number preserving `W` and the total legal-turn count:

```text
T_self = W-preserving Sanmill complete turns / all legal complete turns
```

Raw `gomtdf 12` then selected one complete turn for every retained state and
each fixed shuffle seed. A seed was a pass only when the selected turn was
independently verified to preserve `W` in the Perfect Database.

### 4. Measure the minimum continuation frontier

When a state lost `W` under any default shuffle seed, a deterministic
Perfect-Database W-preserving complete turn was used as a hypothetical stored
fallback. Every legal complete opponent reply was then enumerated and the
next Sanmill decision was tested again under all eight seeds. The expansion
stops there unless explicitly stated. It is a bounded cost measurement, not a
claim of terminal conversion distance.

### 5. Separate WDL preservation from a shortest-win claim

This assessment asks whether search preserves `W`; it does not rank winning
turns by distance to mate. If a future utilisation fragment is advertised as
a short forced win, it should be generated from an audited exact
minimum-complete-turn distance oracle. Every legal attacking choice attaining
the same minimum distance should be accepted, rather than requiring one
arbitrarily unique continuation.

The currently available WDL evidence is sufficient to say that a winning
policy exists. It is not sufficient to state the minimum number of complete
turns to a terminal win, so no such claim is made here.

## Findings

### Human behaviour is informative, but the early signal is positional

Across the 178 high-support book-evolution states there were 339,987 matched
human selections. Perfect-Database replay found 2,919 WDL-dropping selections
(0.859%). Normal continuation within the represented book accounted for
68,080 selections and no observed WDL drops in this support set.

Immediate mill formation was not the driver: it represented 6,552 selections
(1.93%) and only nine WDL drops. The useful candidate signal is therefore
best understood as positional off-book deviation, not as a simplistic
attraction to forming a mill.

This supports using Human-Database frequencies in candidate discovery. It
does not show that Sanmill can induce the same behaviour, particularly where
a candidate is a low-ranked book move under the default shuffled selector.

### Created wins are often narrow for Sanmill itself

The six selected states produced 24 observed human-error branches with total
Human-Database mass 657. Each produced a stable, non-flying `W` for Sanmill.
However, the W-preserving complete-turn space was narrow: each state had
1–11 preserving turns out of 14–22 legal turns, and the Human-frequency-
weighted mean `T_self` was only 10.3%.

This is the important asymmetry. A human mistake may create a theoretical
win, but the resulting position can still be easy for Sanmill's own finite
search to spoil.

### Raw depth-12 conversion is not reliable

| Measurement under default `Shuffling=true` | Result |
|---|---:|
| Exact human-error branches | 24 |
| Seed observations | 192 |
| WDL retained, unweighted | 118 / 192 = 61.5% |
| WDL retained, Human-frequency-weighted | 1,554 / 5,256 = 29.6% |
| Branches safe under all eight seeds | 11 / 24; Human mass 143 / 657 |
| Branches failing under at least one seed | 13 / 24; Human mass 514 / 657 |
| Branches failing under every seed | 7 / 24; Human mass 409 / 657 |

The deterministic `Shuffling=false` control retained 13/24 branches and
25.6% of the Human-frequency-weighted mass. Consequently, the poor result is
not explained by shuffled move order alone. At this depth, the raw engine
often does not select a W-preserving utilisation turn even after the human
has already made the decisive theoretical error.

### A short fallback expands into a policy frontier

The 13 roots that failed under at least one default seed were each given one
deterministic Perfect-Database W-preserving turn. Their legal opponent replies
produced 183 exact next Sanmill decisions (180 after D4 canonicalisation).
No terminal, flying, or unresolved state was encountered in that one-layer
expansion.

| Second-decision raw-search result | Result |
|---|---:|
| Exact nodes / seed observations | 183 / 1,464 |
| WDL retained | 1,237 / 1,464 = 84.5% |
| Nodes safe under all eight seeds | 149 |
| Nodes failing under at least one seed | 34 |
| Nodes failing under every seed | 20 |

For a sound controller, a state that loses `W` under any default seed cannot
be left to a move-order lottery. Thus a two-layer hybrid requires at least
13 first-layer plus 34 second-layer stored responses: 47 exact records before
the next opponent reply is considered. Even under a deliberately simplistic
model of 64 bytes per state record and four bytes per action, this is already
about 3.2 KiB, before history guards, checksums, transforms, and version
metadata.

The next expansion was measured rather than estimated. Giving one
Perfect-Database turn to those 34 second-layer unstable nodes generated 385
third-decision states, an average of 11.3 next decisions per repaired node.
Raw search has not been run over this third frontier, so no third-layer repair
count is claimed. The result is sufficient to establish the direction of the
cost: the library is becoming a policy DAG, not remaining a small sequence of
forced moves.

## Cost interpretation

The asset size is initially modest. The meaningful cost is the combination of
branch coverage and permanent revalidation.

| Controller design | Known action records at the two-layer boundary | Immediate implication |
|---|---:|---|
| Hybrid: hand back to raw search wherever it is seed-robust | 47 | Low storage, but correctness depends on a repeatedly measured search-handoff boundary |
| Full static PDB policy over the measured first opponent reply | 13 + 183 = 196 | Does not rely on raw search at that boundary, but must continue to expand all successor decisions |

The 385-node third frontier concerns only the 34 hybrid repairs; a full
static policy would need to expand all 183 second-decision nodes and would be
larger still. It would be inappropriate to quote a precise terminal DAG size
without an exact terminal-distance oracle and a predeclared stopping or
handoff rule.

A single principal variation may be adequate evidence for explaining or
publishing a puzzle, but it is not coverage evidence for an autonomous
trap-utilisation policy. A live opponent may choose any legal reply. The
runtime policy must therefore cover every reply within its declared envelope
or abandon the fragment safely and return to ordinary play. This distinction
is exactly why one stored response at 13 roots produced 183 next decision
states.

Every semantic change to any of the following would require an offline
rebuild and re-audit of the affected entries:

- the Perfect Database or its rule interpretation;
- canonicalisation or complete-turn encoding;
- engine evaluation, search, move ordering, depth, or shuffling behaviour;
- correction patches or the ordinary baseline configuration; and
- the Human-Database snapshot if behaviour is used to retain or retire
  candidate setups.

The measured 183-node, eight-seed raw-search ensemble took roughly 75 seconds
of serial search time on the test workstation. This is manageable for a
small research artefact, but it scales with every new node and does not
include mining, Perfect-Database enumeration, regression checks, or release
compatibility work.

## Limitations

1. The Human Database represents public historical play, not consented
   Sanmill users. Interface, time control, knowledge, and player population
   may not transfer.
2. The six-state screen was selected after the opening-book census. It is a
   deliberately small, exploratory conversion sample.
3. The experiment measures whether a known human error can be converted; it
   does not demonstrate that Sanmill's proposed setup causes that error more
   often than its ordinary corrected baseline.
4. The continuation horizon is bounded. Perfect-Database `W` proves the
   existence of a winning policy, but this assessment does not claim a short
   path to a terminal win or a complete terminal-distance measure.
5. The assessment is limited to the named Standard Nine Men's Morris
   configuration. It does not establish that the Standard Ultra-strong
   database's terminal, repetition, move-count draw, flying, and removal
   semantics match every live Sanmill configuration. Any product use would
   require an explicit differential rules-parity audit against the exact
   configuration in which the feature is offered.
6. Flying, terminal, pending-removal, unresolved, and history-sensitive
   boundaries are outside the stored-fragment scope. None occurred in the
   measured one- and two-layer expansions, but they remain necessary runtime
   rejection conditions.
7. Eight fixed shuffle seeds are a reproducible robustness screen, not a
   statistical sample of all production randomisation states.

## Recommendation

Keep `PatchMakeTraps` disabled and do not create a runtime trap library,
policy DAG, preference network, opponent profile, or opening-selection rule
from this assessment.

The useful retained lesson is methodological:

```text
Human DB        -> where humans historically make errors
Perfect DB      -> whether a complete turn is objectively safe or losing
Raw Sanmill     -> whether the product engine can actually convert the gain
```

All three are needed. A position should not be considered a practical trap
merely because it is theoretically winning after an opponent error, nor
merely because a shallow engine is confused by it.

Any future proposal should begin only after independently justified target
user evidence becomes available and a current setup-only engine proxy no
longer shows self-harm. It should then test a predeclared, low-risk class with
an explicit continuation budget and a natural disclosed product experiment.
The present evidence does not justify building that infrastructure.

## Audit artefacts

The local, ignored feasibility workspace contains the reproducible census,
Perfect-Database branch enumeration, raw-search manifests, seed outputs, and
hashes:

```text
experiments/trap_utilization_feasibility_20260727/
```

The experiment uses the complete database at
`I:\Mill_Training\NMM_DB\Malom_Standard_Ultra-strong_1.1.0\Std_DD_89adjusted`
and the Human-Database snapshot at
`I:\Mill_Training\NMM_LLM\data\backups\maintainer_upload_20260721\human_db.sqlite`.
