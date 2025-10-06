# Integration Test Failures: Root Cause Analysis

**Date**: 2025-10-06
**Test Results**: 6/26 PASSED (23.1% success rate)
**Issue**: 20/26 tests failing, mostly with "Actual Result" empty

## Root Cause Identified

### Issue 1: Import Format Mismatch (RESOLVED)

**Original Problem**: Import service used `_playOkNotationToMoveString` expecting numeric notation (1-24)
**Test Data Format**: Uses standard algebraic notation (a1-g7, xa4, b4xa4xc4)
**Solution Applied**: Changed to `_wmdNotationToMoveString` in `_importPlayOk` function

**Status**: ✅ FIXED but not used (see Issue 2)

### Issue 2: Wrong Import Path (IDENTIFIED)

**Problem**: Test data is NOT recognized as PlayOK format!

**Detection Logic** (`import_helpers.dart:40-62`):
```dart
bool isPlayOkMoveList(String text) {
  // Line 57: Reject if contains letters a-g
  if (noTag.isEmpty || RegExp(r'[a-gA-G]').hasMatch(noTag)) {
    return false;  // ← Test data fails here!
  }
  return true;
}
```

**Result**: Test data with `a4`, `xa4`, `b4xa4xc4` is classified as **PGN format**, not PlayOK
**Import Path**: Calls `_importPgn` (line 261), NOT `_importPlayOk` (line 207)

### Issue 3: Actual Root Cause - Illegal Moves

**Observation**: `_importPgn` already has multi-capture support (line 468-499)
**Failure Point**: `localPos.doMove(uciMove)` returns false (line 574)
**Error**: `ImportFormatException(" $segment → $uciMove")` thrown at line 576

**Conclusion**: The moves are being parsed correctly, but **`doMove` rejects them as illegal**!

## Failure Analysis

### Category A: Import Failures (14 tests)

**Error Pattern**: `Exception: Failed to import move list:  xa4/xb2/xc4/...`

**Root Cause**: After placing a piece (e.g., `b4`), attempting to capture (`xa4`) is **rejected by Position.doMove()** as illegal.

**Possible Reasons**:
1. **Capture not actually triggered**: The placement didn't trigger intervention/custodian
2. **Wrong capture target**: `xa4` is not a legal target in that position
3. **Rule not enabled**: Custodian/intervention rules not active in test configuration
4. **Implementation bug**: Capture detection logic incorrect

### Category B: Behavior Mismatches (6 tests)

**Error Pattern**: `Did not match any expected sequence` (Actual: d1, Expected: xa7 xg7)

**Root Cause**: AI makes a different move than expected.

**Possible Reasons**:
1. **AI behavior changed**: Implementation updates changed AI move selection
2. **Rule behavior changed**: Custodian/intervention logic changed, affecting legal moves
3. **Test expectations outdated**: Tests written for old behavior
4. **Non-deterministic AI**: AI選擇不同的合法走法

### Passing Tests (6 tests)

**Pattern**: Tests that pass are mostly:
- `five_move_opening`, `six_move_development` - Simpler scenarios
- `placing_black_intervention_mill_other_removed` - Specific edge case
- `invalid_*` tests - Negative tests (expected to fail import)

## Investigation Needed

### High Priority: Verify Rules Are Enabled

Check if custodian and intervention rules are actually enabled in test configuration:

```dart
// In test setup
final ruleSettings = DB().ruleSettings;
print('Has Custodian: ${ruleSettings.hasCustodianRule}');  // Should be true
print('Has Intervention: ${ruleSettings.hasInterventionRule}');  // Should be true
```

### Medium Priority: Validate Test Data

For each failing test case, manually verify:
1. Does the board position actually trigger custodian/intervention?
2. Is the expected capture target legal according to current rules?
3. Are there rule configuration issues (mayRemoveMultiple, etc.)?

### Example: `intervention_single_a4`

**Move List**:
```
1.    a4    d6
2.    c4    d7
3.    b2    f6
4.    b6    b4xa4  ← Fails here
```

**Expected After Move 4**: White places b4, triggers intervention, captures a4, then should capture xc4

**Verification Needed**:
- Does b4 placement actually trigger intervention?
- Is a4 a legal intervention target in this position?
- After capturing a4, is c4 the required second endpoint?

## Recommended Fix Strategy

### Option 1: Fix Test Data (If Tests Are Wrong)

If the current implementation is correct and tests are outdated:
1. Run each test case manually in the app
2. Record actual intervention/custodian triggers
3. Update `expectedSequences` to match current behavior
4. Update move lists if positions don't trigger rules as expected

### Option 2: Fix Implementation (If Rules Are Broken)

If tests are correct and implementation has bugs:
1. Debug why `doMove` returns false for supposedly legal captures
2. Check custodian/intervention detection logic in position.dart
3. Verify FEN import/export doesn't lose capture state
4. Fix bugs in move generation/validation

### Option 3: Investigate Rule Configuration

Most likely issue - verify:
1. Rules enabled: `hasCustodianRule`, `hasInterventionRule`
2. MockDB provides correct settings
3. Test environment matches production configuration

## Next Steps

1. **Add debug logging** to understand why `doMove` fails:
   ```dart
   final bool ok = localPos.doMove(uciMove);
   if (!ok) {
     print('DEBUG: doMove failed for $uciMove');
     print('DEBUG: Position: ${localPos.fen}');
     print('DEBUG: Piece to remove: ${localPos.pieceToRemoveCount}');
     throw ImportFormatException(" $segment → $uciMove");
   }
   ```

2. **Check rule settings** in test runner initialization

3. **Manually validate one failing test** to understand the root cause

## Conclusion

**Import service is working correctly** - it parses multi-capture notation.

**Real issue**: `Position.doMove()` rejects the captures as illegal, which means:
- Either the test data is incorrect (moves don't trigger rules as expected)
- Or the implementation has bugs in capture validation/detection

**Recommendation**: This requires detailed debugging of specific test cases to determine if it's a test data problem or implementation bug. The verification task has successfully identified potential issues that need investigation.
