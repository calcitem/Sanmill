# GameController API Documentation

## Overview

`GameController` is the central singleton class that manages all game-related state and coordinates game flow in the Sanmill Flutter application. It serves as the primary interface for all game operations, from starting a new game to making moves, managing AI interactions, and handling multiplayer sessions.

**Location**: `lib/game_page/services/controller/game_controller.dart`

**Pattern**: Singleton

**Dependencies**: Engine, Position, GameRecorder, various Notifiers, AnimationManager, AnnotationManager

## Class Definition

```dart
class GameController {
  factory GameController() => instance;
  GameController._();
  
  static GameController instance = GameController._();
}
```

## Key Responsibilities

1. **Game Lifecycle Management**: Initialize, start, pause, and dispose games
2. **Move Execution**: Handle user moves and AI moves
3. **State Coordination**: Manage position, history, and UI state
4. **Engine Communication**: Interface with C++ AI engine
5. **Network Coordination**: Handle LAN multiplayer
6. **Animation Management**: Coordinate visual feedback
7. **Accessibility**: Provide screen reader announcements

## Public Properties

### Game Objects

#### `gameInstance`
```dart
late Game gameInstance;
```
The current game configuration and mode.

**Type**: `Game`  
**Mutability**: Mutable reference  
**Usage**: Access game mode, players, timing settings

**Example**:
```dart
final controller = GameController();
controller.gameInstance.gameMode = GameMode.humanVsAi;
```

---

#### `position`
```dart
late Position position;
```
The current board position and game state.

**Type**: `Position`  
**Mutability**: Mutable reference  
**Usage**: Query board state, piece locations, game phase

**Example**:
```dart
final phase = controller.position.phase;
final piece = controller.position.pieceOnBoard(square);
```

---

#### `engine`
```dart
late Engine engine;
```
Interface to the C++ AI engine.

**Type**: `Engine`  
**Mutability**: Mutable reference  
**Usage**: Request AI moves, configure engine options

**Example**:
```dart
await controller.engine.search();
```

---

#### `gameRecorder`
```dart
late GameRecorder gameRecorder;
```
Records and manages move history.

**Type**: `GameRecorder`  
**Mutability**: Mutable reference  
**Usage**: Access move list, export/import games

**Example**:
```dart
final moves = controller.gameRecorder.moveList;
final pgn = controller.gameRecorder.toPGN();
```

---

### Notifiers

#### `headerTipNotifier`
```dart
final HeaderTipNotifier headerTipNotifier;
```
Displays messages to the user in the header area.

**Type**: `HeaderTipNotifier extends ValueNotifier<String>`  
**Usage**: Show game status, turn information, hints

**Example**:
```dart
controller.headerTipNotifier.showTip('Your turn!');

// In widget:
ValueListenableBuilder<String>(
  valueListenable: controller.headerTipNotifier,
  builder: (context, tip, _) => Text(tip),
)
```

---

#### `headerIconsNotifier`
```dart
final HeaderIconsNotifier headerIconsNotifier;
```
Updates player icons and piece counts in the header.

**Type**: `HeaderIconsNotifier`  
**Usage**: Refresh header display when game state changes

---

#### `gameResultNotifier`
```dart
final GameResultNotifier gameResultNotifier;
```
Notifies when game ends with result.

**Type**: `GameResultNotifier`  
**Usage**: Show game-over dialog, update statistics

**Example**:
```dart
controller.gameResultNotifier.value = GameResult(
  winner: PieceColor.white,
  reason: 'Mill formed',
);
```

---

#### `boardSemanticsNotifier`
```dart
final BoardSemanticsNotifier boardSemanticsNotifier;
```
Announces board state for screen readers.

**Type**: `BoardSemanticsNotifier`  
**Usage**: Accessibility support

**Example**:
```dart
controller.boardSemanticsNotifier.announce(
  'White piece placed at A1',
);
```

---

### State Flags

#### `isControllerReady`
```dart
bool isControllerReady = false;
```
Indicates whether the controller is fully initialized.

