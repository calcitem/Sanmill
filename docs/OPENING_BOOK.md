# Opening Book

This document describes Sanmill's **opening book**: a single bundled JSON per
game variant that both drives the AI's opening placement and powers in-game
opening recognition / display. It covers the data model, the runtime
architecture, the settings that control it, and how to maintain or extend it.

## Overview

The opening book is a **frontend-only, advisory** feature. It lives entirely in
the Flutter app; the Rust/TGF engine knows nothing about it. On an AI turn it is
consulted **before** the Human Database and the native search (see
[Interaction with other move sources](#interaction-with-other-move-sources)),
and only during the **placing phase**.

It combines two layers in one asset:

- **Oracle** — a position-keyed best-move table (`canonical FEN -> [moves]`).
  This is the engine-quality data that actually drives AI placement. Each entry
  is stored once for the lexicographically smallest FEN in its 16-way symmetry
  orbit and expanded to all 16 variants at lookup time, so the table stays
  compact without losing coverage.
- **Named openings** — rich, human-curated lines (`line_moves` plus metadata:
  name, family, source, strategic notes, common blunders, recommended
  responses, branch variations, and which side the line favours). These power
  opening **recognition**, the on-board **display**, and the optional
  **favoured-opening director**.

Metadata never lives inside a FEN — a FEN is only ever a lookup key. This mirrors
the chess-world separation of an engine (search), a move book (hash/position ->
move), and an opening-name database (ECO).

It applies to **standard Nine Men's Morris** and **El Filja**. El Filja ships an
oracle only (no curated named lines yet).

## Architecture and data flow

```mermaid
flowchart TD
  OracleSrc["tool/mill_opening_book_oracle_source.dart (authored oracle, with board comments)"] --> Build
  Curated["tool/&lt;variant&gt;_curated_openings.json (authored named lines)"] --> Build
  Build["tool/build_opening_book.dart (dart run)"] --> Json["assets/opening_books/&lt;variant&gt;/opening_book.json (shipped)"]
  Build --> Atlas["tool/&lt;variant&gt;_opening_book_atlas.md (human-readable)"]
  Json --> Repo["OpeningBookRepository.ensureLoaded() (async, at startup)"]
  Repo --> Provider["MillOpeningBookProvider.lookup() -> AI placement"]
  Repo --> Recognizer["MillOpeningRecognizer -> name / notes / favoured side"]
  Provider --> AiTurn["NativeMillAiTurnController (AI turn)"]
  Recognizer --> Header["Game header tip (when 'Show opening information' is on)"]
```

Layers:

- **Authored sources** (`tool/`, build input, not shipped):
  - `tool/mill_opening_book_oracle_source.dart` — the canonical-FEN move oracle,
    keeping ASCII board diagrams in comments for readability.
  - `tool/<variant>_curated_openings.json` — named lines in the source schema
    (snake_case, NMM_LLM-compatible). Only `nmm` has one today.
- **Build tool** `tool/build_opening_book.dart` (`dart run`): merges the oracle
  and the curated lines into the shipped JSON, and emits a human-readable atlas.
- **Shipped asset** `assets/opening_books/<variant>/opening_book.json`: the only
  runtime artefact, registered in `pubspec.yaml`.
- **Runtime (Dart)**:
  - `lib/games/mill/opening_book/opening_book_models.dart` — the data model.
  - `lib/games/mill/opening_book/opening_book_repository.dart` — loads the asset
    once (singleton) and exposes the oracle and named openings.
  - `lib/games/mill/mill_opening_book_symmetry.dart` — FEN normalisation, 16-way
    canonicalisation, and the symmetry-aware oracle lookup.
  - `lib/games/mill/mill_opening_book_provider.dart` — the move source consulted
    on AI turns (oracle lookup + optional favoured-opening director).
  - `lib/games/mill/opening_book/mill_opening_move_selector.dart` — chooses among
    candidate book moves.
  - `lib/games/mill/opening_book/mill_opening_recognizer.dart` — stateless
    opening recognition used for display and the director.

Loading is asynchronous (`rootBundle`), kicked off from `main.dart` via
`OpeningBookRepository.instance.ensureLoaded()`. Every query is synchronous
against the in-memory model, so the AI hot path never blocks; if the book has
not finished loading, a lookup simply misses and the engine search proceeds.

## JSON schema

`opening_book.json` (one per variant):

```jsonc
{
  "schemaVersion": 1,
  "variant": "nmm",            // or "el_filja"
  "symmetry": "ring16",         // Sanmill D4 x inner/outer-ring swap
  "oracle": {
    "<canonical Sanmill FEN>": ["d2", "b4", "d6", "f4", "b2", "b6", "f6", "f2"]
  },
  "openings": [
    {
      "id": "mill-rush-parallel",
      "name": "Mill Rush — Parallel",
      "aliases": ["Parallel Lines"],
      "family": "Mill Rush",
      "side": "W",                 // which colour plays the line: W | B | both
      "source": "book",            // provenance: book | learned | human | oracle
      "sourceReference": "Chapter 15.2 ...",
      "confidence": 1.0,
      "tags": ["aggressive", "placement"],
      "strategicNotes": "…",
      "commonBlunders": ["b4", "a4"],
      "recommendedResponses": { "B": ["b6", "d6", "f6"] },
      "outcomeStats": { "W": 0, "B": 0, "D": 0 },
      "lineMoves": ["d2", "d6", "f4", "b4", "f2", "f6", "b2", "b6"],
      "branchMoves": [
        {
          "branchId": "mill-rush-parallel-b2-alt",
          "deviationPly": 7,
          "deviationMove": "d1",
          "name": "… — d1 Variant",
          "lineContinuation": ["d1", "b6"],
          "strategicNotes": "…",
          "source": "book",
          "outcomeStats": { "W": 0, "B": 0, "D": 0 }
        }
      ],
      "favoredSide": "W"           // who is likely to win: W | B | equal
    }
  ]
}
```

The model (`OpeningEntry.fromJson`) is deliberately tolerant: it accepts both
camelCase and the source snake_case keys, and fills missing fields with neutral
defaults, so hand-edited books and future additions stay loadable.

### `side` vs `favoredSide`

These are different axes and are easy to confuse:

- `side` — which colour **plays** the line (the perspective the moves are
  written from).
- `favoredSide` — who is **likely to win** the line (`W` / `B` / `equal`). This
  is the distilled outcome prior; it drives the display and the favoured-opening
  director.

## Symmetry handling

Nine Men's Morris has a 16-element board symmetry group (the dihedral group D4
combined with the inner/outer ring swap), implemented in
`lib/game_page/services/transform/transform.dart`.

- The oracle stores **one representative** per orbit, keyed by the
  lexicographically smallest normalised FEN
  (`canonicalOpeningBookFen`). FEN fields 14 (`formed_mills`) and 15 (`rule50`)
  are zeroed so volatile counters do not split equivalent positions.
- `lookupCanonicalOpeningBook` maps a query FEN to its canonical key, fetches the
  stored line, and rotates the moves back into the query's frame with the
  inverse symmetry.
- Recognition and the director apply the same 16 transforms to the played
  placement sequence so a rotated/reflected game is matched as the same opening.

## Move selection

When the oracle returns several candidate moves for a position,
`MillOpeningMoveSelector.select` chooses one:

- **Shuffling off**: deterministic first candidate (the oracle lists best-first)
  — identical to the legacy behaviour.
- **Shuffling on** (`shufflingEnabled`): rank-biased weighted sampling that
  favours the stronger, earlier candidates while still varying the opening
  (`bias` defaults to 0.6; `bias == 1.0` is a uniform shuffle).

Because every candidate is already an oracle "best" move, the selector can never
weaken the AI — it only changes which equally-good move is played.

## Opening recognition

`MillOpeningRecognizer.recognize(placementMoves, openings)` is pure and
stateless. It is fed the placement moves played so far (removals filtered out)
and classifies the game, symmetry-aware over all 16 transforms:

- `exact` — the played moves are an in-order prefix of a single line.
- `probable` — an in-order prefix shared by several lines.
- `transposition` — the same squares were occupied by each side in a different
  order (a set match), i.e. the same position reached by another move order.
- `deviation` — a followed line was left, but a named `branchMove` covers the
  deviating move.
- `novel` — nothing matched once enough moves are in (`novelCommitPly`).
- `none` — too early / no book.

The result carries the opening's name, family, source, strategic notes, common
blunders, recommended responses, `favoredSide`, and the book's next move in the
live board frame.

## Favoured-opening director (opt-in)

When **Prefer favourable openings** (`preferFavoredOpenings`, default **off**) is
enabled, `MillOpeningBookProvider` consults a director **before** the oracle:

1. `MillOpeningRecognizer.favoredOpeningMoves` finds every named line that
   (a) favours the AI's own colour and (b) is consistent (under all 16
   symmetries) with the placements played so far, and returns their next moves
   in the live frame, best line first.
