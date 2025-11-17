# Voice Assistant Setup Instructions

This document describes the voice assistant feature that has been added to Sanmill and how to complete the setup.

## Overview

The voice assistant feature uses the `whisper_ggml` package to provide speech recognition capabilities. Users can control the app, configure settings, and play the game using voice commands.

## Features

- **Speech Recognition**: Uses Whisper models for accurate speech-to-text conversion
- **Voice Commands**: Supports commands for:
  - Game control (move pieces, undo, redo, restart)
  - Settings (toggle sound, vibration)
  - AI moves
- **Multi-language Support**: Works with multiple languages (English, Chinese, German, Spanish, French, Japanese, Korean, Russian)
- **On-demand Model Download**: Models are downloaded only when needed, not bundled with the app
- **Model Selection**: Users can choose between different model sizes (Tiny ~75MB, Base ~142MB, Small ~466MB, Medium ~1.5GB)
- **Intelligent Command Recognition**: Handles various voice input formats including spoken numbers ("a one" → "a1")
- **Automatic Retry**: Network failures are automatically retried with exponential backoff
- **Built-in Help**: Interactive help page showing all available voice commands

## Setup Instructions

### 1. Generate Required Code Files

Run the following command in the `src/ui/flutter_app` directory to generate the necessary Hive adapters and JSON serialization code:

```bash
cd src/ui/flutter_app
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

This will generate:
- `lib/voice_assistant/models/voice_assistant_settings.g.dart`
- Updated Hive adapters

### 2. Add Voice Assistant to Navigation

To make the voice assistant accessible from the app, add it to the settings menu:

**File: `lib/custom_drawer/custom_drawer.dart` or appropriate settings navigation**

Add a new menu item:
```dart
SettingsListTile(
  titleString: S.of(context).voiceAssistant,
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => const VoiceAssistantSettingsPage(),
    ),
  ),
),
```

Don't forget to import:
```dart
import '../voice_assistant/widgets/voice_assistant_settings_page.dart';
```

### 3. Add Voice Button to Game Page (Optional)

To add the floating voice button to the game interface:

**File: `lib/game_page/widgets/game_page.dart` or similar**

Add the voice button widget:
```dart
import '../../voice_assistant/widgets/voice_button.dart';

// In the Scaffold
floatingActionButton: const VoiceAssistantButton(),
```

Or add an icon button to the app bar:
```dart
import '../../voice_assistant/widgets/voice_button.dart';

// In the AppBar actions
actions: [
  const VoiceAssistantIconButton(),
  // ... other actions
],
```

### 4. Test the Feature

1. Run the app
2. Navigate to Voice Assistant settings
3. Enable the voice assistant
4. Download a model (start with Tiny for testing)
5. Use the voice button to test voice commands

## Voice Commands

### English Commands

- **Move**: "move a1 to b2", "place on a1"
- **Control**: "undo", "redo", "restart", "new game"
- **AI**: "ai move", "computer move"
- **Settings**: "sound on/off", "vibration on/off"

### Chinese Commands (中文命令)

- **移动**: "移动 a1 到 b2", "放置在 a1"
- **控制**: "撤销", "重做", "重新开始", "新游戏"
- **AI**: "ai走", "电脑走"
- **设置**: "声音开启/关闭", "震动开启/关闭"

## File Structure

```
lib/voice_assistant/
├── models/
│   ├── voice_assistant_settings.dart      # Settings model
│   └── voice_assistant_settings.g.dart    # Generated code
├── services/
│   ├── model_downloader.dart              # Model download service (with retry logic)
│   ├── speech_recognition_service.dart    # Speech-to-text service
│   ├── voice_assistant_service.dart       # Main service coordinator
│   └── voice_command_processor.dart       # Command parsing and execution (enhanced)
└── widgets/
    ├── voice_assistant_settings_page.dart # Settings UI
    ├── voice_button.dart                  # Voice control buttons
    ├── voice_commands_help_page.dart      # Interactive help page
    └── dialogs/
        ├── download_model_dialog.dart     # Download dialog
        └── model_info_dialog.dart         # Model info dialog
```

## Dependencies

The following dependency has been added to `pubspec.yaml`:
```yaml
dependencies:
  whisper_ggml: 1.7.0
```

## Localization

Localization strings have been added to:
- `lib/l10n/intl_en.arb` (English)
- `lib/l10n/intl_zh.arb` (Chinese)

All other language files should be updated using the ARB translation updater skill.

## Recent Improvements

### Enhanced Voice Command Recognition
- Added support for spoken number formats (e.g., "a one" is recognized as "a1")
- Improved position extraction logic for better accuracy
- More flexible command matching

### Robust Network Handling
- Automatic retry mechanism with exponential backoff (up to 3 attempts)
- Better error messages during download failures
- Proper HTTP client cleanup to prevent resource leaks

### User Experience
- Added interactive help page showing all available commands with examples
- Fixed duplicate localization keys
- Added missing common localization strings (download, status, unknown)
- Comprehensive localization for English and Chinese

### Code Quality
- All code comments in English
- Improved error handling throughout
- Better logging for debugging
- Enhanced documentation

## Notes

- Model files are downloaded to the app's documents directory
- Models are language-specific
- The Tiny model is recommended for most users (good balance of size and accuracy)
- Internet connection is required for initial model download
- Microphone permission is required for voice recognition
- Use the built-in help page to learn all available voice commands
