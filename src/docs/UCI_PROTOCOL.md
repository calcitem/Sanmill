# UCI Protocol for Mill Games

## Overview

Sanmill implements a UCI-like (Universal Chess Interface) protocol adapted for Mill (Nine Men's Morris) games. This protocol enables communication between the game engine and GUI (Graphical User Interface) or other clients.

**Based on**: UCI Protocol for Chess (with Mill-specific extensions)  
**Communication**: Line-based text protocol via stdin/stdout  
**Encoding**: ASCII text  
**Line Endings**: Any standard (`\n`, `\r\n`, `\r`)

## Protocol Flow

```
GUI                          Engine
 |                              |
 |---- uci ------------------>  |
 |                              |
 |<--- id name Sanmill ---------|
 |<--- id author ... -----------|
 |<--- option ... --------------|
 |<--- uciok -------------------|
 |                              |
 |---- ucinewgame ------------> |
 |                              |
 |---- position ... ----------> |
 |                              |
 |---- go depth 8 ------------> |
 |                              |
 |<--- info ... ---------------|  (search progress)
 |<--- bestmove a1-b2 ---------|
 |                              |
 |---- quit ------------------> |
 X                              X
```

## Core Commands

### uci

**Purpose**: Initialize engine and request identification

**Syntax**:
```
uci
```

**Engine Response**:
```
id name Sanmill
id author Calcitem
option name Algorithm type spin default 2 min 0 max 4
option name SkillLevel type spin default 1 min 0 max 30
option name MoveTime type spin default 1 min 0 max 60
...
(more options)
...
uciok
```

**Response Fields**:
- `id name <name>`: Engine name
- `id author <author>`: Engine author(s)
- `option ...`: Engine options (see [Options](#engine-options))
- `uciok`: Signals end of identification

**Example**:
```
→ uci
← id name Sanmill
← id author Calcitem
← uciok
```

---

### isready

**Purpose**: Check if engine is ready for new commands

**Syntax**:
```
isready
```

**Engine Response**:
```
readyok
```

**Use Case**: Synchronization after heavy operations (ucinewgame, setoption)

**Example**:
```
→ isready
← readyok
```

---

### ucinewgame

**Purpose**: Signal start of a new game (clear internal state)

**Syntax**:
```
ucinewgame
```

**Engine Response**: (none - silent acknowledgment)

**Side Effects**:
- Clears transposition table
- Resets search state
- Clears move history
- Resets opening book state

**Example**:
```
→ ucinewgame
→ isready
← readyok
```

---

### position

**Purpose**: Set up the board position

**Syntax**:
```
position [startpos | fen <fenstring>] [moves <move1> <move2> ... <movei>]
```

**Parameters**:
- `startpos`: Use initial Mill position
- `fen <fenstring>`: Set position from FEN string (see [FEN Format](#fen-format))
- `moves <move1> ...`: Apply moves to position

**Examples**:
```
# Start position
→ position startpos

# Position with moves
→ position startpos moves a1 d1

# FEN position
→ position fen ********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 0

# FEN with moves
→ position fen ********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 0 moves a1 d1
```

**Engine Response**: (none - silent acknowledgment)

**Error Handling**: Invalid FEN or illegal moves ignored

---

### go

**Purpose**: Start searching for best move

**Syntax**:
```
go [searchmoves <move1> ... <movei>] 
   [depth <d>]
   [movetime <ms>]
   [infinite]
```

**Parameters**:
- `searchmoves <move1> ...`: Restrict search to these moves only
- `depth <d>`: Search to fixed depth (in plies)
- `movetime <ms>`: Search for exact time (milliseconds)
- `infinite`: Search until `stop` command

**Examples**:
```
# Search to depth 8
→ go depth 8

# Search for 5 seconds
→ go movetime 5000

# Search indefinitely
→ go infinite

# Search only specific moves
→ go searchmoves a1-b2 c3-d4 depth 6
```

**Engine Response** (eventually):
```
info depth 1 score cp 0 nodes 24 time 1 pv a1-b2
info depth 2 score cp 2 nodes 156 time 5 pv a1-b2 c3-d4
...
info depth 8 score cp 5 nodes 25436 time 245 pv a1-b2 c3-d4 e5-f6
bestmove a1-b2
```

**See Also**: [Info Output](#info-output), [Best Move](#best-move)

---

### stop

**Purpose**: Stop calculating and output best move found so far

**Syntax**:
```
stop
```

**Engine Response**:
```
bestmove <move>
```

**Example**:
```
→ go infinite
← info depth 5 ...
→ stop
← bestmove a1-b2
```

---

### setoption

**Purpose**: Configure engine options

**Syntax**:
```
setoption name <name> [value <value>]
```

**Parameters**:
- `name <name>`: Option name (case-sensitive)
- `value <value>`: Option value (omit for button options)

**Examples**:
```
# Set search algorithm
→ setoption name Algorithm value 2

# Set skill level
→ setoption name SkillLevel value 8

# Set move time
→ setoption name MoveTime value 2000

# Enable perfect database
→ setoption name PerfectDatabase value true
```

**Engine Response**: (none - silent acknowledgment)

**See Also**: [Engine Options](#engine-options)

---

### quit

**Purpose**: Quit the engine cleanly

**Syntax**:
```
quit
```

**Engine Response**: (engine terminates)

**Side Effects**:
- Stops any ongoing search
- Cleans up resources
- Exits process

**Example**:
```
→ quit
(engine exits)
```

---

## Engine Output

### Best Move

**Syntax**:
```
bestmove <move> [ponder <move>]
```

**Parameters**:
- `<move>`: Best move in algebraic notation (see [Move Notation](#move-notation))
- `ponder <move>`: Predicted opponent response (optional, not implemented)

**Examples**:
```
bestmove a1-b2
bestmove b2-c3
bestmove a1d4
bestmove -       (null move / no legal move)
```

**Special Cases**:
- `bestmove -`: No legal moves available (should not happen in normal play)

---

### Info Output

**Purpose**: Provide search progress information

**Syntax**:
```
info [depth <d>] [score <score>] [nodes <n>] [time <ms>] 
     [pv <move1> ... <movei>] [currmove <move>] [currmovenumber <n>]
```

**Parameters**:
- `depth <d>`: Current search depth (plies)
- `score <score>`: Evaluation score (see [Score Format](#score-format))
- `nodes <n>`: Nodes searched
- `time <ms>`: Time elapsed (milliseconds)
- `pv <move1> ...`: Principal variation (best line found)
- `currmove <move>`: Currently searching this move
- `currmovenumber <n>`: Move number being searched (1-indexed)

**Examples**:
```
info depth 1 score cp 0 nodes 24 time 1 pv a1-b2
info depth 5 score cp 3 nodes 5432 time 123 pv a1-b2 c3-d4 e5-f6
info depth 8 score cp 5 nodes 125678 time 1234 pv a1-b2 c3-d4 e5-f6 g7-a1
```

---

## Data Formats

### FEN Format

**Mill FEN Structure**:
```
<pieces> <side> <phase> <action> <wb_ob> <wb_ih> <bb_ob> <bb_ih> <remove_w> <remove_b> <mill_from_w> <mill_to_w> <mill_from_b> <mill_to_b> <mills_bitmask> <rule50> <fullmove>
```

**Important**: Fields are separated by **spaces** (not underscores).

**Components**:

1. **Pieces** (3 rows separated by `/`):
   - 24 characters representing squares (8 chars per row)
   - `O`: White piece (uppercase 'O')
   - `@`: Black piece
   - `*`: Empty square
   - `X`: Marked piece (for special rules)
   - Row order: Row 1 (a1-h1), Row 2 (a2-h2), Row 3 (a3-h3)

2. **Side to Move**:
   - `w`: White to move
   - `b`: Black to move

3. **Phase**:
   - `n`: None
   - `r`: Ready
   - `p`: Placing phase
   - `m`: Moving phase
   - `o`: Game over

4. **Action**:
   - `p`: Place piece
   - `s`: Select piece
   - `r`: Remove piece (after mill)
   - `?`: None/unknown

5. **White on Board**: Number of white pieces on the board (0-12)

6. **White in Hand**: Number of white pieces remaining to place (0-12)

7. **Black on Board**: Number of black pieces on the board (0-12)

8. **Black in Hand**: Number of black pieces remaining to place (0-12)

9. **White to Remove**: Number of white pieces that need to be removed (0-1)

10. **Black to Remove**: Number of black pieces that need to be removed (0-1)

11. **Last Mill From (White)**: Square number (0 = none)

12. **Last Mill To (White)**: Square number (0 = none)

13. **Last Mill From (Black)**: Square number (0 = none)

14. **Last Mill To (Black)**: Square number (0 = none)

15. **Mills Bitmask**: 64-bit value representing formed mills

16. **Rule 50 Counter**:
    - Number of plies since last piece removal
    - Used for draw detection
    - Range: 0-999

17. **Fullmove Number**:
    - Full move counter (increments after black's move)
    - Range: 0-999

**Standard Initial Position (9 Men's Morris)**:
```
********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 0
```

**Explanation**:
- `********/********/********`: All 24 squares empty
- `w`: White to move
- `p p`: Phase = placing, Action = place
- `0 9 0 9`: White 0 on board/9 in hand, Black 0 on board/9 in hand
- `0 0`: No pieces to remove
- `0 0 0 0`: No last mill squares
- `0`: No mills formed yet
- `0`: Rule50 counter = 0
- `0`: Starting position (fullmove 0)

**Example Positions**:
```
# White has placed 3 pieces (on a1, d1, g1), black has placed 2 (on a7, g7)
O**O**O*/********/O******@ w p p 3 6 2 7 0 0 0 0 0 0 0 0 3

# Midgame position
O*@*@@O*/***@****/O*@*@O** w m p 6 0 6 0 0 0 0 0 0 0 0 12 24

# After forming a mill, need to remove opponent piece
OOO***@*/********/@*****@* w p r 3 6 3 6 0 1 8 9 0 0 65536 0 5
```

**FEN Parsing Rules**:
- Fields are separated by spaces
- Rows in piece placement: 8 characters each
- Row order: Row 1 (bottom), Row 2 (middle), Row 3 (top)
- Case-sensitive piece characters
- All numeric fields are decimal integers

---

### Move Notation

**Algebraic Notation**:

**Square Labels**:
```
a3  b3  c3  d3  e3  f3  g3
a2  b2  c2  d2  e2  f2  g2
a1  b1  c1  d1  e1  f1  g1
```

**Move Types**:

1. **Place** (placing phase):
   ```
   <square>
   ```
   Examples: `a1`, `d2`, `g7`

2. **Move** (moving phase):
   ```
   <from>-<to>
   ```
   Examples: `a1-b2`, `d2-d3`, `a1-g1` (flying move, if allowed)

3. **Remove** (after mill):
   ```
   x<square>
   ```
   Examples: `xa3`, `xg7`, `xd1`

**Complete Examples**:
```
# Placing phase moves
a1       # Place piece on a1
d2       # Place piece on d2
g7       # Place piece on g7

# Moving phase moves
a1-b2    # Move piece from a1 to b2
d2-d3    # Move piece from d2 to d3
a1-g1    # Flying move from a1 to g1 (if flying allowed)

# Removal moves (after forming a mill)
xa3      # Remove opponent piece at a3
xg7      # Remove opponent piece at g7
```

**Special Notation**:
- Null move: `none` or `0000` (engine output only)
- Invalid move: (rejected silently or with error)

---

### Score Format

**Score Types**:

1. **Centipawns** (cp):
   ```
   score cp 5
   ```
   - Positive: Advantage for side to move
   - Negative: Disadvantage for side to move
   - **Note**: In Sanmill, score is scaled differently than Chess
   - Internally: 5 units = 1 piece value, displayed as "cp 1"

2. **Mate Score** (mate):
   ```
   score mate 5
   ```
   - Positive: Mate in N moves (side to move wins)
   - Negative: Mated in N moves (side to move loses)

**Example Scores**:
```
score cp 0        # Equal position
score cp 1        # Small advantage (~1/5 piece)
score cp 5        # Moderate advantage (~1 piece)
score cp -5       # Disadvantage (~1 piece down)
score mate 3      # Mate in 3 moves
score mate -5     # Mated in 5 moves
```

---

## Engine Options

### Algorithm

**Type**: Spin (integer)  
**Default**: 2  
**Range**: 0-4

**Values**:
- `0`: Alpha-Beta Pruning (best for tactical play)
- `1`: PVS (Principal Variation Search)
- `2`: MTD(f) (Memory-enhanced Test Driver, default, faster in some positions)
- `3`: MCTS (Monte Carlo Tree Search, good for complex positions)
- `4`: Random (for testing / weak opponent)

**Example**:
```
→ setoption name Algorithm value 2
```

---

### SkillLevel

**Type**: Spin (integer)  
**Default**: 1  
**Range**: 0-30

**Description**: Controls engine playing strength

**Levels**:
- `0-5`: Beginner (weak play, frequent mistakes)
- `6-15`: Intermediate (reasonable play)
- `16-25`: Advanced (strong play)
- `26-30`: Expert (maximum strength)

**Implementation**: Affects search depth and move selection randomness

**Example**:
```
→ setoption name SkillLevel value 8
```

---

### MoveTime

**Type**: Spin (integer)  
**Default**: 1  
**Range**: 0-60  
**Units**: Custom time units (approximately 640ms per unit)

**Description**: Time allocated per move (if not specified in `go` command)

**Note**: This value is internally converted to milliseconds using the formula:  
`actualTime = value * 10 * 64 + 10` (in milliseconds)

**Examples**:
```
→ setoption name MoveTime value 1     # ~650ms per move
→ setoption name MoveTime value 10    # ~6.4 seconds per move
→ setoption name MoveTime value 60    # ~38 seconds per move
```

---

### UsePerfectDatabase

**Type**: Check (boolean)  
**Default**: false  
**Values**: true / false

**Description**: Enable perfect play endgame databases

**Requirements**:
- Engine compiled with `GABOR_MALOM_PERFECT_AI`
- Database files available at configured path

**Example**:
```
→ setoption name UsePerfectDatabase value true
```

---

### DrawOnHumanExperience

**Type**: Check (boolean)  
**Default**: true  
**Values**: true / false

**Description**: Use human-like draw rules (e.g., 50-move rule, repetition)

**Example**:
```
→ setoption name DrawOnHumanExperience value true
```

---

### ConsiderMobility

**Type**: Check (boolean)  
**Default**: true  
**Values**: true / false

**Description**: Include mobility (number of legal moves) in evaluation

**Impact**: Positional vs tactical play

**Example**:
```
→ setoption name ConsiderMobility value true
```

---

### DeveloperMode

**Type**: Check (boolean)  
**Default**: true  
**Values**: true / false

**Description**: Enable developer/debug mode

**Side Effects**:
- Verbose logging
- Additional info output
- Performance profiling

**Example**:
```
→ setoption name DeveloperMode value false
```

---

### AiIsLazy

**Type**: Check (boolean)  
**Default**: false  
**Values**: true / false

**Description**: Reduce search depth when ahead

**Use Case**: Save computation when winning

**Example**:
```
→ setoption name AiIsLazy value false
```

---

### IDS (Iterative Deepening Search)

**Type**: Check (boolean)  
**Default**: true  
**Values**: true / false

**Description**: Enable iterative deepening search

**Benefits**:
- Better move ordering
- Anytime algorithm (can stop early)
- Time management

**Example**:
```
→ setoption name IDS value true
```

---

## Mill-Specific Extensions

### Phase Detection

Mill games have distinct phases:

1. **Placing Phase**: Players place pieces on empty squares
2. **Moving Phase**: Players move pieces to adjacent squares
3. **Flying Phase**: When a player has ≤ threshold pieces, can move anywhere

**FEN Encoding**: Phase implicitly determined from piece counts

**Move Generation**: Depends on current phase

---

### Mill Formation

When a player forms three-in-a-row:

1. Player may remove an opponent's piece
2. Preference: Remove pieces not in mills
3. If all opponent pieces in mills: May remove from mill (rule-dependent)

**Engine Handling**: Remove moves generated after mill-forming moves

---

### Game Ending Conditions

**Win Conditions**:
1. Opponent reduced to < 3 pieces (cannot form mills)
2. Opponent has no legal moves

**Draw Conditions**:
1. 50-move rule (no piece removal)
2. Three-fold repetition
3. Mutual agreement

**Engine Reporting**:
```
score mate 0      # Win detected
score mate -0     # Loss detected
score cp 0        # Potential draw
```

---

## Error Handling

### Invalid Commands

**Behavior**: Silently ignored (no error message)

**Example**:
```
→ invalid_command
(no response)
```

### Invalid FEN

**Behavior**: Use previous position or initial position

**Example**:
```
→ position fen invalid_fen_string
(position unchanged, no error)
```

### Illegal Moves

**Behavior**: Ignored, position unchanged

**Example**:
```
→ position startpos moves invalid_move
(move ignored)
```

### Option Errors

**Behavior**: Silently ignored, option unchanged

**Example**:
```
→ setoption name Algorithm value 999
(value out of range, option unchanged)
```

**Philosophy**: Robustness over strict error checking

---

## Performance Considerations

### Communication Overhead

- Line-based protocol: Low overhead
- Text parsing: Minimal CPU impact
- Buffered I/O: Efficient

### Search Interruption

**`stop` Command**:
- Checked periodically during search
- Clean interruption (no corruption)
- Returns best move found so far

**Implementation**:
```cpp
// Checked every ~1000 nodes
if (searchAborted.load(std::memory_order_relaxed)) {
    return currentBestValue;
}
```

### Info Output Throttling

**Strategy**: Limit info output frequency
- Minimum interval: ~100ms
- Prevents console spam
- Reduces GUI update overhead

---

## Debugging

### Verbose Mode

**Enable**: Developer Mode option

**Output**:
```
debug: Search starting at depth 8
debug: Node count: 1234, time: 100ms
debug: Best move found: a1-b2, score: +50
```

### Log File

**Location**: `sanmill_debug.log` (if enabled)

**Contents**:
- All UCI commands received
- All engine responses
- Internal debug messages
- Error messages

### Example Session

```
→ uci
← id name Sanmill
← id author Calcitem
← option name Algorithm type spin default 1 min 1 max 4
← option name SkillLevel type spin default 1 min 1 max 10
← uciok

→ isready
← readyok

→ ucinewgame

→ position startpos

→ go depth 6
← info depth 1 score cp 0 nodes 24 time 1 pv a1-b2
← info depth 2 score cp 1 nodes 156 time 8 pv a1-b2 c3-d4
← info depth 3 score cp 2 nodes 892 time 42 pv a1-b2 c3-d4 e5-f6
← info depth 4 score cp 3 nodes 3421 time 156 pv a1-b2 c3-d4 e5-f6 g7-a1
← info depth 5 score cp 4 nodes 12456 time 543 pv a1-b2 c3-d4 e5-f6 g7-a1 b2-c3
← info depth 6 score cp 5 nodes 45123 time 1823 pv a1-b2 c3-d4 e5-f6 g7-a1 b2-c3 d4-e5
← bestmove a1-b2

→ position startpos moves a1-b2 c3-d4

→ go movetime 2000
← info depth 1 score cp 1 nodes 22 time 1 pv e5-f6
← info depth 2 score cp 2 nodes 145 time 7 pv e5-f6 g7-a1
← ...
← bestmove e5-f6

→ stop
← bestmove e5-f6

→ quit
```

---

## Differences from Chess UCI

### Mill-Specific Additions

1. **FEN Format**: Adapted for Mill board (24 squares, 3 rows)
2. **Move Notation**: Simpler (no piece type, no capture notation)
3. **Phase Awareness**: Implicit in move generation
4. **Mill Formation**: Automatic remove move generation

### Unsupported Chess Features

- Castling (not in Mill)
- En passant (not in Mill)
- Promotion (not in Mill)
- Ponder mode (not implemented)
- Multi-PV search (not implemented)
- Tablebase probing (different format)

---

## Implementation Notes

### Thread Safety

- UCI loop: Single-threaded
- Search: Can be interrupted safely
- Options: Modified outside search only

### Memory Management

- No dynamic allocation in hot paths
- Stack-based position management
- Persistent transposition table

### Platform Compatibility

- Windows: Native support
- Linux/macOS: POSIX support
- Web: Not supported (use REST API instead)

---

## References

### External Standards

- UCI Protocol (Chess): http://wbec-ridderkerk.nl/html/UCIProtocol.html
- Mill Game Rules: https://en.wikipedia.org/wiki/Nine_men%27s_morris

### Internal Documentation

- [C++ Architecture](CPP_ARCHITECTURE.md) - Engine architecture
- [Components](CPP_COMPONENTS.md) - Component reference
- [API Documentation](api/) - Detailed API docs

---

**Maintainer**: Sanmill Development Team  
**Protocol Version**: UCI-like (Mill adaptation)  
**License**: GPL v3