2. The provider keeps only the legal candidates and picks one with
   `MillOpeningMoveSelector` (so `shufflingEnabled` adds variety).
3. If no favourable, history-consistent line offers a legal move, it falls
   through to the normal oracle lookup.

This makes the AI choose and follow a strategically favourable named opening for
a more human, varied feel. It may deviate from the objectively strongest oracle
move, which is why it is off by default; with it off, AI move behaviour is
exactly the oracle path.

The placement history is supplied to the provider at its construction sites
(`tap_handler.dart` and `game_controller.dart`) via the shared
`openingBookPlacementHistory()` helper.

## Settings

All three live in the AI play-style card of the general settings page and apply
to Nine Men's Morris / El Filja:

- **Use opening book** (`useOpeningBook`) — master switch; gates oracle lookups
  and the director.
- **Show opening information** (`showOpeningInfo`, default off) — shows the
  recognised opening name, source, favoured side, blunder warnings, and
  recommended replies in the game header while playing.
- **Prefer favourable openings** (`preferFavoredOpenings`, default off) — enables
  the favoured-opening director described above.

`shufflingEnabled` (the existing "Move randomly" toggle) controls move variety
for both the oracle selector and the director.

## Interaction with other move sources

On an AI turn the order is: **opening book → Human Database → native search**
(with an optional perfect-database correction layered on the Human Database
move). See [HUMAN_DATABASE.md](HUMAN_DATABASE.md). When the opening book returns
a move, it is applied directly and tagged `AiMoveType.openingBook`.

