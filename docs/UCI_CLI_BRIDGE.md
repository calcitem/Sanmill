# Sanmill UCI CLI Bridge Reference

This document describes every interface in the `tgf mill uci` CLI that is
relevant to an external bridge adapter (such as a Python subprocess bridge
connecting the NMM_LLM Overseer to the Sanmill search engine).  All
communication is over the process stdin/stdout as line-delimited plain text.

## Starting the process

```
tgf mill uci
```

The executable is built with `cargo build --release -p tgf-cli` and lives at
`target/release/tgf` (Windows: `target/release/tgf.exe`).  Pass `mill uci` as
the first two arguments to enter the UCI loop.  The process stays alive until
you send `quit` or close stdin.

## Board coordinate system

The 24 squares use algebraic labels identical to those in the NMM_LLM code
base.  The board is three concentric squares connected by four spokes:

```
a7 --- d7 --- g7
|      |      |
| b6 - d6 - f6 |
| |    |    | |
| | c5-d5-e5 | |
a4-b4-c4   e4-f4-g4
| | c3-d3-e3 | |
| |    |    | |
| b2 - d2 - f2 |
|      |      |
a1 --- d1 --- g1
```

Outer ring  : a7 d7 g7 g4 g1 d1 a1 a4
Middle ring : b6 d6 f6 f4 f2 d2 b2 b4
Inner ring  : c5 d5 e5 e4 e3 d3 c3 c4

The middle-ring edge midpoints (b4 d2 d6 f4) are the four "central cardinal"
positions with four neighbours each; they are the most strategically valuable
squares per NMM_Strategy §4.2.

These labels are identical in both Sanmill and NMM_LLM (verified against
`crates/tgf-frb/src/games/mill/human_db.rs` and `ai/human_db.py`).

## Move notation

Sanmill uses a flat UCI move sequence.  Each UCI token represents one
*atomic action*; placing a piece that forms a mill requires two separate
tokens (the placement, then the capture).

| Situation | Token format | Example |
|---|---|---|
| Place a piece at a square | `<square>` | `d6` |
| Slide a piece from → to | `<from>-<to>` | `d6-d5` |
| Remove an opponent's piece | `x<square>` | `xb4` |
| Flying move (3 pieces) | same as slide, arbitrary distance | `c3-g7` |

A full game sequence passed to `position startpos moves` looks like:

```
position startpos moves d6 f4 d2 b4 g4 d7 a4 d1 xf4 f4 ...
```

In this example, `xf4` is a capture that follows a mill closure: the previous
move closed a mill and the next token removes the chosen opponent piece.

Draw by threefold repetition: when the engine detects a draw it returns
`bestmove draw`.  Handle this specially in the bridge; do not forward it to
the board as a move.

No legal move / game over: the engine returns `bestmove none` or
`bestmove 0000`.

## UCI handshake

```
→ uci
← id name TGF Mill Rust
← id author The Sanmill developers
← option name SkillLevel ...
← ... (see setoption table)
← uciok
```

After receiving `uciok` send `isready`:

```
→ isready
← readyok
```

The engine is now ready to accept positions and search commands.

## setoption reference

Send setoption commands before the first `go`.  Most options persist for the
life of the process; you do not need to resend them for every move.

### Engine strength

| Option | Type | Default | Notes |
|---|---|---|---|
| `SkillLevel` | spin 0..30 | 1 | Search depth cap; 30 = maximum (best strength) |
| `Algorithm` | spin 0..4 | 2 | 2 = MTD(f), recommended for strength; 0 = alpha-beta |
| `MoveTime` | spin 0..60 | 1 | Per-move thinking time in **seconds** (rounded) |
| `MoveTimeMs` | spin 0..60000 | 1000 | Per-move thinking time in **milliseconds** (Sanmill only) |
| `Shuffling` | check | true | Random tie-breaking; set false for deterministic output |
| `AiIsLazy` | check | false | When true, skips re-searching when score already good |
| `IDSEnabled` | check | false | Iterative deepening; auto-enabled when MoveTimeMs > 0 |

For bridge use set `MoveTimeMs` (not `MoveTime`) to avoid second-rounding.

Example configuration for fast training:

```
setoption name SkillLevel value 14
setoption name Algorithm value 2
setoption name MoveTimeMs value 200
setoption name Shuffling value false
```

Example configuration for high-quality advisory signal:

```
setoption name SkillLevel value 30
setoption name Algorithm value 2
setoption name MoveTimeMs value 1000
setoption name Shuffling value false
```

### Perfect database (optional, requires full 78 GB dataset)

| Option | Type | Default | Notes |
|---|---|---|---|
| `UsePerfectDatabase` | check | false | Enable Malom perfect-DB lookup after search |
| `PerfectDatabasePath` | string | (empty) | Directory containing `std_*.sec2` and `std.secval` |
| `PerfectDatabaseCacheSectors` | spin 0..1048576 | 0 | LRU sector cache capacity (0 = unbounded) |

Set `PerfectDatabasePath` before enabling `UsePerfectDatabase`:

```
setoption name PerfectDatabasePath value D:/user/Documents/strong
setoption name UsePerfectDatabase value true
```

When enabled, the engine uses the DB result for positions the DB covers and
falls back to search otherwise.  The engine still runs the full search first;
DB is a post-search override, not a replacement.

### Eval weights (tuned defaults)

The engine ships with H2H-validated tuned eval weights as its default.  You
can override them per session via the environment variable `TGF_EVAL_WEIGHTS`
(set before starting the process) or via setoption:

```
setoption name EvalWeights value 5,1,1,0,0,0,5,2,1,0,0,0,5,1,1,0,0,0,5,0,1,0,0,0
```

Format: 24 comma-separated integers, four six-value blocks for phases
placing / moving_open / pre_fly / flying.  Each block is
`piece_value, mobility, mill_count, position_value, cardinal_mill, near_fly_bonus`.
A 3-value form (`piece,mobility,mill_count`) applies the same weights to all
phases.  Omit the setoption entirely to use the validated TUNED default.

### Other options for bridge use

| Option | Notes |
|---|---|
| `DrawOnHumanExperience` | Keep true (default). Enables human-game draw heuristic. |
| `DeveloperMode` | Keep true (default) unless you need a production-clean output. |
| `ConsiderMobility` | Keep true (default). Mobility term in evaluator. |
| `ThreefoldRepetitionRule` | Keep true (default). Reports draws correctly. |
| `NMoveRule` | No-capture draw threshold (default 100 plies). |
| `EndgameNMoveRule` | Endgame no-capture draw threshold (default 100 plies). |

## position command

```
position startpos [moves <move1> <move2> ...]
position fen <fen-string> [moves <move1> <move2> ...]
```

`startpos` is the standard Nine Men's Morris opening position.  `fen` is the
Sanmill FEN format used internally (rarely needed; use `startpos moves` for
almost all bridge use cases).

The `moves` token is optional.  The list after it is the full game history as
UCI move tokens (see Move notation above).

```
position startpos moves d6 f4 d2 b4 g4 d7
```

Send `ucinewgame` before starting a new game to reset repetition history and
age the transposition table:

```
ucinewgame
position startpos moves ...
```

## go command

All subcommands are optional.  With no arguments, the engine uses the
configured `SkillLevel` depth and `MoveTimeMs` time limit.

```
go [movetime <ms>] [depth <N>] [nodes <N>] [infinite] [topn <N>]
```

| Token | Effect |
|---|---|
| `movetime <ms>` | Override thinking time for this move only (milliseconds) |
| `depth <N>` | Search exactly to depth N (overrides MoveTimeMs) |
| `nodes <N>` | Abort after this many nodes |
| `infinite` | Search until `stop` is received |
| `topn <N>` | Score all legal moves (see below) and emit top N before bestmove |

Normal output:

```
info depth 10 score cp 12 nodes 14832 bestmove d6
```

Score sign convention: positive = White ahead, negative = Black ahead.
This is always White-perspective regardless of which side is to move.

Mate scores: `score mate 3` means White mates in 3 half-moves from the
current position; `score mate -2` means Black mates in 2.  The mate boundary
is 80 centipawns (`VALUE_MATE = 80`); scores above 48 indicate a forced mate.

Draw output: `bestmove draw` (threefold repetition or n-move rule).  The
bridge must not forward this token to the game board.

No move: `bestmove none` (game is over or position is illegal).

### go topn N

```
go topn 5 movetime 500
```

Runs the full timed/depth search as usual to determine the best move.  After
the main search completes, performs a depth-2 sweep over all legal moves to
produce a ranked list.  Emits top N candidates before the bestmove line:

