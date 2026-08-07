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
| `StrictFailurePolicy` | check | false | Fail closed on rejected histories or a missing/illegal search move |
| `StrictRefereeProfile` | combo | `sanmill-live-v1` | Use `mif-stable-moving-v1` for a portable MIF/NMM referee |
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

### Strict failure policy for machine clients

`StrictFailurePolicy` is an explicit UCI-only safety option. It defaults to
`false`, so Flutter/FRB play and historical UCI clients retain Sanmill's
legacy behavior. Enable it before the first `position` command when a bridge
must distinguish a real search result from recovery behavior:

```
setoption name StrictFailurePolicy value true
```

For a MIF `stable-moving-v1` referee, also select the portable profile before
loading the position:

```
setoption name StrictRefereeProfile value mif-stable-moving-v1
```

That profile counts an imported, ongoing, stable moving/flying origin as
repetition occurrence 1. It continues to clear the active repetition window
on placement and removal, never observes a pending-removal state, and treats
the required removal as part of the same logical turn. The default
`sanmill-live-v1` profile retains the historical post-move-only origin
behavior. Changing the profile clears the loaded position so the caller must
issue `position` again under the selected identity.

Geographical labels such as German, Hungarian, or English do not by
themselves select either behavior: a machine referee needs a versioned rule
authority/profile. MIF `stable-moving-v1` is unambiguously origin-counted.

Strict errors use one stable line format. The text after
`info string sanmill_error ` is compact JSON:

```
info string sanmill_error {"protocol_version":1,"status":"error","code":"search_missing_bestmove","command":"go","message":"the primary search returned no legal action for an ongoing position"}
```

For an ongoing position, Sanmill validates the primary configured search
result against the current Mill rules before consulting Perfect DB, patch
data, the legacy depth-4 recovery search, or random recovery. If the primary
result is missing or illegal, the engine:

1. emits `search_missing_bestmove` or `search_illegal_bestmove`;
2. stops that `go` operation;
3. emits no `bestmove`, `topn`, or fallback result.

The UCI process remains alive so the caller may submit a new valid position.
A strict bridge must therefore finish a pending `go` response when it sees
either a normal line containing `bestmove` or a `sanmill_error` line.

This policy prevents a failed primary search from being masked; it does not
rewrite an explicitly selected `Algorithm` or disable a configured database
or patch override after a *successful* primary search. A reproducible pure
MTD(f) client should also set `Algorithm=2`, `Shuffling=false`,
`UsePerfectDatabase=false`, `PatchAvoidTraps=false`, and
`PatchMakeTraps=false`. Strict sessions do not use lazy SMP, so one worker
cannot hide another worker's failure.

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

With `StrictFailurePolicy=true`, the whole command is transactional. Sanmill
rejects an invalid FEN, an empty `moves` tail, a malformed/truncated action
token, or an action that is not legal at its exact replay index. It does not
activate the successfully replayed prefix. Example:

```
→ position startpos moves a7 a7
← info string sanmill_error {"protocol_version":1,"status":"error","code":"position_history_illegal_action","command":"position","message":"history action 1 is not legal in its replay state","action_index":1,"token":"a7"}
```

`action_index` is zero-based. A following `go` is rejected with
`position_unavailable` and no `bestmove` until a valid `position` or
`ucinewgame` is supplied. A valid mill-forming primary action may leave the
state in pending removal; that is a complete atomic UCI action, not a
truncated history. The required `x<square>` remains the next action and both
actions still belong to one logical Mill turn.

When strict mode is off, the legacy parser remains unchanged: it reports an
invalid tail and keeps the successfully replayed prefix. Machine evaluation
clients should not rely on that compatibility behavior.

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

In strict mode, an ongoing position never reports `bestmove none` as a
recovery result. It reports `sanmill_error` and emits no `bestmove`. Terminal
positions retain the normal terminal/no-move representation.

For deterministic node-limited runs, disable the time limit and shuffling,
enable iterative deepening so the last completed iteration remains usable,
and provide both a depth ceiling and a node budget:

```
setoption name StrictFailurePolicy value true
setoption name MoveTimeMs value 0
setoption name IDSEnabled value true
setoption name Shuffling value false
setoption name SearchShuffleSeed value 7
go depth 12 nodes 256
```

### `go logical nodes N`

Formal evaluators that treat a move plus its mandatory removal as one action
should use the explicit logical-turn extension:

```
go logical nodes 500000
go logical nodes 500000 depth 12
```

This command requires `StrictFailurePolicy=true`, an explicit positive node
budget, and Algorithm 0, 1, or 2. It is a synchronous, single-threaded,
CLI-only cold path. Normal `go` and Flutter/FRB play do not call it.

The command searches only from a stable position with no pending removal. It
returns one protocol action for an ordinary placement, move, or flight, and
returns the primary action plus the required `x<square>` action when the
primary action forms a mill. The returned sequence is validated by the active
Sanmill rules and must:

- complete exactly one logical ply;
- switch the side to move or end the game;
- leave no pending removal.

Every search call shares one aggregate budget. Iterative-deepening passes,
the primary search, and any additional removal search are charged before the
next call receives the remaining budget. `total_nodes` never exceeds
`node_budget`. Normally the primary search already searched the removal and
the command reconstructs it from that search's TT/PV; in that case
`removal_nodes` is zero because those nodes are already included in
`primary_nodes`. A forced single legal removal requires no extra search.

The result is one compact, versioned JSON line and no legacy `bestmove` line:

