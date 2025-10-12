# Position API Documentation

## Overview

`Position` is the central class representing the Mill game board state. It uses bitboard representation for efficient piece tracking and provides methods for move execution, mill detection, and game state queries.

**Location**: `src/position.h`, `src/position.cpp`

**Pattern**: Value object with mutable state

**Dependencies**: Bitboard, Rule, MoveGen, Stack

## Class Definition

```cpp
class Position {
public:
    static void init();
    
    Position();
    ~Position();
    
    // FEN string input/output
    Position &set(const std::string &fenStr);
    std::string fen() const;
    
    // Position representation
    Piece piece_on(Square s) const;
    Color color_on(Square s) const;
    bool empty(Square s) const;
    template <PieceType Pt> int count(Color c) const;
    
    // Properties of moves
    bool legal(Move m) const;
    Piece moved_piece(Move m) const;
    
    // Doing and undoing moves
    void do_move(Move m);
    void undo_move(Sanmill::Stack<Position> &ss);
    
    // Accessing hash keys
    Key key() const noexcept;
    Key key_after(Move m) const;
    
    // Other properties
    Color side_to_move() const;
    int game_ply() const;
    bool has_game_cycle() const;
    bool has_repeated(Sanmill::Stack<Position> &ss) const;
    
    // Mill Game specific
    Square current_square() const;
    Phase get_phase() const;
    Action get_action() const;
    bool reset();
    bool start();
    bool resign(Color loser);
    void change_side_to_move();
    Color get_winner() const noexcept;
    int mills_count(Square s);
    int potential_mills_count(Square to, Color c, Square from = SQ_0);
    bool is_all_in_mills(Color c);
    
    // ... 60+ more methods
};
```

## Key Responsibilities

1. **Board State Management**: Track piece positions using bitboards
2. **Move Execution**: Apply and revert moves with full state preservation
3. **Mill Detection**: Identify three-in-a-row formations
4. **Game Phase Tracking**: Manage placing, moving, flying phases
5. **Legality Checking**: Validate move legality
6. **Game Ending Detection**: Recognize win/loss/draw conditions

## Core Methods

### Position Initialization

#### `Position()`
```cpp
Position();
```

Create a new position object with default initialization.

**Postconditions**:
- All squares empty
- Side to move: WHITE
- Phase: ready
- Piece counts: 0

**Example**:
```cpp
Position pos;
// pos is now in initial state
```

---

#### `set(fen)`
```cpp
Position &set(const std::string &fenStr);
```

Initialize position from FEN string.

