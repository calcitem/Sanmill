# Multi-Rule Puzzle System

## Overview

The Sanmill puzzle system now supports multiple rule variants, allowing puzzles to be properly grouped and filtered based on the game rules they were designed for. This ensures that players only see puzzles compatible with their current rule settings.

## Architecture

### 1. Rule Variant Identification

Each rule variant is identified by:
- **ID**: A unique string identifier (e.g., `standard_9mm`, `twelve_mens_morris`)
- **Name**: Human-readable name (e.g., "Nine Men's Morris")
- **Description**: Brief description of rule features
- **Rule Hash**: MD5 hash of critical rule parameters for quick comparison

### 2. Rule Hash Calculation

The rule hash is calculated from all gameplay-affecting parameters, including:
- Piece counts (piecesCount, flyPieceCount, piecesAtLeastCount)
- Board layout (hasDiagonalLines)
- Placement rules (mayMoveInPlacingPhase)
- Mill formation rules (millFormationActionInPlacingPhase)
- Capture mechanics (enableCustodianCapture, enableInterventionCapture, enableLeapCapture)
- Game ending conditions (boardFullAction, stalemateAction)
- Special rules (oneTimeUseMill, restrictRepeatedMillsFormation)

Cosmetic settings (like timeouts, animations) are excluded to avoid unnecessary hash changes.

### 3. Puzzle Collections

Puzzles are automatically grouped into collections based on their rule variant:

```dart
// Get collection for current rule variant
final RuleVariant variant = RuleVariant.fromRuleSettings(currentRules);
final PuzzleCollection? collection = collectionManager.getCollection(variant.id);

// Access puzzles
final List<PuzzleInfo> allPuzzles = collection?.puzzles ?? [];
final List<PuzzleInfo> beginnerPuzzles = collection?.getPuzzlesByDifficulty(PuzzleDifficulty.beginner) ?? [];
```

## Usage

### Creating Puzzles for Specific Rule Variants

When creating a puzzle, always specify the rule variant it's designed for:

```dart
final PuzzleInfo puzzle = PuzzleInfo(
  id: 'my_puzzle_001',
  title: 'My Custom Puzzle',
  description: 'Description here',
  category: PuzzleCategory.formMill,
  difficulty: PuzzleDifficulty.medium,
  initialPosition: 'FEN_NOTATION_HERE',
  solutionMoves: [['a1', 'b1']],
  optimalMoveCount: 2,
  ruleVariantId: 'standard_9mm', // IMPORTANT: Specify rule variant
);
```

### Predefined Rule Variants

The system includes several predefined variants:

| Variant ID | Name | Description |
|------------|------|-------------|
| `standard_9mm` | Nine Men's Morris | Standard 9-piece game, no diagonals |
| `twelve_mens_morris` | Twelve Men's Morris | 12-piece game with diagonal lines |
| `russian_mill` | Russian Mill | 12-piece game with one-time mill rule |
| `morabaraba` | Morabaraba | 12-piece African variant, no diagonals |
| `cham_gonu` | Cham Gonu | 12-piece Korean variant with custodian capture |

### Filtering Puzzles by Current Rules

```dart
// Get current rule settings
final RuleSettings currentRules = RuleSettings.fromLocale(locale);

// Generate variant from current rules
final RuleVariant currentVariant = RuleVariant.fromRuleSettings(currentRules);

// Filter puzzles for current variant
final PuzzleCollection? collection = collectionManager.getCollection(currentVariant.id);

if (collection != null) {
  // Show puzzles compatible with current rules
  showPuzzles(collection.puzzles);
} else {
  // No puzzles available for this rule variant
  showNoPuzzlesMessage();
}
```

## Directory Structure Recommendation

For organizing puzzle data files, use this structure:

```
puzzles/
├── standard_9mm/           # Hash: abc123...
│   ├── beginner/
│   │   ├── 001.json
│   │   ├── 002.json
│   │   └── ...
│   ├── easy/
│   ├── medium/
│   ├── hard/
│   ├── expert/
│   └── master/
├── twelve_mens_morris/     # Hash: def456...
│   ├── beginner/
│   └── ...
├── russian_mill/           # Hash: ghi789...
│   └── ...
└── custom_variants/
    ├── variant_xyz/        # Hash: xyz...
    └── ...
```

### Benefits of Hash-Based Organization

1. **Consistency**: Same rules always generate same hash
2. **Versioning**: Rule changes create new hash, preserving old puzzles
3. **Validation**: Quickly verify puzzle compatibility
4. **Migration**: Easy to detect when puzzles need updating

## FEN Notation

FEN (Forsyth-Edwards Notation) is used to store board positions:

