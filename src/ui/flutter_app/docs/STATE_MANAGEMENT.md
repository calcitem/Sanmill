# State Management in Sanmill Flutter Application

## Overview

The Sanmill Flutter application uses a **hybrid state management approach** that combines:
1. **Hive** for persistent state (settings, preferences)
2. **ValueNotifier/ValueListenable** for reactive UI updates
3. **Singleton pattern** for global state (GameController, Database)

This document provides a comprehensive guide to understanding and working with state in the application.

## State Categories

The application manages four distinct categories of state:

| Category | Duration | Storage | Examples |
|----------|----------|---------|----------|
| **Persistent State** | Permanent | Hive database | Settings, game history, Elo ratings |
| **Game State** | Session | In-memory (GameController) | Current position, move history |
| **UI State** | Transient | ValueNotifier | Messages, animations, dialogs |
| **Platform State** | System-managed | Platform APIs | Window size, locale |

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    UI Layer                          │
│  ValueListenableBuilder → rebuilds on state change   │
└──────────────────────┬──────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│              State Notifiers Layer                   │
│  ValueNotifier<T> → emits state changes             │
└──────────────────────┬──────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│            Business Logic Layer                      │
│  GameController, Services → modify state            │
└──────────────────────┬──────────────────────────────┘
                       ↓
┌─────────────────────────────────────────────────────┐
│              Data Layer                              │
│  Database (Hive) → persist state                    │
│  Models → represent state                           │
└─────────────────────────────────────────────────────┘
```

## 1. Persistent State (Hive)

### Database Singleton

The `Database` class (aliased as `DB`) provides a single point of access to all persistent state:

```dart
// Access the database singleton
final db = DB();

// Read settings
final generalSettings = db.generalSettings;
final ruleSettings = db.ruleSettings;

// Update settings
db.generalSettings = generalSettings.copyWith(
  aiLevel: 15,
  isAutoRestart: true,
);
```

### Hive Box Structure

The application uses separate Hive boxes for different settings categories:

```dart
// Box Name                Type                 Key
generalSettingsBox    → GeneralSettings    → "settings"
ruleSettingsBox       → RuleSettings       → "settings"
displaySettingsBox    → DisplaySettings    → "settings"
colorSettingsBox      → ColorSettings      → "settings"
statsSettingsBox      → StatsSettings      → "settings"
customThemesBox       → dynamic            → "customThemes"
```

### Data Models

All persistent models follow these patterns:

#### 1. Immutability
Models are immutable and use `copyWith` for modifications:

```dart
@HiveType(typeId: 0)
class GeneralSettings {
  const GeneralSettings({
    this.aiLevel = 1,
    this.isAutoRestart = false,
    // ...
  });

  @HiveField(0)
  final int aiLevel;

  @HiveField(1)
  final bool isAutoRestart;

  // Create modified copy
  GeneralSettings copyWith({
    int? aiLevel,
    bool? isAutoRestart,
  }) {
    return GeneralSettings(
      aiLevel: aiLevel ?? this.aiLevel,
      isAutoRestart: isAutoRestart ?? this.isAutoRestart,
    );
  }
}
```

#### 2. Hive Serialization
Models use Hive type adapters for serialization:

```dart
@HiveType(typeId: 0)
class GeneralSettings {
  @HiveField(0)
  final int aiLevel;
  // Hive automatically serializes/deserializes
}
```

#### 3. Default Values
Models provide sensible defaults:

```dart
const GeneralSettings({
  this.aiLevel = 1,  // Easy by default
  this.isAutoRestart = false,  // Manual restart
  // ...
});
```

### Reading Persistent State

#### Synchronous Read
For immediate access:

```dart
final settings = DB().generalSettings;
final aiLevel = settings.aiLevel;
```

#### Reactive Read
For UI that updates when state changes:

```dart
ValueListenableBuilder<Box<GeneralSettings>>(
  valueListenable: DB().listenGeneralSettings,
  builder: (context, box, _) {
    final settings = box.get(
      DB.generalSettingsKey,
      defaultValue: const GeneralSettings(),
    )!;
    return Text('AI Level: ${settings.aiLevel}');
  },
)
```

### Writing Persistent State

Always use the immutable update pattern:

```dart
// ✅ CORRECT: Immutable update
final currentSettings = DB().generalSettings;
DB().generalSettings = currentSettings.copyWith(
  aiLevel: newLevel,
);

