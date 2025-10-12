# Engine API Documentation

## Overview

The `Engine` class provides a Flutter interface to the C++ AI engine via platform channels using the UCI (Universal Chess Interface) protocol adapted for Mill games. It handles communication, configuration, and move generation for the AI opponent.

**Location**: `lib/game_page/services/engine/engine.dart`

**Pattern**: Service class (instantiated by GameController)

**Protocol**: UCI-like (adapted for Mill)

**Dependencies**: Native C++ engine (via MethodChannel), Platform APIs

## Class Definition

```dart
class Engine {
  Engine();
  
  static const MethodChannel _platform = MethodChannel(
    "com.calcitem.sanmill/engine",
  );
}
```

## Key Responsibilities

1. **Engine Lifecycle**: Start, stop, and manage engine process
2. **UCI Communication**: Send commands and receive responses
3. **Move Generation**: Request AI moves via search
4. **Engine Configuration**: Set options (difficulty, time limits, etc.)
5. **Perfect Database Integration**: Use endgame tablebases
6. **Analysis Mode**: Provide move evaluation and suggestions

## Public Methods

### Lifecycle Methods

#### `startup()`
```dart
Future<void> startup() async
```

Initialize the AI engine and wait for ready signal.

**Returns**: `Future<void>`

**Side Effects**:
- Sends "uci" command to engine
- Configures engine options
- Waits for "uciok" response
- Engine becomes ready for use

**Example**:
```dart
final engine = Engine();
await engine.startup();
// Engine is now ready
```

**Use Cases**:
- Application startup
- Starting a new game
- Reinitializing engine after crash

**Errors**:
- Throws if engine fails to respond
- Throws if platform channel unavailable (web)

---

#### `shutdown()`
```dart
Future<void> shutdown() async
```

Shut down the AI engine and release resources.

**Returns**: `Future<void>`

**Side Effects**:
- Stops any ongoing search
- Closes engine process
- Releases native resources

**Example**:
```dart
await engine.shutdown();
```

**Important**: Always call this when disposing GameController

**Use Cases**:
- Application exit
- Game disposal
- Engine restart

---

### Search Methods

#### `search()`
```dart
Future<EngineRet> search({bool moveNow = false}) async
```

Request the engine to analyze the current position and return the best move.

**Parameters**:
- `moveNow` (bool, optional): Force immediate move response. Default: `false`

**Returns**: `Future<EngineRet>` containing:
  - `move`: The best move found
  - `value`: Position evaluation score
  - `type`: Move type (AI, perfect database, opening book)
  - `response`: Raw engine response string

**Side Effects**:
- Sends position FEN to engine
- Starts engine search
- Clears analysis mode annotations
- May save FEN for debugging (if enabled)

**Example**:
```dart
final result = await engine.search();
print('Best move: ${result.move}');
print('Evaluation: ${result.value}');
print('Source: ${result.type}');
```

**Use Cases**:
- AI turn in Human vs AI mode
- Get move suggestion in analysis mode
- AI vs AI continuous play

**Errors**:
- Throws `EngineNoBestMove` if position has no FEN
- Throws if engine is not running
- Throws if search times out

**Performance**: Search time depends on:
- Engine skill level (1-20)
- Move time limit setting
- Position complexity
- Device capabilities

---

#### `stopSearching()`
```dart
Future<void> stopSearching() async
```

Stop the current search immediately.

**Returns**: `Future<void>`

**Side Effects**:
- Sends "stop" command to engine
- Waits for "bestmove" response
- Cancels ongoing search

**Example**:
```dart
// User requests move now
if (await engine.isThinking()) {
  await engine.stopSearching();
}
```

**Use Cases**:
- "Move Now" button
- Time limit exceeded
- Game interrupted

---

#### `isThinking()`
```dart
Future<bool> isThinking() async
```

Check if the engine is currently analyzing a position.

**Returns**: `Future<bool>` - `true` if engine is searching

**Example**:
```dart
if (await engine.isThinking()) {
  // Disable user input
  showThinkingIndicator();
}
```

**Use Cases**:
- UI state management
- Input validation
- Progress indicators

---

### Configuration Methods

#### `setOptions()`
```dart
Future<void> setOptions() async
```

Configure engine options based on current settings.

**Returns**: `Future<void>`

**Side Effects**:
- Reads settings from Database
- Sends multiple "setoption" commands
- Configures: skill level, move time, algorithm, etc.

**Configured Options**:
- `Skill Level`: AI difficulty (1-20)
- `Move Time`: Time limit per move (ms)
- `Algorithm`: Search algorithm (MCTS, Alpha-Beta, etc.)
- `Perfect Database`: Enable/disable endgame tables
- `Depth Limit`: Maximum search depth
- `Draw On Human Experience`: Auto-draw settings
- And many more...

**Example**:
```dart
// Update settings
DB().generalSettings = settings.copyWith(aiLevel: 15);

// Apply to engine
await engine.setOptions();
```

**Use Cases**:
- Settings change
- Difficulty adjustment
- Engine initialization

