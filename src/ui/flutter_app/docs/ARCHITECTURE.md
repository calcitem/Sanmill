# Sanmill Flutter Application Architecture

## Overview

The Sanmill Flutter application is a cross-platform Mill (Nine Men's Morris) game client that provides a modern, accessible, and feature-rich user experience. This document describes the overall architecture, design principles, and structural organization of the application.

## Design Philosophy

### Core Principles

1. **Modularity**: Code is organized into feature-based modules with clear boundaries
2. **Separation of Concerns**: UI, business logic, and data layers are distinctly separated
3. **Single Source of Truth**: Centralized state management through Hive database
4. **Testability**: Components are designed to be independently testable
5. **Accessibility**: Full support for screen readers and assistive technologies
6. **Cross-Platform**: Single codebase for Android, iOS, Windows, macOS, and Linux

### Architecture Style

The application follows a **layered architecture** with **feature-based organization**:

```
┌─────────────────────────────────────────────────────────┐
│                  Presentation Layer                      │
│  (Widgets, Pages, UI Components, Painters)              │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                  Business Logic Layer                    │
│  (Controllers, Services, Notifiers, Managers)           │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                     Data Layer                           │
│  (Models, Database, Repository Pattern)                 │
└─────────────────────────────────────────────────────────┘
                          ↓↑
┌─────────────────────────────────────────────────────────┐
│                   External Services                      │
│  (AI Engine via UCI, Audio, File System, Network)      │
└─────────────────────────────────────────────────────────┘
```

## Technology Stack

### Core Framework
- **Flutter SDK**: 3.35.5+ (cross-platform UI framework)
- **Dart**: >=3.8.0 <4.0.0 (programming language)

### State Management
- **Hive**: Local key-value database for persistent state
- **ValueNotifier/ValueListenableBuilder**: Reactive state updates
- **ChangeNotifier**: Custom state management for complex flows

### Key Dependencies
- **audioplayers**: Sound effects and audio feedback
- **langchain**: LLM integration for AI features
- **image**: Image processing and manipulation
- **intl**: Internationalization (60+ languages)
- **path_provider**: Platform-specific file paths

## Directory Structure

```
lib/
├── main.dart                          # Application entry point
├── appearance_settings/               # Visual customization module
│   ├── models/                        # Color and display settings models
│   └── widgets/                       # Appearance configuration UI
├── custom_drawer/                     # Navigation drawer component
│   └── widgets/                       # Drawer sub-components
├── game_page/                         # Core game module (PRIMARY)
│   ├── pages/                         # Game-related pages
│   ├── services/                      # Game logic and engine integration
│   │   ├── controller/                # Game controller and state management
│   │   ├── engine/                    # Mill game engine (Dart implementation)
│   │   ├── import_export/             # PGN/file handling
│   │   ├── notifiers/                 # Reactive state notifiers
│   │   ├── painters/                  # Custom canvas painters
│   │   └── sounds/                    # Audio management
│   └── widgets/                       # Game UI components
├── general_settings/                  # General application settings
│   ├── models/                        # Settings data models
│   └── widgets/                       # Settings UI
├── rule_settings/                     # Game rule configuration
│   ├── models/                        # Rule settings models
│   └── widgets/                       # Rule configuration UI
├── shared/                            # Shared utilities and components
│   ├── config/                        # Constants and configuration
│   ├── database/                      # Hive database management
│   ├── dialogs/                       # Reusable dialogs
│   ├── services/                      # Cross-cutting services
│   ├── themes/                        # App theming
│   ├── utils/                         # Helper functions
│   └── widgets/                       # Reusable UI components
├── statistics/                        # Game statistics module
│   ├── model/                         # Stats data models
│   ├── services/                      # Stats computation
│   └── widgets/                       # Stats display UI
├── tutorial/                          # User tutorial module
│   ├── painters/                      # Tutorial animations
│   └── widgets/                       # Tutorial UI
├── misc/                              # Miscellaneous pages
│   ├── about_page.dart
│   ├── how_to_play_screen.dart
│   └── license_agreement_page.dart
├── generated/                         # Auto-generated code
│   ├── assets/                        # Asset references
│   └── intl/                          # Localization files
└── l10n/                              # Localization source files (ARB)
```

## Architectural Layers

### 1. Presentation Layer

**Responsibility**: Render UI and handle user interactions

**Key Components**:
- **Pages**: Full-screen views (e.g., `GamePage`, `AppearanceSettingsPage`)
- **Widgets**: Reusable UI components (e.g., `GameBoard`, `CustomDrawer`)
- **Painters**: Custom canvas rendering (e.g., `PiecePainter`, `BoardPainter`)

**Patterns**:
- **Composition over Inheritance**: Widgets are composed from smaller widgets
- **Stateless First**: Use `StatelessWidget` unless state is necessary
- **Builder Pattern**: Use `ValueListenableBuilder` for reactive updates

### 2. Business Logic Layer

**Responsibility**: Implement game rules, coordinate services, manage application state

**Key Components**:
- **GameController**: Singleton controller managing game flow and state
- **Engine**: AI engine interface (communicates with C++ engine via UCI)
- **Services**: Domain-specific logic (e.g., `SoundManager`, `AnimationManager`)
- **Notifiers**: Observable state containers (e.g., `HeaderTipNotifier`)

**Patterns**:
- **Singleton Pattern**: `GameController`, `Database`, services
- **Observer Pattern**: Notifiers for state changes
- **Strategy Pattern**: Pluggable AI algorithms
- **Command Pattern**: Game moves and undo/redo

### 3. Data Layer

**Responsibility**: Persist and retrieve application state

**Key Components**:
- **Database (DB)**: Singleton managing Hive boxes
- **Models**: Data classes with serialization (e.g., `RuleSettings`, `GeneralSettings`)
- **Adapters**: Hive type adapters for custom serialization

**Patterns**:
- **Repository Pattern**: `Database` class abstracts storage details
- **Data Transfer Objects (DTOs)**: Models are immutable with `copyWith` methods
- **Type Adapters**: Custom serialization for complex types

### 4. External Services Integration

**Responsibility**: Integrate with platform APIs and external engines

**Key Components**:
- **UCI Engine**: C++ game engine communication
- **Audio System**: Sound effects and music playback
- **File System**: Save/load game files
- **Network**: LAN multiplayer support
- **LLM Integration**: AI-powered game analysis

## State Management Strategy

### Persistent State (Hive)

All user preferences and game state are stored in Hive boxes:

```dart
// Central database access point
final db = DB();

// Read settings
final generalSettings = db.generalSettings;
final ruleSettings = db.ruleSettings;

// Update settings
db.generalSettings = generalSettings.copyWith(aiLevel: 10);
```

**Box Structure**:
- `generalSettings`: General app preferences (AI level, sound, etc.)
- `ruleSettings`: Game rule configuration (piece count, flying rule, etc.)
- `displaySettings`: Visual preferences (theme, locale, font size)
- `colorSettings`: Board and piece colors
- `statsSettings`: Game statistics and Elo ratings

### Reactive State (ValueNotifier)

Transient UI state uses `ValueNotifier` and `ValueListenableBuilder`:

```dart
class HeaderTipNotifier extends ValueNotifier<String> {
  HeaderTipNotifier() : super('');
  
  void showTip(String message) {
    value = message;
  }
}

// In widget:
ValueListenableBuilder<String>(
  valueListenable: controller.headerTipNotifier,
  builder: (context, tip, child) => Text(tip),
)
```

**Key Notifiers**:
- `HeaderTipNotifier`: Display messages to user
- `HeaderIconsNotifier`: Update header icon states
- `GameResultNotifier`: Game outcome notifications
- `BoardSemanticsNotifier`: Accessibility updates

### Game State (GameController)

The `GameController` singleton manages the core game state:

```dart
final controller = GameController();
controller.position;        // Current board position
controller.engine;          // AI engine interface
controller.gameRecorder;    // Move history
controller.animationManager; // Animation coordination
```

## Data Flow

### User Action → State Update → UI Refresh

```
User Tap
    ↓
TapHandler (in GameController)
    ↓
Position.makeMove()
    ↓
GameRecorder.add(move)
    ↓
Notifiers.notify()
    ↓
ValueListenableBuilder rebuilds
    ↓
UI updates
```

### AI Move Flow

```
GameController.engineToGo()
    ↓
Engine.search() [UCI to C++]
    ↓
Engine receives bestMove
    ↓
GameController.doMove(aiMove)
    ↓
Animation plays
    ↓
UI updates
```

## Communication Patterns

### Widget-to-Service Communication
Widgets access services through the `GameController` or `DB()` singleton:

```dart
// In a widget:
final controller = GameController();
controller.headerTipNotifier.showTip('Your turn!');
await controller.newGame();
```

### Service-to-Widget Communication
Services notify widgets through `ValueNotifier`:

```dart
// Service updates notifier:
headerTipNotifier.value = 'New message';

// Widget automatically rebuilds:
ValueListenableBuilder<String>(
  valueListenable: headerTipNotifier,
  builder: (context, value, _) => Text(value),
)
```

### Cross-Module Communication
Modules communicate through well-defined interfaces:
- Shared services in `lib/shared/services/`
- Shared models in feature `models/` directories
- Global constants in `lib/shared/config/constants.dart`

## Key Design Patterns

### 1. Singleton Pattern
Used for global state and services:
- `GameController`: Game state management
- `Database`: Persistent storage
- Services: `ScreenshotService`, `EloRatingService`

### 2. Factory Pattern
Used for object creation:
- `Database([Locale? locale])`: Factory constructor
- Model constructors with named parameters

### 3. Builder Pattern
Used for complex UI construction:
- `ValueListenableBuilder`: Reactive UI
- `StreamBuilder`: Async data
- `FutureBuilder`: Async operations

### 4. Observer Pattern
Used for state changes:
- `ValueNotifier` and `ValueListenable`
- `ChangeNotifier` for complex state

### 5. Strategy Pattern
Used for pluggable algorithms:
- AI difficulty levels
- Move selection strategies

## Internationalization (i18n)

### Localization Architecture

1. **Source Files**: ARB (Application Resource Bundle) format in `lib/l10n/`
2. **Master File**: `intl_en.arb` (English is the source language)
3. **Code Generation**: `flutter gen-l10n` generates type-safe accessors
4. **Usage**: Access via `S.of(context).stringKey`

### Language Support
60+ languages including:
- Western European: English, German, French, Spanish, Italian
- Eastern European: Russian, Polish, Czech
- Asian: Chinese (Simplified/Traditional), Japanese, Korean
- Middle Eastern: Arabic, Hebrew, Farsi
- And many more...

### Best Practices
- All user-facing strings MUST be localized
- Never hardcode display strings
- Use context-rich keys (e.g., `gamePageTitle` not `title`)
- Support RTL languages (Arabic, Hebrew)
- Test with longest translations (German, Russian)

## Accessibility

### Screen Reader Support
- Semantic labels on all interactive elements
- `BoardSemanticsNotifier` announces game state changes
- `Semantics` widgets wrap custom painters

### Keyboard Navigation
- Full keyboard support on desktop platforms
- Focus management with `FocusNode`

### Visual Accessibility
- High contrast color themes
- Adjustable font sizes (via `displaySettings.fontScale`)
- Color-blind friendly piece designs

## Performance Considerations

### Rendering Optimization
- **const constructors**: Used extensively for immutable widgets
- **RepaintBoundary**: Isolates expensive repaints
- **Custom Painters**: Efficient canvas rendering for game board

### State Management Optimization
- **Selective rebuilds**: `ValueListenableBuilder` rebuilds only affected widgets
- **Lazy loading**: Assets loaded on demand
- **Dispose pattern**: Proper cleanup in `dispose()` methods

### Memory Management
- **Image caching**: Reuse loaded images
- **Hive lazy boxes**: Load data on access
- **Stream subscriptions**: Always cancel in `dispose()`

## Testing Strategy

### Unit Tests
- Model serialization/deserialization
- Business logic in services
- Utility functions

### Widget Tests
- UI component rendering
- User interaction handling
- State management

### Integration Tests
- Complete user flows
- Cross-module integration
- Platform-specific features

### Testing Tools
- `flutter_test`: Unit and widget tests
- `integration_test`: Full app tests
- `mockito`: Mocking dependencies

## Build Variants

### Environment Configurations
The app supports compile-time environment flags:

```shell
flutter run --dart-define test=true dev_mode=true catcher=false
```

**Flags**:
- `test`: Enable test mode (disable external links)
- `dev_mode`: Show developer options
- `catcher`: Enable/disable crash reporting

Access via `EnvironmentConfig`:

```dart
if (EnvironmentConfig.devMode) {
  // Show debug features
}
```

## Platform-Specific Considerations

### Android
- Material Design guidelines
- Native Android services integration
- Google Play services

### iOS
- Cupertino design integration
- iOS-specific permissions
- App Store guidelines compliance

### Desktop (Windows/macOS/Linux)
- Windowing system integration
- Desktop-specific UI patterns
- File system access

### Web
- Limited features (no file system)
- CORS considerations
- WebAssembly for C++ engine

## Security and Privacy

### Data Privacy
- All data stored locally (no cloud sync)
- Optional crash reporting (user consent)
- No analytics or tracking

### License Compliance
- GPL v3 for all code
- Compatible licenses for dependencies
- Attribution in About page

## Future Architecture Considerations

### Planned Enhancements
1. **Plugin Architecture**: Allow community extensions
2. **Cloud Save**: Optional game sync across devices
3. **Advanced AI**: Integration of neural network engines
4. **Multiplayer**: Enhanced online play with matchmaking

### Scalability
- Modular design allows easy feature addition
- Clear module boundaries prevent tight coupling
- Comprehensive documentation enables community contributions

## References

- [Flutter Architecture Patterns](https://flutter.dev/docs/development/data-and-backend/state-mgmt/intro)
- [AGENTS.md](../../../AGENTS.md): AI Agent development guidelines
- [COMPONENTS.md](COMPONENTS.md): Component catalog
- [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md): State management details
- [WORKFLOWS.md](WORKFLOWS.md): Development workflows

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

