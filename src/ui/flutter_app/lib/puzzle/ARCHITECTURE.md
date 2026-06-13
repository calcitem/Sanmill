# Puzzle Module Architecture

This document provides an overview of the Puzzle module's architecture, key components, and data flow.

## Module Structure

```
lib/puzzle/
├── models/              # Data models and schemas
│   ├── puzzle_info.dart           # Main puzzle definition
│   ├── puzzle_solution.dart       # Solution sequences with side info
│   ├── puzzle_progress.dart       # User progress tracking
│   ├── puzzle_settings.dart       # Global puzzle settings
│   ├── puzzle_category.dart       # Puzzle categories (enum)
│   ├── puzzle_difficulty.dart     # Difficulty levels (enum)
│   └── rule_schema_version.dart   # Rule versioning for compatibility
├── pages/               # UI pages
│   ├── puzzles_home_page.dart     # Main hub (entry point)
│   ├── puzzle_list_page.dart      # Browse all puzzles
│   ├── puzzle_page.dart           # Solve a puzzle
│   ├── puzzle_creation_page.dart  # Create/edit custom puzzles
│   ├── daily_puzzle_page.dart     # Daily puzzle challenge
│   ├── custom_puzzles_page.dart   # Manage custom puzzles
│   ├── puzzle_history_page.dart   # Attempt history
│   ├── puzzle_stats_page.dart     # Statistics overview
│   ├── puzzle_streak_page.dart    # Streak mode
│   └── puzzle_rush_page.dart      # Timed puzzle rush
├── services/            # Business logic
│   ├── puzzle_manager.dart        # Core puzzle CRUD & progress
│   ├── puzzle_validator.dart      # Solution validation
│   ├── puzzle_hint_service.dart   # Progressive hint system
│   ├── puzzle_auto_player.dart    # Auto-play opponent responses
│   ├── puzzle_rating_service.dart # ELO rating calculation
│   ├── puzzle_export_service.dart # Import/export puzzles
│   ├── daily_puzzle_service.dart  # Daily puzzle rotation
│   └── built_in_puzzles.dart      # Built-in puzzle definitions (currently empty)
└── widgets/
    └── puzzle_card.dart           # Puzzle list item widget
```

## Key Data Flow

### 1. Puzzle Creation Flow

```
User (PuzzleCreationPage)
  ├─> Setup initial position (GameMode.setupPosition OR GameMode.humanVsHuman)
  ├─> Record solution moves (GameRecorder tracks ExtMove with side info)
  ├─> PuzzleMove(notation, side) ← extracted from ExtMove.side (NOT alternating!)
  └─> PuzzleManager.addCustomPuzzle() → Hive storage
```

**Critical**: Solution moves now include accurate `side` information from the game engine, supporting consecutive same-side moves (e.g., remove actions).

### 2. Puzzle Solving Flow

```
User (PuzzlePage)
  ├─> Load PuzzleInfo from PuzzleManager
  ├─> GameController loads initialPosition (FEN)
  ├─> User makes move → GameRecorder.appendMove()
  ├─> PuzzleValidator.addMove(notation)
  │   ├─> Track full move history (player + opponent)
  │   └─> _moveCountNotifier += 1 (only for humanColor moves)
  ├─> PuzzleAutoPlayer.autoPlayOpponentResponses()
  │   └─> Match current prefix → pick first matching solution → auto-play next opponent move
  └─> PuzzleValidator.validateSolution()
      ├─> Check if full move sequence matches any solution
      └─> If no match, check objective (formMill, capturePieces, etc.)
```

**Move Count Logic**:
- `_moveCountNotifier`: counts **only player moves** (aligns with optimalMoveCount)
- `PuzzleValidator._playerMoves`: tracks **all moves** (player + opponent) for sequence matching
- During solution playback (`_isPlayingSolution = true`), validation is suppressed

### 3. Hint System Flow

```
User clicks Hint → PuzzleHintService.getNextHint(currentPlayerMoveIndex)
  ├─> Level 0: Return textual hint (if available)
  ├─> Level 1: _getNextPlayerMove(currentPlayerMoveIndex)
  │   └─> solution.getPlayerMoves(playerSide)[currentPlayerMoveIndex]
  └─> Level 2: _getFullSolution() (show entire sequence)
```

**Important**: Hints use `currentPlayerMoveIndex` (not total move count), which is tracked separately from opponent auto-play moves.

### 4. Rating & Progress Tracking

```
PuzzleManager.completePuzzle()
  ├─> Calculate stars (PuzzleProgress.calculateStars)
  │   ├─> moveCount vs optimalMoveCount
  │   ├─> hintsUsed penalty
  │   └─> solutionViewed penalty
  ├─> Update PuzzleSettings.progressMap
  └─> Update user rating (ELO-based)
      └─> _updateUserRating(puzzleRating, success, hintsUsed)
```

### 5. Daily Puzzle & Streak

