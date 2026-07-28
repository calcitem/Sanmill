# Human Replay Index

## Purpose

The Human Replay Index is an anonymised SQLite sidecar for the HumanDB raw
game corpus. HumanDB is deliberately organised around aggregate positions
and move frequencies; it does not retain enough ordered history to reproduce
an individual game prefix. The sidecar supplies that missing link.

Its principal use in Sanmill is reverse puzzle mining:

1. HumanDB identifies a position that was theoretically won and a recorded
   human turn that may have surrendered that win.
2. The replay index locates the source game and reconstructs every preceding
   logical turn.
3. The production Rust/TGF rules replay the history and recorded turn.
4. Perfect DB independently proves the root and child W/D/L values and the
   distance.
5. Publication filters assess solution branching, theme clarity, duplication
   and curriculum balance.

HumanDB annotations are therefore candidate priors, not mathematical proof.

## Versioned Tooling

The production builder is the `tgf mill replay-index` Rust command in
`crates/tgf-cli/src/mill_replay_index/`. It uses bounded parallel workers for
JSON parsing and D4 canonicalisation, with one batched SQLite writer.

The versioned query and candidate-package exporter is
`scripts/extract_human_game_puzzle_candidates.py`.

`scripts/build_human_replay_index.py` is retained as an independent Python
reference builder for small parity fixtures. It is not the recommended
full-corpus path; its purpose is to catch schema, SHA-256, D4 state-key or
notation-transform drift by producing a database that can be compared with
the Rust output.

Build a full index with:

```powershell
cargo run -p tgf-cli --release -- mill replay-index `
  --games-dir "I:\Mill_Training\NMM_LLM\data\human_games" `
  --out "I:\Mill_Training\NMM_LLM\data\human_replay_index.sqlite"
```

Useful builder options are:

| Option | Default | Meaning |
| --- | ---: | --- |
| `--workers` | Up to 8 logical CPUs | Parallel parsing/canonicalisation workers |
| `--files-per-batch` | 64 | Files returned to the SQLite writer per batch |
| `--progress-every` | 5,000 | Source-file progress interval |
| `--cache-mib` | 256 | SQLite build cache |
| `--max-files` | 0 | Smoke-test limit; `0` means the whole corpus |

The builder never overwrites an existing database, README or `.building`
file. It first builds under a `.building` suffix, verifies row counts and
`PRAGMA integrity_check`, computes the database SHA-256 and then publishes
the database.

## Co-located Build Record

Every completed database is accompanied by a same-directory document:

```text
human_replay_index.sqlite
human_replay_index.README.md
```

The generated README records the exact source root, UTC build time, schema
and state-key versions, source/file/turn counts, invalid and duplicate
records, database SHA-256, rebuild command and example query. It also embeds
the privacy and proof-boundary notes from this specification.

The repository document defines the maintained contract; the co-located
README identifies one concrete database build.

## Privacy Boundary

The raw records may contain player names, ratings and other source metadata.
The Rust deserialiser intentionally reads only:

- `source_type`;
- the ordered `moves` list;
- each move's `type`, `notation` and `board_fen_before`.

The index stores no player name, account identifier, rating, result or free
text. A game is referenced by:

- SHA-256 of its exact JSONL row;
- source path relative to the configured corpus root;
- one-based source line number.

The SHA-256 is evidence for maintainers who possess the corpus; it is not a
public player identifier.

## Schema Version 1

### `meta`

`meta` is a `WITHOUT ROWID` key/value table. Required keys are:

| Key | Meaning |
| --- | --- |
| `schema_version` | Replay schema version; currently `1` |
| `build_date` | UTC database build time |
| `source_root` | Absolute corpus root used by the builder |
| `source_file_count` | JSONL files inspected |
| `game_count` | Unique human-versus-human games stored |
| `turn_count` | Ordered logical turns stored |
| `indexed_root_count` | Turns with searchable HumanDB movement keys |
| `duplicate_game_records` | Exact source-row duplicates ignored |
| `invalid_game_records` | Malformed games skipped |
| `skipped_non_human_records` | Rows outside `human_vs_human` |
| `anonymised` | Must be `true` |
| `state_key_model` | Must be `sector-corrected-v1` |

### `games`

| Column | Type | Meaning |
| --- | --- | --- |
| `source_sha256` | `TEXT` | Exact source-row SHA-256; primary key |
| `source_file` | `TEXT` | Path relative to `source_root` |
| `source_line` | `INTEGER` | One-based JSONL line number |
| `logical_turn_count` | `INTEGER` | Complete logical turns in the game |

The table is `WITHOUT ROWID`.

### `turns`

