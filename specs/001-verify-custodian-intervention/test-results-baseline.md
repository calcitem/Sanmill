# Test Results Baseline

**Date**: 2025-10-06
**Task**: T001 - Run existing integration tests

## Execution Environment

- **Platform**: Linux (headless CI environment)
- **Flutter SDK**: 3.35.5 (snap installation)
- **Test Type**: Integration tests with real app build

## Test Execution Status

**Status**: ❌ **SKIPPED** - Build dependency missing

**Error**: CMake error - audioplayers_linux package not found in headless Linux environment

**Root Cause**: Integration tests require full GUI application build with audio player dependencies. This is not available in headless/CI environments without additional system packages.

## Alternative Approach

Since integration tests cannot run in this environment, we will:

1. **Focus on unit tests** that don't require full app build
2. **Create standalone unit tests** for FEN notation, move legality, and rule logic
3. **Document existing integration test coverage** via code analysis (not execution)

## Existing Integration Test Inventory

From `automated_move_test_data.dart`, the following 23 test cases exist in `custodianCaptureAndInterventionCaptureTestConfig`:

### Intervention Capture Tests (10 cases)
1. `movingWhiteInterventionWin` - Moving/White/intervention+mill
2. `movingBlackMillCapture` - Moving/Black/intervention captures from mill
3. `placingWhiteIntervention` - Placing/White/intervention/1 piece captured
4. `placingWhiteCrossMillCapture` - Placing/White/intervention/cross/mill capture
5. `placingWhiteSingleCaptureA4` - Placing/White/intervention/single piece A4
6. `placingWhiteSingleCaptureB2` - Placing/White/intervention/single piece B2
7. `placingWhiteVerticalLineCaptured` - Placing/White/intervention/vertical line
8. `placingBlackInterventionMill` - Placing/Black/intervention+mill
9. `placingBlackSixMoveMill` - Placing/Black/intervention+mill (6 moves)
10. `movingBlackIntervention` - Moving/Black/intervention

### Custodian Capture Tests (6 cases)
11. `movingWhiteCustodianMill` - Moving/White/custodian+mill/select mill
12. `placingWhiteCustodian` - Placing/White/custodian
13. `placingWhiteDoubleCustodian` - Placing/White/2 custodians/1 captured
14. `placingBlackFullBoard` - Placing/Black/custodian/board full
15. `placingBlackCustodianMillRemoved` - Placing/Black/custodian+mill/mill piece removed
16. `placingBlackInterventionMillOtherRemoved` - Placing/Black/intervention+mill/other removed

### Combo & Edge Cases (4 cases)
17. `placingWhiteTwoCaptured` - Placing/White/intervention/2 already captured
18. `advancedMultipleCaptures` - Multiple captures sequences
19. `placingWhiteOneCaptured` - Placing/White/intervention/1 captured
20. `placingWhiteCrossOneCaptured` - Placing/White/intervention/cross/1 captured

### Mill-related Tests (3 cases)
21. `placingWhiteBoardFull` - Placing/White/board full scenarios
22. `placingWhiteBothInMill` - Placing/White/both pieces in mill
23. `placingWhiteInterventionMillOneRemoved` - Placing/White/intervention+mill/one removed

**Total**: 23 test cases covering intervention, custodian, and combinations

## Recommendation

**Proceed with T002 (coverage audit)** via code analysis, then **create unit tests (T003-T007)** that can run without full app build.

Unit tests for FEN parsing, rule logic, and move validation can test the business logic directly without requiring GUI components or audio players.