**Usage**: Check before performing game operations

---

#### `isControllerActive`
```dart
bool isControllerActive = false;
```
Indicates whether a game is currently in progress.

---

#### `isEngineRunning`
```dart
bool isEngineRunning = false;
```
Indicates whether the AI engine is currently thinking.

**Usage**: Disable user input while AI is computing

---

#### `isAnnotationMode`
```dart
bool isAnnotationMode = false;
```
Indicates whether annotation mode is active.

**Usage**: Enable drawing arrows and highlights on board

---

### Managers

#### `animationManager`
```dart
late AnimationManager animationManager;
```
Coordinates all game animations.

**Type**: `AnimationManager`  
**Usage**: Trigger piece move animations, capture effects

**Example**:
```dart
await controller.animationManager.animatePieceMove(
  from: sourceSquare,
  to: targetSquare,
  duration: const Duration(milliseconds: 300),
);
```

---

#### `annotationManager`
```dart
final AnnotationManager annotationManager;
```
Manages position annotations (arrows, highlights).

**Type**: `AnnotationManager`  
**Usage**: Add/remove board annotations for analysis

**Example**:
```dart
controller.annotationManager.addArrow(
  from: square1,
  to: square2,
  color: Colors.green,
);
```

---

## Public Methods

### Initialization

#### `engineToGo()`
```dart
Future<void> engineToGo({
  bool isContinueNextMove = false,
  bool isStartingFromBeginning = false,
}) async
```

Request the AI engine to calculate and execute a move.

**Parameters**:
- `isContinueNextMove` (bool, optional): Continue from current position. Default: `false`
- `isStartingFromBeginning` (bool, optional): Reset and start from beginning. Default: `false`

**Returns**: `Future<void>`

**Side Effects**:
- Sets `isEngineRunning = true`
- Calls `engine.search()`
- Executes AI move when received
- Updates UI via notifiers
- Sets `isEngineRunning = false`

**Example**:
```dart
await controller.engineToGo();
```

**Use Cases**:
- AI vs Human mode: trigger AI move
- AI vs AI mode: continuous play
- Analysis mode: get suggested move

---

### Game Lifecycle

#### `newGame()`
```dart
Future<void> newGame() async
```

Start a new game, resetting all state.

**Returns**: `Future<void>`

**Side Effects**:
- Resets position to initial state
- Clears move history
- Resets game timer
- Clears annotations
- Refreshes UI

**Example**:
```dart
await controller.newGame();
```

**Use Cases**:
- User clicks "New Game" button
- Starting a new game after completion
- Resetting after loading a game

---

#### `reset()`
```dart
void reset()
```

Reset the game state without starting a new game.

**Side Effects**:
- Clears position
- Resets recorder
- Clears notifiers

**Example**:
```dart
controller.reset();
```

---

#### `dispose()`
```dart
void dispose()
```

Clean up resources when game ends.

**Side Effects**:
- Stops engine
- Disposes notifiers
- Cancels subscriptions
- Releases resources
- Sets `isDisposed = true`

**Important**: Always call this when leaving game page

**Example**:
```dart
@override
void dispose() {
  GameController().dispose();
  super.dispose();
}
```

---

### Move Execution

#### `doMove()`
```dart
Future<void> doMove(Move move) async
```

Execute a move on the board.

**Parameters**:
- `move` (Move): The move to execute

**Returns**: `Future<void>`

**Side Effects**:
- Updates position
- Records move in history
- Plays sound effect
- Triggers animation
- Updates notifiers
- Checks for game end

**Example**:
```dart
final move = Move(from: square1, to: square2);
await controller.doMove(move);
```

**Use Cases**:
- User makes a move
- AI makes a move
- Replaying game from history
- Network opponent's move

---

#### `select()`
```dart
bool select(int square)
```

Select a piece or destination square.

**Parameters**:
- `square` (int): The square index (0-23)

**Returns**: `bool` - `true` if selection was successful

