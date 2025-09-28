# Automated Move Tests

This directory contains an automated testing system for validating **REAL AI** move generation after importing move lists in Human vs. Human mode.

## Overview

The automated move testing system allows you to:
1. Import move lists in the standard notation format
2. Execute "move now" to trigger **REAL C++ AI ENGINE** move generation
3. Validate that the resulting move sequences match expected outcomes
4. Generate detailed test reports with pass/fail status

## Important: Real AI Engine Required

**⚠️ These tests use the REAL C++ AI engine with REAL GUI configurations, not mocks or simulations.**

Before running these tests, ensure that:
1. The C++ engine is compiled and available
2. The Flutter app can communicate with the native engine
3. The engine binary is in the correct location for your platform
4. **The tests will use your current GUI settings** (AI difficulty, search algorithm, rules, etc.)

## Files

- `automated_move_test_models.dart` - Data models for test cases and results
- `automated_move_test_runner.dart` - Core test execution engine
- `automated_move_test_data.dart` - Sample test configurations and helper methods
- `automated_move_test.dart` - Main test file with test cases
- `AUTOMATED_MOVE_TESTS_README.md` - This documentation file

## How to Use

### Prerequisites

Before running the tests, make sure the C++ engine is built:

```bash
# From the repository root
cd src
make  # or your platform-specific build command
```

### Running Tests

There are two ways to run the automated move tests:

#### 1. Unit Tests (Framework Testing)
Test the framework without real AI engine:
```bash
# Navigate to the Flutter app directory
cd src/ui/flutter_app

# Run unit tests (tests framework, not real AI)
flutter test test/game/automated_move_test.dart
```

#### 2. Integration Tests (Real AI Testing)
Test with the actual C++ AI engine:
```bash
# Navigate to the Flutter app directory
cd src/ui/flutter_app

# Run integration tests with real AI engine
flutter test integration_test/automated_move_integration_test.dart

# Run with verbose output to see detailed AI execution logs
flutter test integration_test/automated_move_integration_test.dart --verbose
```

**⚠️ For real AI testing, use the integration tests!** The unit tests will fail with "MissingPluginException" because they don't have access to the native C++ engine.

### First Time Setup

When you first run the tests, they will fail because the expected sequences are placeholders. To set up the tests properly:

1. **Run the integration tests once** to see what the AI actually generates:
   ```bash
   flutter test integration_test/automated_move_integration_test.dart --verbose
   ```

2. **Check the test output** for lines like:
   ```
   [AutomatedMoveTestRunner] Final sequence: "1. d2 f6 2. g7 e5 3. b4 a1 ..."
   [AutomatedMoveTestRunner] [FAILED] sample_game_1 (1250ms)
   [AutomatedMoveTestRunner]   Actual: 1. d2 f6 2. g7 e5 3. b4 a1 ...
   ```

3. **Update the test data** in `automated_move_test_data.dart` with the actual sequences:
   ```dart
   expectedSequences: [
     '1. d2 f6 2. g7 e5 3. b4 a1 ...', // Replace with actual AI output
     // Add alternative valid sequences if AI behavior can vary
   ],
   ```

4. **Re-run the tests** to verify they now pass with the correct expected sequences.

### Configuration Settings

The tests will use your current application settings, which means:

**AI Settings (from General Settings)**:
- **Skill Level**: Determines AI strength (1-20)
- **Move Time**: Time limit for AI thinking
- **Search Algorithm**: MTDF, Alpha-Beta, etc.
- **Perfect Database**: Whether to use endgame databases
- **AI Behavior**: Lazy AI, trap awareness, mobility consideration, etc.

**Rule Settings**:
- **Game Variant**: Nine Men's Morris, Twelve Men's Morris, etc.
- **Pieces Count**: Number of pieces per player
- **Board Configuration**: Diagonal lines, flying rules, etc.
- **Mill Formation**: Rules for forming and breaking mills

**To modify test behavior**:
1. **Change settings in the GUI** before running tests
2. Or **modify the database initialization** in the test setup
3. The test output will show current settings being used

### Creating Custom Test Cases

#### Simple Test Case
```dart
final MoveListTestCase customTest = AutomatedMoveTestData.createSimpleTestCase(
  id: 'my_test_1',
  description: 'Test AI response to specific opening',
  moveList: '''
 1.    d2    d6
 2.    a1    g7
 3.    g1    a7
''',
  expectedSequence: 'Expected move sequence after AI execution',
);
```

#### Multi-Option Test Case
```dart
final MoveListTestCase multiTest = AutomatedMoveTestData.createMultiOptionTestCase(
  id: 'multi_test_1',
  description: 'Test with multiple valid AI responses',
  moveList: '''
 1.    b2    f6
 2.    g7    e5
''',
  expectedSequences: [
    'First possible AI sequence',
    'Second possible AI sequence',
    'Third possible AI sequence',
  ],
);
```

