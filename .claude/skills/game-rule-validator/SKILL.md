---
name: "New Rule Completeness Validator"
description: "Validates that all necessary code changes are implemented when adding new game rules; use when adding new game rules or variants to ensure no files are missed."
---

# New Rule Completeness Validator

## Purpose

When adding a new game rule or rule variant to Sanmill, you need to modify multiple files (typically 70-80 files, including ~60 localization files). This skill provides a **completeness checklist** to ensure no necessary code changes are missed.

**Reference**: `docs/guides/ADDING_NEW_GAME_RULES.md`

## Use Cases

- Adding a new game rule variant
- Adding new game mechanics to existing rules (e.g., new capture rules)
- Modifying rule structure or parameters
- Reviewing rule-related pull requests

## Architecture Philosophy

> Sanmill is **configuration-based**, not inheritance-based. Rule variants are expressed as **data** (`Rule` in C++, `RuleSettings` in Flutter) and toggled at runtime. Any new mechanics must be gated by booleans/params so existing variants remain untouched and fast.

## Quick Overview

- **Estimated time**: Simple parameter rule 2-4 hours; new mechanics 6-8 hours
- **Complexity**: ⭐⭐⭐ Medium-High
- **Touched files**: ~70-80 total (incl. ~60 ARB localization files)

## Core Validation Checklist (Required Modifications)

### 1. C++ Engine Rule Definition

#### File: `src/rule.cpp`
- [ ] Added new rule definition to the end of `RULES[]` array
- [ ] Set all required fields:
  - [ ] `name` - Rule name (max 32 chars)
  - [ ] `description` - Rule description (max 512 chars)
  - [ ] `pieceCount`, `flyPieceCount`, `piecesAtLeastCount`
  - [ ] `hasDiagonalLines` - Whether diagonal lines exist
  - [ ] Mill formation action and phase flags
  - [ ] Capture rule configs (custodian, intervention, leap)
  - [ ] Flying, draw rules (`mayFly`, `nMoveRule`, etc.)

**Example structure**:
```cpp
{
  "Your Rule Name",
  "Short description",
  9, 3, 3,                      // pieceCount, flyPieceCount, piecesAtLeastCount
  false,                        // hasDiagonalLines
  MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
  /*mayMoveInPlacingPhase*/ false,
  /*isDefenderMoveFirst*/ false,
  /*mayRemoveMultiple*/ false,
  // ... other fields
  kDefaultCaptureRuleConfig,    // custodian
  kDefaultCaptureRuleConfig,    // intervention
  kDefaultCaptureRuleConfig,    // leap
  /*mayFly*/ true,
  /*nMoveRule*/ 100,
  /*endgameNMoveRule*/ 100,
  /*threefoldRepetitionRule*/ true
}
```

#### File: `src/rule.h`
- [ ] Incremented `N_RULES` constant (to match new RULES[] length)
- [ ] If new parameters needed, added new fields to `Rule` struct?

```cpp
// e.g., if it was 11, now it should be 12
constexpr auto N_RULES = 12;
```

### 2. Flutter UI Models

#### File: `lib/rule_settings/models/rule_settings.dart`
- [ ] Added new rule variant value to `RuleSet` enum
- [ ] Created new `RuleSettings` subclass (e.g., `YourNewVariantRuleSettings`)
- [ ] All fields in new subclass **match 1-to-1** with C++ `Rule` struct
- [ ] Updated `ruleSetDescriptions` map with description
- [ ] Updated `ruleSetProperties` map with default property instance

**Example**:
```dart
enum RuleSet {
  // ... existing variants
  yourNewVariant,  // new
}

class YourNewVariantRuleSettings extends RuleSettings {
  const YourNewVariantRuleSettings({
    // All params must match C++ Rule fields
  }) : super(/* ... */);
}
```

### 3. Flutter UI Selection Interface

#### File: `lib/rule_settings/widgets/modals/rule_set_modal.dart`
- [ ] Added `RadioListTile` or similar UI component for selecting new rule
- [ ] UI item correctly references new `RuleSet` enum value
- [ ] If rule is experimental, marked as "Experimental" in `rule_settings_page.dart`?

### 4. Localization (Internationalization)

