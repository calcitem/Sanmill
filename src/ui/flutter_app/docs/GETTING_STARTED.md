# Getting Started with Sanmill Flutter Development

## Welcome! 欢迎！

This guide will help you get started with contributing to the Sanmill Flutter application, whether you're a human developer or an AI agent.

## Prerequisites

### Required Knowledge

- **Dart**: Basic to intermediate Dart programming
- **Flutter**: Understanding of widgets, state management, and build process
- **Git**: Version control basics
- **Command line**: Terminal/shell navigation

### Recommended Reading

Before diving in, familiarize yourself with these documents:

1. **[ARCHITECTURE.md](ARCHITECTURE.md)** - Understand the system design (15 min read)
2. **[COMPONENTS.md](COMPONENTS.md)** - Know what's available (10 min read)
3. **[STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)** - Learn how state works (20 min read)

## Setup

### 1. Environment Setup

#### Install Flutter

**Option A: Automatic** (Recommended)
```bash
# From repository root
./flutter-init.sh
```

This script:
- Checks if Flutter is installed
- Downloads Flutter 3.35.5 to `.tools/flutter/` if needed
- Configures PATH for current session

**Option B: Manual**

Download Flutter SDK 3.35.5+ from [flutter.dev](https://flutter.dev/docs/get-started/install)

Verify installation:
```bash
flutter doctor
```

Fix any issues reported by `flutter doctor`.

#### Platform-Specific Setup

**Android Development:**
1. Install [Android Studio](https://developer.android.com/studio)
2. Install Android SDK (via Android Studio)
3. Accept licenses: `flutter doctor --android-licenses`

**iOS Development:** (macOS only)
1. Install [Xcode](https://apps.apple.com/us/app/xcode/id497799835)
2. Install CocoaPods: `sudo gem install cocoapods`

**Desktop Development:**
- **Windows**: Visual Studio 2019+ with C++ desktop development tools
- **macOS**: Xcode command-line tools
- **Linux**: Build essentials (`sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev`)

### 2. Clone Repository

```bash
git clone https://github.com/calcitem/Sanmill.git
cd Sanmill
```

### 3. Install Dependencies

```bash
cd src/ui/flutter_app
flutter pub get
```

This downloads all packages defined in `pubspec.yaml`.

### 4. Verify Setup

Run the app:
```bash
flutter run
```

Select a target device when prompted.

If successful, you should see the Sanmill app launch!

## Project Tour

### Quick Directory Overview

```
src/ui/flutter_app/
├── lib/                    # Dart source code
│   ├── main.dart          # App entry point
│   ├── game_page/         # Core game module
│   │   ├── services/      # Game logic
│   │   └── widgets/       # Game UI
│   ├── shared/            # Shared utilities
│   │   ├── database/      # Hive storage
│   │   ├── services/      # Cross-cutting services
│   │   └── widgets/       # Reusable widgets
│   ├── l10n/              # Localization files (60+ languages)
│   └── *_settings/        # Settings modules
├── docs/                  # THIS IS NEW! Documentation
│   ├── ARCHITECTURE.md    # System architecture
│   ├── COMPONENTS.md      # Component catalog
│   ├── WORKFLOWS.md       # Development workflows
│   └── api/               # API documentation
├── test/                  # Tests
├── assets/                # Images, sounds, databases
└── pubspec.yaml           # Dependencies
```

### Key Files to Know

| File | Purpose |
|------|---------|
| `lib/main.dart` | App initialization and entry point |
| `lib/game_page/services/mill.dart` | Game logic library file |
| `lib/game_page/services/controller/game_controller.dart` | Core game controller |
| `lib/shared/database/database.dart` | Database singleton |
| `lib/l10n/intl_en.arb` | English localization strings |
| `lib/shared/config/constants.dart` | App-wide constants |

## Your First Contribution

Let's make a simple change to familiarize yourself with the process.

### Task: Add a Custom Message to the Game Header

#### Step 1: Understand the Current Code

Open `lib/game_page/widgets/game_header.dart` and find where tips are displayed.

The `HeaderTipNotifier` controls the message shown to users.

#### Step 2: Find Where to Add Your Change

Open `lib/game_page/services/controller/game_controller.dart`

Find the `newGame()` method.

#### Step 3: Add Your Message

```dart
Future<void> newGame() async {
  // ... existing code ...
  
  // Add your message here:
  headerTipNotifier.showTip('Welcome to Sanmill!');
  
  // ... rest of the method ...
}
```

#### Step 4: Make It Localized (Proper Way)

**a) Add string to localization file:**

Edit `lib/l10n/intl_en.arb`:
```json
{
  "welcomeToSanmill": "Welcome to Sanmill!",
  "@welcomeToSanmill": {
    "description": "Welcome message shown when starting new game"
  }
}
```

**b) Generate localization:**
```bash
flutter gen-l10n
```

**c) Use localized string:**
```dart
// Instead of hardcoded string:
headerTipNotifier.showTip(S.of(context).welcomeToSanmill);
```

