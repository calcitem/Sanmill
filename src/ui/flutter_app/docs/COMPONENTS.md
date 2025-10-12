# Sanmill Flutter Application Component Catalog

## Overview

This document provides a comprehensive catalog of all reusable components in the Sanmill Flutter application. Components are organized by category to help developers (human and AI) quickly locate and understand the building blocks available for constructing features.

## Component Categories

- [Core Game Components](#core-game-components)
- [UI Widgets](#ui-widgets)
- [Services](#services)
- [Data Models](#data-models)
- [Utilities](#utilities)
- [Painters](#painters)
- [Managers](#managers)

---

## Core Game Components

### GameController
**Location**: `lib/game_page/services/controller/game_controller.dart`

**Purpose**: Central singleton controller managing all game state and coordination

**Key Responsibilities**:
- Game lifecycle management (new game, reset, dispose)
- Move execution and validation
- AI engine coordination
- History navigation (undo/redo)
- Network game coordination (LAN multiplayer)

**Public API**:
- `newGame()`: Start a new game
- `reset()`: Reset game state
- `doMove(move)`: Execute a move
- `takeBack()`: Undo last move
- `position`: Current board position
- `engine`: AI engine interface
- `gameRecorder`: Move history

**Dependencies**: Engine, Position, GameRecorder, Notifiers

**Usage Context**: Required for all game functionality

---

### Engine
**Location**: `lib/game_page/services/engine/engine.dart`

**Purpose**: Interface to C++ AI engine via UCI protocol

**Key Responsibilities**:
- Send UCI commands to native engine
- Receive and parse engine responses
- Manage engine options and difficulty
- Handle perfect database integration

**Public API**:
- `startup()`: Initialize engine
- `search()`: Request AI move
- `setOption(name, value)`: Configure engine
- `shutdown()`: Clean up engine

**Dependencies**: Native C++ engine (via platform channel)

**Usage Context**: AI move generation, analysis mode

---

### Position
**Location**: `lib/game_page/services/engine/position.dart`

**Purpose**: Represent and manipulate game board state

**Key Responsibilities**:
- Board state representation (bitboards)
- Move generation and validation
- Mill detection
- Game phase management (placing, moving, flying)

**Public API**:
- `makeMove(move)`: Apply move to position
- `undoMove()`: Revert last move
- `isLegal(move)`: Validate move legality
- `get mills`: List of formed mills
- `phase`: Current game phase

**Dependencies**: Bitboard operations, rule engine

**Usage Context**: Core game logic, move validation

---

### GameRecorder
**Location**: `lib/game_page/services/controller/game_recorder.dart`

**Purpose**: Record and manage game move history

**Key Responsibilities**:
- Move list management
- PGN export/import
- Position setup
- History navigation

**Public API**:
- `add(move, notation)`: Record a move
- `takeBack()`: Remove last move
- `moveList`: Complete move history
- `toPGN()`: Export to PGN format

**Dependencies**: Position, Move types

**Usage Context**: Game history, export/import

---

## UI Widgets

### GameBoard
**Location**: `lib/game_page/widgets/game_board.dart`

**Purpose**: Main interactive game board widget

**Key Responsibilities**:
- Render game board
- Handle user touch/click input
- Display pieces and animations
- Accessibility support

**Public API**:
- Constructor parameters: `controller`, `size`
- Responds to taps and drags

**Dependencies**: GameController, Painters, AnimationManager

**Usage Context**: Primary game interface

**See Also**: [API Documentation](api/widgets/GameBoard.md)

---

### CustomDrawer
**Location**: `lib/custom_drawer/custom_drawer.dart`

**Purpose**: Application navigation drawer

**Key Responsibilities**:
- Main menu navigation
- Settings access
- Game mode selection
- About/Help access

**Public API**:
- `CustomDrawer()`: Main drawer widget
- `CustomDrawerHeader()`: Drawer header
- `CustomDrawerItem()`: Drawer menu items

**Dependencies**: None (self-contained)

**Usage Context**: App-wide navigation

**See Also**: [API Documentation](api/widgets/CustomDrawer.md)

---

### PlayArea
**Location**: `lib/game_page/widgets/play_area.dart`

**Purpose**: Complete game play area including board and controls

**Key Responsibilities**:
- Layout game board
- Display game status
- Show move indicators
- Integrate board semantics

**Public API**:
- Constructor: `controller`, `boardWidth`, `gamePageState`

**Dependencies**: GameBoard, GameHeader, Toolbars

**Usage Context**: Game page layout

---

### GameHeader
**Location**: `lib/game_page/widgets/game_header.dart`

**Purpose**: Display game status and player information

**Key Responsibilities**:
- Show current player
- Display tip messages
- Show piece counts
- Player timer display

**Public API**:
- Constructor: `controller`, `context`

**Dependencies**: HeaderTipNotifier, HeaderIconsNotifier

**Usage Context**: Game status display

---

### Settings Components

#### SettingsCard
**Location**: `lib/shared/widgets/settings/settings_card.dart`

**Purpose**: Card container for grouped settings

#### SettingsListTile
**Location**: `lib/shared/widgets/settings/settings_list_tile.dart`

**Purpose**: Individual setting item in a list

**Usage**: Used across all settings pages

---

### AppearanceSettingsPage
**Location**: `lib/appearance_settings/widgets/appearance_settings_page.dart`

**Purpose**: Visual customization interface

**Features**:
- Theme selection
- Color customization
- Font size adjustment
- Background images
- Piece styles

**Dependencies**: ColorSettings, DisplaySettings models

---

### RuleSettingsPage
**Location**: `lib/rule_settings/widgets/rule_settings_page.dart`

**Purpose**: Game rule configuration interface

**Features**:
- Piece count selection
- Flying rule toggle
- Time limits
- Game variants

**Dependencies**: RuleSettings model

---

### GeneralSettingsPage
**Location**: `lib/general_settings/widgets/general_settings_page.dart`

**Purpose**: General app preferences

**Features**:
- AI difficulty
- Sound settings
- Language selection
- Developer options

**Dependencies**: GeneralSettings model

---

## Services

### Database (DB)
**Location**: `lib/shared/database/database.dart`

**Purpose**: Central data persistence service

**Key Responsibilities**:
- Manage Hive boxes
- CRUD operations for all settings
- Database migrations
- Type adapter registration

**Public API**:
- `DB()`: Singleton accessor
- `generalSettings`: Get/set general settings
- `ruleSettings`: Get/set rule settings
- `displaySettings`: Get/set display settings
- `colorSettings`: Get/set color settings
- `listenGeneralSettings`: Reactive updates

**Dependencies**: Hive, Models, Adapters

**Usage Context**: All persistent state operations

**See Also**: [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)

---

### SoundManager
**Location**: `lib/game_page/services/sounds/sound_manager.dart`

**Purpose**: Audio playback management

**Key Responsibilities**:
- Play sound effects (place, remove, mill, etc.)
- Manage audio players
- Volume control
- Sound theme selection

**Public API**:
- `playSound(soundType)`: Play a sound effect
- `dispose()`: Clean up audio resources

**Dependencies**: audioplayers package, GeneralSettings

**Usage Context**: Game feedback, user actions

---

### AnimationManager
**Location**: `lib/game_page/services/animation/animation_manager.dart`

**Purpose**: Coordinate game animations

**Key Responsibilities**:
- Piece move animations
- Capture animations
- Mill formation effects
- Animation timing

**Public API**:
- `animatePieceMove(from, to, duration)`
- `animateCapture(square)`
- `currentAnimation`: Active animation state

**Dependencies**: Animation controllers, Painters

**Usage Context**: Visual feedback for moves

---

### AnnotationManager
**Location**: `lib/game_page/services/annotation/annotation_manager.dart`

**Purpose**: Manage position annotations (arrows, highlights)

**Key Responsibilities**:
- Add/remove annotations
- Render annotations on board
- Save/load annotations
- Annotation types (arrow, circle, square)

**Public API**:
- `addAnnotation(type, data)`
- `clearAnnotations()`
- `annotations`: Current annotation list

**Dependencies**: Custom painters

**Usage Context**: Analysis mode, teaching

---

### ScreenshotService
**Location**: `lib/shared/services/screenshot_service.dart`

**Purpose**: Capture and share game screenshots

**Key Responsibilities**:
- Capture board state as image
- Generate share images
- Save to gallery

**Public API**:
- `captureBoard(widget)`: Take screenshot
- `shareImage(image)`: Share via platform share sheet

**Dependencies**: image package, share_plus

**Usage Context**: Share functionality

---

### NetworkService
**Location**: `lib/game_page/services/network/network_service.dart`

**Purpose**: LAN multiplayer networking

**Key Responsibilities**:
- Peer discovery
- Move synchronization
- Network protocol handling

**Public API**:
- `startServer()`: Host a game
- `connectToServer(host)`: Join a game
- `sendMove(move)`: Send move to opponent

**Dependencies**: network_info_plus

**Usage Context**: LAN multiplayer mode

---

### LoadService / ExportService
**Location**: `lib/game_page/services/import_export/`

**Purpose**: File import/export operations

**Key Responsibilities**:
- Load games from files
- Export games to PGN
- Import game notation

**Public API**:
- `LoadService.loadGame(context, path)`
- `ExportService.exportGame(recorder)`

**Dependencies**: GameRecorder, file system

**Usage Context**: Save/load games, sharing

---

### LoggerService
**Location**: `lib/shared/services/logger.dart`

**Purpose**: Application logging

**Public API**:
- `logger.i(message)`: Info log
- `logger.w(message)`: Warning log
- `logger.e(message)`: Error log

**Dependencies**: logger package

**Usage Context**: Debugging, error tracking

---

### SnackBarService
**Location**: `lib/shared/services/snackbar_service.dart`

**Purpose**: Display temporary messages to user

**Public API**:
- `SnackBarService.showRootSnackBar(message)`

**Dependencies**: Scaffold messenger

**Usage Context**: User feedback, notifications

---

## Data Models

### GeneralSettings
**Location**: `lib/general_settings/models/general_settings.dart`

**Purpose**: General application preferences

**Fields**:
- `aiLevel`: AI difficulty (1-20)
- `isAutoRestart`: Auto restart after game
- `isAutoChangeLevel`: Auto adjust difficulty
- `screenReaderSupport`: Enable screen reader
- `keepMuteWhenTakingBack`: Mute during undo
- Sound preferences (tone, volume, etc.)

**Serialization**: Hive type adapter

---

### RuleSettings
**Location**: `lib/rule_settings/models/rule_settings.dart`

**Purpose**: Game rule configuration

**Fields**:
- `piecesCount`: Number of pieces (9, 10, 12)
- `flyPieceCount`: Flying threshold
- `hasDiagonalLines`: Diagonal board variant
- `mayMoveInPlacingPhase`: Allow moving while placing
- `isDefenderMoveFirst`: Defender goes first
- `boardFullAction`: Action when board is full
- Time limit settings

**Serialization**: Hive type adapter

---

### DisplaySettings
**Location**: `lib/appearance_settings/models/display_settings.dart`

**Purpose**: Visual appearance preferences

**Fields**:
- `locale`: App language
- `themeMode`: Light/dark/system
- `boardTop`: Board margin
- `fontScale`: Font size multiplier
- `standardNotationEnabled`: Show move notation
- `isPieceCountInHandShown`: Show piece count

**Serialization**: Hive type adapter

---

### ColorSettings
**Location**: `lib/appearance_settings/models/color_settings.dart`

**Purpose**: Board and piece color customization

**Fields**:
- `boardLineColor`: Line color
- `darkBackgroundColor`: Dark square color
- `boardBackgroundColor`: Board background
- `whitePieceColor`, `blackPieceColor`: Piece colors
- `pieceHighlightColor`: Selected piece color
- `messageColor`: Message text color

**Serialization**: Hive type adapter

---

### StatsSettings
**Location**: `lib/statistics/model/stats_settings.dart`

**Purpose**: Game statistics and Elo ratings

**Fields**:
- Win/loss/draw counts by difficulty
- Elo ratings
- Game history

**Serialization**: Hive type adapter

---

## Utilities

### StringHelper
**Location**: `lib/shared/utils/helpers/string_helpers/string_helper.dart`

**Purpose**: String manipulation utilities

**Functions**:
- String formatting
- Move notation conversion
- Text processing

---

### ArrayHelper
**Location**: `lib/shared/utils/helpers/array_helpers/array_helper.dart`

**Purpose**: Array/list manipulation utilities

---

### Constants
**Location**: `lib/shared/config/constants.dart`

**Purpose**: Application-wide constants

**Content**:
- UI dimensions
- Animation durations
- Default values
- Global keys

---

## Painters

### BoardPainter
**Location**: `lib/game_page/services/painters/board_painter.dart`

**Purpose**: Render game board (lines, points, background)

**Customization**: Adapts to different board types (9, 10, 12 men's morris)

---

### PiecePainter
**Location**: `lib/game_page/services/painters/piece_painter.dart`

**Purpose**: Render game pieces on board

**Features**:
- Multiple piece styles
- Highlight effects
- Selection indicators

---

### AnimationPainter
**Location**: `lib/game_page/services/painters/animations/`

**Purpose**: Render piece animations

**Types**:
- Move animations
- Capture animations
- Mill formation effects

---

## Managers

### AnimationManager
**Location**: `lib/game_page/services/animation/animation_manager.dart`

**Purpose**: Coordinate all game animations

**See**: [Services](#animationmanager) section above

---

### AnnotationManager
**Location**: `lib/game_page/services/annotation/annotation_manager.dart`

**Purpose**: Manage position annotations

**See**: [Services](#annotationmanager-1) section above

---

## Component Dependencies Graph

```
GamePage
  └── PlayArea
      ├── GameHeader
      │   ├── HeaderTipNotifier
      │   └── HeaderIconsNotifier
      ├── GameBoard
      │   ├── BoardPainter
      │   ├── PiecePainter
      │   ├── AnimationPainter
      │   └── BoardSemanticsNotifier
      └── GameToolbar
          └── GameController

GameController
  ├── Engine (C++ via UCI)
  ├── Position
  ├── GameRecorder
  ├── AnimationManager
  ├── AnnotationManager
  ├── SoundManager
  ├── NetworkService
  └── Various Notifiers

Database (DB)
  ├── GeneralSettings
  ├── RuleSettings
  ├── DisplaySettings
  ├── ColorSettings
  └── StatsSettings

Settings Pages
  ├── AppearanceSettingsPage
  │   ├── DisplaySettings
  │   └── ColorSettings
  ├── RuleSettingsPage
  │   └── RuleSettings
  └── GeneralSettingsPage
      └── GeneralSettings
```

## Component Selection Guide

### When to Use Which Component

#### Need to execute a game move?
→ Use `GameController.doMove()`

#### Need to display game state?
→ Use `GameBoard` widget with `GameController`

#### Need to store user preferences?
→ Use `Database` (DB) with appropriate model

#### Need to play a sound?
→ Use `SoundManager`

#### Need to animate a piece?
→ Use `AnimationManager`

#### Need to show a message?
→ Use `SnackBarService` or `HeaderTipNotifier`

#### Need to navigate?
→ Use `Navigator` or `CustomDrawer`

#### Need to access settings?
→ Use `DB().generalSettings`, `DB().ruleSettings`, etc.

## Component Naming Conventions

- **Pages**: `*Page` suffix (e.g., `GamePage`, `AboutPage`)
- **Widgets**: Descriptive noun (e.g., `GameBoard`, `CustomDrawer`)
- **Services**: `*Service` or `*Manager` suffix
- **Models**: Plain noun (e.g., `RuleSettings`, `Position`)
- **Notifiers**: `*Notifier` suffix (e.g., `HeaderTipNotifier`)
- **Painters**: `*Painter` suffix (e.g., `BoardPainter`)

## Best Practices

1. **Prefer Composition**: Combine small, focused components
2. **Single Responsibility**: Each component should have one clear purpose
3. **Dependency Injection**: Pass dependencies via constructor
4. **Immutable Models**: Use `copyWith` for modifications
5. **Const Constructors**: Use `const` wherever possible
6. **Document Public APIs**: All public methods should have doc comments

## Adding New Components

When adding a new component:

1. **Choose the right location**: Follow the feature-based directory structure
2. **Define clear interface**: Document public API
3. **Add to this catalog**: Update this document
4. **Write tests**: Unit tests for logic, widget tests for UI
5. **Update ARCHITECTURE.md**: If introducing new patterns

## References

- [ARCHITECTURE.md](ARCHITECTURE.md): Overall architecture
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md): State management details
- [API Documentation](api/): Detailed API docs for key components
- [WORKFLOWS.md](WORKFLOWS.md): How to use components in common workflows

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