```
info topn rank 1 move d6 score cp 12
info topn rank 2 move f4 score cp  8
info topn rank 3 move d2 score cp  5
info topn rank 4 move g4 score cp  2
info topn rank 5 move d7 score cp  0
info depth 10 score cp 12 nodes 14832 bestmove d6
```

The `bestmove` is still determined by the main full-depth search (highest
quality).  The topn rankings come from the shallow sweep (sufficient for
relative ordering and feature construction).

All scores are White-perspective, matching the main search convention.

Parse the output by reading lines until you see `bestmove`.  Lines that start
with `info topn rank` carry the ranked candidates; the final `info depth`
line carries the main search result; `bestmove` terminates the response.

Use case: Overseer training feature construction.  Instead of calling `go`
once per legal move (up to 24 round trips per position), a single
`go topn N movetime M` call returns all needed scores.

## eval command

```
eval
```

Returns the static evaluation of the current position without running any
search.  Output:

```
info eval score cp N
info eval score mate N   (if position is in mate-distance range)
```

Score is White-perspective, same sign convention as `go`.

Use cases:
- Verifying that the coordinate mapping between the bridge and the engine is
  correct (static eval of a known position should match expectations).
- Batch feature extraction where search depth is not needed.
- Quick sanity check after sending a `position` command.

Example:

```
position startpos
eval
→ info eval score cp 0

position startpos moves d6 f4 d2
eval
→ info eval score cp 3
```

## stop command

```
stop
```

Aborts a running `go infinite` search and emits the best move found so far.
For timed searches (`go movetime N`) the engine stops automatically; `stop`
is not normally needed.

## quit command

```
quit
```

Gracefully terminates the process.  Always send `quit` before closing stdin to
avoid orphaned processes.

## d command (debug / human-readable board)

```
d
```

Prints an ASCII representation of the current board to stdout.  Useful for
debugging the bridge state mapping.  Output is informational and not parseable;
prefix all lines with `#` before passing them elsewhere.

## Example bridge session

A minimal Python bridge session for Overseer training:

```
→ uci
← id name TGF Mill Rust
← id author The Sanmill developers
← ... (option lines) ...
← uciok

→ isready
← readyok

→ setoption name SkillLevel value 14
→ setoption name Algorithm value 2
→ setoption name MoveTimeMs value 200
→ setoption name Shuffling value false

→ ucinewgame
→ position startpos moves d6 f4 d2 b4
→ go topn 5 movetime 200
← info topn rank 1 move g4 score cp 8
← info topn rank 2 move d7 score cp 6
← info topn rank 3 move a4 score cp 4
← info topn rank 4 move d1 score cp 2
← info topn rank 5 move g7 score cp 0
← info depth 8 score cp 8 nodes 9244 bestmove g4

→ position startpos moves d6 f4 d2 b4 g4
→ eval
← info eval score cp 5

→ quit
```

## Parity test cases for the bridge

Run these sanity checks before using the bridge in training to confirm that
position encoding, move notation, and side-to-move are all correct.

1. Initial position eval must be 0:
   `position startpos` / `eval` → `info eval score cp 0`

2. First bestmove must be a placement square:
   `position startpos` / `go depth 1` → `bestmove` token must be one of the
   24 square labels (a7 d7 g7 … c4).

3. Flying-phase move notation: after reducing one side to 3 pieces, the
   bestmove for that side must be a `from-to` pair where `from` and `to` are
   not adjacent (any empty square is reachable).

4. Draw detection: replay a known threefold-repetition sequence.  The engine
   must return `bestmove draw`, not a normal move.

5. topn count matches request: `go topn 5` must emit exactly min(5, legal_count)
   `info topn rank` lines.  At the start there are 24 legal placements, so
   `go topn 5` emits exactly 5 lines.

## Relevant source files

| File | Purpose |
|---|---|
| `crates/tgf-cli/src/mill_uci/mod.rs` | Main UCI loop, `eval`, `go topn` dispatch |
| `crates/tgf-cli/src/mill_uci/board.rs` | `GoOptions`, `parse_go_options`, coordinate codec |
| `crates/tgf-cli/src/mill_uci/setoption.rs` | `setoption` parser |
| `crates/tgf-mill/src/rules/types.rs` | `MillEvalWeights`, `TGF_EVAL_WEIGHTS` format |
| `crates/tgf-frb/src/games/mill/human_db.rs` | Coordinate system, symmetry group (Python parity) |