But wait! `newGame()` doesn't have a `BuildContext`!

**d) Solution: Pass context or use existing pattern:**

Look at how other methods do it. You'll see that tips are usually set where `BuildContext` is available (in widgets).

For now, let's add a parameter:
```dart
Future<void> newGame({BuildContext? context}) async {
  // ... existing code ...
  
  if (context != null) {
    headerTipNotifier.showTip(S.of(context).welcomeToSanmill);
  }
  
  // ... rest of the method ...
}
```

#### Step 5: Test Your Change

```bash
flutter run
```

Start a new game and verify your message appears!

#### Step 6: Format and Commit

```bash
# Back to repo root
cd ../../..

# Format code
./format.sh s

# Check what changed
git status
git diff

# Stage changes
git add .

# Commit (following project conventions)
git commit -m "Add welcome message to new game

Display 'Welcome to Sanmill!' message when starting a new game.
- Add welcomeToSanmill localization string
- Update newGame() to show welcome tip

Refs #[your_issue_number_if_applicable]"
```

**Congratulations!** You've made your first contribution! 🎉

## Common Development Tasks

### Running the App

```bash
cd src/ui/flutter_app

# Run on default device
flutter run

# Run on specific device
flutter devices           # List devices
flutter run -d android    # Run on Android
flutter run -d chrome     # Run on Chrome (web)
flutter run -d macos      # Run on macOS
```

### Hot Reload vs. Hot Restart

While app is running:
- **Hot Reload**: Press `r` - Fast, preserves state
- **Hot Restart**: Press `R` - Full restart, loses state

Use hot reload for UI changes, hot restart for logic changes.

### Viewing Logs

```bash
# While app is running, logs appear in console
# Filter for specific tags:
grep "\\[Controller\\]" 

# Or use Flutter DevTools
flutter pub global activate devtools
flutter pub global run devtools
```

### Debugging

**1. Add breakpoints in IDE:**
- VS Code: Click left of line number
- Android Studio: Click left gutter

**2. Run in debug mode:**
```bash
flutter run --debug
```

**3. Use print/logger:**
```dart
import '../../shared/services/logger.dart';

logger.d('Debug message: $variable');
```

### Running Tests

```bash
# All tests
flutter test

# Specific test file
flutter test test/models/general_settings_test.dart

# With coverage
flutter test --coverage
```

### Building for Release

```bash
# Android APK
flutter build apk

# Android App Bundle (for Play Store)
flutter build appbundle

# iOS (macOS only)
flutter build ios

# Desktop
flutter build windows  # or macos, linux
```

## Understanding the Architecture

### Data Flow Example: User Makes a Move

```
1. User taps board square
   ↓
2. GameBoard widget calls onBoardTap()
   ↓
3. GameController.select(square)
   ↓
4. Position.makeMove(move)
   - Updates bitboards
   - Changes turn
   - Detects mills
   ↓
5. GameRecorder.add(move)
   - Records in history
   ↓
6. Notifiers updated
   - headerTipNotifier ← "Black's turn"
   - headerIconsNotifier ← update pieces
   - boardSemanticsNotifier ← announce move
   ↓
7. ValueListenableBuilder rebuilds
   ↓
8. UI updates
```

### State Storage Hierarchy

```
Persistent (Hive Database)
└── Settings Models
    ├── GeneralSettings
    ├── RuleSettings
    ├── DisplaySettings
    └── ColorSettings

Session (GameController)
└── Game State
    ├── Position (board state)
    ├── GameRecorder (history)
    └── Engine (AI)

Transient (ValueNotifiers)
└── UI State
    ├── HeaderTipNotifier (messages)
    ├── HeaderIconsNotifier (player icons)
    └── BoardSemanticsNotifier (accessibility)
```

## Development Workflows

For detailed step-by-step workflows, see [WORKFLOWS.md](WORKFLOWS.md).