// ❌ WRONG: Cannot mutate fields
DB().generalSettings.aiLevel = newLevel;  // Compile error
```

### Database Migration

The application supports database migrations for schema changes:

```dart
// In database.dart
static Future<void> _migrateDatabase() async {
  final int currentVersion = _versionBox.get('version', defaultValue: 0)!;
  
  if (currentVersion < 1) {
    // Migrate to version 1
    _migrateToV1();
  }
  
  if (currentVersion < 2) {
    // Migrate to version 2
    _migrateToV2();
  }
  
  _versionBox.put('version', latestVersion);
}
```

## 2. Game State (GameController)

### Singleton Game Controller

The `GameController` is a singleton that manages all game-related state:

```dart
final controller = GameController();

// Access game state
final position = controller.position;       // Current board state
final engine = controller.engine;           // AI engine
final recorder = controller.gameRecorder;   // Move history

// Modify game state
await controller.newGame();
controller.doMove(move);
controller.takeBack();
```

### Game State Components

```dart
class GameController {
  // Game objects
  late Game gameInstance;         // Game configuration
  late Position position;         // Current board state
  late Engine engine;             // AI engine interface
  late GameRecorder gameRecorder; // Move history
  
  // State notifiers
  HeaderTipNotifier headerTipNotifier;
  HeaderIconsNotifier headerIconsNotifier;
  GameResultNotifier gameResultNotifier;
  BoardSemanticsNotifier boardSemanticsNotifier;
  
  // State flags
  bool isControllerReady = false;
  bool isEngineRunning = false;
  bool isAnnotationMode = false;
  
  // Managers
  late AnimationManager animationManager;
  AnnotationManager annotationManager;
}
```

### Game State Lifecycle

```
1. GameController() → Created (singleton)
           ↓
2. _init() → Initialize game objects
           ↓
3. isControllerReady = true
           ↓
4. gameInstance.start() → Start game
           ↓
5. [Game playing...]
           ↓
6. dispose() → Clean up (on game end)
```

### Position State

The `Position` class represents the complete board state:

```dart
class Position {
  // Board representation
  int pieceOnBoard(square);           // Get piece at square
  void putPiece(square, piece);       // Place piece
  void removePiece(square);           // Remove piece
  
  // Game state
  Phase phase;                        // PLACING, MOVING, FLYING
  int playerOnTurn;                   // Current player
  int action;                         // Current action type
  
  // Move validation
  bool isLegal(move);                 // Check move legality
  List<Move> generateMoves();         // Get all legal moves
  
  // Mill detection
  List<int> mills;                    // Current mills
  bool inCheck(player);               // Check if in check
}
```

### Making Moves

Moves flow through multiple layers:

```dart
// User action → TapHandler
onTap(square) {
  controller.select(square);  // Select piece
  controller.place(square);   // Place piece
}

// TapHandler → GameController
controller.select(square) {
  if (canSelect) {
    position.makeMove(move);
    gameRecorder.add(move);
    notifyListeners();
  }
}

// GameController → Position
position.makeMove(move) {
  // Update bitboards
  // Change turn
  // Update game state
}
```

## 3. UI State (Notifiers)

### ValueNotifier Pattern

For transient UI state, we use `ValueNotifier`:

```dart
class HeaderTipNotifier extends ValueNotifier<String> {
  HeaderTipNotifier() : super('');
  
  void showTip(String message) {
    value = message;
  }
  
  void clearTip() {
    value = '';
  }
}
```

### Key Notifiers

#### HeaderTipNotifier
**Purpose**: Display temporary messages to the user

```dart
// Update tip
controller.headerTipNotifier.showTip('Your turn!');

// Listen for changes
ValueListenableBuilder<String>(
  valueListenable: controller.headerTipNotifier,
  builder: (context, tip, _) => Text(tip),
)
```

#### HeaderIconsNotifier
**Purpose**: Update player icons (active player, piece counts)

```dart
class HeaderIconsData {
  final int player1Count;
  final int player2Count;
  final bool isPlayer1Turn;
}

controller.headerIconsNotifier.value = HeaderIconsData(...);
```

#### GameResultNotifier
**Purpose**: Notify when game ends

```dart
controller.gameResultNotifier.showResult(
  winner: player,
  reason: 'Mill formed',
);
```

#### BoardSemanticsNotifier
**Purpose**: Announce board state for screen readers

```dart
controller.boardSemanticsNotifier.announceBoardState(
  'White piece placed at A1',
);
```

### Creating Custom Notifiers

Follow this pattern for new notifiers:

```dart
class MyCustomNotifier extends ValueNotifier<MyDataType> {
  MyCustomNotifier() : super(MyDataType.initial());
  
  // Public methods to update state
  void updateData(MyDataType newData) {
    value = newData;
  }
  
