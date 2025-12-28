# AI Thinking Hang Detection Tests

> **⚠️ IMPORTANT UPDATE**: All tests now include **thorough state reset** between iterations, including the critical `isControllerReady = false` flag reset. This ensures each test starts from a completely clean state, maximizing chances of reproducing intermittent bugs.

## Purpose

Automated tests to detect and reproduce the intermittent bug where AI gets stuck in "thinking..." state after a human move.

             ## Quick Start

### First Move Test (Recommended for Bug Detection) ⭐
```bash
# Tests ONLY the first 2 moves (human move 1, AI move 2)
# Most hangs occur on AI's first response
flutter test integration_test/ai_thinking_hang_first_move_test.dart -d <platform>
# 500 games × 2 moves, ~5-10 min
```

### Visual Test
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

| File | Games | Moves/Game | Timeout | UI | Use Case |
|------|-------|------------|---------|----|----|
| `ai_thinking_hang_first_move_test.dart` | 500 | **2** | 30s | ❌ | **First move bug detection** ⭐ |
| `ai_thinking_hang_visual_test.dart` | 10 | 40 | 30s | ✅ | Daily testing, debugging |
| `ai_thinking_hang_quick_test.dart` | 5 | 20 | 15s | ❌ | Fast validation |
| `ai_thinking_hang_test.dart` | 100 | 50 | 30s | ❌ | CI/CD, stress testing |
| `ai_hang_test_logger.dart` | - | - | - | - | Logging utility |

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

### First Move Test (Recommended)

#### Linux/Mac
```bash
./run_ai_first_move_test.sh linux
```

#### Windows
```powershell
.\run_ai_first_move_test.ps1 -Device windows
```

### Full Test Suite

#### Linux/Mac
```bash
./run_ai_hang_test.sh linux
```

#### Windows
```powershell
.\run_ai_hang_test.ps1 -Device windows
```

## Troubleshooting

**Test won't start**: Run `flutter pub get`

**Test too slow**: Use quick test or reduce `maxGamesToTest`

**Can't reproduce bug**:
- Increase game count (e.g., 500-1000 games for first move test)
- Test on different platforms (Linux/Windows/Android)
- Run multiple times - bug is intermittent
- Ensure thorough state reset is working (check logs for "State reset complete")
- Try different AI difficulty levels
- Check if `isControllerReady` flag is being reset properly

**State not clean between tests**:
- All tests now include thorough state reset with:
  - Engine shutdown/restart
  - GameController force reset
  - `isControllerReady = false` flag reset (CRITICAL)
  - Proper delays for cleanup
- If issues persist, increase delay values in reset code

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
   - **Thorough state reset** (see below)
   - Human makes random legal move
   - Wait for AI response (with timeout)
   - If timeout → capture state and stop
   - Continue until game ends or max moves
3. Output summary report

### State Reset Process (Critical for Bug Reproduction)

Each test iteration performs a **thorough state reset** to ensure clean conditions:

1. **Shutdown engine** if currently running
2. **Force reset** GameController (`reset(force: true)`)
3. **Reset ready flag** (`isControllerReady = false`) - **CRITICAL!**
4. **Wait for UI settle** (500ms)
5. **Additional delay** (300ms) to ensure complete cleanup
6. **Restart engine** fresh

This comprehensive reset is essential for:
- Preventing state leakage between test iterations
- Ensuring each game starts from a truly clean state
- Maximizing chances of reproducing intermittent bugs
- Avoiding false negatives due to cached state

### Timeout Detection
Uses `Completer` and `Timer` to detect when AI fails to respond within configured timeout period.

### Move Generation
Uses engine's `analyzePosition()` method to obtain legal moves, ensuring 100% valid move generation.

## First Move Test Strategy

The `ai_thinking_hang_first_move_test.dart` is specifically designed for the observation that **most hangs occur on AI's first response** (move 2).

### Why This Test?
- **Faster**: Only tests 2 moves per game → can test 500 games in ~5-10 min
- **Focused**: Targets the exact scenario where bugs occur most frequently
- **Higher Coverage**: Tests many different opening positions quickly

### Test Flow
```
For each game (500 iterations):
  1. Human plays move 1 (random legal move)
  2. Wait for AI move 2 (30s timeout)
  3. If timeout → HANG DETECTED, save state, STOP
  4. If success → start next game
```

### When to Use
- When you suspect the bug occurs on AI's first move
- For rapid iteration during debugging
- As a quick smoke test before full testing

## Related Files

- `lib/game_page/services/controller/game_controller.dart` - `engineToGo()` method
- `lib/game_page/services/engine/engine.dart` - `search()` method
- `automated_move_test_runner.dart` - Test framework reference

