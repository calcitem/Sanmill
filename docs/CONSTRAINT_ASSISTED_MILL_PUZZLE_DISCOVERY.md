# Constraint-Assisted Discovery of Nine Men’s Morris Puzzles

*A methodological proposal for combining Perfect DB with SMT, constraint programming, SAT/ASP and formal verification*

---

- **Document type:** Sanmill technical white paper
- **Purpose:** Independent review by Mill specialists
- **Status:** Expert-reviewed; complete-turn certification, a Z3/CP-SAT
  discovery pilot, a replay-backed HumanDB pilot, an engine-error-corpus
  adapter, a unique-draw-defence pilot and the product curriculum
  implemented; full strategy-tree certificate sidecars remain pending
- **Language:** British English
- **Repository baseline:** Sanmill source reviewed on 28 July 2026
- **Prepared for:** Rules, composition and endgame experts

> This paper separates mathematical proof, candidate discovery and expert judgement.

---

# Review brief

## Abstract

This paper proposes an offline, evidence-preserving method for discovering and curating Nine Men’s Morris puzzles for Sanmill. The central design choice is deliberately conservative: the perfect-play database remains the game-theoretic authority; the Rust/TGF rules engine remains the authority for legal state transitions; mathematical tools are used to discover, constrain, verify and select candidates, but not to replace either authority. Small database sectors can be enumerated exhaustively. Large sectors should be mined by deterministic stratified sampling, constraint-directed synthesis and replay-derived candidates. Every surviving position is then certified against all complete legal logical turns, including any compulsory removal after a mill. All equally short forced wins are accepted as solutions, whereas a slower forced win is recognised but does not complete a shortest-win puzzle. A separate reachability assessment distinguishes clearly labelled compositions from replay-backed positions. Finally, CP-SAT or an equivalent integer model selects a balanced pack from the certified pool under explicit quotas for tactical or strategic theme, phase, difficulty, material, symmetry class and similarity. The mobile and desktop application receives only the resulting static puzzle data and provenance; the database and solvers remain PC-side build tools.

> **Executive recommendation.** Adopt a two-stage pipeline: first build a large, immutable evidence pool certified by Perfect DB; then choose the public puzzle pack globally with CP-SAT. Use Z3 selectively for candidate synthesis and local consistency constraints, not for proving the full game. Use Kani or equivalent Rust-focused verification for critical encoders and canonicalisation. Do not ship any of these solvers in the Sanmill application.

## Expert-reviewed policy decisions

- Both rule-consistent compositions and replay-backed positions may be published. They must be labelled **Composed position** and **Replay-backed position** respectively; no reachability claim may be implied without a witness.

- One complete logical turn consists of a primary action plus any compulsory removal made by the same player after forming a mill. For distance accounting, one such player turn is one **logical ply**.

- The objective is the shortest forced win. Every first turn or later continuation that achieves the same minimum distance is accepted as correct. A move that still forces a win but takes longer is recognised as a slower win and prompts the player to try again.

- Public **Win in N** labels count moves by the solving side. A sequence in which the solver moves, the defender replies and the solver then wins is **Win in 2**.

- Public objective titles begin with the side to move, for example
  **White · Win in 5** or **Black · Hold the draw**. This makes the solver
  immediately visible without relying on board orientation.

- A **Hold the draw** study starts from a database draw and accepts only a
  complete logical turn that preserves that result. A unique-draw-save
  puzzle additionally requires every other legal logical turn to lose.

- The official solution line uses mathematically optimal defence: the defender preserves the best available outcome and, when defeat is forced, delays it for as long as possible. A separately labelled human or illustrative line may also be shown.

- The default expert view shows one official shortest line and states how many other equally short solutions exist. The complete strategy tree remains in the evidence record.

- Every Sanmill rules variant is certified separately against a matching database policy. Russian rules may be added when the implementation, exact database coverage and generation budget make this straightforward; they do not block the first pilot.

- “Tactical or strategic theme” is preferred to the unexplained shorthand “motif”. Proposed theme labels remain soft metadata until specialists have reviewed actual positions.

## Scope and non-goals

The proposal concerns offline puzzle discovery and curation. It does not propose a runtime hint engine, a replacement for the existing Perfect DB, or a claim that mathematical solvers can measure beauty. It is intended to make computer-found material reproducible and auditable before human selection.

# 1. Current Sanmill baseline

Sanmill already follows the right deployment pattern. The built-in puzzle pack is generated offline from the Malom perfect-play database by the tgf-cli puzzle generator, committed as a plain .sanmill_puzzles asset, and loaded without a runtime database or foreign-function interface. This means stronger PC-side discovery tools can be introduced without increasing the application’s binary size, startup time or licence surface.

The existing generator samples legal-shaped positions, queries exact root outcomes, rejects uncovered or unsuitable states, measures mistakes and shallow-search difficulty, removes symmetric duplicates and exports a solution. This is a credible foundation. Its broad sampler, however, constructs disjoint bitboards within material budgets rather than proving that the sampled position occurs in a legal history. Acceptance is sparse—approximately one useful root per several thousand attempts under typical filters—and a greedy run makes the final composition depend on sample order.

The first expert-reviewed implementation removed the earlier
**action-level** principal-variation shortcut. Root choices are now classified
exhaustively as complete logical turns, including compulsory removal.
Reviewer-facing lines use strict Perfect DB ordering for both sides: the
attacker chooses a fastest win and the defender chooses the best available
result or, in a forced loss, the longest resistance. For a replay-backed
puzzle, the compact asset stores one deterministic principal variation for
each equally shortest first turn; this display policy does not replace the
all-turn root proof. Public move counts ignore removal tokens, and the
application distinguishes a recorded or terminal slower win from a shortest
completion. The remaining limitation is evidential breadth: a separate,
immutable certificate sidecar is still required to archive the complete
strategy tree rather than only its reviewer-facing variations.

The first full-database expansion added 39 symmetry-unique movement-phase
compositions from the four-, five- and six-men-per-side sectors, taking the
built-in pack from 60 to 99 puzzles. Two further candidates were rejected as
symmetry-equivalent to accepted roots. Every puzzle is explicitly labelled
`source:composed`; no legal replay witness is claimed. This is an engineering
expansion of the candidate pack, not a substitute for the proposed blind
expert review or for a future replay-backed and placement-phase sample.

A subsequent constraint-directed pilot used Z3 5.0.0 to enumerate
rule-shaped board geometries for five deliberately different themes:
capture choice, mill blocking, dual threat, mill abandonment and zugzwang.
Z3 was a source of proposals, not a chess-like evaluator. Rust/TGF rebuilt
each position, enumerated all legal complete first turns and required every
equally short winning turn to satisfy the requested theme predicate. Perfect
DB alone supplied the W/D/L and distance claims. The generator also excluded
the 99 existing roots and twelve editorial-reference roots under all 16
supported board symmetries. The reference roots are retained in the
version-controlled
`crates/tgf-cli/testdata/puzzle_exclusions/mill_editorial_baseline.fen`
record, giving 111 distinct exclusions when combined with the 99-puzzle base
pack. The record is an editorial collision baseline, not application content.

An exact ring-16 audit against the July 2026 HumanDB source corpus found that
some reference roots occur in recorded games and others do not. Corpus
occurrence is evidence of reachability, whereas absence is only a coverage
result.

That process produced 82 publishable, database-certified candidates. A
deterministic OR-Tools CP-SAT 9.15.6755 model selected 15: three from each
theme, seven with White to move and eight with Black to move. The selected
difficulty distribution is three beginner, three easy, five medium, one hard
and three expert puzzles. The built-in pack therefore contains 114 puzzles in
version 1.3.0. Every entry has exactly one `topic:*`, one `curriculum:*` and
one `progression:*` tag, and the asset is ordered first by teaching topic and
then from beginner to expert. All 15 new positions remain explicitly
composed: the structural model and exact endgame proof do not imply that a
legal replay from the initial position exists.

A subsequent real-game pilot built a versioned, anonymised SQLite replay
sidecar over the HumanDB raw corpus. The production Rust command
`tgf mill replay-index` uses bounded parallel workers for JSON parsing and D4
canonicalisation, with one batched SQLite writer. Its first full build
processed 95,389 source files in 46.4 seconds, retained 94,540 unique games,
4,470,985 complete logical turns and 2,662,650 searchable movement roots, and
ignored 849 exact duplicate source rows. The resulting database is accompanied
by a same-directory Markdown build record containing its schema, counts,
source path and SHA-256.

