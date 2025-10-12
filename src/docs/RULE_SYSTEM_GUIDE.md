# Rule System Guide

## Overview

Sanmill's rule system provides a flexible, configuration-based approach to supporting multiple Mill game variants. Rules are defined as data structures rather than code, making it easy to add new variants without modifying engine logic.

**Architecture**: Configuration-driven (not inheritance-based)  
**Storage**: Static array of Rule structures  
**Selection**: Index-based rule selection

## Core Concepts

### Configuration-Based Design

```
Rule Variant = Data Structure with Parameters
    ↓
No need for subclasses or virtual functions
    ↓
Add new variant = Add array entry + UI mapping
```

**Advantages**:
- Simple to add new rules
- No code duplication
- Easy to serialize/persist
- Clear parameter visibility
- AI-friendly (declarative)

---

## Rule Structure

### Complete Definition

```cpp
struct Rule {
    char name[32];                    // Display name
    char description[512];            // Full description
    
    // Piece Configuration
    int pieceCount;                   // Pieces per player (6, 9, 12)
    int flyPieceCount;                // Flying threshold (3, 4)
    int piecesAtLeastCount;          // Minimum pieces to continue (3)
    
    // Board Topology
    bool hasDiagonalLines;           // Enable diagonal moves
    
    // Placing Phase Rules
    MillFormationActionInPlacingPhase millFormationActionInPlacingPhase;
    bool mayMoveInPlacingPhase;      // Allow moves during placing
    
    // Moving Phase Rules
    bool isDefenderMoveFirst;        // Second player moves first
    bool mayRemoveMultiple;          // Remove multiple pieces per mill
    bool restrictRepeatedMillsFormation;  // Anti-repetition rule
    bool mayRemoveFromMillsAlways;   // Can always remove from mills
    bool oneTimeUseMill;             // Mills are one-time use
    
    // Endgame Rules
    BoardFullAction boardFullAction;  // Action when board fills
    StalemateAction stalemateAction;  // Action when no moves
    bool mayFly;                      // Flying allowed
    
    // Capture Rules (Special Variants)
    CaptureRuleConfig custodianCapture;      // Custodian capture
    CaptureRuleConfig interventionCapture;   // Intervention capture
    CaptureRuleConfig leapCapture;          // Leap capture
    
    // Draw Rules
    unsigned int nMoveRule;          // N-move rule (50 typical)
    unsigned int endgameNMoveRule;   // Endgame N-move rule
    bool threefoldRepetitionRule;    // Three-fold repetition
};
```

---

## Field Reference

### Basic Configuration

#### `name`
**Type**: `char[32]`  
**Purpose**: Display name for UI  
**Examples**: "Nine Men's Morris", "Twelve Men's Morris", "Dooz"

#### `description`
**Type**: `char[512]`  
**Purpose**: Full description of variant  
**Examples**: "Classic Nine Men's Morris", "Persian variant called Dooz"

---

### Piece Configuration

#### `pieceCount`
**Type**: `int`  
**Range**: 3-12 (typical: 6, 9, 12)  
**Purpose**: Number of pieces each player starts with  
**Impact**: 
- Higher count = longer game
- Affects opening book
- Determines game complexity

**Examples**:
```cpp
pieceCount = 9;   // Nine Men's Morris (standard)
pieceCount = 12;  // Twelve Men's Morris
pieceCount = 6;   // Six Men's Morris (simpler)
pieceCount = 3;   // Three Men's Morris (quick game)
```

---

#### `flyPieceCount`
**Type**: `int`  
**Range**: 0-4 (typical: 3)  
**Purpose**: Threshold for flying (when pieces ≤ this, can fly to any square)  
**Impact**:
- Lower = flying starts earlier
- 0 = no flying ever
- Higher = flying only in dire situations

**Examples**:
```cpp
flyPieceCount = 3;  // Fly when down to 3 pieces (standard)
flyPieceCount = 4;  // Fly when down to 4 pieces (easier)
flyPieceCount = 0;  // No flying allowed (harder)
```

**Dependency**: Only relevant if `mayFly = true`

---

#### `piecesAtLeastCount`
**Type**: `int`  
**Range**: 2-3 (typical: 3)  
**Purpose**: Minimum pieces to continue playing (lose if reduced below this)  
**Impact**: Game ending condition

**Examples**:
```cpp
piecesAtLeastCount = 3;  // Standard (lose with 2 pieces)
piecesAtLeastCount = 2;  // Continue with 2 pieces
```

**Constraint**: `piecesAtLeastCount <= flyPieceCount + 1`

---