#### Files: `lib/l10n/intl_*.arb` (~60 files)
- [ ] `intl_en.arb` - Added English translations
- [ ] `intl_zh_CN.arb` - Added Simplified Chinese translations
- [ ] All other `intl_*.arb` files - At least copied English version
- [ ] Ran `flutter gen-l10n` to generate localization code

**Key strings**:
- Rule name
- Rule description
- Any new UI labels or hints

## Conditional Validation Checklist (Based on Mechanic Type)

### 5. Game Logic Modifications (If Gameplay Changed)

#### File: `src/position.cpp` (C++ side)
- [ ] **Must modify**: If new rule changes placement, movement, or capture logic
- [ ] Used **conditional guards** for performance:
  ```cpp
  if (!rule.yourFeature) return fastPath();
  // new logic
  ```
- [ ] Handled all edge cases

#### File: `lib/game_page/services/engine/position.dart` (Flutter side)
- [ ] **Must mirror** logic from C++ `position.cpp`
- [ ] C++ and Dart game logic remain **fully symmetric**
- [ ] Implemented `_putPiece`, `_movePiece`, `_removePiece` related logic

> **Important**: User-visible game logic must be **symmetrically implemented** in both C++ and Dart. Move generation (movegen) is C++ only.

### 6. Move Generation (C++ Only)

#### File: `src/movegen.cpp`
- [ ] If custom movement patterns exist (e.g., special move rules), updated move generation logic?
- [ ] Added conditional guards to avoid affecting other rules?

### 7. Mill Formation

#### File: `src/mills.cpp`
- [ ] If rule has non-standard mill formation, updated this file?

### 8. Engine Options (If Added New Rule Fields)

#### File: `lib/game_page/services/engine/engine.dart`
- [ ] **Must modify**: If `Rule` struct gained new fields
- [ ] Added logic in `setRuleOptions()` method to send new parameters
- [ ] Parameter names match UCI option names

#### File: `src/ucioption.cpp`
- [ ] **Must modify**: If `Rule` struct gained new fields
- [ ] Added corresponding UCI option definitions
- [ ] Added `on_change` handlers to apply values to global `rule` object

**Example**:
```cpp
// ucioption.cpp
{"YourNewOption", "false", "bool", {}, on_your_new_option}

void on_your_new_option(Option &o) {
    rule.yourNewField = o.get<bool>();
}
```

### 9. FEN Format Extension (Only If Dynamic State Persistence Needed)

> **When to extend FEN**: Only when you must persist **dynamic state that cannot be recomputed from the board**.

#### Need to extend if:
- [ ] Need to track capture targets (custodian/intervention)
- [ ] Need to persist temporary user choice (e.g., `preferredRemoveTarget`)
- [ ] Need to store intermediate multi-step state across moves/undo/search
- [ ] Need history-dependent constraints (e.g., "same piece can't move twice")

#### **Do NOT extend** for:
- ✗ Static rule params (piece counts, `hasDiagonalLines`, etc.)
- ✗ Anything derivable from board (piece counts, mills)
- ✗ Global flags (`mayFly`, `mayRemoveMultiple`)

#### Files: `src/position.h`, `src/position.cpp`
- [ ] If FEN extension needed:
  - [ ] Added new fields in `position.h`
  - [ ] Added export logic in `fen()` method
  - [ ] Added parsing logic in `set()` method
  - [ ] Followed backward compatibility rules: new fields at end, missing fields have safe defaults

#### File: `lib/game_page/services/engine/position.dart`
- [ ] Mirrored C++ FEN fields
- [ ] Implemented `_getFen()` export logic
- [ ] Implemented `setFen()` parsing logic

#### Files: `tests/test_position.cpp`, Flutter integration tests
- [ ] Added FEN round-trip tests (export then reimport, state should match)

### 10. Evaluation and Search (Rare)

#### File: `src/evaluate.cpp`
- [ ] If rule variant requires special evaluation logic, updated?

#### File: `src/search.cpp`
- [ ] If rule variant requires special search logic, updated?

## Testing Validation Checklist

### 11. C++ Tests

#### Files: `tests/test_*.cpp`
- [ ] Rule loading and bounds tests (`set_rule(i)` correctly loads new rule)
- [ ] Position/logic unit tests (including new mechanics)
- [ ] If FEN extended, added FEN round-trip tests (`tests/test_position.cpp`)
- [ ] Ran `make test` to ensure all tests pass