Common tasks:
- [Adding a New UI Feature](WORKFLOWS.md#workflow-1-adding-a-new-ui-feature)
- [Fixing a Bug](WORKFLOWS.md#workflow-4-fixing-a-bug)
- [Adding Localization Strings](WORKFLOWS.md#workflow-6-adding-internationalization-i18n-strings)
- [Creating a New Setting](WORKFLOWS.md#workflow-7-creating-a-new-settings-option)

## Best Practices

See [BEST_PRACTICES.md](BEST_PRACTICES.md) for comprehensive guidelines.

### Quick Rules

**DO:**
- ✅ Use `const` constructors
- ✅ Localize all strings
- ✅ Add semantic labels
- ✅ Dispose resources
- ✅ Format before commit (`./format.sh s`)
- ✅ Write tests

**DON'T:**
- ❌ Hardcode strings
- ❌ Use `print()` (use `logger`)
- ❌ Skip documentation
- ❌ Mutate models (use `copyWith()`)
- ❌ Commit without formatting

## Troubleshooting

### "flutter: command not found"

**Solution:**
```bash
# Run flutter-init.sh
./flutter-init.sh

# Or add Flutter to PATH manually
export PATH="$PATH:/path/to/flutter/bin"
```

### "Waiting for another flutter command to release the startup lock"

**Solution:**
```bash
# Kill Flutter process
killall -9 dart

# Or delete lock file
rm ~/flutter/bin/cache/lockfile
```

### "MissingPluginException"

**Solution:**
```bash
# Stop app
# Uninstall from device
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

### "Version solving failed"

**Solution:**
```bash
# Delete pubspec.lock
rm pubspec.lock

# Update dependencies
flutter pub get
```

### Gradle Build Errors (Android)

**Solution:**
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter run
```

## Resources

### Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - System architecture
- **[COMPONENTS.md](COMPONENTS.md)** - Component catalog
- **[STATE_MANAGEMENT.md](STATE_MANAGEMENT.md)** - State management
- **[WORKFLOWS.md](WORKFLOWS.md)** - Development workflows
- **[BEST_PRACTICES.md](BEST_PRACTICES.md)** - Code quality guidelines

### API Documentation

- **[GameController](api/GameController.md)** - Game controller API
- **[Engine](api/Engine.md)** - AI engine API
- **[Position](api/Position.md)** - Board position API

### External Resources

- **[Flutter Documentation](https://flutter.dev/docs)** - Official Flutter docs
- **[Dart Language Tour](https://dart.dev/guides/language/language-tour)** - Dart language guide
- **[Effective Dart](https://dart.dev/guides/language/effective-dart)** - Dart best practices
- **[Sanmill Wiki](https://github.com/calcitem/Sanmill/wiki)** - Project wiki

### Community

- **[GitHub Discussions](https://github.com/calcitem/Sanmill/discussions)** - Ask questions
- **[Issue Tracker](https://github.com/calcitem/Sanmill/issues)** - Report bugs, request features
- **[Pull Requests](https://github.com/calcitem/Sanmill/pulls)** - Submit code changes

## Next Steps

Now that you're set up:

1. **Explore the codebase**: Browse `lib/` to understand the structure
2. **Read the architecture**: Study [ARCHITECTURE.md](ARCHITECTURE.md)
3. **Try a workflow**: Follow a workflow from [WORKFLOWS.md](WORKFLOWS.md)
4. **Find an issue**: Look for "good first issue" labels on GitHub
5. **Make a contribution**: Follow the contribution guidelines in [CONTRIBUTING.md](../../../CONTRIBUTING.md)

## Tips for Success

### For Human Developers

- **Start small**: Fix a typo, improve documentation, add a small feature
- **Ask questions**: Use GitHub Discussions if you're stuck
- **Read existing code**: Learn patterns by studying similar features
- **Test thoroughly**: Test on multiple platforms when possible
- **Be patient**: It's a large codebase; take time to understand it

### For AI Agents

- **Read documentation first**: Understand architecture before generating code
- **Follow established patterns**: Match existing code style and structure
- **Use provided components**: Check [COMPONENTS.md](COMPONENTS.md) before creating new components
- **Follow workflows**: Use workflows from [WORKFLOWS.md](WORKFLOWS.md) for consistency
- **Generate proper commits**: Follow commit message conventions

## Getting Help

**Stuck? Need clarification?**

1. **Check documentation**: Answer might be in docs
2. **Search existing issues**: Someone may have asked already
3. **Ask in Discussions**: Post in [GitHub Discussions](https://github.com/calcitem/Sanmill/discussions)
4. **Join the community**: Connect with other contributors

**Remember**: Everyone was a beginner once. Don't hesitate to ask questions!

---

**Happy Coding! 编码愉快！**

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