  // Helper methods
  void reset() {
    value = MyDataType.initial();
  }
}
```

## 4. State Update Patterns

### Pattern 1: Direct Update (Persistent State)

For settings and preferences:

```dart
// Read
final currentSettings = DB().generalSettings;

// Modify
final updatedSettings = currentSettings.copyWith(
  aiLevel: newLevel,
);

// Write
DB().generalSettings = updatedSettings;

// UI automatically updates via ValueListenableBuilder
```

### Pattern 2: Notifier Update (Transient UI State)

For temporary UI state:

```dart
// Update
controller.headerTipNotifier.value = 'New message';

// Or use helper method
controller.headerTipNotifier.showTip('New message');

// UI rebuilds automatically
```

### Pattern 3: Controller Method (Game State)

For game actions:

```dart
// Call controller method
await controller.newGame();
controller.doMove(move);

// Controller updates internal state
// Controller notifies relevant notifiers
// UI rebuilds in response
```

### Pattern 4: Callback (Event-driven)

For one-time events:

```dart
// Pass callback to widget
GameBoard(
  onMoveComplete: (move) {
    // Handle move completion
  },
)

// Widget calls callback at appropriate time
onMoveComplete?.call(move);
```

## State Flow Examples

### Example 1: Changing AI Difficulty

```
User taps difficulty slider
        ↓
Slider onChange callback
        ↓
Read current settings:
  settings = DB().generalSettings
        ↓
Create updated settings:
  updated = settings.copyWith(aiLevel: newValue)
        ↓
Write to database:
  DB().generalSettings = updated
        ↓
ValueListenableBuilder detects change
        ↓
UI rebuilds with new value
        ↓
Engine receives new difficulty:
  engine.setOption('Skill Level', newValue)
```

### Example 2: Making a Move

```
User taps board square
        ↓
GameBoard onTap handler
        ↓
GameController.select(square)
        ↓
Position.makeMove(move)
  - Update bitboards
  - Change turn
  - Detect mills
        ↓
GameRecorder.add(move)
  - Record move notation
  - Update move list
        ↓
Update notifiers:
  - headerTipNotifier ← 'Black's turn'
  - headerIconsNotifier ← update piece counts
  - boardSemanticsNotifier ← 'Piece moved to...'
        ↓
ValueListenableBuilder rebuilds
        ↓
UI updates
  - Board redraws
  - Header updates
  - Screen reader announces
```

### Example 3: Loading Game from File

```
User selects 'Load Game'
        ↓
File picker dialog
        ↓
User selects file
        ↓
LoadService.loadGame(path)
  - Read file contents
  - Parse PGN notation
        ↓
Create new GameController
        ↓
GameController.setupPosition(fen)
  - Parse FEN string
  - Set up position
        ↓
GameController.replay(moves)
  - Play each move
  - Update position
        ↓
Navigate to GamePage
        ↓
UI displays loaded position
```

## Best Practices

### DO: Use Immutable Updates

```dart
// ✅ CORRECT
final updated = settings.copyWith(aiLevel: 5);
DB().generalSettings = updated;
```

### DON'T: Mutate State Directly

```dart
// ❌ WRONG
settings.aiLevel = 5;  // Won't compile (fields are final)
```

### DO: Dispose Resources

```dart
@override
void dispose() {
  _controller.dispose();
  _notifier.dispose();
  _subscription.cancel();
  super.dispose();
}
```

### DON'T: Forget to Cancel Subscriptions

```dart
// ❌ WRONG: Memory leak
StreamSubscription subscription = stream.listen(...);
// Never cancelled!
```

### DO: Use const Constructors

```dart
// ✅ CORRECT
const GeneralSettings();
const Text('Hello');
```

### DON'T: Create Unnecessary Objects

```dart
// ❌ WRONG
Text('Hello');  // New object every rebuild
```

### DO: Minimize Rebuild Scope

```dart
// ✅ CORRECT: Only Text rebuilds
ValueListenableBuilder<String>(
  valueListenable: notifier,
  builder: (context, value, child) {
    return Text(value);  // Only this rebuilds
  },
)
```

### DON'T: Rebuild Entire Widget Tree

```dart
// ❌ WRONG: Entire page rebuilds
setState(() {
  message = newMessage;
});
```

### DO: Use Type-Safe Access

```dart
// ✅ CORRECT
final settings = DB().generalSettings;
final level = settings.aiLevel;
```

### DON'T: Use Dynamic Types

```dart
// ❌ WRONG
dynamic settings = DB().generalSettings;
var level = settings.aiLevel;  // No type safety
```

## Performance Considerations

### 1. Minimize Rebuilds

Use `ValueListenableBuilder` to rebuild only affected widgets:

```dart
// Only the Text widget rebuilds when tip changes
ValueListenableBuilder<String>(
  valueListenable: controller.headerTipNotifier,
  builder: (context, tip, child) {
    return Text(tip);
  },
)
```

### 2. Use Keys for List Items

When displaying lists with state:

```dart
ListView.builder(
  itemCount: moves.length,
  itemBuilder: (context, index) {
    return MoveListItem(
      key: ValueKey(moves[index].id),  // Preserve state
      move: moves[index],
    );
  },
)
```

### 3. Avoid Unnecessary State

Don't store derived values:

```dart
// ❌ WRONG
class MyState {
  int count;
  int doubleCount;  // Derived from count
}