### Board Topology

#### `hasDiagonalLines`
**Type**: `bool`  
**Purpose**: Add diagonal connections to board  
**Impact**:
- `true`: 24 + 4 diagonal connections = 28 total connections
- `false`: 24 standard connections only
- Affects move generation
- Changes board complexity

**Standard Board** (hasDiagonalLines = false):
```
a3 -------- b3 -------- c3
|           |           |
|   a2 ---- b2 ---- c2  |
|   |       |       |   |
a1  a1 ---- b1 ---- c1  c1
```

**With Diagonals** (hasDiagonalLines = true):
```
a3 -------- b3 -------- c3
|\          |          /|
| \  a2 -- b2 -- c2  / |
|  \ |     |     | /  |
a1--a1 --- b1 --- c1--c1
```

**Examples**:
```cpp
hasDiagonalLines = false;  // Nine Men's Morris
hasDiagonalLines = true;   // Twelve Men's Morris
```

---

### Placing Phase Rules

#### `millFormationActionInPlacingPhase`
**Type**: `enum MillFormationActionInPlacingPhase`  
**Purpose**: What happens when forming mill during placing  
**Values**:

```cpp
enum class MillFormationActionInPlacingPhase {
    removeOpponentsPieceFromBoard = 0,  // Remove from board (standard)
    removeOpponentsPieceFromHandThenOpponentsTurn = 1,  // Remove from hand, opponent's turn
    removeOpponentsPieceFromHandThenYourTurn = 2,       // Remove from hand, your turn
    opponentRemovesOwnPiece = 3,                        // Opponent removes own piece
    markAndDelayRemovingPieces = 4,                     // Mark for later removal
    removalBasedOnMillCounts = 5,                       // Based on mill count difference
};
```

**Examples**:
```cpp
// Standard Mill rules
millFormationActionInPlacingPhase = 
    MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard;

// El Filja variant
millFormationActionInPlacingPhase = 
    MillFormationActionInPlacingPhase::removalBasedOnMillCounts;
```

---

#### `mayMoveInPlacingPhase`
**Type**: `bool`  
**Purpose**: Allow moving already-placed pieces during placing phase  
**Impact**:
- `true`: Can move pieces even when pieces still in hand
- `false`: Must place all pieces before moving (standard)

**Examples**:
```cpp
mayMoveInPlacingPhase = false;  // Standard (place all first)
mayMoveInPlacingPhase = true;   // Can move during placing
```

---

### Moving Phase Rules

#### `isDefenderMoveFirst`
**Type**: `bool`  
**Purpose**: Second player moves first in moving phase  
**Impact**: Strategic advantage switching

**Examples**:
```cpp
isDefenderMoveFirst = false;  // Standard (first player continues)
isDefenderMoveFirst = true;   // Second player moves first
```

---

#### `mayRemoveMultiple`
**Type**: `bool`  
**Purpose**: Form multiple mills in one move → remove multiple pieces  
**Impact**:
- `true`: Double/triple mill = remove 2/3 pieces
- `false`: Remove only one piece regardless (standard)

**Examples**:
```cpp
mayRemoveMultiple = false;  // Standard (one removal per turn)
mayRemoveMultiple = true;   // Multiple removals for multiple mills
```

---

#### `restrictRepeatedMillsFormation`
**Type**: `bool`  
**Purpose**: Prevent immediate re-forming of same mill  
**Impact**: Anti-repetition measure

**Rule**: If you formed mill by moving piece from A to B, you cannot immediately move it back to A to re-form the same mill.

**Examples**:
```cpp
restrictRepeatedMillsFormation = false;  // Can reform mills freely
restrictRepeatedMillsFormation = true;   // Cannot immediately reform
```

---

#### `mayRemoveFromMillsAlways`
**Type**: `bool`  
**Purpose**: Can remove pieces from mills at any time  
**Impact**:
- `false`: Must remove non-mill pieces first (standard)
- `true`: Can remove from mills immediately

**Examples**:
```cpp
mayRemoveFromMillsAlways = false;  // Protect mills (standard)
mayRemoveFromMillsAlways = true;   // Mills unprotected
```

---

#### `oneTimeUseMill`
**Type**: `bool`  
**Purpose**: Each mill can only be used for removal once  
**Impact**: Tactical complexity

**Examples**:
```cpp
oneTimeUseMill = false;  // Can use mill repeatedly (standard)
oneTimeUseMill = true;   // Mill is "consumed" after first use
```

---

### Endgame Rules

#### `boardFullAction`
**Type**: `enum BoardFullAction`  
**Purpose**: What happens when board fills during placing phase  
**Values**:

```cpp
enum class BoardFullAction {
    firstPlayerLose = 0,              // First player loses (standard)
    firstAndSecondPlayerRemovePiece = 1,  // Both remove a piece
    secondAndFirstPlayerRemovePiece = 2,  // Both remove (opposite order)
    sideToMoveRemovePiece = 3,            // Current player removes
    agreeToDraw = 4,                      // Game is drawn
};
```

**Examples**:
```cpp
boardFullAction = BoardFullAction::firstPlayerLose;  // Standard
boardFullAction = BoardFullAction::agreeToDraw;      // Draw when full
```

---

#### `stalemateAction`
**Type**: `enum StalemateAction`  
**Purpose**: What happens when player has no legal moves  
**Values**:

```cpp
enum class StalemateAction {
    endWithStalemateLoss = 0,           // Lose (standard)
    changeSideToMove = 1,               // Pass turn
    removeOpponentsPieceAndMakeNextMove = 2,     // Remove and continue
    removeOpponentsPieceAndChangeSideToMove = 3, // Remove and pass
    endWithStalemateDraw = 4,           // Draw
};
```

**Examples**:
```cpp
stalemateAction = StalemateAction::endWithStalemateLoss;  // Standard
stalemateAction = StalemateAction::endWithStalemateDraw;  // Draw on stalemate
```

---

#### `mayFly`
**Type**: `bool`  
**Purpose**: Allow flying when pieces ≤ `flyPieceCount`  
**Impact**: Endgame mobility

**Examples**:
```cpp
mayFly = true;   // Standard (can fly when down to 3)
mayFly = false;  // No flying (harder endgame)
```

---

### Capture Rules (Special Variants)

#### `CaptureRuleConfig` Structure

```cpp
struct CaptureRuleConfig {
    bool enabled;                        // Is this capture rule active?
    bool onSquareEdges;                  // Apply on square edges?
    bool onCrossLines;                   // Apply on cross lines?
    bool onDiagonalLines;                // Apply on diagonal lines?
    bool inPlacingPhase;                 // Apply in placing phase?
    bool inMovingPhase;                  // Apply in moving phase?
    bool onlyAvailableWhenOwnPiecesLeq3; // Only when ≤3 pieces?
};
```

---

#### `custodianCapture`
**Purpose**: Capture by surrounding opponent piece  
**Mechanism**: If opponent piece between two of your pieces, capture it

**Example**:
```
Before: * O *
After:  * . *  (O captured)
```

```cpp
custodianCapture = {
    .enabled = false,  // Standard Mill: disabled
    // ... other fields
};
```

---

#### `interventionCapture`
**Purpose**: Capture by blocking opponent piece  
**Mechanism**: If your piece "intervenes" between two opponent pieces

**Example** (if enabled):
```
Before: O . O
Move:   O * O  (place * between)
After:  . * .  (both O captured)
```

```cpp
interventionCapture = {
    .enabled = false,  // Standard Mill: disabled
};
```

---

#### `leapCapture`
**Purpose**: Capture by "leaping" over opponent piece  
**Mechanism**: Jump over opponent to empty square captures the piece

```cpp
leapCapture = {
    .enabled = false,  // Standard Mill: disabled
};
```

**Note**: These capture rules are for special regional variants. Standard Mill does not use them.

---

### Draw Rules

#### `nMoveRule`
**Type**: `unsigned int`  
**Range**: 0-1000 (typical: 50-100)  
**Purpose**: Draw if no piece removed in N plies  
**Impact**: Prevents endless games

**Examples**:
```cpp
nMoveRule = 100;  // Draw after 100 plies without removal
nMoveRule = 50;   // Stricter (shorter games)
```

---

#### `endgameNMoveRule`
**Type**: `unsigned int`  
**Range**: 0-100 (typical: 10-100)  
**Purpose**: Special N-move rule when both players have ≤ threshold pieces  
**Impact**: Faster draws in endgame

**Examples**:
```cpp
endgameNMoveRule = 100;  // Same as regular rule
endgameNMoveRule = 10;   // Much shorter in endgame (Morabaraba)
```

---

#### `threefoldRepetitionRule`
**Type**: `bool`  
**Purpose**: Draw if same position occurs three times  
**Impact**: Prevents infinite loops

**Examples**:
```cpp
threefoldRepetitionRule = true;   // Standard (draw on repetition)
threefoldRepetitionRule = false;  // No repetition draw
```

---

## Predefined Rules

### RULES Array