```
DailyPuzzleService.getTodaysPuzzle()
  ├─> Calculate dayNumber (days since epoch: 2025-01-01)
  ├─> Select puzzle: allPuzzles[dayNumber % allPuzzles.length]
  └─> Load streak stats from puzzleAnalyticsBox.dailyPuzzleStats

PuzzleStreakPage
  ├─> Shuffle all puzzles → sequential challenge
  ├─> Track currentStreak & bestStreak
  └─> Save streak result to puzzleAnalyticsBox.puzzleStreakHistory
```

**Persistence**: ✅ Daily puzzle stats and streak results are now persisted in Hive.

### 6. Import/Export Flow

```
Export:
  PuzzleManager.exportAndSharePuzzles(puzzles)
    └─> PuzzleExportService.sharePuzzles()
        ├─> Convert PuzzleInfo.toJson()
        ├─> Validate for contribution (if requested)
        └─> Share via platform share sheet

Import:
  PuzzleManager.importPuzzles()
    └─> PuzzleExportService.importPuzzles()
        ├─> Pick file → parse JSON
        ├─> PuzzleInfo.fromJson() for each puzzle
        └─> PuzzleManager.addCustomPuzzle() (mark as custom)
```

## Key Services & Dependencies

### PuzzleManager (Singleton)
- **Purpose**: Central hub for puzzle CRUD, progress tracking, and statistics
- **Dependencies**: `built_in_puzzles`, `puzzle_export_service`, `puzzle_rating_service`, `Database (Hive)`
- **Key Methods**:
  - `getAllPuzzles()` → Returns all puzzles (currently custom-only, built-in list is empty)
  - `completePuzzle()` → Records completion, calculates stars, updates rating
  - `importPuzzles()` / `exportAndSharePuzzles()` → Handles puzzle exchange

### PuzzleValidator
- **Purpose**: Validate player's solution against expected sequences
- **Strategy**:
  1. **Primary**: Match full move sequence (player + opponent) against all solutions
  2. **Fallback**: Check category-specific objectives (formMill, capturePieces, etc.)
- **Key Methods**:
  - `validateSolution(currentPosition)` → Returns `ValidationResult` (correct/wrong/inProgress)
  - `_findMatchingSolution()` → First-match strategy across all solutions

### PuzzleHintService
- **Purpose**: Progressive hint system (textual → next move → full solution)
- **State**: Tracks `_hintsGiven` and `_currentHintLevel`
- **Key Methods**:
  - `getNextHint(currentPlayerMoveIndex)` → Returns next hint based on level
  - `_getNextPlayerMove(index)` → Filters solution to player moves only

### PuzzleAutoPlayer
- **Purpose**: Auto-play opponent responses in puzzle mode
- **Strategy**:
  - Pick first solution matching current move prefix
  - Auto-play next move until it's the human's turn again
- **Key Methods**:
  - `autoPlayOpponentResponses()` → Async auto-play loop
  - `pickSolutionForPrefix()` → First-match strategy

### DailyPuzzleService (Singleton)
- **Purpose**: Deterministic daily puzzle rotation + streak tracking
- **Rotation**: `allPuzzles[dayNumber % allPuzzles.length]` (ensures same puzzle for same day)
- **⚠️ Limitation**: Streak stats are in-memory only (not persisted)

## Data Models

### PuzzleInfo
```dart
{
  id: String,
  title: String,
  description: String,
  category: PuzzleCategory,       // formMill, capturePieces, etc.
  difficulty: PuzzleDifficulty,  // beginner, easy, medium, hard, expert, master
  initialPosition: String,        // FEN notation
  solutions: List<PuzzleSolution>,
  hint: String?,
  completionMessage: String?,
  tags: List<String>,
  isCustom: bool,
  author: String?,
  createdDate: DateTime,
  version: int,                  // Format version (currently 1)
  rating: int?,                  // ELO-based puzzle rating
  ruleVariantId: String,         // e.g., 'standard_9mm', 'twelve_mens_morris'

  // Computed properties:
  playerSide: PieceColor,        // Derived from initialPosition.sideToMove
  optimalSolution: PuzzleSolution?, // First solution with isOptimal=true
  optimalMoveCount: int,         // Player move count in optimal solution
}
```

### PuzzleSolution
```dart
{
  moves: List<PuzzleMove>,  // Full sequence (player + opponent)
  description: String?,
  isOptimal: bool,          // Default true

  // Methods:
  getPlayerMoves(playerSide): List<PuzzleMove>,  // Filter by side
  getPlayerMoveCount(playerSide): int,           // Count player moves only
}
```

### PuzzleMove
```dart
{
  notation: String,  // Algebraic notation (e.g., "a1", "a1-d4", "xa4")
  side: PieceColor,  // white or black (REQUIRED, not alternating!)
  comment: String?,  // Optional annotation
}
```

## Rule Compatibility & Versioning