HumanDB was used only as a candidate prior: winning annotated roots at which
the recorded turn differed from the canonical winning turn were joined to
the replay sidecar. Rust/TGF then replayed every transformed game prefix and
recorded turn, and Perfect DB independently required a genuine win-to-draw or
win-to-loss swing. The candidates were stratified by annotated distance
(`1–15`, `16–31` and `32+`) rather than imposing a universal short-distance
cut-off. This matters for blockade: the published replay sample includes
immobilisation wins in 14 and 30 solver moves.

The v1.4.0 built-in pack contains 127 puzzles: 114 labelled compositions and
13 replay-backed human missed wins. The replay additions are balanced by side
(seven White, six Black) and progression (three short, five medium and five
long). Their primary topics are greedy-mill trap, wrong-mill trap, double
mill, quiet move, sacrifice and immobilisation. Every replay record retains
the anonymised source-game SHA-256, complete transformed history, recorded
human turn, HumanDB snapshot SHA-256, source logical ply and deterministic
presentation transform. All 127 entries have exactly one `topic:*`,
`curriculum:*`, `progression:*` and `distance-band:*` tag.

The embedded v1.5.0 review build adds a 30-position engine-error-corpus
shortlist chosen globally by CP-SAT from 87 certified records. It contains
15 positions for each side to move and draws from six profiles: balanced
advanced play, balanced expert play, 6v4, 7v4, play against a flying defender
and late placement after at least twelve primary placements. The resulting
application asset contains 157 puzzles: 144 labelled compositions and the
same 13 replay-backed positions. The new entries remain visibly tagged
`review-status:expert-pending`; consequently the package version is
`1.5.0-review.1` and its `isOfficial` field remains false until specialist
assessment is complete.

The v1.6.0 review build adds the ten-position strategy-theme shortlist as a
second traceable pending batch.

The v1.6.1 similarity repair audits every pair after all 16 board
automorphisms and solver-side colour normalisation. It removes 16 positions
from nine recognisably similar clusters and replaces them with a CP-SAT
shortlist of 16 independently certified candidates. The application asset
therefore remains at 167 puzzles: 154 labelled compositions and the same 13
replay-backed positions. Fifty-six entries are pending specialist
assessment, the package version is `1.6.1-review.1`, and `isOfficial`
remains false.

The v1.7.0 review build introduces mixed public objectives. It retains all
167 previous positions but derives every winning title, description,
`win-in-*` tag and generated ID from the exported optimal solution. This
repairs 49 legacy metadata counts, including position `#656830EE`, whose
public label is now **White · Win in 5**. All winning and draw-defence titles
also state White or Black explicitly.

The same build adds ten movement-phase **Hold the draw** studies selected
globally by CP-SAT from exact Perfect DB outcome-contrast records. They are
balanced five–five by side to move and remain at least four stones apart
from the previous asset and from one another after all board symmetries and
solver-side colour normalisation. Each root is a draw with exactly one
drawing logical turn; every other legal logical turn is a loss. The
application asset therefore contains 177 puzzles: 164 labelled
compositions and 13 replay-backed positions. Sixty-six entries are pending
specialist assessment, the package version is `1.7.0-review.1`, and
`isOfficial` remains false.

## 1.1 Implemented curriculum

Classification is deliberately hierarchical rather than a flat collection of
machine tags. Every puzzle belongs to one teaching strand, one primary topic
within that strand and one difficulty level. A position may retain secondary
descriptive tags, such as sacrifice or precision, but these do not give it two
places in the curriculum.

| **Strand**              | **Primary topics**                                                                 | **Teaching purpose**                                                   |
|-------------------------|------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| **01 — foundations**    | Capture choice; quiet move                                                         | Read the whole logical turn and look beyond the most forcing action.    |
| **02 — mill tactics**   | Mill block; greedy-mill trap; wrong-mill trap; double mill; dual threat; right-angle threat; mill recovery | Compare immediate mills with prevention, preparation and paired threats. |
| **03 — positional play** | Mill abandonment; junction release; ring transfer; sacrifice; mobility squeeze   | Give up static structure or material, transfer pressure and restrict activity. |
| **04 — endgames**       | Draw save; immobilisation; flying defence; zugzwang                                | Preserve defensive resources, control mobility and calculate rule-sensitive endings. |
| **05 — calculation**    | General forced wins that do not yet have a clearer specialist-approved topic       | Retain sound material without pretending that a weak label is a theme. |

Within each topic, the asset is sorted through the public sequence
**beginner → easy → medium → hard → expert**, then by winning distance and
rating. The strand order is pedagogical, not a claim that every puzzle in one
strand is easier than every puzzle in the next. Empty reserved topics are
acceptable until a certified and expert-approved example exists; puzzles are
not forced into them merely to make the taxonomy look complete.

| **Existing strength**      | **Why it matters**                                  | **Proposed extension**                                                |
|----------------------------|-----------------------------------------------------|-----------------------------------------------------------------------|
| **Offline generation**     | No database or solver is needed by the application. | Keep all SMT/CP/SAT tools in the PC-side build pipeline.              |
| **Exact root W/D/L**       | Puzzle claims start from perfect-play evidence.     | Certify every complete logical turn, not only the chosen action.      |
| **Symmetry deduplication** | Rotated and reflected copies do not crowd the pack. | Record the canonical key and test all 16 board presentations.         |
| **Shallow search probes**  | Provides an empirical difficulty signal.            | Treat the signal as ranking evidence, never as proof.                 |
| **Random broad sampling**  | Can reach a very large state space.                 | Add stratification, constraints, replay sources and global selection. |

## 1.2 Editorial reference audit

A July 2026 maintainer-inbox audit recovered 36 ordinary prompt positions
and eight positions from two study sheets. The 44 raw roots form 42 ring-16
classes: two pairs on the study sheets are intentionally equivalent after
exchanging the outer and inner rings. One item refers to two further diagrams
which were absent from the supplied folder; no position was guessed from
prose alone.

Exactly three supplied prompts carry explicit replay provenance and game
links. The other 41 raw roots form 39 canonical classes. Four roots also
occur in the separate twelve-root editorial collision baseline. This overlap
is between reference sets, not Sanmill’s pack.

An exact audit of the current 177-position review build found **no match**
between its roots and any of the 44 editorial reference diagrams under all
16 supported board automorphisms.
Opposite-side-to-move and colour-exchanged checks also found no match. No
existing Sanmill puzzle therefore needs removal or reorientation.
The committed asset replay test repeats both the colour-preserving and
solver-colour-normalised collision checks for every built-in puzzle, so this
is a release invariant rather than a one-off report.

The collision policy is mechanical:

- a root without explicit replay provenance is excluded from every Sanmill
  candidate pack under ring-16 symmetry;
- a replay-attributed root remains excluded from composed mining;
- it may reappear only as a replay-backed HumanDB candidate, never merely on
  the strength of the attribution;
- its exported raw board must differ from the reference presentation, even
  though deduplication and evidence retain the same canonical identity; and
- reference records are used solely as mining and release-test inputs.

Editorial references influence only candidate search and collision checks.
Published puzzle copy is independently generated from certified board
evidence and limited to concise Sanmill-authored prompts and solution
annotations.

Perfect DB analysis explains why these reference sets differ from a generic
forced-win collection. Of the 36 ordinary prompt roots, 17 are wins,
18 are draws and one is a loss for the side to move. The eight sheet studies
are wins. Eight paired prompts move only one stone yet cross a W/D/L
boundary. The recurring selection signals are therefore:

- six- or seven-piece attacking constructions against four defenders;
- comparison of near-identical positions rather than an isolated tactic;
- a unique drawing resource, flying-phase defence or blockade;
- swing mills, double mills, mill redundancy and ring-exchange structure;
- quiet or counter-intuitive first turns, including a tempting mill which
  fails; and
- theoretically drawn positions in which one move creates the strongest
  practical pressure.

These observations are discovery priors, not automatic quality labels. The
first reproducible review-profile run produced 19 independent forced-win
review candidates: eight 6v4, eight 7v4 and three against a flying defender.
Eighteen
exercise flying somewhere in the certified line; the set includes eight
greedy-mill traps, seven quiet-move studies, two capture-choice studies, one
immobilisation and one double mill. A separate one-stone perturbation miner
produced 80 broad W/D/L contrast pairs across 3v4, 4v3, 6v4 and 7v4 sectors.
A low-mobility 4v3 pass added ten sharper pairs in which the drawing position
has exactly one drawing turn: three W/D contrasts and seven D/L contrasts.
All 90 were checked against the then-current 127 roots and every editorial
reference record. They remain unreviewed files under `out/`; none of that
separate contrast set was silently added to the application.

## 1.3 Engine-error records as a discovery prior