## Maintaining and extending the book

The shipped JSON is **generated** — do not hand-edit
`assets/opening_books/**/opening_book.json`. Edit the authored sources and
regenerate:

1. To add/adjust **named openings**, edit `tool/<variant>_curated_openings.json`
   (only `nmm` exists today; create `el_filja_curated_openings.json` to add
   El Filja lines). Each entry follows the source schema; set `favored_side`
   (`W` / `B` / `equal`) so the display and director can use it. Only entries
   with `source: "book"` are bundled.
2. To add/adjust the **move oracle**, edit
   `tool/mill_opening_book_oracle_source.dart`.
3. Regenerate:

   ```bash
   cd src/ui/flutter_app
   dart run tool/build_opening_book.dart
   ```

   This rewrites `assets/opening_books/<variant>/opening_book.json` and the
   `tool/<variant>_opening_book_atlas.md` reference, and runs an oracle parity
   check (the round-tripped JSON must reproduce the authored oracle exactly, so
   AI placement strength is unchanged).

### The atlas

JSON cannot carry the oracle's board diagrams (FEN keys contain `/*` and `*/`,
so comments are unsafe). Instead the build tool emits a committed, human-readable
Markdown atlas per variant (`tool/<variant>_opening_book_atlas.md`) with an ASCII
board for every oracle position and a metadata summary for every named opening.
It renders on GitHub and is regenerated alongside the JSON.

## Limitations and non-goals

- The book covers the **placing phase** only.
- Runtime **learning** (persisting `outcome_stats`, exploring new lines,
  adaptive opening swaps, novel auto-naming) is not implemented. `outcomeStats`
  is retained in the model, read-only, to support such a subsystem later.
- El Filja ships an oracle only; it has no curated named lines yet.

## Provenance

The curated named openings and the rich schema (`favoredSide`, `branchMoves`,
`recommendedResponses`, …) are derived from and inspired by Ben Brandwood's
NMM_LLM project. The move oracle is Sanmill's own engine-derived table.
