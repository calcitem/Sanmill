# Adding New Game Rules to Sanmill

> **Architecture philosophy:** Sanmill is **configuration‑based**, not inheritance‑based. Rule variants are expressed as **data** (`Rule` in C++, `RuleSettings` in Flutter) and toggled at runtime. Any new mechanics must be gated by booleans/params so existing variants remain untouched and fast.

---

## 0) At‑a‑Glance (Quick Start)

**What changes:** C++ engine + Flutter UI + (optionally) game logic on both sides.
**Estimated time:** 4–8 hours (simple parameter rule: 2–4h; new mechanics: 6–8h)
**Complexity:** ⭐⭐⭐ Medium‑High
**Touched files:** ~70–80 total (incl. ~60 ARB localization files)

**Main steps**

1. **C++**: Add rule to `RULES[]`; bump `N_RULES`.
2. **Flutter**: Add `RuleSet` enum + `RuleSettings` subclass + modal entry + localizations.
3. **Logic**: If you changed gameplay (placement/movement/capture), implement it in **both** `position.cpp` and `position.dart`; movegen in C++ only.
4. **FEN**: Extend only if you must persist dynamic state (see §4).
5. **Test**: Unit + widget + FEN round‑trip; benchmark before/after.

---

## 1) Architecture & Files

### 1.1 Components (configuration‑based)

```
Game Rules System:
├── C++ Engine
│   ├── src/rule.h   (Rule struct; N_RULES)
│   ├── src/rule.cpp (RULES[]; defaults)
│   ├── src/position.*  (position state + rules logic)
│   ├── src/movegen.cpp (legal move generation)
│   ├── src/evaluate.cpp, src/search.cpp (use position/movegen)
│   ├── src/ucioption.cpp (UCI options: rule fields <-> setoption mapping)
│   └── src/uci.cpp (UCI loop + setoption parser)
│
├── Flutter UI
│   ├── lib/rule_settings/models/rule_settings.dart (RuleSet + RuleSettings)
│   ├── lib/rule_settings/widgets/... (selection UIs)
│   ├── lib/game_page/services/engine/position.dart (client-side mirror)
│   └── lib/l10n/intl_*.arb (localization)
│
└── Tests (C++: tests/*, Flutter: test/*, integration_test/*)
```

### 1.2 Required modifications (core)

| Area               | File                                                   | Change                                                                                             |
| ------------------ | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------- |
| **C++ Engine**     | `src/rule.cpp`                                         | Add new rule to `RULES[]`                                                                          |
|                    | `src/rule.h`                                           | Increment `N_RULES`                                                                                |
| **Flutter models** | `lib/rule_settings/models/rule_settings.dart`          | Add `RuleSet` value; add `YourXxxRuleSettings`; update `ruleSetDescriptions` & `ruleSetProperties` |
| **Flutter UI**     | `lib/rule_settings/widgets/modals/rule_set_modal.dart` | Add `RadioListTile` for the variant                                                                |
| **Localization**   | `lib/l10n/intl_en.arb`, `intl_zh*.arb`, `intl_*.arb`   | Add strings and generate via `flutter gen-l10n`                                                    |

### 1.3 Conditional modifications (when adding mechanics)

| Area              | File                                          | When                                                   |
| ----------------- | --------------------------------------------- | ------------------------------------------------------ |
| **C++**           | `src/rule.h`                                  | Add fields if current `Rule` lacks needed flags/params |
|                   | `src/position.cpp`                            | **Always** if you changed position rules               |
|                   | `src/movegen.cpp`                             | If custom movement patterns exist                      |
|                   | `src/mills.cpp`                               | If non‑standard mill formations                        |
|                   | `src/evaluate.cpp`                            | If evaluation must reflect the variant                 |
| **Flutter**       | `lib/game_page/services/engine/position.dart` | **Mirror** `position.cpp` logic for UI/human moves     |
| **Models**        | `rule_settings.dart`                          | Add matching fields for any new `Rule` fields          |
| **UI (optional)** | `rule_settings_page.dart`                     | Mark as “Experimental”                                 |
| **Tests**         | C++/Dart test files                           | Add unit/movegen/position/widget tests as needed       |

### 1.4 Additional files you may need to modify