The compact correction patch is not itself a puzzle database: its canonical
keys do not retain the original FEN presentation, and its corrective child
identifies an engine repair rather than a complete puzzle solution. The
reproducible FEN-bearing JSONL records used to build that patch are useful,
however. Each record states that the configured engine made a measured W/D/L
error, together with its search depth and propagated reach mass. This is
stronger candidate evidence than an arbitrary legal-shaped sample, but it is
still only a discovery prior.

The Rust puzzle command can now stream those JSONL files without loading the
corpus into memory. It validates each FEN with the production rules, removes
terminal and pending-removal roots, canonicalises all board symmetries, keeps
a bounded ranked heap per phase/material shape and schedules small
sector-local blocks for Perfect DB certification. The source files receive a
content manifest. Source severity, depth, mass and trap score are retained as
audit metadata; none is treated as proof.

The advanced review profiles impose additional aesthetic proxies:

- exactly one shortest complete first turn;
- several plausible alternatives, including a minimum number which lose the
  win rather than merely winning more slowly;
- a quiet shortest first action;
- failure of shallow depth-2/4 probes, or of every depth-2/4/6/8 probe for
  the expert tier;
- a bounded exported equal-length solution set, normally at most 32 lines;
  and
- exclusion of the existing Sanmill pack and all recorded editorial roots
  under the full ring-16 symmetry group.

All profile outputs are explicitly marked unofficial review packs. A selected
batch may be embedded in the built-in asset for prerelease review only when it
retains an `expert-pending` batch marker and the package remains unofficial.
Promotion from that review state is a separate, deliberate release step after
specialist approval and final collision tests.

The source `trap_score` combines W/D/L severity with log-scaled reach mass. It
does **not** measure surprise, visual concealment or teaching value. A
separate hidden-trap profile therefore requires an immediate mill-forming
mistake, a quiet winning turn and failure of every shallow probe; its title
and first textual hint do not disclose the trap.

Six opt-in strategy-led profiles add narrower structural requirements to
the same engine-error corpus. They search for deliberately permitting an
opposing mill, compressing movement mobility, vacating a four-way junction
to gain control elsewhere, and creating a new recovery link to an existing
mill. Two further profiles require a landing piece to support perpendicular
open mills, or a move between adjacent rings to create a new open mill.
These ideas are implemented as exact Rust predicates rather than text
matching. Every equally short winning first turn must satisfy the selected
predicate, and Perfect DB must still certify the win. The names are
provisional working labels; a matching position is only a review candidate,
not proof that the idea is clear or aesthetically worthwhile.

For the advanced placement profile, at least twelve primary placements must
already have occurred, corresponding to six complete alternating rounds.
Earlier positions are not declared worthless: blockades, tempo and paired
threats may still support a foundations curriculum. They are simply not
promoted as advanced examples of the familiar advice against greedy early
captures.

## 1.4 Strategy-led extension pilot

The six new predicates were exercised against the same FEN-bearing
engine-error corpus. Before the run, the collision input was rebuilt from the
then-current 157-puzzle application asset and all three version-controlled
editorial records. The resulting 213 raw FENs formed 207 distinct ring-16
classes. This caught one candidate which an older, 127-puzzle exclusion run
would have repeated from the 30-puzzle embedded review batch.

From 20,000 ranked source candidates per profile, Perfect DB and the
publication gates certified ten mobility-squeeze, ten junction-release, two
mill-recovery, two right-angle-threat and ten ring-transfer records. Four
positions satisfied two requested predicates, leaving 30 distinct roots from
34 rows. The allow-mill profile found structural matches but no position
survived the complete strategy-tree, contrast and distance gates. An
expanded 100,000-root pass was also left empty rather than filling a theme
quota with weaker material.

CP-SAT selected a ten-position supplementary review set: two
mobility-squeeze, three junction-release, one mill-recovery, one
right-angle-threat and three ring-transfer candidates, balanced five–five by
side to move. All ten have different first actions.
In addition to exact ring-16 and solver-colour-normalised deduplication, the
selector required at least four differing coloured points under the closest
symmetry, both within the shortlist and against the current application and
editorial-reference roots. This reference-distance pass removed eight
near-variants from the 34-row pool; there were no additional exact
colour-exchanged collisions. The shortlist is embedded as a second
`expert-pending` application batch for blind specialist review. A
deterministic Markdown renderer produces diagrams first and places one
Perfect DB-ordered line and the provisional machine label in a separate
answer key.

# 2. Semantics fixed for mining

## 2.1 Five different meanings of ‘valid position’

A candidate can satisfy one notion of validity and fail another. The pipeline must record these levels separately rather than compressing them into a single Boolean flag.

| **Level**                       | **Meaning**                                                          | **Evidence**                                              | **Publication policy**                             |
|---------------------------------|----------------------------------------------------------------------|-----------------------------------------------------------|----------------------------------------------------|
| **V0 — bitboard consistency**   | White and black occupancy are disjoint; counts fit the encoding.     | SMT/SAT constraints or Rust assertions.                   | Necessary but never sufficient.                    |
| **V1 — rules consistency**      | Phase, side to move, hand counts, removals and legal actions agree.  | Rust/TGF state construction and legal move generation.    | Reject on any disagreement.                        |
| **V2 — database applicability** | The exact ruleset/variant is covered and the query resolves.         | Perfect DB variant identity, coverage and result.         | Required for a solved puzzle.                      |
| **V3 — reachability**           | A legal history from an approved initial state reaches the position. | Explicit replay, bounded proof or equivalent certificate. | Required or explicitly labelled by expert policy.  |
| **V4 — compositional value**    | The position is natural, instructive, surprising or elegant.         | Theme evidence plus expert judgement.                     | Required for inclusion; not mechanically provable. |

## 2.2 The unit of analysis is a complete logical turn

In Mill, forming a mill may leave the same player obliged to remove an opponent’s piece. The primary move and the removal are therefore one logical decision for puzzle classification. Evaluating the intermediate board can reverse perspective incorrectly, overlook a bad capture after a good mill-forming move, or report several solutions that are really branches of the same turn. Certification must enumerate complete legal logical turns with chronological query history. For distance accounting, one player’s complete logical turn is one logical ply; a two-ply exchange is not called one turn in this document.

> **Non-negotiable rule.** No puzzle is accepted from action-level outcomes alone when a compulsory continuation is possible. A primary action plus its legal removal choice is classified as one complete logical turn.

## 2.3 Operational definitions

Let $\mathcal{L}(s)$ be the set of complete legal logical turns from state $s$. Let $O(s,\tau)$ be the exact outcome of turn $\tau$ from the original side’s perspective, after all mandatory continuations. Let $D(s,\tau)$ be the total logical-ply distance to terminal victory when $\tau$ is chosen, including $\tau$, with the attacker minimising the distance and the defender maximising it when defeat cannot be avoided. Let $\operatorname{Root}(s)$ be the Perfect DB outcome of the position itself.

$$
\begin{aligned}
\operatorname{WinningTurns}(s)
  &= \left\{\tau \in \mathcal{L}(s) \mid O(s,\tau)=W\right\}, \\
D^*(s)
  &= \min_{\tau \in \operatorname{WinningTurns}(s)} D(s,\tau), \\
\operatorname{ShortestWinningTurns}(s)
  &= \left\{
       \tau \in \operatorname{WinningTurns}(s)
       \mid D(s,\tau)=D^*(s)
     \right\}, \\
\operatorname{SlowerWinningTurns}(s)
  &= \left\{
       \tau \in \operatorname{WinningTurns}(s)
       \mid D(s,\tau)>D^*(s)
     \right\}.
\end{aligned}
$$

> **Forced defence tree.** Every relevant defender reply belongs in the
> machine evidence record. The reviewer-facing view shows one deterministic
> principal variation and the number of alternatives. The product asset may
> retain a bounded set of equal-length lines so that later equally short
> attacking choices are accepted; a candidate which exceeds the profile cap
> is rejected. This compact validation set is not a serialised proof tree.

Every member of $\operatorname{ShortestWinningTurns}(s)$ is a correct solution, including at the first move. A member of $\operatorname{SlowerWinningTurns}(s)$ is not accepted as completion of a shortest-win puzzle, but the interface should acknowledge that it still wins and invite the player to find the faster solution. A turn with non-winning outcome receives the ordinary incorrect response. The database’s raw StrictSteps value is retained alongside the derived logical-ply and public move counts.

# 3. Division of authority

The method is safest when every component has a narrow, explicit jurisdiction. Disagreements must fail closed and enter an audit queue; one component must not silently repair another.