**Parameters**:
- `fenStr`: FEN string in Mill format (see [FEN Format](#fen-format))

**Returns**: Reference to this position (for chaining)

**Side Effects**:
- Replaces entire board state
- Resets move history
- Clears cached values

**Example**:
```cpp
Position pos;
pos.set("********/********/********_w_0_0");  // Initial position
pos.set("***O****/********/O*******_b_0_5");  // Custom position
```

**Error Handling**: Invalid FEN results in unchanged position (fail-safe)

---

#### `fen()`
```cpp
std::string fen() const;
```

Export position to FEN string.

**Returns**: FEN string representing current position

**Use Cases**:
- Save game state
- Send position to engine
- Debug position representation

**Example**:
```cpp
Position pos;
pos.set("********/********/********_w_0_0");
std::string fen = pos.fen();
// fen == "********/********/********_w_0_0"
```

---

### Move Execution

#### `do_move(move)`
```cpp
void do_move(Move m);
```

Execute a move and update position state.

**Parameters**:
- `m`: Move to execute (must be legal)

**Preconditions**:
- `legal(m)` returns true
- Game not over

**Side Effects**:
- Updates piece positions
- Switches side to move
- Increments ply counter
- Updates hash key
- May change game phase
- May trigger game ending

**Performance**: **ULTRA-CRITICAL** - called ~500K times/second in search

**Example**:
```cpp
Position pos;
pos.set("startpos");

Move move = /* generate move */;
assert(pos.legal(move));

pos.do_move(move);
// Position now reflects move execution
```

**Important Notes**:
- No undo information stored in Position itself
- Use with `Sanmill::Stack<Position>` for undo capability
- Assumes move is legal (no validation in release builds)

---

#### `undo_move(stack)`
```cpp
void undo_move(Sanmill::Stack<Position> &ss);
```

Revert to previous position state.

**Parameters**:
- `ss`: Stack containing position history

**Preconditions**:
- Stack not empty
- Previous state exists

**Side Effects**:
- Restores previous board state
- Decrements ply counter
- Restores hash key

**Performance**: **CRITICAL** - called frequently in search

**Example**:
```cpp
Position pos;
Sanmill::Stack<Position> history;

// Save current state
history.push(pos);

// Make move
pos.do_move(move);

// Undo move
pos.undo_move(history);
// Position restored to previous state
```

---

### Position Queries

#### `piece_on(square)`
```cpp
Piece piece_on(Square s) const;
```

Get piece at given square.

**Parameters**:
- `s`: Square to query (0-23)

**Returns**: 
- `NO_PIECE`: Square is empty
- `W_PIECE`: White piece
- `B_PIECE`: Black piece
- `BAN_STONE`: Banned square

**Performance**: O(1) - bitboard lookup

**Example**:
```cpp
Position pos;
pos.set("***O****/********/O*******_b_0_5");

Piece p = pos.piece_on(SQ_A1);  // W_PIECE
p = pos.piece_on(SQ_D1);        // B_PIECE
p = pos.piece_on(SQ_E1);        // NO_PIECE
```

---

#### `color_on(square)`
```cpp
Color color_on(Square s) const;
```

Get color of piece at square.

**Parameters**:
- `s`: Square to query

**Returns**:
- `WHITE`: White piece
- `BLACK`: Black piece
- `NOBODY`: Empty or banned

**Example**:
```cpp
Color c = pos.color_on(SQ_A1);
if (c == WHITE) {
    // White piece at a1
}
```

---

#### `empty(square)`
```cpp
bool empty(Square s) const;
```

Check if square is empty.

**Parameters**:
- `s`: Square to check

**Returns**: true if square has no piece (excluding banned squares)

**Performance**: O(1) - bitboard test

**Example**:
```cpp
if (pos.empty(SQ_A1)) {
    // Can place piece here (in placing phase)
}
```

---

#### `count<PieceType>(color)`
```cpp
template <PieceType Pt>
int count(Color c) const;
```

Count pieces of given type and color.

**Template Parameters**:
- `Pt`: Piece type (ON_BOARD, IN_HAND, TOTAL)

**Parameters**:
- `c`: Color to count (WHITE or BLACK)

**Returns**: Number of pieces

**Example**:
```cpp
int whitePiecesOnBoard = pos.count<ON_BOARD>(WHITE);
int blackPiecesInHand = pos.count<IN_HAND>(BLACK);
int totalWhitePieces = pos.count<TOTAL>(WHITE);
```

---

### Move Validation

#### `legal(move)`
```cpp
bool legal(Move m) const;
```

Check if move is legal in current position.

**Parameters**:
- `m`: Move to validate

**Returns**: true if move is legal

**Validation Checks**:
1. Move format valid
2. Source square has piece of correct color (if applicable)
3. Destination square is empty
4. Move obeys phase rules (placing/moving/flying)
5. Remove target is opponent piece
6. Remove follows mill formation rules

**Performance**: **CRITICAL** - called frequently

**Example**:
```cpp
Move move = /* generated move */;

if (pos.legal(move)) {
    pos.do_move(move);
} else {
    // Handle illegal move
}
```

---

#### `moved_piece(move)`
```cpp
Piece moved_piece(Move m) const;
```

Get piece being moved.

**Parameters**:
- `m`: Move to query

**Returns**: Piece type being moved

**Example**:
```cpp
Piece piece = pos.moved_piece(move);
assert(piece == W_PIECE || piece == B_PIECE);
```

---

### Game State Queries

#### `side_to_move()`
```cpp
Color side_to_move() const;
```

Get color of player to move.

**Returns**: WHITE or BLACK

**Example**:
```cpp
if (pos.side_to_move() == WHITE) {
    // White's turn
}
```

---

#### `get_phase()`
```cpp
Phase get_phase() const;
```

Get current game phase.

**Returns**:
- `Phase::ready`: Game not started
- `Phase::placing`: Placing phase (pieces in hand)
- `Phase::moving`: Moving phase (all pieces placed)
- `Phase::gameOver`: Game ended

**Example**:
```cpp
switch (pos.get_phase()) {
    case Phase::placing:
        // Generate placing moves
        break;
    case Phase::moving:
        // Generate moving/flying moves
        break;
    case Phase::gameOver:
        // Game ended
        break;
}
```

---

#### `get_action()`
```cpp
Action get_action() const;
```

Get required action for current player.

**Returns**:
- `Action::none`: No action required
- `Action::select`: Must select piece to move
- `Action::place`: Must place piece
- `Action::remove`: Must remove opponent piece (after mill)

**Example**:
```cpp
if (pos.get_action() == Action::remove) {
    // Generate remove moves only
}
```

---

#### `game_ply()`
```cpp
int game_ply() const;
```

Get total number of plies (half-moves) played.

**Returns**: Ply count (0-based)

**Example**:
```cpp
int plies = pos.game_ply();
// plies == 0 at start, increases with each move
```

---

### Hash Keys

#### `key()`
```cpp
Key key() const noexcept;
```

Get Zobrist hash key for current position.

**Returns**: Hash key (32-bit or 64-bit depending on configuration)

**Use Cases**:
- Transposition table lookups
- Repetition detection
- Position comparison

**Example**:
```cpp
Key hash = pos.key();
if (transpositionTable.probe(hash)) {
    // Position found in cache
}
```

---

#### `key_after(move)`
```cpp
Key key_after(Move m) const;
```

Calculate hash key after making move (without actually making it).

**Parameters**:
- `m`: Move to simulate

**Returns**: Hash key that would result from move

**Use Cases**:
- Prefetch transposition table entries
- Speculative lookups

**Example**:
```cpp
Key futureKey = pos.key_after(move);
// Can use futureKey before actually making move
```

---

### Mill Detection

#### `mills_count(square)`
```cpp
int mills_count(Square s);
```

Count number of mills passing through given square.

**Parameters**:
- `s`: Square to check

**Returns**: Number of mills (0-2 typically)

**Use Cases**:
- Evaluate position (mills are valuable)
- Determine if piece can be removed (pieces in mills protected)

**Performance**: O(1) - uses precomputed mill tables

**Example**:
```cpp
int mills = pos.mills_count(SQ_D2);
if (mills > 0) {
    // Square is part of a mill
}
```

---

#### `potential_mills_count(to, color, from)`
```cpp
int potential_mills_count(Square to, Color c, Square from = SQ_0);
```

Count mills that would be formed by placing/moving piece.

**Parameters**:
- `to`: Destination square
- `c`: Color of piece
- `from`: Source square (SQ_0 for placing)

**Returns**: Number of mills formed (0-2)

**Use Cases**:
- Move ordering (prioritize mill-forming moves)
- Evaluation (potential mills valuable)

**Example**:
```cpp
int millsFormed = pos.potential_mills_count(SQ_D2, WHITE, SQ_D1);
if (millsFormed > 0) {
    // This move forms a mill
}
```

---

#### `is_all_in_mills(color)`
```cpp
bool is_all_in_mills(Color c);
```

Check if all pieces of given color are in mills.

**Parameters**:
- `c`: Color to check

**Returns**: true if all pieces protected by mills

**Use Cases**:
- Determine if can remove from mills (if all in mills, must remove from mill)
- Position evaluation

**Performance**: Called frequently, should be fast

**Example**:
```cpp
if (pos.is_all_in_mills(BLACK)) {
    // Can remove black piece even from mill
}
```

---

### Game Control

#### `reset()`
```cpp
bool reset();
```

Reset position to initial state.

**Returns**: true on success

**Side Effects**:
- Clears all pieces
- Sets side to move to WHITE
- Phase to ready
- Resets counters

**Example**:
```cpp
pos.reset();
// Position now in initial state
```

---

#### `start()`
```cpp
bool start();
```

Start the game (transition from ready to placing phase).

**Returns**: true on success

**Side Effects**:
- Sets phase to placing
- Initializes piece counts

**Example**:
```cpp
pos.reset();
pos.start();
assert(pos.get_phase() == Phase::placing);
```

---

#### `resign(loser)`
```cpp
bool resign(Color loser);
```

End game by resignation.

**Parameters**:
- `loser`: Color that resigns

**Returns**: true on success

**Side Effects**:
- Sets game over state
- Sets winner to opponent of loser

**Example**:
```cpp
pos.resign(WHITE);  // White resigns, Black wins
```

---

#### `change_side_to_move()`
```cpp
void change_side_to_move();
```

Switch side to move.

**Side Effects**:
- Swaps WHITE ↔ BLACK

**Use Cases**:
- Manual position setup
- Special rule handling

**Example**:
```cpp
pos.change_side_to_move();
// Side to move now switched
```

---

### Game Ending

#### `get_winner()`
```cpp
Color get_winner() const noexcept;
```

Get winner of game (if game over).

**Returns**:
- `WHITE`: White won
- `BLACK`: Black won
- `DRAW`: Game drawn
- `NOBODY`: Game not over

**Example**:
```cpp
if (pos.get_phase() == Phase::gameOver) {
    Color winner = pos.get_winner();
    if (winner == DRAW) {
        // Game drawn
    }
}
```

---

#### `check_if_game_is_over()`
```cpp
bool check_if_game_is_over();
```

Check and update game ending conditions.

**Returns**: true if game ended

**Side Effects**: May set game over state

**Checks**:
- Piece count < minimum (loser)
- No legal moves (loser)
- 50-move rule (draw)
- Repetition (draw)

**Example**:
```cpp
pos.do_move(move);
if (pos.check_if_game_is_over()) {
    // Game ended
}
```

---

### Repetition Detection

#### `has_game_cycle()`
```cpp
bool has_game_cycle() const;
```

Check if position is in a cycle (repetition).

**Returns**: true if position repeated

**Use Cases**:
- Draw detection
- Three-fold repetition rule

**Example**:
```cpp
if (pos.has_game_cycle()) {
    // Position repeated, may claim draw
}
```

---

#### `has_repeated(stack)`
```cpp
bool has_repeated(Sanmill::Stack<Position> &ss) const;
```

Check if current position occurred before.

**Parameters**:
- `ss`: Position history stack

**Returns**: true if position repeated

**Algorithm**: Compare hash keys in history

**Example**:
```cpp
Sanmill::Stack<Position> history;
// ... play moves, pushing to history ...

if (pos.has_repeated(history)) {
    // Threefold repetition
}
```

---

## Data Structures

### Bitboards

Position uses bitboards for efficient piece tracking:

```cpp
private:
    Bitboard byTypeBB[PIECE_TYPE_NB];  // Pieces by type
    Bitboard byColorBB[COLOR_NB];      // Pieces by color
```

**Bit Layout**:
```
Bit:  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23
Sq:  a1 b1 c1 d1 e1 f1 g1 h1 a2 b2 c2 d2 e2 f2 g2 h2 a3 b3 c3 d3 e3 f3 g3 h3
```

---

### State Information

```cpp
private:
    Color sideToMove;                  // Current player
    Phase phase;                       // Game phase
    Action action;                     // Required action
    int gamePly;                       // Total plies
    Square currentSquare;              // Last move square
    Piece board[SQUARE_NB];           // Piece array (parallel to bitboards)
    // ... more state fields
```

---

## FEN Format

### Structure

```
<pieces>_<side>_<rule50>_<ply>
```

### Example

```
********/********/********_w_0_0
```

**Fields**:
1. **Pieces** (3 rows, `/` separated):
   - `*`: White piece
   - `O`: Black piece
   - Empty: space or no character
   - `@`: Banned square

2. **Side**: `w` (white) or `b` (black)

3. **Rule50**: Plies since last capture

4. **Ply**: Total plies played

---

## Performance Characteristics

### Time Complexity

- `do_move()`: O(1) - bitboard operations
- `undo_move()`: O(1) - state restoration
- `legal()`: O(1) - bitboard checks
- `mills_count()`: O(1) - precomputed tables
- `is_all_in_mills()`: O(1) - bitboard check

### Space Complexity

- Per Position: ~200 bytes
  - Bitboards: 12 bytes
  - State: ~50 bytes
  - History: ~138 bytes

---

## Usage Patterns

### Standard Game Flow

```cpp
Position pos;

// Initialize
pos.set("********/********/********_w_0_0");
pos.start();

// Game loop
while (pos.get_phase() != Phase::gameOver) {
    // Generate moves
    std::vector<Move> moves = generate_legal_moves(pos);
    
    // Select move (AI or user)
    Move move = selectMove(moves);
    
    // Execute
    assert(pos.legal(move));
    pos.do_move(move);
    
    // Check ending
    pos.check_if_game_is_over();
}

// Get result
Color winner = pos.get_winner();
```

---

### Search Integration

```cpp
Position pos;
Sanmill::Stack<Position> stack;

// Recursive search
Value search(Position &pos, int depth) {
    if (depth == 0 || pos.get_phase() == Phase::gameOver) {
        return evaluate(pos);
    }
    
    Value bestValue = -VALUE_INFINITE;
    
    for (Move move : generate_legal_moves(pos)) {
        // Save state
        stack.push(pos);
        
        // Make move
        pos.do_move(move);
        
        // Recurse
        Value value = -search(pos, depth - 1);
        
        // Undo move
        pos.undo_move(stack);
        
        // Update best
        bestValue = std::max(bestValue, value);
    }
    
    return bestValue;
}
```

---

## Thread Safety

**Not Thread-Safe**: Position objects should not be shared between threads

**Recommendation**: Each search thread should have its own Position copy

---

## Debugging

### Debug Output

```cpp
#ifdef DEBUG_MODE
pos.print();  // Print board state
debugPrintf("Position key: %llx\n", pos.key());
#endif
```

### Assertions

Position uses extensive assertions in debug builds:

```cpp
assert(is_ok());              // Consistency check
assert(legal(move));          // Move validation
assert(s >= SQ_A1 && s < SQ_NB);  // Bounds check
```

---

## Common Pitfalls

### 1. Forgetting to Check Legality

```cpp
// BAD: Assumes move is legal
pos.do_move(move);

// GOOD: Check first
if (pos.legal(move)) {
    pos.do_move(move);
}
```

### 2. Not Saving State for Undo

```cpp
// BAD: Can't undo
pos.do_move(move);
pos.undo_move(stack);  // Stack empty!

// GOOD: Save state
stack.push(pos);
pos.do_move(move);
pos.undo_move(stack);  // OK
```

### 3. Using Position After Game Over

```cpp
// BAD: Game over, moves illegal
if (pos.get_phase() == Phase::gameOver) {
    pos.do_move(move);  // Illegal!
}

// GOOD: Check phase
if (pos.get_phase() != Phase::gameOver) {
    pos.do_move(move);
}
```

---

## See Also

- [C++ Architecture](../CPP_ARCHITECTURE.md) - Overall engine architecture
- [Components](../CPP_COMPONENTS.md) - Component catalog
- [MoveGen API](MoveGen.md) - Move generation
- [Search API](Search.md) - Search algorithms

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