| File                                                       | When to modify                                                                                         |
| ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `lib/game_page/services/engine/engine.dart`                | **Required** if you added new `Rule` struct fields — must update `setRuleOptions()` to send new params |
| `src/ucioption.cpp`                                         | **Required** if you added new `Rule` fields — add matching UCI options and on_change handlers          |
| `rule_settings.dart` → `isLikelyXxx()` method              | **Recommended** — add detection method for auto‑identification of your variant                         |
| `rule_settings.dart` → `fromLocale()` factory              | **Optional** — if variant is culturally significant, map locale to your settings                       |
| `lib/game_page/services/import_export/import_service.dart` | **Optional** — if you want auto‑detection when importing games                                         |
| `lib/shared/database/database.dart`                        | **Rarely** — only if changing app‑wide defaults behavior                                               |
| `include/config.h`                                         | **Rarely** — only if changing `DEFAULT_RULE_NUMBER`                                                    |
| `src/evaluate.cpp` / `src/search.cpp`                      | **Rarely** — only if variant requires special evaluation or search logic                               |

### 1.5 Legacy (do **not** edit)

| File                       | Status                                     |
| -------------------------- | ------------------------------------------ |
| `src/ui/qt/game_rule.cpp`  | Legacy Qt GUI                              |
| `src/ui/qt/game_state.cpp` | Legacy Qt GUI (auto updates via `N_RULES`) |

---

## 2) Rule Definitions (C++ & Flutter)

**C++** (`src/rule.h`)

```cpp
struct CaptureRuleConfig {
  bool enabled;
  bool onSquareEdges, onCrossLines, onDiagonalLines;
  bool inPlacingPhase, inMovingPhase;
  bool onlyAvailableWhenOwnPiecesLeq3;
};

struct Rule {
  char name[32];
  char description[512];
  int pieceCount, flyPieceCount, piecesAtLeastCount;
  bool hasDiagonalLines;
  // Mill & phase flags...
  MillFormationActionInPlacingPhase millFormationActionInPlacingPhase;
  bool mayMoveInPlacingPhase, isDefenderMoveFirst, mayRemoveMultiple;
  bool restrictRepeatedMillsFormation, mayRemoveFromMillsAlways, oneTimeUseMill;
  // Actions at phase boundaries and stalemate
  BoardFullAction boardFullAction;
  StalemateAction stalemateAction;
  // Capture rules (non-mill):
  CaptureRuleConfig custodianCapture, interventionCapture, leapCapture;
  // Flying/draw:
  bool mayFly;
  unsigned int nMoveRule, endgameNMoveRule;
  bool threefoldRepetitionRule;
};

constexpr auto N_RULES = 11;
extern const Rule RULES[N_RULES];
```

**Flutter** (`lib/rule_settings/models/rule_settings.dart`)

```dart
enum RuleSet { current, nineMensMorris, twelveMensMorris, /*...*/ yourNewVariant }

class RuleSettings {
  final int piecesCount, flyPieceCount, piecesAtLeastCount;
  final bool hasDiagonalLines, mayMoveInPlacingPhase, isDefenderMoveFirst;
  final bool mayRemoveMultiple, restrictRepeatedMillsFormation, mayRemoveFromMillsAlways, oneTimeUseMill;
  // Capture toggles mirror C++:
  final bool enableCustodianCapture, enableInterventionCapture, enableLeapCapture;
  // Line/phase/endgame subflags for each capture...
  final bool mayFly; final int nMoveRule, endgameNMoveRule; final bool threefoldRepetitionRule;
  // ...
}
```

> **Engine communication:** Flutter does **not** select by array index. It pushes **individual** parameters via `setRuleOptions()` (UCI). C++ merges to the global `rule`. Keep Flutter and C++ fields **1‑to‑1**.

---

## 3) Advanced Capture Rules (non‑mill)

> Added since v6.8; disabled by default via `kDefaultCaptureRuleConfig`.

### 3.1 Custodian (sandwich)

* **Pattern**: `[You] – [Opp] – [You (just placed/moved)]`
* **Removals**: **exactly 1**; if multiple are sandwiched, **player chooses 1**.
* **Scopes**: independent toggles for square/cross/diagonal; placing vs moving; optional ≤3 own pieces restriction.

C++ API (illustrative):

```cpp
bool Position::checkCustodianCapture(Square sq, Color us, std::vector<Square>& out);
int  Position::activateCustodianCapture(Color us, const std::vector<Square>& sel); // returns 1
```

### 3.2 Intervention (center locks endpoints)