| **Authority**           | **What it decides**                                                                       | **What it must not decide**                                              |
|-------------------------|-------------------------------------------------------------------------------------------|--------------------------------------------------------------------------|
| **Rust/TGF rules**      | State construction, phase, legal actions, complete turn transitions and replay.           | Whether a legal position is won, beautiful or suitable for a pack.       |
| **Perfect DB**          | Exact W/D/L and distance information within its matched rule and coverage domain.         | Human difficulty, naturalness, teaching value or reachability by itself. |
| **SMT/SAT/ASP**         | Structural constraints, bounded histories, theme-shaped candidates and model enumeration. | Full-game truth when the database already supplies it.                   |
| **CP-SAT/MIP**          | A globally balanced subset under explicit quotas and diversity constraints.               | The correctness of a candidate’s game-theoretic label.                   |
| **Heuristic search**    | Search difficulty, principal-variation stability and an optional human-like line.          | The official proof line, shortest-win distance or forced-win result.      |
| **Formal verification** | Selected implementation properties of encoders, invariants and canonicalisation.          | The aesthetic value of a puzzle.                                         |
| **Mill experts**        | Rule interpretation, compositional standards, naturalness, pedagogy and final approval.   | Reconstructing omitted machine evidence by trust.                        |

# 4. Proposed end-to-end pipeline

The recommended architecture separates discovery from selection. A large evidence pool is generated once and can be re-ranked without re-querying the full database. Public packs are then selected from that pool under a versioned policy. This removes sampling-order bias and gives experts a stable set of candidates to compare.

| **Stage**                       | **Operation**                                                                                                  | **Required output / gate**                                     |
|---------------------------------|----------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------|
| **1. Freeze semantics**         | Select ruleset, database variant, outcome ordering, turn unit, reachability and shortest-solution policy.      | Signed policy identifier and machine-readable configuration.   |
| **2. Discover candidates**      | Combine exhaustive small-sector enumeration, stratified sampling, constrained synthesis and replay harvesting. | Deterministic candidate stream with source and seed.           |
| **3. Validate state**           | Construct the Rust state, regenerate legal turns and reject mismatches.                                        | Rules-consistent state and canonical key.                      |
| **4. Certify by Perfect DB**    | Query root and every complete logical turn; build the forced strategy tree.                                    | Exact outcome certificate or fail-closed rejection.            |
| **5. Assess reachability**      | Replay a history, run a bounded proof or apply the agreed composed-position label.                             | Reachability class and witness.                                |
| **6. Characterise**             | Extract candidate themes, exact branching, distances, search probes and similarity fingerprints.              | Evidence record; no single opaque difficulty score.            |
| **7. Select globally**          | Solve quotas and diversity constraints over the certified pool.                                                | Reproducible pack manifest plus rejected-nearby alternatives.  |
| **8. Expert review and export** | Blind-review samples, record decisions, then export structured puzzle data.                                    | Approved .sanmill_puzzles asset and archived evidence sidecar. |

> **Deployment boundary.** Perfect DB, Z3, CP-SAT, MiniZinc, SAT/ASP and verification tools stay on the PC used to generate the pack. The application receives only versioned puzzle JSON and, where desired, compact reviewer-facing provenance. No runtime solver integration is required.

# 5. Candidate discovery

## 5.1 Exhaustive enumeration where it is genuinely complete

Small no-hand material sectors can be enumerated through the exact symmetry-reduced database index. This is the strongest discovery mode because every position in the declared subspace is considered. It is appropriate for sparse moving and flying endgames, where tactical ideas are concentrated and the state count remains tractable. The output must identify the exact sector and enumeration bounds so that ‘complete’ is never inferred for the roughly 28-billion-position database as a whole.

## 5.2 Stratified sampling for large sectors

Broad random sampling remains necessary in the large state space, but it should be stratified. A deterministic sampler should allocate budgets by phase, on-board material, pieces in hand, side to move, flying status, database distance band and coarse mobility. Within each stratum, reproducible pseudo-random seeds permit exact reruns. Sampling weights should be recorded rather than hidden in code.

The replay pilot uses the following discovery bands. They are workload and
curriculum strata, not correctness gates:

| **Band** | **Annotated distance prior** | **Typical review emphasis** |
|----------|------------------------------|-----------------------------|
| **Short** | `1–15` | Immediate tactics and compact conversions. |
| **Medium** | `16–31` | Multi-stage plans and sustained mill pressure. |
| **Long** | `32+` | Strategic squeezes, blockade, flying defence and endgame conversion. |

A long distance does not make a candidate unsuitable. The publication test is
whether its theme remains intelligible, its shortest first turn is meaningful
and its reviewer-facing principal variation is usable. In particular,
immobilisation candidates must not be discarded merely because the final
blockade lies beyond distance 15.

- Oversample rare tactical circumstances—such as a forced win with material deficit—while retaining enough ordinary positions for comparison.

- Cap acceptance from any one database sector before pack selection, so the evidence pool is not dominated by a conveniently dense region.

- Retain rejected counts by reason: uncovered, illegal, non-winning, insufficient decision contrast, duplicate, unreachable or uninteresting.

- Separate the candidate seed from the selection seed; changing pack quotas must not alter which positions were originally examined.

## 5.3 Constraint-directed synthesis with SMT

Z3 is useful when the desired candidate is easier to describe as a set of logical relations than to encounter by chance. The 24 board points map naturally to fixed-width bit-vectors. Constraints can enforce disjoint occupancy, material counts, selected mill lines, adjacency, empty targets, phase conditions and symmetry-breaking. Models can then be enumerated with blocking clauses and submitted to the Rust rules engine and Perfect DB.

Examples include positions in which a quiet move creates two future mill threats, a visually tempting mill loses after every legal removal, only a non-capturing move preserves the fastest win, or a flying side has many legal moves but only a small set of equally short solutions. Crucially, the SMT model should describe the geometry and local tactical preconditions; the Perfect DB decides whether the intended game-theoretic property is actually true.

A schematic bit-vector encoding is:

$$
\begin{aligned}
w,b &\in \{0,1\}^{24}, \\
w \land b &= 0, \\
\operatorname{popcount}(w) &= W_{\mathrm{board}}, \\
\operatorname{popcount}(b) &= B_{\mathrm{board}}, \\
\Phi_{\mathrm{candidate}}
  &= \Phi_{\mathrm{theme}}
   \land \Phi_{\mathrm{symmetry}}
   \land \Phi_{\mathrm{phase/material}}.
\end{aligned}
$$

$$
\text{SMT model}
\;\longrightarrow\;
\text{Rust legality}
\;\longrightarrow\;
\text{complete-turn Perfect DB certification}.
$$

## 5.4 Replay- and expert-derived candidates

Played games, annotated studies and expert submissions provide a different and valuable prior: the position has a natural context. Every imported game must be replayed by the current Rust rules, normalised to the selected variant and re-certified by Perfect DB. Frequency is not correctness, and a famous position is not exempt from complete-turn validation. The original source and attribution should remain in provenance.

For large raw corpora, repeated JSONL scans are the wrong abstraction. The
implemented Human Replay Index normalises each source game once into two
SQLite tables: an anonymised game record and its ordered complete turns.
Opening turns are retained for replay, while only post-placement movement
roots receive HumanDB-compatible `state_key` and `canonical_notation` lookup
fields. This avoids both repeated parsing and a needlessly large opening
lookup index.

The index deliberately stores no player name, account identifier, rating or
free text. A maintainer can trace a record through its exact source-row
SHA-256, relative source file and line number. The database is a derived
candidate index, not proof: its aggregate HumanDB join is followed by a legal
Rust/TGF replay, a root-position equality check, a legal recorded-turn check
and a fresh Perfect DB evaluation.

Presentation variation is also separated from identity. One deterministic
pseudo-random member of Sanmill's 16 board automorphisms transforms the
history, root and recorded turn at export. Deduplication still uses the
canonical 16-transform root, so presentation changes do not multiply one
source puzzle into several apparent examples. If that first deterministic
choice reproduces a replay reference presentation, extraction advances
through the same orbit until the raw board differs. If no distinct presentation
exists because of a position’s stabiliser, the candidate is rejected.

## 5.5 Symmetry and model enumeration

Discovery should canonicalise under all supported board rotations and reflections before any expensive downstream work. The canonical key belongs in every evidence record. Solver-side symmetry-breaking can reduce duplicate models, but the authoritative canonicalisation must remain the tested Rust/database implementation. Sanmill has already encountered a stabiliser-related hashing defect in which symmetric presentations could map differently; this history justifies explicit 16-presentation regression tests.

# 6. Mathematical tool selection

No single solver is ‘best’ for every stage. The most suitable stack is small and compositional: use one tool where its native model matches the problem, exchange plain candidate/evidence files, and keep the Rust/Perfect DB boundary authoritative.