**Side Effects**:
- Updates selected square
- Highlights valid moves
- May execute move if destination selected

**Example**:
```dart
final success = controller.select(10);
if (success) {
  // Selection succeeded
}
```

**Use Cases**:
- User taps a piece
- User taps a destination
- Touch interaction handling

---

#### `place()`
```dart
bool place(int square)
```

Place a piece during the placing phase.

**Parameters**:
- `square` (int): The square index where to place

**Returns**: `bool` - `true` if placement was successful

**Example**:
```dart
final success = controller.place(5);
```

---

#### `remove()`
```dart
bool remove(int square)
```

Remove opponent's piece after forming a mill.

**Parameters**:
- `square` (int): The square index of piece to remove

**Returns**: `bool` - `true` if removal was successful

**Example**:
```dart
final success = controller.remove(15);
```

---

### History Navigation

#### `takeBack()`
```dart
Future<bool> takeBack({bool byButton = false}) async
```

Undo the last move.

**Parameters**:
- `byButton` (bool, optional): Whether triggered by UI button. Default: `false`

**Returns**: `Future<bool>` - `true` if undo was successful

**Side Effects**:
- Reverts position
- Removes from history
- Updates UI
- May request network approval in LAN mode

**Example**:
```dart
final success = await controller.takeBack(byButton: true);
if (success) {
  logger.i('Move undone');
}
```

**Use Cases**:
- User clicks "Undo" button
- Reviewing game history
- Network takeback request

---

#### `stepForward()`
```dart
void stepForward()
```

Step forward one move in history (redo).

**Side Effects**:
- Advances position by one move
- Updates UI

**Example**:
```dart
controller.stepForward();
```

---

#### `goToHistoryIndex()`
```dart
void goToHistoryIndex(int index)
```

Jump to a specific position in move history.

**Parameters**:
- `index` (int): The move index to jump to

**Example**:
```dart
controller.goToHistoryIndex(10);  // Go to position after move 10
```

---

### Game State Query

#### `isPositionSetup`
```dart
bool get isPositionSetup
```

Check if a custom position is set up.

**Returns**: `bool`

**Example**:
```dart
if (controller.isPositionSetup) {
  // Handle custom position
}
```

---

#### `clearPositionSetupFlag()`
```dart
void clearPositionSetupFlag()
```

Clear the position setup flag.

---

## Usage Patterns

### Pattern 1: Starting a New Human vs AI Game

```dart
// Get controller instance
final controller = GameController();

// Set game mode
controller.gameInstance.gameMode = GameMode.humanVsAi;

// Start new game
await controller.newGame();

// Listen for tips
ValueListenableBuilder<String>(
  valueListenable: controller.headerTipNotifier,
  builder: (context, tip, _) => Text(tip),
)

// If AI goes first
if (isAITurn) {
  await controller.engineToGo();
}
```

### Pattern 2: Handling User Move

```dart
// User taps a square
void onBoardTap(int square) {
  final controller = GameController();
  
  if (controller.isEngineRunning) {
    // Don't allow input while AI is thinking
    return;
  }
  
  // Try to select/place piece
  final success = controller.select(square);
  
  if (success && isAITurn) {
    // Trigger AI move
    controller.engineToGo();
  }
}
```

### Pattern 3: Undo/Redo

```dart
// Undo button
ElevatedButton(
  onPressed: () async {
    final success = await controller.takeBack(byButton: true);
    if (!success) {
      SnackBarService.showRootSnackBar('Cannot undo');
    }
  },
  child: const Text('Undo'),
)

// Redo button
ElevatedButton(
  onPressed: () {
    controller.stepForward();
  },
  child: const Text('Redo'),
)
```

### Pattern 4: Game End Handling

```dart
ValueListenableBuilder(
  valueListenable: controller.gameResultNotifier,
  builder: (context, result, _) {
    if (result != null) {
      // Show game over dialog
      showGameResultDialog(
        context: context,
        winner: result.winner,
        reason: result.reason,
      );
    }
    return const SizedBox.shrink();
  },
)
```