### RuleVariant & Schema
- Each puzzle has a `ruleVariantId` (e.g., 'standard_9mm', 'russian_mill')
- `RuleSchemaVersion` ensures hash stability when new rule parameters are added
- **Current schema**: v1 (includes 40+ rule parameters)
- **⚠️ TODO (L341)**: Migration logic for v2 not yet implemented

### Compatibility Check
```dart
// PuzzlePage checks if current rules match puzzle's ruleVariantId
if (puzzle.ruleVariantId != currentVariant.id) {
  _showRuleMismatchWarning();
}
```

## Validation & Quality Assurance

### PuzzleValidationService
- **Used by**: Export/contribution flow (not real-time solving)
- **Checks**:
  - Required fields (title, description, initialPosition, solutions)
  - FEN format validation
  - Solution structure (at least one optimal solution)
  - Side alternation (validates that sides alternate correctly)
  - Length constraints (for contribution)

### Validation Levels
1. **Quick Validate**: Basic checks (used in UI)
2. **Full Validate**: Comprehensive checks (used in export)
3. **Contribution Validate**: Stricter checks (author required, min lengths)

## Persistence & Storage

### Hive Boxes
- `puzzleSettings` (Box<PuzzleSettings>):
  - `allPuzzles: List<PuzzleInfo>` (currently custom-only)
  - `progressMap: Map<String, PuzzleProgress>`
  - `userRating: int` (default 1500)
- `puzzleAnalytics` (Box<dynamic>):
  - `attemptHistory: List<PuzzleAttemptResult>`

### ✅ Persistence Complete
1. **Daily Puzzle Stats** (daily_puzzle_service.dart)
   - Status: ✅ Implemented
   - Storage: `puzzleAnalyticsBox.dailyPuzzleStats`
   - Impact: Streak persists across app restarts

2. **Streak Results** (puzzle_streak_page.dart)
   - Status: ✅ Implemented
   - Storage: `puzzleAnalyticsBox.puzzleStreakHistory`
   - Impact: Best streak and history preserved

## Multi-Solution Support

### Strategy
- Multiple `PuzzleSolution` objects can exist for one puzzle
- One solution must be marked `isOptimal=true`
- Validation and auto-play use **first-match** strategy:
  ```dart
  for (solution in solutions) {
    if (matchesCurrentPrefix(solution)) return solution; // First match wins
  }
  ```

### Potential Issue
- If user follows alternative line A, but auto-play/hints use optimal line B
- **Mitigation**: First-match strategy ensures consistency within a single attempt
- **Limitation**: Hints won't adapt to user's chosen alternative line

## Entry Points

### User Navigation Flow
```
PuzzlesHomePage (main hub)
  ├─> Daily Puzzle → DailyPuzzlePage → PuzzlePage
  ├─> All Puzzles → PuzzleListPage → PuzzlePage
  ├─> Puzzle Rush → PuzzleRushPage → PuzzlePage (timed)
  ├─> Puzzle Streak → PuzzleStreakPage → PuzzlePage (streak mode)
  ├─> Custom Puzzles → CustomPuzzlesPage
  │     ├─> Create → PuzzleCreationPage
  │     ├─> Edit → PuzzleCreationPage(puzzleToEdit)
  │     ├─> Import → PuzzleManager.importPuzzles()
  │     └─> Export → PuzzleManager.exportAndSharePuzzles()
  ├─> History → PuzzleHistoryPage
  └─> Statistics → PuzzleStatsPage
```

## Known Limitations & Future Work

1. **Built-in Puzzles**: Currently empty (`getBuiltInPuzzles() returns []`)
   - All puzzles are user-created or imported
   - **Impact**: New users need to import or create puzzles to start

2. **Rule Schema Migration**:
   - v2 migration not implemented (TODO: L341 in rule_schema_version.dart)
   - **Impact**: Framework ready, will be needed when new rule parameters are added
   - **Mitigation**: Comprehensive migration guide in RULE_SCHEMA_MIGRATION.md

3. **Localization**:
   - `titleLocalizationKey`, `descriptionLocalizationKey` fields exist
   - **Impact**: Puzzle content localization not yet connected to ARB files
   - **Mitigation**: UI is fully localized, puzzle content uses raw strings

4. **Multi-Solution Hint Consistency**:
   - Hints always follow optimal solution
   - **Impact**: May confuse users who chose alternative line
   - **Mitigation**: First-match strategy ensures consistency within single attempt

## Testing & Quality

### Recommended Test Coverage
- [ ] Create custom puzzle with remove actions (side consistency)
- [ ] Multi-solution puzzle validation
- [ ] Daily puzzle rotation (deterministic)
- [ ] Import/export round-trip
- [ ] Rule variant mismatch warning
- [ ] Move count accuracy (player moves only)
- [ ] Solution playback (no premature validation)
- [ ] Hint progression (textual → next move → full solution)

---

*Last updated: 2025-12-30*
*Schema version: v1*