---

#### `setSkillLevel()`
```dart
Future<void> setSkillLevel() async
```

Update only the skill level option.

**Returns**: `Future<void>`

**Example**:
```dart
DB().generalSettings = settings.copyWith(aiLevel: 10);
await engine.setSkillLevel();
```

**Use Cases**:
- Quick difficulty change
- Auto-adjust difficulty feature
- Testing different strengths

---

#### `setMoveTime()`
```dart
Future<void> setMoveTime() async
```

Update the move time limit.

**Returns**: `Future<void>`

**Example**:
```dart
DB().ruleSettings = settings.copyWith(moveTime: 5000);
await engine.setMoveTime();
```

---

### Analysis Methods

#### `getBestMove()`
```dart
Future<String?> getBestMove({bool moveNow = false}) async
```

Get the best move without executing it (for analysis).

**Parameters**:
- `moveNow` (bool, optional): Force immediate response. Default: `false`

**Returns**: `Future<String?>` - Move string or `null`

**Example**:
```dart
final bestMove = await engine.getBestMove();
// Show hint: "Best move is: $bestMove"
```

**Use Cases**:
- Hint feature
- Analysis mode
- Move comparison

---

#### `getEngineEvaluation()`
```dart
Future<int?> getEngineEvaluation() async
```

Get the engine's evaluation of current position.

**Returns**: `Future<int?>` - Evaluation score (centipawns) or `null`

**Score Interpretation**:
- Positive: Advantage for side to move
- Negative: Disadvantage for side to move
- ~0: Equal position
- ±1000+: Winning/losing position

**Example**:
```dart
final eval = await engine.getEngineEvaluation();
if (eval != null) {
  print('Position evaluation: ${eval / 100} pawns');
}
```

**Use Cases**:
- Display evaluation bar
- Position analysis
- Training mode feedback

---

### Position Management

#### `position()`
```dart
Future<void> position() async
```

Send the current position to the engine.

**Returns**: `Future<void>`

**Side Effects**:
- Converts current Position to FEN
- Sends "position fen <fen>" command
- Engine updates internal board state

**Example**:
```dart
// After making a move
await engine.position();
await engine.search();
```

**Use Cases**:
- Before search
- Position setup
- Engine synchronization

---

## Engine Return Type

```dart
class EngineRet {
  const EngineRet({
    required this.move,
    this.value,
    required this.type,
    this.response,
  });
  
  final String move;          // Move string (e.g., "a1-b2")
  final int? value;           // Evaluation score
  final AiMoveType type;      // Source of move
  final String? response;     // Raw engine output
}
```

### AiMoveType Enum

```dart
enum AiMoveType {
  unknown,          // Unknown source
  ai,              // Generated by AI search
  openingBook,     // From opening book
  perfectDatabase, // From endgame tablebase
  drawByRule,      // Automatic draw
  resignByRule,    // Automatic resign
}
```

## Engine Exceptions

```dart
class EngineNoBestMove implements Exception {
  const EngineNoBestMove();
}
```

Thrown when engine cannot provide a move (invalid position, no legal moves, etc.)

## UCI Protocol Commands

The engine implements a UCI-like protocol:

| Command | Purpose | Example |
|---------|---------|---------|
| `uci` | Initialize engine | → `uci`<br>← `uciok` |
| `setoption name X value Y` | Set option | `setoption name Skill Level value 10` |
| `position fen <fen>` | Set position | `position fen <fen_string>` |
| `go` | Start search | `go` |
| `stop` | Stop search | `stop`<br>← `bestmove a1-b2` |
| `quit` | Shut down | `quit` |

## Engine Options Reference

### Skill Level (1-20)
Controls AI strength:
- 1-5: Beginner
- 6-10: Intermediate
- 11-15: Advanced
- 16-20: Expert

### Algorithm
Search algorithm selection:
- `MCTS`: Monte Carlo Tree Search
- `Alpha-Beta`: Alpha-Beta pruning
- `MTD(f)`: Memory-enhanced Test Driver
- `Random`: Random move selection

### Move Time (ms)
Time limit for each move:
- 0: Infinite (depth-limited)
- 100-30000: Milliseconds to think

### Perfect Database
Use endgame tablebases:
- `true`: Use perfect play database
- `false`: Search only

### Draw Settings
Automatic draw/resign conditions:
- `Draw On Human Experience`: Auto-accept draws
- `Resign If Most Lose`: Auto-resign lost positions
- `Resign Threshold`: Score threshold for resign

## Usage Patterns

### Pattern 1: Basic AI Move

```dart
// In GameController
Future<void> engineToGo() async {
  isEngineRunning = true;
  
  try {
    // Request AI move
    final result = await engine.search();
    
    // Execute the move
    final move = parseMove(result.move);
    await doMove(move);
    
    // Log move source
    logger.i('AI move: ${result.move} (${result.type})');
  } catch (e) {
    logger.e('Engine error: $e');
    headerTipNotifier.showTip('Engine error');
  } finally {
    isEngineRunning = false;
  }
}
```