**Run tests**:
```bash
cd src
make build all
make test
```

### 12. Flutter Tests

#### Widget tests
- [ ] New rule displays correctly in modal
- [ ] Selecting new rule correctly saves and restores

#### Engine mirror tests
- [ ] Test scenarios cover `_putPiece`, `_movePiece`, `_removePiece`
- [ ] C++ and Dart logic produce same results

#### Integration tests
- [ ] Select new rule → start new game → verify behavior visible

**Run tests**:
```bash
cd src/ui/flutter_app
flutter test
```

### 13. Performance Benchmarks

- [ ] Ran benchmarks (if project has `make benchmark`)
- [ ] Ensured **no performance regression when new feature is off**
- [ ] Verified conditional guards enable early exits on hot paths

## Build, Format, and Generate

### 14. Code Formatting

```bash
# Format all code
./format.sh
```

- [ ] C++ code formatted (clang-format)
- [ ] Dart code formatted (dart format)

### 15. Localization Generation

```bash
cd src/ui/flutter_app
flutter gen-l10n
```

- [ ] Generated localization code without errors

### 16. Full Build

```bash
# C++ build
cd src
make build all

# Flutter build (pick a platform to test)
cd ../src/ui/flutter_app
flutter build apk  # Android
# or
flutter build ios   # iOS
# or
flutter build windows  # Windows
```

- [ ] All platforms build successfully

## Quality & Safety Assurance Checklist

### 17. Backward Compatibility
- [ ] **All existing rule variants** remain unchanged
- [ ] **All old tests** still pass
- [ ] New features don't affect existing game logic (via conditional guards)

### 18. Performance Parity
- [ ] When new feature is **off**, no performance regression
- [ ] Hot paths remain efficient (early exits)
- [ ] Benchmarks show acceptable performance

### 19. Code Symmetry
- [ ] C++ and Dart user-visible logic **fully symmetric**
- [ ] Same inputs produce same outputs
- [ ] Tests verify symmetry

### 20. Documentation and Comments
- [ ] Clear docs and comments near each new flag
- [ ] Complex logic has explanatory comments
- [ ] Updated `docs/guides/ADDING_NEW_GAME_RULES.md` (if needed)

### 21. Localization Completeness
- [ ] At minimum, includes English (EN) and Simplified Chinese (ZH_CN)
- [ ] Ideally, all ARB files updated
- [ ] All translation strings meaningful with no placeholders

## Complete QA Checklist (Summary)

Before submitting PR, confirm all of the following:

- [ ] `RULES[]` has new entry, `N_RULES` incremented
- [ ] Flutter `RuleSet` enum and `RuleSettings` subclass match C++
- [ ] UI selection interface added, strings localized
- [ ] Game logic uses conditional guards and early exits
- [ ] C++ ↔ Dart position logic symmetric
- [ ] FEN extended if necessary; round-trip tests added
- [ ] If new `Rule` fields added, engine options updated
- [ ] All tests pass (C++ and Flutter)
- [ ] Benchmarks show no performance drop when feature off
- [ ] Code formatted, builds succeed
- [ ] Documentation and comments clear and complete

## Validation Workflow

### Phase 1: Planning (1 hour)
1. Determine specific requirements for rule variant
2. Determine if simple parameter adjustment or new mechanics needed
3. List files that need modification

### Phase 2: C++ Implementation (2-3 hours)
1. Modify `src/rule.h` and `src/rule.cpp`
2. If new mechanics needed, modify `src/position.cpp`, `src/movegen.cpp`, etc.
3. If new fields added, update `src/ucioption.cpp`
4. Run C++ tests, ensure they pass

### Phase 3: Flutter Implementation (2-3 hours)
1. Modify `rule_settings.dart` (enum + subclass + mappings)
2. Modify `rule_set_modal.dart` (UI selection)
3. If game logic modified, mirror to `position.dart`
4. Update `engine.dart`'s `setRuleOptions()`
5. Run Flutter tests, ensure they pass

### Phase 4: Localization (30 minutes)
1. Update `intl_en.arb` and `intl_zh_CN.arb`
2. Batch update other ARB files (can use English initially)
3. Run `flutter gen-l10n`

### Phase 5: Testing & Validation (1-2 hours)
1. Run all C++ tests
2. Run all Flutter tests
3. Manually test new rule behavior in UI
4. Check performance benchmarks
5. Verify backward compatibility