```cpp
constexpr auto N_RULES = 11;
extern const Rule RULES[N_RULES];
```

**Current Variants** (as of v7.0):
- RULES[0]: Nine Men's Morris (standard)
- RULES[1]: Twelve Men's Morris
- RULES[2]: Dooz (Persian variant)
- RULES[3]: Morabaraba (South African variant)
- RULES[4]: Russian Mill
- RULES[5]: Lasker Morris
- RULES[6]: Cheng San Qi (Chinese variant)
- RULES[7]: Da San Qi (Chinese variant)
- RULES[8]: Zhi Qi (Chinese variant)
- RULES[9]: El Filja (Algerian variant)
- RULES[10]: Experimental (for testing)

---

## Rule Selection

### C++ Side

```cpp
// Select rule by index
bool set_rule(int ruleIdx) noexcept;

// Usage
if (set_rule(1)) {  // Twelve Men's Morris
    // Rule set successfully
} else {
    // Invalid index
}

// Current rule (global)
extern Rule rule;

// Access current rule
int pieces = rule.pieceCount;
bool flying = rule.mayFly;
```

---

### Flutter Side

```dart
// Flutter enum (maps to C++ indices)
enum RuleSet {
  current,           // Use current settings
  nineMensMorris,    // RULES[0]
  twelveMensMorris,  // RULES[1]
  morabaraba,        // Derived from RULES[1] + modifications
  dooz,              // RULES[2]
  laskerMorris,      // RULES[3]
  // ... more variants
}

// Mapping to C++ index
int _ruleSetToCppIndex(RuleSet ruleSet) {
  switch (ruleSet) {
    case RuleSet.nineMensMorris:
      return 0;
    case RuleSet.twelveMensMorris:
      return 1;
    case RuleSet.dooz:
      return 2;
    // ...
  }
}
```

---

## Adding New Rule Variant

### Step 1: C++ - Add to RULES Array

```cpp
// src/rule.cpp

const Rule RULES[N_RULES] = {
    { /* Existing rules 0-10 */ },
    
    // New Rule at RULES[11]
    {
     "My New Variant",                    // name
     "Description of my variant",          // description
     10,                                   // pieceCount
     3,                                    // flyPieceCount
     3,                                    // piecesAtLeastCount
     false,                                // hasDiagonalLines
     MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
     false,                                // mayMoveInPlacingPhase
     false,                                // isDefenderMoveFirst
     false,                                // mayRemoveMultiple
     false,                                // restrictRepeatedMillsFormation
     false,                                // mayRemoveFromMillsAlways
     false,                                // oneTimeUseMill
     BoardFullAction::firstPlayerLose,     // boardFullAction
     StalemateAction::endWithStalemateLoss, // stalemateAction
     kDefaultCaptureRuleConfig,            // custodianCapture
     kDefaultCaptureRuleConfig,            // interventionCapture
     kDefaultCaptureRuleConfig,            // leapCapture
     true,                                 // mayFly
     100,                                  // nMoveRule
     100,                                  // endgameNMoveRule
     true},                                // threefoldRepetitionRule
};
```

### Step 2: C++ - Update N_RULES

```cpp
// src/rule.h

constexpr auto N_RULES = 12;  // Increment from 11 to 12 (example)
```

**Note**: The actual current value is 11. This is an example showing how to increment when adding a new rule.

### Step 3: Flutter - Add Enum Value

```dart
// lib/rule_settings/models/rule_settings.dart

enum RuleSet {
  current,
  nineMensMorris,
  // ... existing ...
  myNewVariant,  // Add new enum value
}
```

### Step 4: Flutter - Create Settings Class

```dart
class MyNewVariantRuleSettings extends RuleSettings {
  const MyNewVariantRuleSettings()
    : super(
        piecesCount: 10,  // Must match C++ pieceCount
        flyPieceCount: 3,
        hasDiagonalLines: false,
        // ... match all parameters from C++ Rule
      );
}
```

### Step 5: Flutter - Add to Maps

```dart
const Map<RuleSet, String> ruleSetDescriptions = {
  // ... existing ...
  RuleSet.myNewVariant: 'Description of my variant',
};

const Map<RuleSet, RuleSettings> ruleSetProperties = {
  // ... existing ...
  RuleSet.myNewVariant: MyNewVariantRuleSettings(),
};
```

### Step 6: Flutter - Map to C++ Index

```dart
int _ruleSetToCppIndex(RuleSet ruleSet) {
  switch (ruleSet) {
    // ... existing cases ...
    case RuleSet.myNewVariant:
      return 11;  // RULES[11] in C++
  }
}
```