### Pattern 2: Analysis Mode

```dart
// Get best move without playing
Future<void> showHint() async {
  final bestMove = await engine.getBestMove();
  final eval = await engine.getEngineEvaluation();
  
  if (bestMove != null) {
    headerTipNotifier.showTip(
      'Best move: $bestMove (eval: $eval)',
    );
    
    // Highlight suggested move
    annotationManager.addAnnotation(
      type: AnnotationType.arrow,
      data: bestMove,
      color: Colors.green,
    );
  }
}
```

### Pattern 3: Move Now

```dart
// Force immediate move
Future<void> moveNow() async {
  if (await engine.isThinking()) {
    // Stop current search and get immediate move
    final result = await engine.search(moveNow: true);
    await doMove(parseMove(result.move));
  }
}
```

### Pattern 4: Difficulty Adjustment

```dart
// Change difficulty mid-game
Future<void> changeDifficulty(int newLevel) async {
  // Update settings
  final settings = DB().generalSettings;
  DB().generalSettings = settings.copyWith(aiLevel: newLevel);
  
  // Apply to engine
  await engine.setSkillLevel();
  
  // Notify user
  headerTipNotifier.showTip('Difficulty: $newLevel');
}
```

### Pattern 5: Perfect Database Move

```dart
// Check if move is from perfect database
final result = await engine.search();

if (result.type == AiMoveType.perfectDatabase) {
  // This is a proven perfect move
  headerTipNotifier.showTip('Perfect move played');
} else if (result.type == AiMoveType.openingBook) {
  headerTipNotifier.showTip('Book move');
} else {
  // Normal AI search
  if (result.value != null) {
    headerTipNotifier.showTip('Eval: ${result.value}');
  }
}
```

## Best Practices

### DO: Check Platform Availability

```dart
// ✅ CORRECT: Engine checks platform internally
final result = await engine.search();

// Engine handles web gracefully (returns empty result)
```

### DON'T: Call Search While Thinking

```dart
// ❌ WRONG
await engine.search();
await engine.search();  // May interfere!

// ✅ CORRECT
if (!await engine.isThinking()) {
  await engine.search();
}
```

### DO: Handle Exceptions

```dart
// ✅ CORRECT
try {
  final result = await engine.search();
} on EngineNoBestMove {
  logger.w('No legal moves available');
  handleGameEnd();
} catch (e) {
  logger.e('Engine error: $e');
}
```

### DO: Update Options After Settings Change

```dart
// ✅ CORRECT
DB().generalSettings = newSettings;
await engine.setOptions();  // Apply to engine

// ❌ WRONG
DB().generalSettings = newSettings;
// Engine still uses old settings!
```

### DON'T: Forget to Shutdown

```dart
// ✅ CORRECT
@override
void dispose() {
  engine.shutdown();
  super.dispose();
}

// ❌ WRONG: Native resources leak
```

## Performance Considerations

### Search Time
- Skill Level 1-5: 10-100ms
- Skill Level 6-10: 100-500ms
- Skill Level 11-15: 500-2000ms
- Skill Level 16-20: 2000-10000ms

### Memory Usage
- Base: ~10 MB (engine process)
- Perfect Database: +50-200 MB
- Opening Book: +5-20 MB

### Threading
- Engine runs in separate native thread
- Platform channel marshals data to UI thread
- No blocking of UI

## Debugging

### Enable Engine Logging

```dart
// In engine.dart
Future<void> _send(String command) async {
  logger.t("$_logTag send: $command");  // Already enabled
  await _platform.invokeMethod("send", command);
}
```

### Save Search Positions

```dart
// Enable FEN saving for debugging
Future<void> search() async {
  // ...
  await _saveFenToFile(fen);  // Saves to app documents
  // ...
}
```

### Check Engine Response

```dart
final result = await engine.search();
logger.d('Engine response: ${result.response}');
logger.d('Move type: ${result.type}');
logger.d('Evaluation: ${result.value}');
```

## Platform-Specific Notes

### Android
- Engine compiled as native library (.so)
- Uses JNI bridge
- Full feature support

### iOS
- Engine compiled as framework
- Uses Objective-C bridge
- Full feature support

### Windows/macOS/Linux
- Engine compiled as executable
- Uses FFI or platform channel
- Full feature support

### Web
- Engine not available (no native code)
- Methods return empty/default values
- UI gracefully degrades

## Related Components

- [GameController](GameController.md): Primary engine consumer
- [Position](Position.md): Provides FEN for engine
- [EngineAI in C++](../../../../src/engine_controller.cpp): Native engine implementation
- [UCI Protocol](https://en.wikipedia.org/wiki/Universal_Chess_Interface): Protocol reference

## Version History

- **v7.0.0**: Added analysis mode evaluation
- **v6.0.0**: Perfect database integration
- **v5.0.0**: Opening book support
- **v4.0.0**: MCTS algorithm added
- **v3.0.0**: Initial UCI-like implementation

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