| **Tool**            | **Best use in this pipeline**                                                                                                     | **Caution**                                                                          | **Offline licence note**                                               |
|---------------------|-----------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|------------------------------------------------------------------------|
| **Z3 (SMT)**        | 24-bit board constraints, bounded histories, model enumeration, bit-vector equivalence checks and small optimisation experiments. | Do not re-solve the entire game tree; avoid a second, drifting rules implementation. | MIT; retain notices if redistributed.                                  |
| **OR-Tools CP-SAT** | Final pack selection with Boolean variables, quotas, incompatibilities and weighted objectives.                                   | Uses integer/Boolean modelling; scale quality features explicitly.                   | Apache-2.0.                                                            |
| **MiniZinc**        | Rapid, readable prototypes of selection and finite-domain discovery models across several back-ends.                              | Choose and pin a back-end before treating performance as representative.             | Build-time research tool; verify the selected distribution components. |
| **CaDiCaL / SAT**   | Very large Boolean encodings, exhaustive model enumeration and independent checks of local constraints.                           | Lower-level encoding and weaker explanatory structure than SMT.                      | MIT for CaDiCaL.                                                       |
| **clingo / ASP**    | Declarative theme rules, alternative model enumeration and explainable combinatorial generation.                                  | Game-state arithmetic may be less direct than bit-vectors.                           | MIT.                                                                   |
| **Kani**            | Bit-precise verification of the actual Rust encoders, invariants, conversions and selected canonicalisation properties.           | Bounded proof scope must be stated; not a database substitute.                       | MIT or Apache-2.0.                                                     |
| **HiGHS / MIP**     | Linear pack-selection models, especially if objectives become predominantly linear.                                               | Less direct than CP-SAT for logical clauses and reified conditions.                  | MIT.                                                                   |
| **TLA+ / Alloy**    | Protocol-level exploration of pipeline state, cache/version transitions or compact bounded relational models.                     | Supplementary; not needed for the first implementation.                              | Check the chosen tool distribution and version.                        |

> **Recommended default stack.** Rust/TGF + Perfect DB for truth; Z3 only where constraint-directed candidate generation adds value; OR-Tools CP-SAT for pack selection; Kani for high-risk Rust invariants. MiniZinc, SAT and ASP are excellent experimental alternatives but need not become mandatory dependencies.

Sanmill is distributed under AGPL-3.0. Permissively licensed offline tools are usually straightforward to operate alongside it, but this paper is not legal advice. Any redistributed solver binary or source requires its notices and terms to be honoured. The licence and attribution conditions of the Perfect DB itself—and of any imported expert/game corpus—must also be confirmed before derived puzzle data is published.

# 7. Perfect DB certification

## 7.1 Freeze the rules/database identity

A database answer is exact only for the rules under which the database was constructed. The evidence record must therefore include the Mill variant, flying rule, removal convention, repetition and draw rules, database release identifier, file manifest or digest, and the Sanmill rules-policy identifier. A query that is uncovered or mismatched is not ‘probably correct’; it is rejected.

Before generation, maintain a compatibility row for every supported Sanmill rules policy. The row must compare at least:

- board topology and mill lines;
- placement, movement and flying thresholds;
- removal restrictions after forming a mill;
- repetition and move-count draw rules;
- side-to-move and history requirements;
- Perfect DB variant, coverage, release and manifest digest.

The first pilot may use the already matched standard rules. A Russian-rules pack is an optional extension only when the implementation is straightforward, the compatibility row passes and exact database coverage is available. Puzzle evidence and pack selection must never mix unmatched variants.

## 7.2 Enumerate complete logical turns

For each candidate s, the certifier should query Root(s), enumerate all complete logical turns through the history-aware Perfect DB API, and record the exact outcome and raw distance for every turn. The database library’s strict ordering—which favours faster wins and slower losses while leaving draws tied—defines the official proof line after conversion to the agreed logical-ply unit. The unfiltered set of outcomes and distances must remain in the certificate.

The certifier should independently regenerate the same complete turns with Rust/TGF and compare action tokens, successor state and count. A mismatch between rule generation and database enumeration indicates an encoding, history or variant defect and must stop the candidate.

## 7.3 Distinguish a line from a strategy

A principal variation is convenient for display, but a forced puzzle is a strategy against all relevant defences. At every defender node, the evidence includes every reply that preserves the defender’s best attainable outcome; when all such replies lose, the official line chooses a reply that delays defeat for as long as possible. At every attacker node, every equally short winning turn is accepted. A human-like reply from the heuristic engine may be stored as a separately labelled illustrative line, in addition to—not instead of—the exact strategy tree.

| **Certification property**     | **Machine test**                                                                                         | **Failure result**                                         |
|--------------------------------|----------------------------------------------------------------------------------------------------------|------------------------------------------------------------|
| **Exact root claim**           | Root(s) is covered and has the required W/D/L value.                                                     | Reject.                                                    |
| **Complete-turn agreement**    | Rust and Perfect DB enumerate the same legal logical turns, including removals.                          | Quarantine as an implementation discrepancy.               |
| **Shortest-solution set**      | At least one complete logical turn has winning outcome and minimum winning distance; retain all ties.    | Reject if empty; never discard an equally short solution.  |
| **Slower winning alternatives** | Every winning turn with greater distance is retained and classified as slower rather than losing.      | Quarantine if classification or feedback would be wrong.   |
| **Minimum decision contrast**  | At least the configured number of legal turns fail to achieve the shortest forced win.                   | Reject under that composition policy.                      |
| **Forced continuation**        | The exported tree covers every relevant optimal defence to the configured horizon or terminal result.    | Reject or label as an illustrative line only.              |
| **Coverage integrity**         | Every database query resolves in the same rules policy, variant and manifest.                            | Reject; never substitute heuristic evaluation.             |

## 7.4 Distance and ‘Win in N’

The database’s raw step count remains evidence, but the public label counts moves by the solving side. First convert the database distance to complete logical plies, where one player’s primary action plus any compulsory removal is one logical ply. If $D_{\mathrm{ply}}(s)$ is the exact number of alternating logical plies to terminal victory under the official distance policy, then:

$$
N_{\mathrm{public}}(s) = \left\lceil \frac{D_{\mathrm{ply}}(s)}{2} \right\rceil
$$

Thus solver move, defender reply, solver winning move is **Win in 2**. The raw database distance, logical-ply distance, public value and conversion-policy version must all be stored. A future database representation may count internal actions differently, but it must not silently alter an existing public label.

# 8. Reachability and composed positions

Perfect DB addressability does not, by itself, prove that a position can arise from the approved initial state. A bitboard may respect piece budgets yet conflict with placement history, capture counts, side-to-move parity or a rule-specific transition. This is especially important for solver-synthesised positions because the generator is rewarded for satisfying the final constraints, not for supplying a history unless asked.

| **Reachability class**               | **Required evidence**                                                                       | **Suggested use**                                                   |
|--------------------------------------|---------------------------------------------------------------------------------------------|---------------------------------------------------------------------|
| **R0 — inconsistent**                | Fails Rust construction, action generation, count or phase invariants.                      | Reject immediately.                                                 |
| **R1 — rule-consistent composition** | Legal current state and exact DB result, but no history witness.                            | Publish as **Composed position** after expert approval.                  |
| **R2 — replay-backed**               | A supplied game/history replays under the frozen rules to the candidate.                    | Publish as **Replay-backed position** after source review.               |
| **R3 — formally witnessed**          | A generated legal action sequence from an approved initial state is independently replayed. | Publish as **Replay-backed position**, retaining the stronger R3 record. |

## 8.1 Practical proof methods

- Replay proof: retain the exact chronological action sequence and replay it through Rust/TGF. This is the preferred certificate when a candidate came from a game corpus.

- Bounded SMT/model checking: unroll legal transitions for K logical turns and ask for a history ending at the target canonical state. A satisfying model supplies a witness; an unsatisfiable result proves only that no history exists within the declared bound.

- Reverse predecessor search: work backwards from a target in small sectors, respecting captures and phase boundaries, until a known reachable frontier is found.

- Forward reachability cache: build compact canonical frontiers for selected early-game depths and join them to backward searches.

- Independent replay: regardless of how a witness is found, the final sequence must be replayed by the production Rust rules before the R3 label is assigned.

> **Confirmed publication policy.** Both R1 compositions and R2/R3 reachable studies are permitted, but they remain visibly distinguishable in review and in the published pack. No composed position is described as game-derived without a replay witness.

# 9. Interestingness and difficulty

Exact solvability is necessary but not sufficient. A database can supply millions of correct positions that are repetitive, visually obvious or pedagogically empty. The pipeline should keep several transparent measurements and present them to experts; it should not collapse them prematurely into a supposedly objective ‘beauty’ score.