```
Format: [Ring1]/[Ring2]/[Ring3] [Side] [Phase] [Action]
        [WhiteOnBoard] [WhiteInHand] [BlackOnBoard] [BlackInHand]
        [WhiteToRemove] [BlackToRemove]
        [WhiteLastMillFrom] [WhiteLastMillTo] [BlackLastMillFrom] [BlackLastMillTo]
        [MillsBitmask] [Rule50] [Ply]
```

Where:
- `Ring`: Board positions (@ = Black, O = White, * = Empty, X = Marked)
- `Side`: w = White to move, b = Black to move
- `Phase`: r = Ready, p = Placing, m = Moving, o = GameOver
- `Action`: p = Place, s = Select, r = Remove

Example:
```
OO*****/*******/******* w p p 2 7 0 9 0 0 0 0 0 0 0 0 1
```

## Best Practices

### 1. Always Specify Rule Variant

```dart
// ✅ Good
PuzzleInfo(
  // ... other fields
  ruleVariantId: 'standard_9mm',
)

// ❌ Bad - relies on default
PuzzleInfo(
  // ... other fields
  // Missing ruleVariantId
)
```

### 2. Validate Puzzles Against Rule Variant

Before adding puzzles to a collection, validate they work with the rule variant:

```dart
bool isPuzzleValid(PuzzleInfo puzzle, RuleSettings rules) {
  // Check if FEN is compatible with board layout
  if (rules.hasDiagonalLines) {
    // Validate diagonal positions in FEN
  }

  // Check if solution moves are legal under these rules
  // ... validation logic

  return true;
}
```

### 3. Handle Missing Variants Gracefully

```dart
final PuzzleCollection? collection = collectionManager.getCollection(variantId);

if (collection == null) {
  // Option 1: Show message
  showSnackBar('No puzzles available for current rules');

  // Option 2: Fall back to similar variant
  final PuzzleCollection fallback = collectionManager.getCollection('standard_9mm');

  // Option 3: Allow creating custom puzzles
  navigateToCustomPuzzleCreation();
}
```

### 4. Update Puzzles When Rules Change

```dart
void onRulesChanged(RuleSettings newRules) {
  // Regenerate variant
  final RuleVariant newVariant = RuleVariant.fromRuleSettings(newRules);

  // Reload puzzles for new variant
  final PuzzleCollection? newCollection = collectionManager.getCollection(newVariant.id);

  // Update UI
  setState(() {
    currentPuzzles = newCollection?.puzzles ?? [];
  });
}
```

## Migration Guide

### Converting Existing Puzzles

If you have existing puzzles without rule variant IDs:

```dart
// 1. Determine which rule variant each puzzle was designed for
// 2. Add ruleVariantId to each puzzle
// 3. Reorganize into collections

for (final PuzzleInfo puzzle in oldPuzzles) {
  final String variantId = detectVariantFromPuzzle(puzzle);

  final PuzzleInfo updated = puzzle.copyWith(
    ruleVariantId: variantId,
  );

  savePuzzle(updated);
}
```

## Future Enhancements

Potential improvements to the system:

1. **Automatic Variant Detection**: Analyze FEN to guess compatible variants
2. **Cross-Variant Adaptation**: Automatically convert puzzles between similar variants
3. **Variant Tags**: Allow puzzles to support multiple variants if solution is compatible
4. **Community Variants**: Support for user-defined rule variants with custom hashes
5. **Puzzle Import/Export**: Include variant metadata in puzzle files

## References

- [Rule Settings Documentation](../rule_settings/README.md)
- [FEN Notation Specification](../game/FEN_SPEC.md)
- [Puzzle Format Specification](PUZZLE_FORMAT.md)

## Example: Complete Puzzle Definition

```dart
final PuzzleInfo examplePuzzle = PuzzleInfo(
  id: 'example_001',
  title: 'Basic Mill Formation',
  description: 'Form a mill in one move',
  category: PuzzleCategory.formMill,
  difficulty: PuzzleDifficulty.beginner,

  // FEN notation - must be compatible with rule variant
  initialPosition: 'OO*****/*******/******* w p p 2 7 0 9 0 0 0 0 0 0 0 0 1',

  // Solution moves
  solutionMoves: [
    ['c1'], // Multiple solutions possible
  ],

  optimalMoveCount: 1,
  hint: 'Look for two pieces in a row',
  tags: ['beginner', 'mill', 'placement'],

  // Rule variant - ensures compatibility
  ruleVariantId: 'standard_9mm',

  // Optional metadata
  author: 'Puzzle Creator',
  rating: 1200,
  isCustom: false,
  version: 1,
);
```