### Step 7: Add Localization

```json
// lib/l10n/intl_en.arb
{
  "myNewVariant": "My New Variant"
}

// lib/l10n/intl_zh_CN.arb
{
  "myNewVariant": "我的新规则变体"
}
```

Then run: `flutter gen-l10n`

### Step 8: Test

```cpp
// C++ test
#include "rule.h"
#include <cassert>

void testMyNewVariant() {
    assert(set_rule(11));  // Load new rule
    assert(rule.pieceCount == 10);
    assert(std::string(rule.name) == "My New Variant");
}
```

```dart
// Flutter test
test('MyNewVariant settings correct', () {
  const settings = MyNewVariantRuleSettings();
  expect(settings.piecesCount, equals(10));
});
```

---

## Validation Rules

### Consistency Constraints

1. **Piece Count**: `pieceCount >= piecesAtLeastCount + 1`
2. **Flying**: `flyPieceCount <= piecesAtLeastCount` (if `mayFly = true`)
3. **Board Size**: Standard board supports up to ~12 pieces per side
4. **Parameters Must Match**: C++ Rule ↔ Flutter RuleSettings

### Validation Checklist

- [ ] `pieceCount` in reasonable range (3-12)
- [ ] `flyPieceCount` ≤ `piecesAtLeastCount`
- [ ] `piecesAtLeastCount` ≥ 2
- [ ] Capture rules have consistent `enabled` flag
- [ ] N-move rules > 0 (or 0 to disable)
- [ ] C++ and Flutter parameters match exactly

---

## Common Patterns

### Standard Mill Variant

```cpp
{
 "Standard Name",
 "Standard Description",
 9,      // 9 pieces
 3,      // fly at 3
 3,      // minimum 3
 false,  // no diagonals
 MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
 false,  // place all first
 false,  // first player continues
 false,  // one removal per turn
 false,  // can reform mills
 false,  // must remove non-mill first
 false,  // mills reusable
 BoardFullAction::firstPlayerLose,
 StalemateAction::endWithStalemateLoss,
 kDefaultCaptureRuleConfig,  // no captures
 kDefaultCaptureRuleConfig,
 kDefaultCaptureRuleConfig,
 true,   // flying allowed
 100,    // 50-move rule
 100,    // endgame 50-move
 true    // threefold repetition
}
```

### Harder Variant (No Flying)

```cpp
{
 "No Flying Variant",
 "Standard rules but no flying (harder endgame)",
 9,
 0,      // no flying threshold
 3,
 false,
 MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
 false, false, false, false, false, false,
 BoardFullAction::firstPlayerLose,
 StalemateAction::endWithStalemateLoss,
 kDefaultCaptureRuleConfig, kDefaultCaptureRuleConfig, kDefaultCaptureRuleConfig,
 false,  // no flying!
 50,     // shorter game
 50,
 true
}
```

### Extended Variant (12 Pieces + Diagonals)

```cpp
{
 "Twelve Men's Morris",
 "Extended board with diagonals and 12 pieces",
 12,     // more pieces
 3,
 3,
 true,   // diagonals enabled!
 MillFormationActionInPlacingPhase::removeOpponentsPieceFromBoard,
 false, false, false, false, false, false,
 BoardFullAction::firstPlayerLose,
 StalemateAction::endWithStalemateLoss,
 kDefaultCaptureRuleConfig, kDefaultCaptureRuleConfig, kDefaultCaptureRuleConfig,
 true,
 100,
 100,
 true
}
```

---

## Troubleshooting

### Issue: Rule doesn't load
**Cause**: Invalid index or N_RULES not updated  
**Solution**: 
1. Check index < N_RULES
2. Update N_RULES in rule.h
3. Rebuild engine

### Issue: Game behaves incorrectly
**Cause**: Parameter mismatch C++ ↔ Flutter  
**Solution**: Verify all parameters match exactly

### Issue: Crashes on rule selection
**Cause**: Out-of-bounds array access  
**Solution**: Ensure index mapping correct in Flutter

### Issue: Can't remove pieces
**Cause**: `mayRemoveFromMillsAlways` or mill detection issue  
**Solution**: Check mill detection logic and parameter settings

---

## See Also

- [ADDING_NEW_GAME_RULES.md](../../docs/guides/ADDING_NEW_GAME_RULES.md) - Complete guide
- [Position API](api/Position.md) - Position management
- [RuleSettings](../ui/flutter_app/lib/rule_settings/models/rule_settings.dart) - Flutter side

---

**Maintainer**: Sanmill Development Team  
**License**: GPL v3