```
info string sanmill_logical_turn {"protocol_version":1,"status":"ok","full_turn_actions":["d6-d5","xc3"],"logical_move_id":"d6-d5xc3","model_action":{"from":"d6","to":"d5","capture":"c3"},"logical_ply_delta":1,"resulting_fen":"...","resulting_side_to_move":"black","terminal":false,"winner":null,"winner_code":null,"outcome_reason":"ongoing","effective_depth":8,"completed_depth":8,"score_kind":"cp","score":11,"score_perspective":"white","node_budget":500000,"primary_nodes":11776,"removal_nodes":0,"total_nodes":11776,"search_calls":8}
```

`model_action` is the direct NMM_LLM `{from,to,capture}` representation.
`completed_depth` is the last fully completed primary IDS pass;
`effective_depth` is the requested/configured ceiling. The reported score is
from White's perspective. A terminal root returns `status: "terminal"`, no
actions, and zero consumed nodes.

`go logical` never consults Perfect DB or patch/trap data and never enters the
legacy depth-4 or random recovery chain. An invalid command, an unstable
root, an unsupported algorithm, or a budget that cannot produce a complete
legal turn emits `info string sanmill_error {...}` and no move. The command
does not mutate the UCI position; replay the returned actions in the next
`position` command, just as for normal UCI.

For cross-process reproducibility, use:

```
setoption name StrictFailurePolicy value true
setoption name Algorithm value 2
setoption name MoveTimeMs value 0
setoption name IDSEnabled value true
setoption name Shuffling value false
setoption name SearchShuffleSeed value 7
setoption name Threads value 1
```

With identical rule options, full action history, seed, depth ceiling, and
node budget, the JSON action sequence, node accounting, and resulting FEN are
stable across fresh processes.

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

Parse normal output by reading lines until you see `bestmove`. Lines that
start with `info topn rank` carry the ranked candidates; the final
`info depth` line carries the main search result. In a strict session,
`info string sanmill_error` also terminates the response and no `bestmove`
follows it.

Use case: Overseer training feature construction.  Instead of calling `go`
once per legal move (up to 24 round trips per position), a single
`go topn N movetime M` call returns all needed scores.

## `statejson` command

```
statejson
```

Returns a versioned snapshot of the exact position and history currently
owned by the UCI process. It is the machine-readable replacement for parsing
`d`, `fen`, `moves`, and `hist` debug text. An abbreviated response is:

```
info string sanmill_state {"protocol_version":1,"status":"ok","ruleset_id":"nmm","rules_identity":{"format_version":1,"sha256":"3e62cb93a1e0afe4534ce4824d233344816050b547bb8761dd7fe985d8ad399f"},"history_origin":"game_start","fen":"********/********/******** w p p 0 9 0 9 0 0 -1 -1 -1 -1 0 0 1 ids:nodes","side_to_move":"white","phase":"placing","action":"place","pending_removal":false,"pending_removal_count":0,"pending_removals":[0,0],"legal_actions":["d5","e5","..."],"action_token_count":0,"logical_ply_count":0,"logical_plies_by_side":[0,0],"no_capture_count":0,"repetition_current_count":0,"repetition_history_length":0,"snapshot_history_length":0,"history_sha256":"3399f97a1de994f4513ae6a7dabb0377392ddea95def7bceb242456d81444e09","terminal":false,"winner":null,"winner_code":null,"outcome_reason":"ongoing","outcome_reason_code":"ongoing"}
```

Protocol version 1 includes:

- the ruleset ID, complete serialized rule options, and a SHA-256 identity for
  those options;
- `strict_referee_identity`, which binds those options to the selected origin
  profile and reports its RFC 8785 `semanticDigest`;
- the authoritative FEN, side, phase, current atomic action, pending-removal
  count, and stable rule-order legal action list;
- atomic action count, logical-ply count and per-side counts;
- no-capture and repetition counters;
- snapshot/repetition history lengths and the same deterministic
  `sanmill.data-query.history.v1` SHA-256 used by `mill data-query`;
- terminal, winner, and raw plus stable-code termination reason fields.

`history_origin` is `game_start` for `position startpos` and `fresh_setup` for
an explicit FEN. Counts and the history digest cover the canonical action
tokens supplied after that origin. A mill-forming primary action therefore
increments `action_token_count` but not `logical_ply_count`; its removal
increments both the action count and the completed logical-ply count.

The strict-referee digest identifies Sanmill's complete option/profile
combination (`SANMILL-STRICT-REFEREE-RULES/1`). It is not an MRS document
digest and must not be substituted for the `semanticDigest` of a portable
ruleset manifest.

The command only reads the live state. It runs no search, database, patch, or
random code. Pending removal remains visible as such. Terminal positions use
`status: "terminal"` with an empty legal-action list. If strict parsing
rejected the most recent `position`, the response is
`status: "position_unavailable"` and deliberately omits the old FEN and state
fields until a valid position or `ucinewgame` is supplied.

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
| `crates/tgf-cli/src/mill_uci/mod.rs` | Main UCI loop and command dispatch |
| `crates/tgf-cli/src/mill_uci/board.rs` | `GoOptions`, `parse_go_options`, coordinate codec |
| `crates/tgf-cli/src/mill_uci/logical_turn.rs` | One-budget complete logical-turn search |
| `crates/tgf-cli/src/mill_uci/state_json.rs` | Versioned live-state JSON snapshot |
| `crates/tgf-cli/src/mill_uci/setoption.rs` | `setoption` parser |
| `crates/tgf-cli/tests/strict_uci.rs` | Cross-process strict-policy and fixed-node regressions |
| `crates/tgf-mill/src/rules/types.rs` | `MillEvalWeights`, `TGF_EVAL_WEIGHTS` format |
| `crates/tgf-frb/src/games/mill/human_db.rs` | Coordinate system, symmetry group (Python parity) |