// ✅ CORRECT
class MyState {
  int count;
  int get doubleCount => count * 2;  // Computed property
}
```

### 4. Batch Updates

Combine multiple state updates:

```dart
// ✅ CORRECT: Single update
DB().generalSettings = settings.copyWith(
  aiLevel: 5,
  isAutoRestart: true,
  screenReaderSupport: true,
);

// ❌ WRONG: Multiple updates
DB().generalSettings = settings.copyWith(aiLevel: 5);
DB().generalSettings = settings.copyWith(isAutoRestart: true);
DB().generalSettings = settings.copyWith(screenReaderSupport: true);
```

## Testing State

### Unit Testing Models

```dart
test('GeneralSettings copyWith updates fields', () {
  const original = GeneralSettings(aiLevel: 1);
  final updated = original.copyWith(aiLevel: 5);
  
  expect(updated.aiLevel, 5);
  expect(original.aiLevel, 1);  // Original unchanged
});
```

### Testing Notifiers

```dart
test('HeaderTipNotifier updates value', () {
  final notifier = HeaderTipNotifier();
  
  notifier.showTip('Test message');
  
  expect(notifier.value, 'Test message');
});
```

### Widget Testing with State

```dart
testWidgets('Widget updates when state changes', (tester) async {
  final notifier = ValueNotifier<int>(0);
  
  await tester.pumpWidget(
    MaterialApp(
      home: ValueListenableBuilder<int>(
        valueListenable: notifier,
        builder: (context, value, _) => Text('$value'),
      ),
    ),
  );
  
  expect(find.text('0'), findsOneWidget);
  
  notifier.value = 5;
  await tester.pump();
  
  expect(find.text('5'), findsOneWidget);
});
```

## Debugging State

### Logging State Changes

```dart
class GeneralSettings {
  GeneralSettings copyWith({...}) {
    final updated = GeneralSettings(...);
    logger.d('Settings updated: $updated');
    return updated;
  }
}
```

### Debug Notifiers

```dart
class HeaderTipNotifier extends ValueNotifier<String> {
  @override
  set value(String newValue) {
    logger.d('Tip changed: $value → $newValue');
    super.value = newValue;
  }
}
```

### Flutter DevTools

Use Flutter DevTools to inspect:
- Widget tree and rebuilds
- Performance timeline
- Memory usage

## Common Pitfalls

### 1. Forgetting to Listen

```dart
// ❌ WRONG: Reads once, never updates
final settings = DB().generalSettings;
Text('${settings.aiLevel}');

// ✅ CORRECT: Updates when settings change
ValueListenableBuilder<Box<GeneralSettings>>(
  valueListenable: DB().listenGeneralSettings,
  builder: (context, box, _) {
    final settings = box.get(DB.generalSettingsKey)!;
    return Text('${settings.aiLevel}');
  },
)
```

### 2. Creating State in build()

```dart
// ❌ WRONG: New notifier every rebuild
@override
Widget build(BuildContext context) {
  final notifier = ValueNotifier<int>(0);  // Memory leak!
  return ...;
}

// ✅ CORRECT: Create in initState
late final ValueNotifier<int> notifier;

@override
void initState() {
  super.initState();
  notifier = ValueNotifier<int>(0);
}
```

### 3. Not Disposing

```dart
// ❌ WRONG: No disposal
class MyWidget extends StatefulWidget {
  late final ValueNotifier notifier;
  
  @override
  void initState() {
    notifier = ValueNotifier(...);
  }
  // Missing dispose!
}

// ✅ CORRECT
@override
void dispose() {
  notifier.dispose();
  super.dispose();
}
```

## References

- [ARCHITECTURE.md](ARCHITECTURE.md): Overall architecture
- [COMPONENTS.md](COMPONENTS.md): Component catalog
- [Flutter State Management](https://flutter.dev/docs/development/data-and-backend/state-mgmt/intro)
- [Hive Documentation](https://docs.hivedb.dev/)

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

