# Position API Documentation

## Overview

The `Position` class represents the complete state of a Mill game board at any given moment. It manages piece placement, game phase, move validation, mill detection, and game outcome determination. This is the core data structure for all game logic.

**Location**: `lib/game_page/services/engine/position.dart`

**Pattern**: Mutable state object (managed by GameController)

**Dependencies**: Rule settings, bitboard operations, move types

## Class Definition

```dart
class Position {
  Position();
}
```

## Key Responsibilities

1. **Board State Management**: Track all pieces on the board
2. **Phase Management**: Handle placing, moving, flying, and game-over phases
3. **Move Validation**: Determine legal moves for current player
4. **Mill Detection**: Identify when mills are formed
5. **Game Outcome**: Detect wins, losses, and draws
6. **FEN Conversion**: Import/export position as FEN string
7. **Undo/Redo**: Support history navigation

## Core Properties

### Board Representation

#### Board Array
```dart
final List<PieceColor> _board;
```
Internal board representation (32 squares for standard 9 men's morris)

**Squares are indexed 0-31** (varies by board type)

---

#### `pieceOnBoard(square)`
```dart
PieceColor pieceOnBoard(int square)
```

Get the piece color at a specific square.

**Parameters**:
- `square` (int): Square index (0-31)

**Returns**: `PieceColor` - `white`, `black`, or `none`

**Example**:
```dart
final piece = position.pieceOnBoard(10);
if (piece == PieceColor.white) {
  print('White piece at square 10');
}
```

---

#### `putPiece(square, piece)`
```dart
void putPiece(int square, PieceColor piece)
```

Place a piece on the board.

**Parameters**:
- `square` (int): Square index
- `piece` (PieceColor): Piece color to place

**Side Effects**:
- Updates board state
- Updates piece counts
- May trigger mill detection

**Example**:
```dart
position.putPiece(5, PieceColor.white);
```

---

#### `removePiece(square)`
```dart
void removePiece(int square)
```

Remove a piece from the board.

**Parameters**:
- `square` (int): Square index

**Side Effects**:
- Updates board state
- Updates piece counts
- May affect game phase

**Example**:
```dart
position.removePiece(15);
```

---

### Piece Counts

#### `pieceInHandCount`
```dart
final Map<PieceColor, int> pieceInHandCount;
```

Number of pieces each player has yet to place.

**Example**:
```dart
final whitePieces = position.pieceInHandCount[PieceColor.white];
print('White has $whitePieces pieces to place');
```

---

#### `pieceOnBoardCount`
```dart
final Map<PieceColor, int> pieceOnBoardCount;
```

Number of pieces each player currently has on the board.

**Example**:
```dart
final blackOnBoard = position.pieceOnBoardCount[PieceColor.black];
if (blackOnBoard < 3) {
  // Black has lost (fewer than 3 pieces)
}
```

---

#### `pieceToRemoveCount`
```dart
final Map<PieceColor, int> pieceToRemoveCount;
```

Number of opponent pieces the current player must remove (after forming mill).

**Example**:
```dart
if (position.pieceToRemoveCount[PieceColor.white]! > 0) {
  // White must remove a black piece
}
```

---

### Game State

#### `phase`
```dart
Phase phase;
```

Current game phase.

**Type**: `Phase` enum
- `Phase.placing`: Placing pieces on board
- `Phase.moving`: Moving pieces on board
- `Phase.flying`: Flying phase (less than flyPieceCount)
- `Phase.gameOver`: Game has ended

**Example**:
```dart
if (position.phase == Phase.placing) {
  // Show placement UI
} else if (position.phase == Phase.moving) {
  // Show move UI
}
```

---

#### `action`
```dart
Act action;
```

Current action expected from player.

**Type**: `Act` enum
- `Act.place`: Place a piece
- `Act.select`: Select a piece to move
- `Act.remove`: Remove opponent's piece

**Example**:
```dart
switch (position.action) {
  case Act.place:
    headerTip = 'Place a piece';
  case Act.select:
    headerTip = 'Select a piece';
  case Act.remove:
    headerTip = 'Remove opponent piece';
}
```

---

#### `sideToMove`
```dart
PieceColor get sideToMove => _sideToMove;
```

Current player to move.

**Returns**: `PieceColor` - `white` or `black`

**Example**:
```dart
if (position.sideToMove == PieceColor.white) {
  print("White's turn");
}
```

---

#### `them`
```dart
PieceColor get them => _them;
```

Opponent color.

**Returns**: `PieceColor`

---

#### `winner`
```dart
PieceColor winner;
```

Winner of the game (if game is over).

**Values**: `white`, `black`, `draw`, or `nobody`

---

#### `gameOverReason`
```dart
GameOverReason? gameOverReason;
```

Reason for game ending.

**Type**: `GameOverReason` enum
- `loseNoLegalMoves`: No legal moves available
- `loseTimeOut`: Time limit exceeded  
- `loseLessThanThree`: Fewer than 3 pieces
- `loseBoardIsFull`: Board full in placing phase
- `loseResign`: Player resigned
- `drawByRule`: Draw by rule
- And more...

---

### Score Tracking

#### `score`
```dart
static Map<PieceColor, int> score;
```

Game score across multiple games (session statistics).

**Example**:
```dart
print('Score: ${position.scoreString}');
// Output: "5 - 2 - 3" (White-Draw-Black)
```

---

#### `resetScore()`
```dart
static void resetScore()
```

Reset the score counters.

**Example**:
```dart
Position.resetScore();
```

---

## Move Operations

### `makeMove(move)`
```dart
bool makeMove(Move move)
```

Execute a move on the position.

**Parameters**:
- `move` (Move): The move to execute

**Returns**: `bool` - `true` if move was successful

**Side Effects**:
- Updates board state
- Changes turn (if appropriate)
- Detects mills
- Checks for game end
- Updates phase/action

**Example**:
```dart
final move = Move(from: 5, to: 10);
final success = position.makeMove(move);
if (success) {
  // Move executed
}
```

---

### `undoMove()`
```dart
void undoMove()
```

Undo the last move.

**Side Effects**:
- Reverts board state
- Restores previous turn
- Restores phase/action

**Example**:
```dart
position.undoMove();
```

---

### `isLegalMove(move)`
```dart
bool isLegalMove(Move move)
```

Check if a move is legal in current position.

**Parameters**:
- `move` (Move): The move to validate

**Returns**: `bool` - `true` if move is legal

**Example**:
```dart
if (position.isLegalMove(move)) {
  position.makeMove(move);
}
```

---

### `generateMoves()`
```dart
List<Move> generateMoves()
```

Generate all legal moves for current player.

**Returns**: `List<Move>` - All legal moves

**Example**:
```dart
final legalMoves = position.generateMoves();
print('${legalMoves.length} legal moves available');
```

**Performance**: O(n) where n is number of pieces

---

## Mill Detection

### `isInMill(square)`
```dart
bool isInMill(int square)
```

Check if a piece at given square is part of a mill.

**Parameters**:
- `square` (int): Square index

**Returns**: `bool` - `true` if square is in a mill

**Example**:
```dart
if (position.isInMill(10)) {
  // Piece at square 10 is protected (cannot be removed)
}
```

**Use Cases**:
- Determine which pieces can be removed
- Highlight mills on board
- Validate removal

---

### `millCount`
```dart
int get millCount
```

Total number of mills currently on the board.

**Returns**: `int`

---

## Game State Queries

### `hasGameResult`
```dart
bool get hasGameResult
```

Check if game has ended.

**Returns**: `bool` - `true` if phase is `gameOver`

**Example**:
```dart
if (position.hasGameResult) {
  showGameOverDialog(position.winner, position.gameOverReason);
}
```

---

### `isEmpty()`
```dart
bool isEmpty()
```

Check if board is empty (initial state).

**Returns**: `bool`

---

### `isNoDraw()`
```dart
bool isNoDraw()
```

Check if draw is not allowed (someone is winning).

**Returns**: `bool` - `true` if either side has positive score

---

### `pieceCountDiff()`
```dart
int pieceCountDiff()
```

Calculate piece count advantage.

**Returns**: `int` - Positive if White is ahead, negative if Black is ahead

**Example**:
```dart
final diff = position.pieceCountDiff();
if (diff > 0) {
  print('White is ahead by $diff pieces');
}
```

---

## FEN Operations

### `fen`
```dart
String? get fen
```

Export current position as FEN (Forsyth-Edwards Notation) string.

**Returns**: `String?` - FEN string or `null` if cannot generate

**FEN Format**:
```
<board> <turn> <phase> <action> <counts> <mills> [move50]
```

**Example**:
```dart
final fenString = position.fen;
print('Position FEN: $fenString');
// Can be saved, shared, or sent to engine
```

**Use Cases**:
- Save game state
- Send position to engine
- Share position
- Position setup

---

### `setFen(fen)`
```dart
bool setFen(String fen)
```

Import position from FEN string.

**Parameters**:
- `fen` (String): FEN string to import

**Returns**: `bool` - `true` if successfully imported

**Side Effects**:
- Replaces entire board state
- Sets phase, turn, counts
- Validates FEN format

**Example**:
```dart
const savedFen = 'xxxxx...';
if (position.setFen(savedFen)) {
  print('Position loaded');
} else {
  print('Invalid FEN');
}
```

**Use Cases**:
- Load saved game
- Set up custom position
- Network game synchronization

---

## Advanced Features

### Custodian and Intervention Capture

The Position class supports advanced capture rules:

#### Custodian Capture
Capturing by surrounding (specific rule variants)

#### Intervention Capture
Capturing by blocking (specific rule variants)

These are automatically handled by the Position class based on rule settings.

---

### Rule Compliance

Position respects all rule settings from `DB().ruleSettings`:
- Number of pieces (9, 10, 12)
- Diagonal lines enabled/disabled
- Flying rule threshold
- Move during placing phase
- Time limits
- Draw conditions

**Example**:
```dart
final rules = DB().ruleSettings;
if (rules.piecesCount == 12) {
  // Position handles 12 men's morris
}
```

---

## Usage Patterns

### Pattern 1: Check Move Legality

```dart
// Validate before executing
final move = Move(from: square1, to: square2);

if (position.isLegalMove(move)) {
  final success = position.makeMove(move);
  if (success) {
    // Update UI
  }
} else {
  // Show error
  SnackBarService.showRootSnackBar('Illegal move');
}
```

### Pattern 2: Get All Legal Moves

```dart
// For AI or hint feature
final legalMoves = position.generateMoves();

if (legalMoves.isEmpty) {
  // No legal moves - game over
  position.checkGameEnd();
} else {
  // Show possible moves
  for (final move in legalMoves) {
    highlightSquare(move.to);
  }
}
```

### Pattern 3: Detect Mill Formation

```dart
// After placing/moving a piece
if (position.action == Act.remove) {
  // Mill formed - must remove opponent piece
  headerTipNotifier.showTip('Remove opponent piece');
  
  // Check which pieces can be removed
  for (int sq = 0; sq < sqNumber; sq++) {
    if (position.pieceOnBoard(sq) == opponent) {
      if (!position.isInMill(sq)) {
        highlightRemovable(sq);
      }
    }
  }
}
```

### Pattern 4: Check Game End

```dart
// After each move
if (position.hasGameResult) {
  // Game ended
  final winner = position.winner;
  final reason = position.gameOverReason;
  
  // Update score
  if (winner == PieceColor.white) {
    Position.score[PieceColor.white] = 
      Position.score[PieceColor.white]! + 1;
  }
  
  // Show result
  showGameResultDialog(winner, reason);
}
```

### Pattern 5: Save and Restore Position

```dart
// Save current position
final savedFen = position.fen;
await saveToFile(savedFen);

// Later, restore position
final loadedFen = await loadFromFile();
if (position.setFen(loadedFen)) {
  // Position restored
  refreshUI();
}
```

### Pattern 6: Phase-Specific Logic

```dart
switch (position.phase) {
  case Phase.placing:
    // Show piece-in-hand count
    final count = position.pieceInHandCount[position.sideToMove];
    showPieceCount(count);
    
  case Phase.moving:
    // Normal move logic
    if (position.action == Act.select) {
      highlightPieces(position.sideToMove);
    }
    
  case Phase.flying:
    // Can move to any empty square
    showFlyingIndicator();
    
  case Phase.gameOver:
    // Show result
    showGameResult();
}
```

## Best Practices

### DO: Check Phase Before Operations

```dart
// ✅ CORRECT
if (position.phase == Phase.placing) {
  position.putPiece(square, piece);
}

// ❌ WRONG
position.putPiece(square, piece);  // May be wrong phase!
```

### DON'T: Modify Internal State Directly

```dart
// ❌ WRONG
position._board[5] = PieceColor.white;  // Private field

// ✅ CORRECT
position.putPiece(5, PieceColor.white);
```

### DO: Validate Moves

```dart
// ✅ CORRECT
if (position.isLegalMove(move)) {
  position.makeMove(move);
}

// ❌ WRONG
position.makeMove(move);  // May be illegal
```

### DO: Check Game End After Each Move

```dart
// ✅ CORRECT
position.makeMove(move);
if (position.hasGameResult) {
  handleGameEnd();
}
```

### DON'T: Assume Square Indices

```dart
// ❌ WRONG
for (int i = 0; i < 24; i++) {  // Wrong for 12 men's morris!
  // ...
}

// ✅ CORRECT
for (int i = 0; i < sqNumber; i++) {
  // sqNumber adapts to current board type
}
```

## Performance Considerations

### Move Generation
- Time: O(n) where n = pieces on board
- Space: O(m) where m = legal moves
- Typical: 5-30 legal moves per position

### Mill Detection
- Time: O(1) per square (precomputed mill lines)
- Cached during move execution

### FEN Conversion
- Time: O(n) where n = board size
- Space: O(1) (fixed string size)

## Related Components

- [GameController](GameController.md): Manages Position lifecycle
- [Engine](Engine.md): Analyzes Position via FEN
- [Move Types](../types/Move.md): Move representation
- [Rule Settings](../../rule_settings/models/rule_settings.dart): Rule configuration

## Version History

- **v7.0.0**: Added intervention and custodian capture
- **v6.0.0**: Added FEN import/export
- **v5.0.0**: Added 12 men's morris support
- **v4.0.0**: Optimized mill detection
- **v3.0.0**: Initial Position class

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