| Column | Type | Meaning |
| --- | --- | --- |
| `source_sha256` | `TEXT` | Parent game |
| `logical_ply` | `INTEGER` | One-based complete-turn number |
| `notation` | `TEXT` | Recorded Sanmill full-turn notation |
| `canonical_notation` | `TEXT` | HumanDB D4-frame notation; `NULL` before movement |
| `board_fen` | `TEXT` | Compact position immediately before the turn |
| `state_key` | `TEXT` | HumanDB-compatible key; `NULL` before movement |
| `move_type` | `TEXT` | Source move type |
| `side_to_move` | `INTEGER` | `0` for White, `1` for Black |
| `placed_white` | `INTEGER` | White pieces placed so far |
| `placed_black` | `INTEGER` | Black pieces placed so far |
| `white_on_board` | `INTEGER` | Current White material |
| `black_on_board` | `INTEGER` | Current Black material |

The composite primary key is (`source_sha256`, `logical_ply`), and the table
is `WITHOUT ROWID`.

Secondary indexes are:

- `turns_by_state_and_move` on (`state_key`, `canonical_notation`) for the
  HumanDB join;
- `turns_by_material_and_ply` on (`logical_ply`, `white_on_board`,
  `black_on_board`) for movement-root filtering.

Both are partial indexes restricted to rows with a non-null `state_key`.
Opening turns remain available for replay but do not consume canonical
lookup-index space.

## Coordinate and Symmetry Contract

The raw compact board uses NMM_LLM's 24-point outer/middle/inner order.
`state_key` and `canonical_notation` use HumanDB's eight D4 transformations
and the `sector-corrected-v1` model implemented centrally by
`tgf-mill::human_db_codec`.

The ninth-to-sixteenth Sanmill presentation transforms apply the
outer/inner-ring swap. They are intentionally applied only when a candidate
puzzle is exported:

- the replay database stores one source orientation;
- the exporter chooses one deterministic pseudo-random transform from 16;
- Rust/TGF replays the transformed history;
- deduplication uses a canonical key across all 16 transforms.

Thus symmetry changes presentation without multiplying one source position
into several apparent puzzles.

## Distance Bands and Themes

The query layer supports separate HumanDB distance bands:

- `1–15`: short tactics and immediate conversions;
- `16–31`: medium plans;
- `32+`: strategic squeezes, blockade and immobilisation routes.

Distance is not itself a quality score. Longer candidates must still have a
clear instructional theme and a manageable exported strategy tree.
Immobilisation and blockade candidates must not be discarded merely because
their exact distance exceeds 15.

The extractor also applies the editorial collision policy by default. Roots
without replay provenance are rejected under ring-16 symmetry. If a
replay-backed root matches a recorded reference presentation, its
deterministic presentation is advanced until the raw board differs. These
checks supplement, rather than replace, the run-specific
`tgf puzzle-gen --exclude-fens` input containing the current Sanmill pack and
the remaining editorial reference roots. Published puzzle wording is derived
only from the independently certified position and solution evidence.

For example, query the medium band with:

```powershell
python scripts/extract_human_game_puzzle_candidates.py `
  --replay-index "I:\Mill_Training\NMM_LLM\data\human_replay_index.sqlite" `
  --human-db "I:\Mill_Training\NMM_LLM\data\backups\maintainer_upload_20260721\human_db.sqlite" `
  --out "out\puzzle-mining\human-replay-medium-candidates.json" `
  --min-annotated-dtw 16 `
  --max-annotated-dtw 31
```

Set `--max-annotated-dtw 0` for no upper bound.

## Example SQL Join

Attach the aggregate HumanDB as schema `human`, then query:

```sql
SELECT
    r.source_sha256,
    r.logical_ply,
    r.notation,
    p.malom_dtw,
    m.malom_wdl_after
FROM turns AS r
JOIN human.positions AS p
  ON p.state_key = r.state_key
JOIN human.moves AS m
  ON m.state_key = r.state_key
 AND m.notation = r.canonical_notation
WHERE p.malom_wdl = 'W'
  AND p.canonical_winning_move IS NOT NULL
  AND r.canonical_notation <> p.canonical_winning_move
  AND m.malom_wdl_after IN ('D', 'W');
```

The last condition means the aggregate annotation suggests that the recorded
turn changed a win into a draw or loss from the original player's
perspective. The puzzle generator must still confirm that interpretation
against the configured Perfect DB.

## Change Rules

Changes to any of the following require a schema/model review and tests:

- stored columns or privacy boundary;
- compact-board coordinate order;
- canonical symmetry or notation transform;
- logical-turn counting;
- source-row hashing;
- movement-root eligibility;
- generated README fields.

If a change makes an existing database ambiguous or unsafe to query, increase
`schema_version`. If only HumanDB coordinate semantics change, update
`state_key_model` and reject incompatible pairings explicitly.