### Phase 6: Code Review & Documentation (30 minutes)
1. Run code formatting
2. Review all changes
3. Update docs and comments
4. Complete QA checklist

## Common Pitfalls and Notes

### ❌ Common Mistakes

1. **Forgot to increment `N_RULES`**
   - Symptom: Runtime crash or rule loading failure
   - Fix: Ensure `N_RULES` in `src/rule.h` matches `RULES[]` length

2. **C++ and Flutter fields don't match**
   - Symptom: UI-set rule parameters don't take effect
   - Fix: Ensure `RuleSettings` fields match `Rule` struct 1-to-1

3. **Missing UCI options**
   - Symptom: New Rule field values always default
   - Fix: Add corresponding options and handlers in `ucioption.cpp`

4. **Didn't mirror game logic to Dart**
   - Symptom: UI preview inconsistent with actual game
   - Fix: Ensure `position.dart` mirrors `position.cpp` logic

5. **Incomplete localization**
   - Symptom: Some languages show placeholders or English
   - Fix: At minimum complete English and Chinese, others can use English placeholder

6. **Performance regression**
   - Symptom: Game slower even when not using new feature
   - Fix: Use conditional guards, ensure early exits

7. **Over-extended FEN**
   - Symptom: FEN strings too long, hard to debug
   - Fix: Only extend FEN when must persist dynamic state

### ✓ Best Practices

1. **Incremental development**: Implement C++ first, test, then do Flutter
2. **Frequent testing**: Run relevant tests after each file modification
3. **Use conditional guards**: Ensure new code doesn't affect existing rules
4. **Maintain symmetry**: C++ and Dart logic should be readable side-by-side
5. **Documentation first**: Write comments and docs before code
6. **Reference existing rules**: Look at other rules in `RULES[]` as templates

## Reference Files and Resources

### Core Documentation
- **`docs/guides/ADDING_NEW_GAME_RULES.md`** - Official guide for adding rules (must read)

### C++ Files
- `src/rule.h` - Rule struct definition
- `src/rule.cpp` - RULES[] array
- `src/position.h/.cpp` - Game position and logic
- `src/movegen.cpp` - Move generation
- `src/ucioption.cpp` - UCI options
- `src/mills.cpp` - Mill formation logic
- `include/config.h` - Default config (rarely modified)

### Flutter Files
- `lib/rule_settings/models/rule_settings.dart` - Rule models
- `lib/rule_settings/widgets/modals/rule_set_modal.dart` - UI selection
- `lib/game_page/services/engine/position.dart` - Position mirror
- `lib/game_page/services/engine/engine.dart` - Engine communication
- `lib/l10n/intl_*.arb` - Localization files

### Test Files
- `tests/test_*.cpp` - C++ unit tests
- `test/` - Flutter unit and widget tests
- `integration_test/` - Flutter integration tests

## Output Format

Validation results should be reported clearly:

```
✓ [Complete] Core File Modifications
  ✓ src/rule.cpp - RULES[] added
  ✓ src/rule.h - N_RULES incremented
  ✓ rule_settings.dart - RuleSet enum added
  ...

⚠ [Warning] Conditional File Modifications
  ✓ src/position.cpp - Logic updated
  ✗ position.dart - Logic not mirrored (needs fix)
  ...

✓ [Complete] Test Validation
  ✓ C++ tests all passed (25/25)
  ✓ Flutter tests all passed (42/42)
  ...

✗ [Failed] Localization
  ✓ intl_en.arb - Updated
  ✓ intl_zh_CN.arb - Updated
  ✗ Other ARB files - Not updated (needs completion)
  ...

📊 Completion: 75% (15/20 checks passed)
💡 Recommendation: Priority fix position.dart mirror and localization
```

## Summary

Adding a new game rule is a systematic effort requiring careful coordination between the C++ engine and Flutter UI. Using this checklist ensures:

- ✓ No necessary file modifications are missed
- ✓ C++ and Flutter stay synchronized
- ✓ Backward compatibility is not broken
- ✓ Performance is not affected
- ✓ Test coverage is adequate
- ✓ Localization is complete

**Remember**: When in doubt, refer to `docs/guides/ADDING_NEW_GAME_RULES.md` and existing rule implementations.
