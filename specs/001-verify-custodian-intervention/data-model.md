# Data Model: Custodian and Intervention Rules

**Date**: 2025-10-06
**Feature**: Verify Custodian and Intervention Rule Implementation
**Phase**: 1 - Design & Contracts

## Entity Definitions

### 1. Game Position

Represents the complete game state including piece locations, active rules, and capture state.

**Attributes**:
- `board: Map<Square, Piece>` - Current piece positions on board
- `activePlayer: Color` - Current player (White/Black)
- `phase: GamePhase` - Placing, Moving, or GameOver
- `ruleConfig: RuleConfiguration` - Active game rule settings
- `captureState: CaptureState` - Current capture opportunity state
- `pieceToRemoveCount: int` - Remaining captures in current sequence
- `history: List<Move>` - Move history for undo/redo

**Relationships**:
- Has one `CaptureState`
- Has one `RuleConfiguration`
- Produces `FENNotation` via toFEN()

**State Transitions**:
```
Normal Move → Check for Mill/Custodian/Intervention
  ↓
If any capture triggered → CaptureState = Active
  ↓
Player selects first capture → Determine active rule
  ↓
Execute captures per rule → Update pieceToRemoveCount
  ↓
pieceToRemoveCount == 0 → CaptureState = Inactive
```

**Validation Rules**:
- pieceToRemoveCount must be ≥ 0
- captureState must match pieceToRemoveCount (active iff count > 0)
- board must contain valid pieces only (no null references)

---

### 2. Capture State

Tracks active capture mechanisms and valid targets for current position.

**Attributes**:
- `hasMill: bool` - Mill formed on last move
- `millTargets: List<Square>` - Pieces eligible for mill capture
- `hasCustodian: bool` - Custodian pattern triggered
- `custodianTarget: Square?` - Sandwiched piece (null if not active)
- `custodianLine: Line?` - Three-point line for custodian (endpoints + middle)
- `hasIntervention: bool` - Intervention pattern triggered
- `interventionTargets: List<Square>` - Endpoint pieces (0 or 2 elements)
- `interventionLine: Line?` - Three-point line for intervention
- `selectedTargets: List<Square>` - Pieces already captured in sequence
- `activeRule: CaptureRule?` - Determined by first selection (mill/custodian/intervention/null)

**Relationships**:
- Belongs to one `GamePosition`
- References `Square` positions on board
- Affects move legality validation

**State Transitions**:
```
Initial: All flags false, targets empty, activeRule = null
  ↓
After move: Detection logic sets flags and target lists
  ↓
First capture selected → activeRule determined
  ↓
(If intervention) Second capture must be other endpoint
  ↓
All captures complete → Reset to Initial
```

**Validation Rules**:
- custodianTarget must be opponent piece and in custodianLine.middle
- interventionTargets must have exactly 0 or 2 elements
- interventionTargets must be endpoints of interventionLine
- If activeRule == custodian, only custodianTarget is legal
- If activeRule == intervention, only interventionTargets are legal (first selection determines which, second must be other)
- If activeRule == mill, only millTargets are legal
- custodianLine and interventionLine cannot both be non-null for same move (different geometric patterns)

---

### 3. FEN Notation

Serialized representation of game state including custodian/intervention markers.

**Attributes**:
- `positionString: String` - Board layout in FEN format
- `custodianMarker: String?` - Format: "c:a1" (square identifier)
- `interventionMarker: String?` - Format: "i:a1,b1" (comma-separated squares)
- `pieceCountMarker: String?` - Format: "p:2" (remaining captures)
- `sideToMove: String` - "w" or "b"
- `fullMoveNumber: int` - Move counter

**Relationships**:
- Represents one `GamePosition` snapshot
- Can be imported to restore `GamePosition`
- Can be exported from `GamePosition`

**Format Specification**:
```
Sanmill FEN format (from position.cpp):
[board_layout] [side] [phase] [action] [w_onboard] [w_inhand] [b_onboard] [b_inhand]
[w_toremove] [b_toremove] [w_mill_from] [w_mill_to] [b_mill_from] [b_mill_to]
[mills_bitmask] [halfmove] [fullmove] [c:w-count-squares|b-count-squares]
[i:w-count-squares|b-count-squares] [p:square]

Board layout: O=White, @=Black, *=Empty, X=Marked, separated by / for ranks
Side: w or b
Phase: n/r/p/m/o (none/ready/placing/moving/gameOver)
Action: p/s/r/? (place/select/remove/none)
Custodian marker (c:): w-1-8|b-0- (white has 1 target at square 8, black none)
Intervention marker (i:): w-0-|b-2-8.16 (white none, black has 2 targets at squares 8 and 16)
Preferred target (p:): p:21 (square 21)

Examples:
- Custodian active: "***O@O***/********/******** w p r 3 6 3 6 0 1 0 0 0 0 0 0 1 c:w-0-|b-1-8"
- Intervention active: "**@*O*@**/********/******** b m r 3 6 3 6 1 0 0 0 0 0 0 0 1 i:w-2-1.7|b-0-"
- Both markers: "O*@*O*@*O/********/******** w p r 3 6 3 6 0 1 0 0 0 0 0 0 1 c:w-0-|b-1-2 i:w-0-|b-2-1.7"
- No captures: "O*@*O*@*O/********/******** w p p 3 6 3 6 0 0 0 0 0 0 0 0 1"
```

