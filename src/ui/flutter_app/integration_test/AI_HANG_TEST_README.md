# AI Thinking Hang Detection Tests

## Purpose

Automated tests to detect and reproduce the intermittent bug where AI gets stuck in "thinking..." state after a human move.

## Quick Start

### Visual Test (Recommended)
```bash
# Shows game board UI - best for observation
flutter test integration_test/ai_thinking_hang_visual_test.dart -d <platform>
# 10 games, ~10-20 min
```

### Quick Test
```bash
# Fast validation without UI
flutter test integration_test/ai_thinking_hang_quick_test.dart -d <platform>
# 5 games, ~2-5 min
```

### Full Test
```bash
# Comprehensive testing for CI/CD
flutter test integration_test/ai_thinking_hang_test.dart -d <platform>
# 100 games, ~30-60 min
```

Replace `<platform>` with: `windows`, `linux`, or `android`

## Test Files

| File | Games | Timeout | UI | Use Case |
|------|-------|---------|----|----|
| `ai_thinking_hang_visual_test.dart` | 10 | 30s | ✅ | Daily testing, debugging |
| `ai_thinking_hang_quick_test.dart` | 5 | 15s | ❌ | Fast validation |
| `ai_thinking_hang_test.dart` | 100 | 30s | ❌ | CI/CD, stress testing |
| `ai_hang_test_logger.dart` | - | - | - | Logging utility |

## Configuration

Edit test files to adjust parameters:

```dart
const int maxGamesToTest = 100;              // Number of games
const int aiResponseTimeoutSeconds = 30;     // AI timeout in seconds
const int maxMovesPerGame = 50;              // Max moves per game
```

## Output Examples

### Normal (No Issues)
```
[AIThinkingHangTest] ✓ AI responded successfully
[AIThinkingHangTest] Games played: 100
[AIThinkingHangTest] Hangs detected: 0
[AIThinkingHangTest] ✓ No hangs detected
```

### Hang Detected
```
[AIThinkingHangTest] ❌ HANG DETECTED: Game 42, Move 18
[AIThinkingHangTest] Position FEN: [FEN string]
[AIThinkingHangTest] Move history: [move sequence]
[AIThinkingHangTest] STOPPING TEST - Bug reproduced!
```

## When Hang is Detected

Save immediately:
1. **FEN position** - for exact board reproduction
2. **Move history** - complete move sequence
3. **Game/Move number** - when issue occurred
4. **Engine state** - diagnostic information

## Running Scripts

### Linux/Mac
```bash
./run_ai_hang_test.sh linux
```

### Windows
```powershell
.\run_ai_hang_test.ps1 -Device windows
```

## Troubleshooting

**Test won't start**: Run `flutter pub get`

**Test too slow**: Use quick test or reduce `maxGamesToTest`

**Can't reproduce bug**: Increase game count, test on different platforms, or run multiple times

## CI/CD Integration

```yaml
# Example GitHub Actions workflow
jobs:
  ai-hang-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - run: flutter test integration_test/ai_thinking_hang_test.dart -d linux
```

## Technical Details

### Test Flow
1. Start app and configure Human vs AI mode
2. For each game:
   - Human makes random legal move
   - Wait for AI response (with timeout)
   - If timeout → capture state and stop
   - Continue until game ends or max moves
3. Output summary report

### Timeout Detection
Uses `Completer` and `Timer` to detect when AI fails to respond within configured timeout period.

### Move Generation
Uses engine's `analyzePosition()` method to obtain legal moves, ensuring 100% valid move generation.

## Related Files

- `lib/game_page/services/controller/game_controller.dart` - `engineToGo()` method
- `lib/game_page/services/engine/engine.dart` - `search()` method
- `automated_move_test_runner.dart` - Test framework reference