### Pattern 5: LAN Multiplayer

```dart
// Host game
final controller = GameController();
controller.gameInstance.gameMode = GameMode.humanVsLan;
controller.networkService = NetworkService();
await controller.networkService!.startServer();

// Receive opponent's move
controller.networkService!.onMoveReceived = (move) {
  controller.doMove(move);
};

// Send local move
await controller.doMove(move);
controller.networkService!.sendMove(move);
```

## Best Practices

### DO: Always Check isEngineRunning

```dart
// ✅ CORRECT
if (!controller.isEngineRunning) {
  controller.select(square);
}
```

### DON'T: Access Before Initialization

```dart
// ❌ WRONG
final controller = GameController();
controller.position.makeMove(move);  // May not be initialized!

// ✅ CORRECT
if (controller.isControllerReady) {
  controller.position.makeMove(move);
}
```

### DO: Use Notifiers for UI Updates

```dart
// ✅ CORRECT: Reactive UI
ValueListenableBuilder<String>(
  valueListenable: controller.headerTipNotifier,
  builder: (context, tip, _) => Text(tip),
)

// ❌ WRONG: Manual polling
Text(controller.headerTipNotifier.value)  // Won't update
```

### DO: Dispose Properly

```dart
// ✅ CORRECT
@override
void dispose() {
  if (!GameController().isDisposed) {
    GameController().dispose();
  }
  super.dispose();
}
```

### DON'T: Create Multiple Instances

```dart
// ❌ WRONG: Defeats singleton pattern
final controller1 = GameController();
final controller2 = GameController();
// These are the SAME instance (singleton)

// ✅ CORRECT: Acknowledge singleton
final controller = GameController();
// Use this instance throughout
```

## Thread Safety

The GameController is **not thread-safe**. All operations must be performed on the main UI thread. Async operations (like `engineToGo()`) are safe because they return to the main thread for UI updates.

## Testing

### Unit Testing

```dart
test('GameController starts new game', () async {
  final controller = GameController();
  await controller.newGame();
  
  expect(controller.position.phase, Phase.placing);
  expect(controller.gameRecorder.moveList, isEmpty);
});
```

### Widget Testing

```dart
testWidgets('GameController updates UI on move', (tester) async {
  final controller = GameController();
  
  await tester.pumpWidget(
    MaterialApp(
      home: ValueListenableBuilder<String>(
        valueListenable: controller.headerTipNotifier,
        builder: (context, tip, _) => Text(tip),
      ),
    ),
  );
  
  controller.headerTipNotifier.showTip('Test message');
  await tester.pump();
  
  expect(find.text('Test message'), findsOneWidget);
});
```

## Common Pitfalls

### 1. Not Checking Engine State

```dart
// ❌ WRONG: May execute while AI is thinking
controller.doMove(move);

// ✅ CORRECT
if (!controller.isEngineRunning) {
  await controller.doMove(move);
}
```

### 2. Forgetting to Dispose

```dart
// ❌ WRONG: Memory leak
// No disposal code

// ✅ CORRECT
@override
void dispose() {
  GameController().dispose();
  super.dispose();
}
```

### 3. Ignoring Async Nature

```dart
// ❌ WRONG: Not awaiting
controller.newGame();
controller.doMove(move);  // May execute before newGame completes!

// ✅ CORRECT
await controller.newGame();
await controller.doMove(move);
```

## Related Components

- [Engine](Engine.md): AI engine interface
- [Position](Position.md): Board state management
- [GameRecorder](GameRecorder.md): Move history
- [AnimationManager](../services/AnimationManager.md): Animation coordination
- [STATE_MANAGEMENT.md](../STATE_MANAGEMENT.md): State management patterns

## Version History

- **v7.0.0**: Added annotation mode support
- **v6.0.0**: Added LAN multiplayer support
- **v5.0.0**: Initial GameController design

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