**Validation Rules**:
- Custodian marker format: "c:w-count-sq1.sq2|b-count-sq3" where count is number of targets, squares separated by '.'
- Intervention marker format: "i:w-count-sq1.sq2|b-count-sq3.sq4" (typically 0 or 2 targets per color)
- Preferred target marker format: "p:square_number" (single square number)
- Referenced squares must be valid (SQ_BEGIN to SQ_END range)
- Referenced squares in c:/i: must exist on board and contain pieces
- Import must fail if validation fails (FR-035)
- Export must preserve exact values even if inconsistent (FR-039)

---

### 4. Rule Configuration

Game rule settings that affect capture logic.

**Attributes**:
- `mayRemoveMultiple: bool` - Allow multiple captures from one mill (default: true)
- `mayRemoveFromMillDuringPlacing: bool` - Mill protection during placement phase
- `hasCustodianRule: bool` - Enable custodian capture (default: varies by variant)
- `hasInterventionRule: bool` - Enable intervention capture (default: varies by variant)
- `millFormationRule: MillRule` - Standard/Diagonal/etc.

**Relationships**:
- Belongs to one `GamePosition`
- Affects `CaptureState` detection logic

**Impact on Capture Logic**:
- If mayRemoveMultiple == false AND multiple mills formed: pieceToRemoveCount = 1 (FR-036)
- If mayRemoveMultiple == false AND intervention chosen: still requires 2 captures (FR-038)
- Mill protection affects mill targets but NOT custodian/intervention targets (FR-004, FR-009)

---

### 5. Square

Board position identifier.

**Attributes**:
- `file: char` - Column (a-g typically for Nine Men's Morris)
- `rank: int` - Row (1-7 typically)
- `index: int` - Linear index (0-23 for standard board)

**Relationships**:
- Referenced by `CaptureState` for targets
- Referenced by `FENNotation` for capture markers
- Part of `GamePosition` board map

**Validation Rules**:
- Must be valid board position (e.g., a1-g7 for standard layout)
- index must match file/rank encoding

---

### 6. Line

Three-point line on board (for custodian/intervention detection).

**Attributes**:
- `endpoint1: Square` - First endpoint
- `center: Square` - Middle position
- `endpoint2: Square` - Second endpoint
- `direction: Direction` - Horizontal, Vertical, or Diagonal

**Relationships**:
- Referenced by `CaptureState.custodianLine`
- Referenced by `CaptureState.interventionLine`

**Validation Rules**:
- All three squares must be collinear
- center must be geometrically between endpoints
- Used for pattern matching: custodian (piece at endpoint, opponent in center) or intervention (piece at center, opponents at endpoints)

---

### 7. Capture Rule (Enum)

Identifies which capture mechanism is active.

**Values**:
- `mill` - Traditional mill capture
- `custodian` - Sandwiching capture
- `intervention` - Center-placement capture
- `null` - No capture active

**Usage**:
- Stored in `CaptureState.activeRule`
- Determined by player's first capture selection (FR-033)
- Once set, restricts subsequent captures in sequence

---

## Entity Relationship Diagram

```
GamePosition (1) ─── (1) CaptureState
    │                       │
    │                       ├─ (0..1) custodianLine: Line
    │                       ├─ (0..1) interventionLine: Line
    │                       ├─ (0..*) custodianTarget: Square
    │                       ├─ (0..*) interventionTargets: List<Square>
    │                       ├─ (0..*) millTargets: List<Square>
    │                       └─ (0..1) activeRule: CaptureRule
    │
    ├─── (1) RuleConfiguration
    │
    └─── produces ──→ FENNotation
                            │
                            └─ references ──→ Square (via c:/i: markers)
```

---

## Data Integrity Constraints

1. **Capture State Consistency**:
   - pieceToRemoveCount > 0 ⟺ (hasMill OR hasCustodian OR hasIntervention)
   - activeRule != null ⟺ selectedTargets.length > 0
   - If activeRule == custodian: custodianTarget != null
   - If activeRule == intervention: interventionTargets.length == 2

2. **FEN Marker Consistency**:
   - c: marker present ⟺ hasCustodian == true on import
   - i: marker present ⟺ hasIntervention == true on import
   - p: marker value == pieceToRemoveCount on import/export
   - Both c: and i: can be present simultaneously (FR-034)

3. **Rule Configuration Constraints**:
   - If mayRemoveMultiple == false: max 1 capture per turn from mill alone
   - Intervention always requires 2 captures regardless of mayRemoveMultiple
   - Custodian always requires 1 capture regardless of mayRemoveMultiple

4. **Board State Constraints**:
   - All target squares (custodian, intervention, mill) must contain opponent pieces
   - Targets must be on board (valid Square references)
   - No duplicate targets across lists (a piece can't be both custodian and intervention target simultaneously, but can overlap with mill targets)

---

*Data model complete. Ready for test scenario generation.*
