# GameBoard Widget API Documentation

## Overview

`GameBoard` is the main interactive game board widget that displays the Mill game board, handles user input (taps and gestures), renders pieces and animations, and provides visual feedback for game actions.

**Location**: `lib/game_page/widgets/game_board.dart` (part of `game_page.dart`)

**Type**: `StatefulWidget` with `TickerProviderStateMixin`

**Dependencies**: GameController, AnimationManager, Painters, GameImages

## Class Definition

```dart
class GameBoard extends StatefulWidget {
  const GameBoard({super.key, required this.boardImage});

  final ImageProvider? boardImage;

  @override
  State<GameBoard> createState() => _GameBoardState();
}
```

## Purpose

The GameBoard widget is the **core interactive element** of the game. It:
- Renders the game board using custom painters
- Displays pieces at their positions
- Handles touch/click input from users
- Plays animations for moves, captures, and mills
- Shows visual feedback (highlights, selection indicators)
- Manages semantic labels for accessibility

## Constructor Parameters

### `boardImage`
```dart
final ImageProvider? boardImage;
```

The background image for the board.

**Type**: `ImageProvider?` (nullable)

**Purpose**: Provides custom board background (wood texture, marble, etc.)

**Default Behavior**: If `null`, uses solid background color from theme

**Example**:
```dart
GameBoard(
  boardImage: AssetImage('assets/images/background_image_1.jpg'),
)

// Or with no image:
GameBoard(boardImage: null)
```

---

## Key Features

### 1. Touch Input Handling

The board responds to user taps and translates screen coordinates to board squares.

**Flow**:
```
User taps screen
  ↓
_onBoardTap(TapUpDetails)
  ↓
Convert tap position to square index
  ↓
Call GameController.select(square) or .place(square)
  ↓
Board updates via setState()
```

### 2. Custom Rendering

Uses multiple custom painters:
- **BoardPainter**: Draws board lines, points, background
- **PiecePainter**: Renders game pieces
- **AnimationPainter**: Renders move/capture animations
- **AnnotationPainter**: Draws analysis annotations (arrows, highlights)

### 3. Animation System

Supports 30+ piece effect animations:
- Placement effects: Ripple, Glow, Sparkle, etc.
- Removal effects: Explode, Shatter, Vanish, etc.
- Mill formation effects: Fireworks, Starburst, etc.

Animations are managed by `AnimationManager` which coordinates multiple simultaneous animations.

### 4. Accessibility

Provides comprehensive screen reader support:
- Semantic labels for each square
- Announcements for piece placement
- Move descriptions
- Game status updates

---

## State Management

### Internal State (_GameBoardState)

```dart
class _GameBoardState extends State<GameBoard> 
    with TickerProviderStateMixin {
  late Future<GameImages> gameImagesFuture;
  late AnimationManager animationManager;
  bool _isDialogShowing = false;
}
```

**Fields**:
- `gameImagesFuture`: Loads piece and board images asynchronously
- `animationManager`: Coordinates all board animations
- `_isDialogShowing`: Prevents duplicate game-over dialogs (AI vs AI)

### Lifecycle Methods

```dart
@override
void initState() {
  super.initState();
  gameImagesFuture = _loadImages();
  animationManager = AnimationManager(this);
  GameController().gameResultNotifier.addListener(_showResult);
}

@override
void dispose() {
  GameController().gameResultNotifier.removeListener(_showResult);
  animationManager.dispose();
  super.dispose();
}
```

---

## Public Interface (Indirect)

The GameBoard doesn't expose public methods directly. Instead, it responds to:

### GameController State Changes

The board rebuilds when GameController state changes:
- `position`: Board state
- `phase`: Game phase (placing, moving, flying)
- `action`: Current action (select, place, remove)
- `selectedPieceSquare`: Currently selected piece

### Example Integration

```dart
// In GamePage:
class GamePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameBoard(
        boardImage: _getBoardImage(),
      ),
    );
  }

  ImageProvider? _getBoardImage() {
    final displaySettings = DB().displaySettings;
    if (displaySettings.boardImageIndex > 0) {
      return AssetImage(
        'assets/images/background_image_${displaySettings.boardImageIndex}.jpg',
      );
    }
    return null;
  }
}
```

---

## Visual Rendering

### Rendering Layers (Bottom to Top)

1. **Background**: Board image or solid color
2. **Board Lines**: Custom painted lines and points
3. **Pieces**: Game pieces at their positions
4. **Highlights**: Selected piece indicators, valid move highlights
5. **Animations**: Move/capture/mill animations
6. **Annotations**: Analysis arrows and highlights (analysis mode)

### CustomPaint Structure

```dart
CustomPaint(
  painter: BoardPainter(
    boardImage: boardImage,
    colorSettings: colorSettings,
  ),
  foregroundPainter: PiecePainter(
    position: controller.position,
    animationValue: animation.value,
  ),
  child: GestureDetector(
    onTapUp: _onBoardTap,
  ),
)
```

---

## Touch Input Details

### Square Selection Algorithm

```dart
int _coordinatesToSquare(Offset point) {
  // 1. Convert screen coordinates to board coordinates
  final boardSize = size.width;
  final x = point.dx / boardSize;
  final y = point.dy / boardSize;
  
  // 2. Find nearest square
  double minDistance = double.infinity;
  int nearestSquare = -1;
  
  for (int sq = 0; sq < sqNumber; sq++) {
    final squarePos = getSquarePosition(sq);
    final distance = (squarePos - point).distance;
    if (distance < minDistance) {
      minDistance = distance;
      nearestSquare = sq;
    }
  }
  
  return nearestSquare;
}
```