#### Custom Test Configuration
```dart
final AutomatedMoveTestConfig customConfig = AutomatedMoveTestData.createCustomConfig(
  configName: 'My Custom Tests',
  batchDescription: 'Testing specific AI behaviors',
  testCases: [customTest, multiTest],
  maxWaitTimeMs: 15000,
  stopOnFirstFailure: false,
);
```

### Move List Format

The system accepts move lists in the standard notation format:

```
 1.    b2    f6
 2.    g7    e5
 3.    b4    a1
 4.    b6xa1    a7
 5.    d2    c5xb6
 6.    d5xe5xc5    c3
 7.    f2xf6    g1
 8.    e4    d1
 9.    c4    a4
10.    d6    d7
11.    f4    g4
12.    e3    d3xd2
13.    f2-d2xd1xd3    a7-b6
14.    d5-e5xg1    g4-g1
15.    e3-f2xb6    a4-a1xb2
16.    b4-b2
```

Key format requirements:
- Line numbers followed by a period (e.g., "1.", "2.")
- Moves separated by whitespace
- Capture moves indicated with 'x' (e.g., "b6xa1")
- Multi-step moves connected with 'x' (e.g., "d5xe5xc5")
- Movement indicated with '-' (e.g., "f2-d2")

## Test Process

1. **Setup**: Game controller is reset and set to Human vs. Human mode
2. **Import**: The move list is imported using `ImportService.import()`
3. **Execute**: `moveNow()` is called to trigger AI move generation
4. **Validate**: The resulting move sequence is compared against expected sequences
5. **Report**: Test results are printed with detailed pass/fail information

## Expected Sequences

To determine the correct expected sequences for your test cases:

1. Run the test initially with placeholder expected sequences
2. Observe the actual AI-generated sequences in the test output
3. Update your test cases with the correct expected sequences
4. Re-run tests to validate they pass

## Configuration Options

### Test Case Options
- `id`: Unique identifier for the test case
- `description`: Human-readable description of what the test validates
- `moveList`: The move sequence to import
- `expectedSequences`: List of valid expected outcomes
- `enabled`: Whether the test case should be executed

### Test Configuration Options
- `configName`: Name of the test configuration
- `batchDescription`: Overall description of the test batch
- `testCases`: List of test cases to execute
- `maxWaitTimeMs`: Maximum time to wait for AI moves (default: 10000ms)
- `stopOnFirstFailure`: Whether to stop on first failure (default: false)

## Sample Configurations

The system includes several pre-defined test configurations:

- `basicTestConfig`: Basic tests with sample move sequences
- `comprehensiveTestConfig`: More extensive test suite
- `quickTestConfig`: Fast validation tests for CI/CD

## Output Format

Test results are printed in a structured format:

```
[AutomatedMoveTestRunner] Starting test batch: Basic AI Move Tests
[AutomatedMoveTestRunner] Batch description: Basic automated tests to validate AI move generation after importing move lists
[AutomatedMoveTestRunner] Executing test case: sample_game_1
[AutomatedMoveTestRunner] [PASSED] sample_game_1 (1250ms)
[AutomatedMoveTestRunner]   Description: Test AI behavior after importing a complete game sequence
[AutomatedMoveTestRunner]   Matched: Expected sequence 1

[AutomatedMoveTestRunner] =====================================
[AutomatedMoveTestRunner] TEST BATCH SUMMARY
[AutomatedMoveTestRunner] =====================================
[AutomatedMoveTestRunner] Configuration: Basic AI Move Tests
[AutomatedMoveTestRunner] Total Tests: 3
[AutomatedMoveTestRunner] Passed: 2
[AutomatedMoveTestRunner] Failed: 1
[AutomatedMoveTestRunner] Success Rate: 66.7%
[AutomatedMoveTestRunner] Total Time: 3750ms
[AutomatedMoveTestRunner] =====================================
```

## Troubleshooting

### Common Issues

1. **Timeout Errors**: Increase `maxWaitTimeMs` if AI takes longer to respond
2. **Import Failures**: Verify move list format matches expected notation
3. **Mock Engine Issues**: Ensure engine mocks are properly configured in test setup

### Debugging Tips

1. Enable verbose test output to see detailed execution logs
2. Check that the game controller is properly reset between tests
3. Verify that expected sequences exactly match AI output format
4. Use shorter test cases for debugging complex scenarios

## Integration with CI/CD

The tests can be integrated into continuous integration pipelines:

```yaml
# Example GitHub Actions step
- name: Run Automated Move Tests
  run: flutter test test/game/automated_move_test.dart --verbose
```

## Future Enhancements

Potential improvements to the testing system:
- Support for different game variants
- Performance benchmarking capabilities
- Automated expected sequence generation
- Integration with game analysis tools
- Support for parallel test execution