* **Pattern**: `[Opp] – [You (center)] – [Opp]` on a line → capture both endpoints.
* **Removals**: **all trapped pieces on the chosen line** (typically 2), **no player choice per piece**.
* **Multiple lines triggered**: use the **first applicable** line. **Priority**: Cross > Square edges > Diagonals.
* **Scopes**: same toggles as above; optional ≤3 own pieces restriction.
* **Paired removal**: second removal must be on **the same line**:

```cpp
Bitboard Position::findPairedInterventionTarget(Square firstRemoved, Bitboard candidates);
```

C++ API:

```cpp
bool Position::checkInterventionCapture(Square sq, Color us, std::vector<Square>& out);
int  Position::activateInterventionCapture(Color us, const std::vector<Square>& sel); // returns out.size()
```

### 3.3 Leap (experimental)

* Jump over adjacent opponent to empty behind; **experimental**.

### 3.4 Interaction with mills & multi‑removal

* **Mill vs non‑mill priority**: player must choose **one mode** when both trigger. Choosing one **cancels** the other for that move.
* **`mayRemoveMultiple`**:

    * **Custodian** ignores it (always 1).
    * **Intervention** ignores it (all trapped on one line).
    * **Mill** respects it.

### 3.5 Default capture config

```cpp
constexpr CaptureRuleConfig kDefaultCaptureRuleConfig{
  /*enabled*/ false,
  /*onSquareEdges*/ true, /*onCrossLines*/ true, /*onDiagonalLines*/ true,
  /*inPlacingPhase*/ true, /*inMovingPhase*/ true,
  /*onlyAvailableWhenOwnPiecesLeq3*/ false
};
```

---

## 4) **Critical**: FEN Format Extension

Only extend FEN if you must persist **dynamic state** that cannot be recomputed.

### 4.1 Extend FEN **when** (any of):

* Need to track **capture targets** for custodian/intervention.
* Need to persist **temporary user choice**, e.g., **preferredRemoveTarget** for an intervention line.
* Need to store **intermediate multi‑step state** across moves/undo/search.
* Need **history‑dependent constraints** (e.g., “same piece can’t move twice”).

**Do *not* extend** for:

* Static rule params (piece counts, `hasDiagonalLines`, etc.).
* Anything derivable from the board (piece counts, mills).
* Global flags (`mayFly`, `mayRemoveMultiple`), which are rule params.

### 4.2 Concrete FEN fields (v6.8+)

Append optional trailing fields (backward‑compatible):

```
...STANDARD_FEN... [c:...] [i:...] [p:...]
```

* **`c:`** custodian targets per color
  `c:w-COUNT-S1.S2...|b-COUNT-S1.S2...`  (e.g., `c:w-1-21|b-0-`)
* **`i:`** intervention targets per color
  `i:w-COUNT-S1.S2...|b-COUNT-S1.S2...`  (e.g., `i:w-0-|b-2-8.24`)
* **`p:`** preferred remove target square (intervention line anchoring)
  `p:21`

### 4.3 C++ generation/parsing sketch

```cpp
// fen()
auto emit = [&](char tag, const Bitboard* targets, const int* counts) {
  ss << ' ' << tag << ':'
     << "w-" << counts[WHITE] << "-"; /* list white squares '.'-separated */
  ss << '|'
     << "b-" << counts[BLACK] << "-"; /* list black squares '.'-separated */
};
emit('c', custodianCaptureTargets, custodianRemovalCount);
emit('i', interventionCaptureTargets, interventionRemovalCount);
if (preferredRemoveTarget != SQ_NONE) ss << " p:" << int(preferredRemoveTarget);

// set()
/* after standard fields */
for (auto tok : trailingTokens) {
  if (tok.starts_with("c:")) { /* parse capture field for custodian */ }
  else if (tok.starts_with("i:")) { /* parse capture field for intervention */ }
  else if (tok.starts_with("p:")) { preferredRemoveTarget = Square(parsedInt); }
}
```

**Dart mirror** (`position.dart`): implement helpers to emit/parse capture fields, parse in `setFen()`, and **rebuild intervention pair mappings** after parse to enforce paired removal on the same line.

### 4.4 Impacted files

**Must update**

* C++: `src/position.h` (new fields), `src/position.cpp` (`fen()` & `set()`), tests (`tests/test_position.cpp`).
* Dart: `lib/game_page/services/engine/position.dart` (fields, `_getFen()`, `setFen()`), plus rebuild helpers; tests (integration round‑trip).