## 9.1 Exact features

- Root W/D/L; raw and logical-ply distance; number of complete legal turns; and counts of shortest, slower-winning and non-winning first turns.

- Forced-tree width and depth; number of equal-best defences; number of attacker decision points; and whether the win survives every capture choice after a mill.

- Material, phase, mobility, flying status and sector identity before and after the key turn.

- Symmetry class, canonical key and similarity to previously approved puzzles.

## 9.2 Search-derived features

Run the ordinary Sanmill search at controlled depths and seeds. Record the first depth at which the winning turn is stable, node count, score margin, principal-variation churn and the ranking of tempting losing alternatives. These measures approximate difficulty for this engine and configuration only. They must never override Perfect DB or be presented as a universal human rating.

## 9.3 Tactical and strategic theme features

A tactical or strategic theme is a recurring idea that explains why a
solution works. Candidate themes include quiet moves, delayed mills, double
threats, opening and closing mills, forced capture choice, material
sacrifice, blockade or immobilisation, tempo transfer, flying-stage geometry,
and a tempting immediate mill that fails. Detectors can be implemented in
Rust or prototyped as SMT/ASP predicates, but their labels are provisional.
The computer may flag a possible pattern; specialists should name, merge or
reject themes after seeing actual positions.

The current Rust filter has six additional strategy-led predicates. They
are deliberately conservative and inspect the complete first turn:

| **Working label**       | **Exact first-turn requirement** |
|-------------------------|----------------------------------|
| **Allow mill**          | A quiet winning turn leaves an opposing open mill which was already reachable, does not occupy its target, and leaves the opponent at least one legal mill-closing action. |
| **Mobility squeeze**    | A quiet movement turn cuts non-flying defender mobility by at least two actions and at least 25 per cent, without merely ending the game or reducing mobility to zero. |
| **Junction release**    | The winning piece leaves a degree-four point for a lower-degree point, was not leaving its own formed mill, and the turn reduces opposing mobility. |
| **Mill recovery**       | A quiet move from outside a formed mill creates a new adjacent feeder link to one of the side’s existing mills. |
| **Right-angle threat**  | The quiet landing point belongs to two different open mill lines, one horizontal and one vertical, with two distinct closing targets. |
| **Ring transfer**       | A quiet move crosses one ring boundary and creates a new open-mill target through its destination. |

These predicates describe visible board changes only. They do not assert
that the offered mill is the defender’s best reply, that every mobility
reduction is instructive, or that a feeder link will be used in the displayed
line. Those are reviewer questions. Requiring every equally short winning
first turn to match the same predicate prevents a labelled theme from being
an incidental feature of only one interchangeable solution.

| **Expert review dimension** | **Suggested question**                                                       | **Machine evidence**                                         |
|-----------------------------|------------------------------------------------------------------------------|--------------------------------------------------------------|
| **Correctness**             | Is the claimed objective unambiguous under the selected rules?               | Complete-turn certificate and strategy tree.                 |
| **Naturalness**             | Does the position look like meaningful Mill rather than a solver artefact?   | Reachability class, replay and sector context.               |
| **Clarity**                 | Can the intended idea be explained without concealing alternative solutions? | Shortest-solution count, defence branches and theme labels.  |
| **Surprise**                | Is the key move non-obvious for a principled reason?                         | Search ranking, tempting alternatives and exact refutations. |
| **Economy**                 | Are all pieces and branches relevant to the idea?                            | Ablation variants generated and re-certified offline.        |
| **Teaching value**          | What transferable concept will a player learn?                               | Expert annotation; not inferred from solver score.           |

# 10. Global pack optimisation

The certified pool should be much larger than the published pack. Choosing candidates greedily as they are found makes the result depend on enumeration order and often over-represents common sectors or themes. CP-SAT converts editorial intentions into an auditable global selection problem.

For each certified candidate $i$, introduce a Boolean variable $x_i$. Hard constraints set the pack size and quotas by difficulty, phase, material, reachability and variant, with one position per symmetry class, sector caps and near-duplicate exclusions. Theme balance should initially be a soft objective until experts have validated the vocabulary against real positions. The objective rewards expert score, theme clarity and evidence completeness while penalising similarity.

Exact deduplication first canonicalises the 16 board transformations. A
second key normalises White and Black to **solver** and **defender**, so a
colour-exchanged copy with the corresponding side to move cannot be selected
twice. An optional minimum-position-distance constraint counts differing
solver-coloured and defender-coloured points under the closest symmetry; it
is a diversity gate, not a game-theoretic metric.

The application pack uses a minimum distance of **four**. This rejects exact
copies, colour-exchanged copies, one-stone changes and the smallest
two-stone edits. The same default is enforced while selecting candidates,
against reference FEN records, when merging review batches and by the
committed Rust asset test. A selector run may choose a stricter threshold,
but a merge may not weaken the application invariant.

$$
x_i \in \{0,1\},
\qquad
\sum_{i\in I} x_i = N
$$

$$
q_g^{\min}
\le
\sum_{i\in g} x_i
\le
q_g^{\max},
\qquad
\forall g\in G
$$

$$
\sum_{i\in c} x_i \le 1,
\qquad
\forall c\in \mathcal{C}
$$

$$
\operatorname*{maximise} \quad \sum_{i\in I} q_i x_i - \lambda \sum_{(i,j)\in\mathcal{P}} s_{ij} y_{ij}
$$

Here, $G$ is the set of editorial quota groups, $\mathcal{C}$ is the set of symmetry classes, and $\mathcal{P}$ is the set of candidate pairs whose similarity is penalised.

Record every coefficient, quota and solver seed in the pack manifest. Infeasibility must be reported, not silently relaxed. Experts should also receive near-optimal alternatives because a small objective difference may conceal a strong qualitative preference.

# 11. Evidence and provenance schema

Keep the public .sanmill_puzzles file compact and stable, and archive a richer evidence sidecar for expert review. Each puzzle must remain reproducible without the original generator’s memory or log files.

The reviewer-facing presentation and the machine certificate serve different purposes. By default, an expert sees the position, rules variant, public **Win in N** value, reachability label, one official shortest line and the number of other equally short solutions. The reviewer may expand the record to inspect the complete strategy tree. A separately labelled human or illustrative line is optional.

| **Field group**        | **Minimum contents**                                                                                                            |
|------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| **Position**           | Canonical FEN/state, side to move, phase, hand/on-board counts, pending-removal state and canonical symmetry key.               |
| **Rules and database** | Rules-policy identifier, variant, draw/repetition/flying/removal conventions, database version and manifest digest.             |
| **Exact proof**        | Root W/D/L, raw and logical-ply distance, every complete logical turn and outcome, shortest and slower winning sets, and forced strategy tree. |
| **Reachability**       | R0–R3 class, witness type, explicit replay where available and source attribution.                                              |
| **Characterisation**   | Candidate themes, material/phase/sector, exact branching metrics, search probes and similarity fingerprint.                    |
| **Reproduction**       | Generator commit, configuration digest, candidate source, seed, solver names/versions, constraint model version and timestamps. |
| **Editorial record**   | Reviewer decisions, comments, approved wording, difficulty label, composition category and final pack-selection policy.         |

The shipped puzzle should use the repository’s structured version-1.0 solution objects with explicit side-to-move information. One official distance-optimal line may be included for the interface, while the full strategy tree remains in the evidence sidecar if size or presentation makes it unsuitable for the application asset. The asset should also carry the count of equally short first solutions when the format permits it.

If the player chooses a slower winning turn, the application does not complete the puzzle. It should distinguish that result from a losing or drawing move and respond encouragingly, for example: “Good move — it still wins, but there is a faster solution. Well done; try again.”

# 12. Validation and acceptance gates

The pipeline should be fail-closed and deterministic. A candidate passes only when every gate required by the selected publication policy succeeds.

| **Gate**               | **Acceptance test**                                                                           | **Retained evidence**                                  |
|------------------------|-----------------------------------------------------------------------------------------------|--------------------------------------------------------|
| **G0 — encoding**      | Bitboards are disjoint, counts fit, serialisation round-trips and no out-of-board bit is set. | Constraint model result and Rust round-trip.           |
| **G1 — rules**         | Rust/TGF constructs the state and independently enumerates legal complete turns.              | State digest and turn list.                            |
| **G2 — applicability** | Rules-policy and Perfect DB variant/manifest match; every query is covered.                   | Policy and database identifiers.                       |
| **G3 — exact outcome** | Root and all complete-turn outcomes satisfy the puzzle objective.                             | Unfiltered W/D/L and distance table.                   |
| **G4 — shortest set**  | Every equally short winning turn is accepted; slower winning turns are separately classified. | Distance-labelled winning sets at every attacker node. |
| **G5 — defence**       | Every relevant best defence is represented; official and illustrative lines are distinguished. | Forced strategy tree and labelled display lines.       |
| **G6 — reachability**  | Required R-class is proven and the witness replays in production Rust.                        | History witness and replay digest.                     |
| **G7 — symmetry**      | All 16 presentations share the canonical key and exact outcome; duplicates are removed.       | Symmetry test record.                                  |
| **G8 — quality**       | Theme/difficulty evidence is complete and expert review approves the composition.             | Feature record and signed review decision.             |
| **G9 — reproduction**  | A clean rerun produces the same evidence and exported puzzle bytes.                           | Tool versions, config, seed, commit and output digest. |