### Touch Response Matrix

| Game Phase | Action | Tap Empty Square | Tap Own Piece | Tap Opponent Piece |
|------------|--------|------------------|---------------|-------------------|
| Placing | Place | Place piece | No effect | No effect |
| Moving | Select | Select dest | Select piece | No effect |
| Moving | Move | Invalid | Reselect | Invalid |
| Any | Remove | Invalid | Invalid | Remove piece |

---

## Animation Integration

### Playing a Move Animation

```dart
// GameBoard automatically plays animations via AnimationManager
Future<void> _playMoveAnimation(Move move) async {
  final effectName = DB().displaySettings.pieceEffectName;
  
  await animationManager.playMoveEffect(
    from: move.from,
    to: move.to,
    effectName: effectName,
  );
}
```

### Available Effects

**Placement Effects** (piece appears):
- Ripple, Glow, Sparkle, Fade, Expand, Aura, Burst

**Removal Effects** (piece disappears):
- Explode, Shatter, Vanish, Shrink, Melt, Disperse

**Special Effects** (mill formation):
- Fireworks, Starburst, WarpWave, NeonFlash

---

## Accessibility Features

### Semantic Labels

Each square has a semantic label describing:
- Square position (e.g., "A1", "B2")
- Piece present (if any)
- Piece color
- Selection state

```dart
Semantics(
  label: _getSquareSemantics(square),
  button: true,
  enabled: _isSquareInteractive(square),
  child: square widget,
)
```

### Screen Reader Announcements

```dart
// When piece is placed:
controller.boardSemanticsNotifier.announce(
  S.of(context).piecePlacedAt(squareName),
);

// When mill is formed:
controller.boardSemanticsNotifier.announce(
  S.of(context).millFormed,
);
```

---

## Performance Optimizations

### 1. RepaintBoundary

```dart
RepaintBoundary(
  child: GameBoard(...),
)
```

Isolates board repaints from the rest of the UI.

### 2. Const Constructors

Static elements use `const` constructors to avoid unnecessary rebuilds.

### 3. Async Image Loading

Images are loaded asynchronously with `FutureBuilder` to prevent blocking.

### 4. Efficient CustomPaint

Painters only repaint when necessary (implement `shouldRepaint` efficiently).

---

## Common Usage Patterns

### Pattern 1: Basic Integration

```dart
class GamePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final boardWidth = constraints.maxWidth * 0.9;
            return SizedBox(
              width: boardWidth,
              height: boardWidth,
              child: GameBoard(
                boardImage: AssetImage('assets/images/board.jpg'),
              ),
            );
          },
        ),
      ),
    );
  }
}
```

### Pattern 2: With Custom Background

```dart
GameBoard(
  boardImage: displaySettings.boardImageIndex > 0
    ? AssetImage('assets/images/background_image_${displaySettings.boardImageIndex}.jpg')
    : null,
)
```

### Pattern 3: Responsive Sizing

```dart
LayoutBuilder(
  builder: (context, constraints) {
    final double boardWidth = min(
      constraints.maxWidth * 0.9,
      constraints.maxHeight * 0.6,
    );
    
    return SizedBox(
      width: boardWidth,
      height: boardWidth,
      child: GameBoard(boardImage: _getBoardImage()),
    );
  },
)
```

---

## Testing

### Widget Tests

```dart
testWidgets('GameBoard renders correctly', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameBoard(boardImage: null),
      ),
    ),
  );
  
  expect(find.byType(GameBoard), findsOneWidget);
  expect(find.byType(CustomPaint), findsWidgets);
});
```

### Accessibility Tests

```dart
testWidgets('GameBoard has semantic labels', (tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: GameBoard(boardImage: null),
      ),
    ),
  );
  
  // Verify semantics
  expect(
    tester.getSemantics(find.byType(GameBoard)),
    matchesSemantics(
      hasEnabledState: true,
      isButton: true,
    ),
  );
});
```

---

## Troubleshooting

### Issue: Board Not Responding to Taps

**Cause**: GameController not initialized  
**Solution**: Ensure `GameController().isControllerReady == true`

### Issue: Animations Not Playing

**Cause**: AnimationManager not properly initialized  
**Solution**: Check that `TickerProviderStateMixin` is mixed in

### Issue: Image Not Loading

**Cause**: Asset not declared in `pubspec.yaml`  
**Solution**: Add image to `assets` section in `pubspec.yaml`

### Issue: Incorrect Touch Coordinates

**Cause**: Board size calculation error  
**Solution**: Verify board is properly sized with `LayoutBuilder`

---

## Best Practices

### DO: Use LayoutBuilder for Responsive Sizing

```dart
// ✅ Good
LayoutBuilder(
  builder: (context, constraints) {
    return GameBoard(
      boardImage: image,
    );
  },
)
```

### DON'T: Hardcode Board Size

```dart
// ❌ Bad
SizedBox(
  width: 400,
  height: 400,
  child: GameBoard(...),
)
```

### DO: Wrap in RepaintBoundary

```dart
// ✅ Good
RepaintBoundary(
  child: GameBoard(boardImage: image),
)
```

### DO: Dispose Properly

The GameBoard handles its own disposal, but ensure the parent widget doesn't keep references to it after disposal.

---

## Related Components

- [GameController](../GameController.md): Controls game state
- [AnimationManager](../../services/AnimationManager.md): Manages animations
- [Painters](../../services/painters/): Custom painters for rendering
- [PlayArea](PlayArea.md): Container for GameBoard

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