**May update**

* `src/uci.cpp` (if state flows via UCI), import/export, any `copyWith()` cloning.

### 4.5 Backward compatibility rules

* New fields go at the **end**; missing fields parse to **safe defaults**.
* Only **emit** extra fields when active (avoid noise).
* Provide round‑trip tests: old FEN loads fine; new FEN exports/imports identical state.

---

## 5) Step‑by‑Step Implementation

### 5.1 C++ configuration

`src/rule.cpp` (add at end of `RULES[]`; then bump `N_RULES`)

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
  /*restrictRepeatedMillsFormation*/ false,
  /*mayRemoveFromMillsAlways*/ false,
  /*oneTimeUseMill*/ false,
  BoardFullAction::firstPlayerLose,
  StalemateAction::endWithStalemateLoss,
  kDefaultCaptureRuleConfig,    // custodian
  kDefaultCaptureRuleConfig,    // intervention
  kDefaultCaptureRuleConfig,    // leap (experimental)
  /*mayFly*/ true,
  /*nMoveRule*/ 100, /*endgameNMoveRule*/ 100,
  /*threefoldRepetitionRule*/ true
}
```

`src/rule.h`

```cpp
// Bump by 1 to match the new RULES[] length
constexpr auto N_RULES = /* e.g., 12 */;
```

### 5.2 Engine/gameplay logic

* **Guarded logic**:

  ```cpp
  if (!rule.yourFeature) return fastPath();
  // new logic
  ```
* **Mirror** any edits in `position.cpp` within Flutter’s `position.dart`.
* **Move generation** is **C++ only** (`src/movegen.cpp`); UI uses engine legality.

### 5.3 Flutter UI

* Add enum + subclass + description/properties + modal `RadioListTile`:

  ```dart
  enum RuleSet { /*...,*/ yourNewVariant }
  class YourNewVariantRuleSettings extends RuleSettings { /* fields match C++ */ }
  const ruleSetDescriptions[...] = 'Your description';
  const ruleSetProperties[...] = YourNewVariantRuleSettings();
  ```
* Mark as **Experimental** in `rule_settings_page.dart` if not production‑ready.
* (Optional) `fromLocale()` returns this variant for specific locales.

### 5.4 Engine options from Flutter

`engine.dart::setRuleOptions()` sends every parameter individually (20+).
**Add new options** whenever `Rule` gains a field. On the C++ side, define the
matching UCI options and on_change handlers in `src/ucioption.cpp` so values are
applied to the global `rule`.

---

## 6) Build, Format, Test

```bash
# Localization (Flutter)
cd src/ui/flutter_app
flutter gen-l10n
cd ../../..

# Format all
./format.sh s

# C++ build & tests
cd src
make build all
make test
cd ..

# Flutter tests
cd src/ui/flutter_app
flutter test
```

(Adjust paths if your workspace differs.)

---

## 7) Testing Strategy

### 7.1 C++ tests

* Rule load & bounds (`set_rule(i)`)
* Position/logic unit tests (including new mechanics)
* FEN round‑trip if extended (`tests/test_position.cpp`)

### 7.2 Flutter tests

* Widget: rule appears in modal & persists
* Engine mirror: scenarios that exercise `_putPiece/_movePiece/_removePiece`
* Integration: select rule → new game → behavior visible

### 7.3 Performance

* Benchmark before/after (`make benchmark` if available)
* Ensure **no regression when feature is off** (early exits)

---

## 8) Quality & Safety Bar

* **Backward compatibility** (all existing variants unchanged; all old tests pass)
* **Performance parity** when new feature is off (hot paths remain hot)
* **Code symmetry** between C++/Dart for user‑visible logic
* **Clear docs & comments** near every new flag
* **Localization complete** (at least EN + ZH; ideally all ARBs)

**QA checklists (condensed)**

* [ ] `RULES[]` entry + `N_RULES` bumped
* [ ] Flutter `RuleSet` + `RuleSettings` match C++
* [ ] UI selection + strings present
* [ ] Logic guards and early exits
* [ ] C++ ↔ Dart symmetry for position logic
* [ ] FEN extended only if necessary; round‑trip tests
* [ ] Engine options updated for new params
* [ ] Benchmarks show no off‑feature slowdown