## 12.1 Independent checks

- Property tests should compare the SMT/SAT encoding with Rust for large samples of valid and deliberately invalid states.

- Canonicalisation tests should cover every board symmetry and stabiliser case, with regression vectors retained permanently.

- Selected certificates should be cross-checked by an independent enumerator or solver implementation where practical.

- Every reachability witness and every exported solution line should be replayed from its declared start state.

- A clean-machine generation run should verify dependency pinning, licence notices, database manifest and byte-for-byte deterministic output.

- Generated JSON, FEN, manifest and Markdown artefacts use UTF-8 with explicit
  LF line endings, so their recorded SHA-256 values do not depend on the host
  operating system’s newline convention.

# 13. Staged implementation for Sanmill

The method can be introduced incrementally around the existing tgf-cli generator. The first useful improvement does not require a new solver: it requires stronger logical-turn certification and a persistent evidence pool.

The current implementation completes Stage 0, the product-facing subset of
Stage 2, and pilot implementations of Stages 3, 4 and 5. Complete root turns
are classified, official lines use exact delay-defeat defence, logical-turn
move counts reach the Flutter client, and a slower win receives encouraging
non-completion feedback. Z3 proposals cross a plain JSON boundary and are
independently checked in Rust; CP-SAT then selects a balanced subset without
making any correctness claim. HumanDB source games cross a separate,
anonymised SQLite/replay boundary and are independently replayed before
Perfect DB certification. A persistent full proof-evidence pool and complete
strategy-tree sidecars remain staged work.

| **Stage**                    | **Status**             | **Engineering work**                                                                                                 | **Review milestone**                                         |
|------------------------------|------------------------|----------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------|
| **0 — policy codification**  | Implemented            | Encode the confirmed complete-turn, shortest-solution, distance, reachability and variant policies.                  | This expert-reviewed decision record is versioned.            |
| **1 — evidence pool**        | Pending                | Refactor generation into candidate mining and certification; write deterministic JSON Lines evidence.                | Existing generator results can be regenerated and compared.  |
| **2 — logical-turn proof**   | Product subset complete | Use the history-aware all-logical-turn outcome API; export exact strategy trees, official lines and optional human lines separately. | Experts inspect a small, fully evidenced sample.      |
| **3 — reachability**         | Replay pilot implemented | Build the anonymised replay index, retain transformed histories and label composed and replay-backed positions separately. | Review the 13 real-game missed-win positions and provenance. |
| **4 — constraint discovery** | Pilot implemented      | Accept Z3-generated candidates behind a validated plain-file interface; re-evaluate themes and legality in Rust.      | Review the five-theme pilot for naturalness and teaching value. |
| **5 — pack selection**       | Pilot implemented      | Use deterministic CP-SAT selection with symmetry, side, difficulty, topic and diversity constraints.                 | Experts review the selected pack and the declared quotas.     |
| **6 — release**              | Partly implemented     | Export the structured curriculum asset; archive full evidence, notices, manifests and deterministic build instructions. | Final expert approval and release digest.                  |

A practical PC workflow could expose four commands: puzzle-mine (candidate stream), puzzle-certify (Perfect DB evidence), puzzle-select (CP-SAT editorial model) and puzzle-export (stable Sanmill format). These names are illustrative; the important boundary is that each stage consumes immutable files, records its configuration and can be rerun independently.

# 14. Principal risks and mitigations

| **Risk**                           | **Consequence**                                                    | **Mitigation**                                                    |
|------------------------------------|--------------------------------------------------------------------|-------------------------------------------------------------------|
| **Rules/database drift**           | An exact answer is applied to a subtly different game.             | Versioned policy and manifest; reject mismatches.                 |
| **Action/turn confusion**          | A mill-forming action is classified before the compulsory removal. | Complete logical-turn API and Rust/database turn-list comparison. |
| **Distance-label ambiguity**       | Raw database steps are exposed as an incorrect public Win in N.     | Versioned raw-step-to-logical-ply conversion; count solver moves. |
| **Unreachable synthesis**          | An artificial state is presented as a game-derived study.          | R0–R3 labels and explicit witness policy.                         |
| **Single-line proof**              | Alternative best defences or equally short solutions are concealed. | Show an alternative count; store the strategy tree separately.    |
| **Heuristic difficulty precision** | Engine-specific measurements are mistaken for human ratings.       | Retain raw probes and require expert calibration.                 |
| **Sampling and selection bias**    | Common sectors and early candidates dominate.                      | Stratified mining plus global constrained selection.              |
| **Solver/model drift**             | A constraint encoding diverges from production Rust.               | Differential/property tests, pinned versions and Kani checks.     |
| **Licence or attribution gap**     | A solver, database or corpus is redistributed improperly.          | Keep tools offline, retain notices and confirm source/data terms. |
| **False claim of completeness**    | Sampled coverage is described as exhaustive.                       | Declare exact sector/bounds and retain candidate accounting.      |
| **Aesthetic automation**           | A numerical objective replaces composition judgement.              | Use models to shortlist; experts retain final authority.          |

# 15. Expert-reviewed policy record

Initial specialist review produced the following binding assumptions for the pilot:

- A complete logical turn includes compulsory removal and counts as one logical ply.
- All equally short first moves and continuations are correct.
- A slower forced win is acknowledged but does not complete a shortest-win puzzle.
- **Win in N** counts moves by the solving side.
- Public titles state the side to move before the objective.
- **Hold the draw** accepts a complete logical turn only when exact database
  evidence says it preserves a draw; a unique draw save has no other drawing
  or winning turn.
- The official line uses the defence that delays defeat; a human line may be shown separately.
- The default review view shows one solution line and the number of equally short alternatives.
- R1 compositions and R2/R3 replay-backed positions are both allowed under clear labels.
- Each rules variant requires an explicit Perfect DB compatibility record.
- Russian rules are optional for the first pilot, subject to implementation effort and exact coverage.

The following matters remain editorial rather than semantic and should be calibrated on actual pilot positions:

- which candidate tactical or strategic themes are recognised and what Mill terminology should name them;
- which machine features correlate with novice, intermediate, advanced and expert difficulty;
- the minimum economy, naturalness and teaching-value standard;
- which theme and difficulty targets become hard pack quotas rather than soft preferences;
- attribution requirements for database-, game- and expert-derived material.

> **Next outcome.** Blind-review the 66 embedded pending candidates and the
> resulting 177-puzzle curriculum order. Retain the 13 constraint-directed
> compositions and 13 replay-backed human missed wins as calibration
> material. Use specialist scoring, together with anonymised aggregate user
> pass rates, to refine theme names, difficulty bands, long blockade
> presentation and pack balance. Full machine certificate sidecars should be
> added before describing the wider pack as an evidence-complete release.

The next product milestone is approximately **500 official curated
puzzles**, not a million-position application bundle. Perfect DB and HumanDB
may support a much larger PC-side candidate warehouse, but candidates should
advance into the Flutter asset gradually through exact certification,
specialist scoring, diversity selection and observed user completion data.

# Appendix A. Sanmill implementation touchpoints

- `crates/tgf-cli/src/mill_puzzle/mod.rs` — existing offline Perfect DB puzzle generator, filters, deduplication and export.

- `crates/tgf-cli/src/mill_puzzle/candidate_input.rs` — validated plain-JSON boundary for solver-generated candidates and solver provenance.

- `crates/tgf-cli/src/mill_puzzle/mine_entry_input.rs` — bounded-memory,
  symmetry-aware adapter from FEN-bearing engine-error JSONL records to the
  exact puzzle-certification pipeline.

- `crates/tgf-cli/src/mill_puzzle/motifs.rs` — Rust-side predicates applied
  to every shortest complete first turn for the five constraint-directed
  pilot themes and six strategy-led review themes.

- `crates/tgf-cli/src/mill_puzzle/sampler.rs` — broad legal-shaped bitboard
  sampling with separate solver/defender material ranges; currently does not
  prove game-tree reachability.

- `crates/tgf-cli/src/mill_puzzle/solver.rs` — official line construction using fastest database attack and delay-defeat database defence over complete logical turns.

- `crates/tgf-cli/src/mill_replay_index/` — bounded-parallel Rust builder for
  the anonymised HumanDB replay SQLite sidecar and its co-located build record.

- `src/ui/flutter_app/lib/puzzle/pages/puzzle_page.dart` — shortest-win
  completion policy and encouraging feedback for slower winning lines.

- `crates/perfect-db/src/mill.rs` — history-aware complete-logical-turn choices and all-turn outcome enumeration.

- `crates/perfect-db/src/index/hash.rs` — canonical hashing and stabiliser regression context.

- `crates/tgf-cli/src/mill_endgame/mod.rs` — exhaustive small-sector enumeration over exact symmetry-reduced indices.

- `src/ui/flutter_app/lib/puzzle/services/built_in_puzzles.dart` — offline-generated static pack loading with no runtime database dependency.

- `src/ui/flutter_app/tool/merge_puzzle_packs.dart` — symmetry-aware pack merge, curriculum classification and progressive ordering.

- `scripts/generate_mill_smt_candidates.py` — pinned Z3 Boolean/pseudo-Boolean candidate model and deterministic enumeration.

- `scripts/select_mill_puzzles_cp_sat.py` — deterministic CP-SAT editorial
  selector over already certified candidates, including per-difficulty,
  solution-line, candidate-distance and reference-distance gates.

- `scripts/mill_puzzle_similarity.py` — dependency-free ring-16,
  solver-side-normalised similarity definition shared by selection, audit
  and merge tools.

- `scripts/audit_mill_puzzle_similarity.py` — whole-package conflict and
  connected-cluster report.

- `scripts/prune_mill_puzzle_similarity.py` — deterministic maximum-cardinality
  repair step used to remove an existing pack’s conflicting positions before
  certified replacements are selected.

- `scripts/build_mill_editorial_collisions.py` — editorial-reference and
  existing-pack collision-input preparation.

- `crates/tgf-cli/testdata/puzzle_exclusions/mill_editorial_baseline.fen` —
  version-controlled editorial collision roots used by the non-duplication
  test.

- `crates/tgf-cli/testdata/puzzle_exclusions/mill_editorial_non_replay.fen` —
  editorial roots without explicit replay provenance.

- `crates/tgf-cli/testdata/puzzle_exclusions/mill_editorial_replay.fen` —
  replay-attributed editorial roots and links, subject to replay and
  different-presentation gates rather than a general allow-list.

- `scripts/extract_human_game_puzzle_candidates.py` — indexed HumanDB
  distance-band query, reference-aware deterministic presentation
  and replay-candidate package export.

- `scripts/mine_mill_review_candidates.py` — reproducible 6v4, 7v4,
  flying-defence, precision-trap and long-endgame forced-win review profiles.

- `scripts/mine_mill_engine_blunder_candidates.py` — reproducible
  engine-error-corpus profiles for balanced quiet play, material odds,
  flying defence and post-six-round placement, plus opt-in allow-mill,
  mobility-squeeze, junction-release, mill-recovery, right-angle-threat and
  ring-transfer searches, with optional parallel profile execution. It fails
  closed if the supplied collision record does not include every root in the
  current built-in pack.

- `scripts/mine_mill_outcome_contrast_studies.py` — persistent Rust/TGF
  data-query client for one-stone W/D/L contrast pairs and unique draw-saving
  candidates.

- `scripts/build_mill_draw_review_candidates.py` — CP-SAT selection of
  side-balanced, symmetry-distant unique draw saves into a review package.

- `scripts/mill_puzzle_objectives.py` and
  `scripts/normalize_mill_puzzle_objectives.py` — one public move-count and
  objective contract shared by asset repair, merge validation and tests.

- `scripts/merge_mill_review_candidates.py` — deterministic promotion of a
  certified CP-SAT shortlist into the application asset, including review
  provenance, curriculum classification and an idempotent batch marker.

- `scripts/render_mill_puzzle_review_pack.py` — deterministic, blind
  Typora-compatible Markdown diagrams with a separate one-line answer key
  and no HTML or CSS. It also checks that optimal lines match the public
  solver-move distance and marked slower wins are genuinely longer.

- `scripts/build_human_replay_index.py` — independent Python reference
  builder retained for small Rust/Python schema and canonicalisation parity
  checks; the Rust command is the production full-corpus path.

- `docs/HUMAN_REPLAY_INDEX.md` — versioned purpose, privacy, schema,
  symmetry, rebuild and traceability contract for the replay database.

- `docs/PUZZLE_FORMAT.md` — versioned structured puzzle, solution, move and
  replay-provenance format.

# Appendix B. Pilot review package

The embedded review package comprises 13 retained constraint-directed
compositions, 13 replay-backed human missed wins and 66 pending candidates
in a 177-puzzle application asset. The replay subset contains three short,
five medium and five long positions, including two immobilisation studies.
The first engine-error shortlist is balanced 15–15 by side to move. The
strategy-theme supplement is balanced five–five. The 16-position similarity
repair batch is balanced eight–eight, includes two beginner replacements
with different primary topics, caps displayed solution lines at 32 and
applies a minimum distance of four both internally and against the retained
151-position base. The ten-position draw-defence batch is balanced five–five,
contains exactly one database-certified drawing turn per root and applies
the same minimum distance of four against the complete 167-position base.
The four pending batches remain separately traceable as `expert-pending`
material.
Reviewers should receive anonymised diagrams in curriculum order and,
separately, in random order, with one official shortest line, the
equally-short-first-turn count and the appropriate `source:composed` or
`source:replay-backed` label. They should score correctness, naturalness,
clarity, surprise, economy and teaching value without being told whether a
composition was found by broad sampling or Z3-directed search.

This compact pilot tests the new machinery; it does not replace the broader
comparative study originally proposed. Before a large evidence-complete
release, retain the target of 60 independently reviewed positions: 20
exhaustively enumerated small-sector studies, 20 stratified large-sector
samples and 20 constraint-directed or replay-derived positions. Require full
complete-turn certificate sidecars for that study. Use matched Standard rules
for the baseline; add a Russian-rules sample only when implementation
compatibility and exact database coverage are both recorded.

# Appendix C. Reference and licence notes

External tool descriptions below refer to official project documentation current on 28 July 2026. Licence notes are concise engineering indicators, not legal advice; release preparation should verify the exact versions and redistributed components.

1.  [Sanmill repository](https://github.com/calcitem/Sanmill). AGPL-3.0 project source and implementation baseline.

2.  [Sanmill offline Mill puzzle generator](https://github.com/calcitem/Sanmill/blob/master/crates/tgf-cli/src/mill_puzzle/mod.rs). Current Perfect DB mining and acceptance pipeline.

3.  [Sanmill broad puzzle sampler](https://github.com/calcitem/Sanmill/blob/master/crates/tgf-cli/src/mill_puzzle/sampler.rs). Notes the distinction between legal-shaped sampling and game-tree reachability.

4.  [Sanmill Perfect DB logical-turn API](https://github.com/calcitem/Sanmill/blob/master/crates/perfect-db/src/mill.rs). Complete logical-turn and all-outcome queries.

5.  [Z3 Guide: logic and SMT](https://microsoft.github.io/z3guide/docs/logic/intro/). Official guide to Z3’s supported logics and solving model.

6.  [Z3 Guide: bit-vectors](https://microsoft.github.io/z3guide/docs/theories/Bitvectors/). Official fixed-width bit-vector theory reference.

7.  [Z3 repository](https://github.com/Z3Prover/z3). Source and MIT licence.

8.  [Google OR-Tools: CP-SAT Solver](https://developers.google.com/optimization/cp/cp_solver). Official integer/Boolean constraint-programming documentation.

9.  [Google OR-Tools repository](https://github.com/google/or-tools). Source and Apache-2.0 licence.

10. [MiniZinc](https://www.minizinc.org/). Official high-level constraint-modelling language and solver ecosystem.

11. [CaDiCaL SAT solver](https://github.com/arminbiere/cadical). Source and MIT licence.

12. [clingo and Potassco](https://potassco.org/clingo/). Official answer-set solving system documentation.

13. [HiGHS optimisation software](https://highs.dev/). Official LP/MIP/QP solver project.

14. [Kani Rust Verifier](https://model-checking.github.io/kani/). Official bit-precise model-checking documentation for Rust.

15. [TLA+ tools repository](https://github.com/tlaplus/tlaplus). TLC model checker and MIT-licensed tools.

16. [Alloy language reference](https://alloytools.org/download/alloy-language-reference.pdf). Bounded finite relational modelling reference.
