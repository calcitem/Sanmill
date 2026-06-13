# Puzzle Contribution Guide

## Overview

Thank you for your interest in contributing puzzles to Sanmill! Community-contributed puzzles help make our collection richer and more diverse for all players.

This guide explains how to create high-quality puzzles and submit them for inclusion in the official puzzle collection.

## Table of Contents

1. [What Makes a Good Puzzle](#what-makes-a-good-puzzle)
2. [Creating Your Puzzle](#creating-your-puzzle)
3. [Puzzle Metadata Requirements](#puzzle-metadata-requirements)
4. [Exporting Your Puzzle](#exporting-your-puzzle)
5. [Submission Process](#submission-process)
6. [Review Criteria](#review-criteria)
7. [Attribution](#attribution)
8. [Frequently Asked Questions](#frequently-asked-questions)

## What Makes a Good Puzzle

A high-quality puzzle should have these characteristics:

### 1. **Single Clear Solution**
- There should be one best move or sequence
- The solution should be forced or clearly superior to alternatives
- Avoid positions where multiple moves lead to similar outcomes

### 2. **Instructive Value**
- The puzzle should teach a tactical pattern or strategic concept
- Examples: double attacks, mill traps, defensive techniques, endgame tactics
- Players should learn something from solving it

### 3. **Appropriate Difficulty**
- Match the difficulty rating to the actual challenge level:
  - **Beginner**: 1-2 moves, basic mill formation
  - **Easy**: 2-3 moves, simple tactics
  - **Medium**: 3-5 moves, combination of tactics
  - **Hard**: 5-7 moves, complex calculation
  - **Expert**: 7+ moves, deep strategy
  - **Master**: Exceptional positions requiring expert-level play

### 4. **Natural Position**
- Position should look like it could occur in a real game
- Avoid artificial or contrived setups
- Prefer positions from actual games when possible

### 5. **Engaging Challenge**
- The solution should require thought, not be obvious
- Include surprising or beautiful moves when possible
- Make the player think "Aha!" when they find the solution

## Creating Your Puzzle

### Step 1: Find or Create a Position

You can create puzzles from:

1. **Your Own Games**: Review your games and find interesting tactical moments
2. **Study Positions**: Create instructive positions that teach specific concepts
3. **Historical Games**: Famous games from Mill tournaments or literature
4. **Endgame Studies**: Classic endgame positions and techniques

### Step 2: Set Up the Position

Using Sanmill's Custom Puzzle creator:

1. Navigate to **Puzzles → Custom Puzzles → Add Custom Puzzle**
2. Set up the board position using FEN notation or the visual editor
3. Ensure the position is legal and valid

### Step 3: Verify the Solution

1. Play through the solution yourself multiple times
2. Check all alternative moves to ensure they're inferior
3. Verify there are no dual solutions (multiple equally good solutions)
4. Test the puzzle with other players to confirm difficulty

### Step 4: Add Complete Metadata

Fill in all required fields:

- **Title**: Descriptive name (e.g., "Double Mill Trap", "Endgame Precision")
- **Description**: What the puzzle teaches or the goal
- **Category**: Tactical theme (Opening, Middle Game, Endgame, etc.)
- **Difficulty**: Accurate rating based on testing
- **Rule Variant**: Which rule set this puzzle uses
- **Author**: Your name or username
- **Source**: Where the position came from (optional)

## Puzzle Metadata Requirements

### Required Fields

| Field | Description | Example |
|-------|-------------|---------|
| **Title** | Short, descriptive name | "The Windmill Combination" |
| **Description** | What to accomplish | "White to play and force a win in 5 moves" |
| **Initial Position** | Position notation | See Position Format below |
| **Solution Moves** | Correct move sequences | `[["d1-d2", "f7-d7", "d2-f2"]]` |
| **Optimal Move Count** | Minimum moves to solve | `3` |
| **Category** | Tactical theme | `formMill`, `winGame`, etc. |
| **Difficulty** | Challenge level | `beginner`, `easy`, `medium`, etc. |
| **Rule Variant ID** | Which rules apply | `standard_9mm` |
| **Author** | Your name/username | "YourName" |

### Optional Fields

| Field | Description | Example |
|-------|-------------|---------|
| **Tags** | Additional keywords | `["zugzwang", "sacrifice"]` |
| **Source** | Position origin | "World Championship 2023, Game 7" |
| **Rating** | ELO-style rating | `1800` (if known) |
| **Created Date** | When you created it | `2025-01-15` |

### Categories

Choose the category that best fits your puzzle:

- **formMill**: Form a mill in N moves
- **capturePieces**: Capture N pieces
- **winGame**: Win the game in N moves
- **defend**: Defend against opponent's threats
- **findBestMove**: Find the best move in a complex position
- **endgame**: Endgame puzzles with few pieces remaining
- **opening**: Opening phase tactics (placement phase)
- **mixed**: Mixed/combined tactics that don't fit other categories

## Position Format

The initial position describes the board state using a specialized notation.

### Standard Format

```
RING1/RING2/RING3 SIDE PHASE ACTION WHITEONBOARD WHITEINHAND BLACKONBOARD BLACKINHAND ...
```

### Example

```
OO******/********/******** w p p 2 7 0 9 0 0 0 0 0 0 0 0 1
```

**Breakdown**:
- `OO******/********/********`: Board position (3 rings × 8 positions each = 24 squares)
  - Each ring separated by `/`
  - Each ring has exactly 8 positions arranged clockwise
  - `*` = empty square, `O` = white piece, `@` = black piece
- `w`: Side to move (`w` = white, `b` = black)
- `p`: Game phase (`r` = ready, `p` = placing, `m` = moving, `o` = game over)
- `p`: Action (`p` = place, `s` = select, `r` = remove)
- `2 7 0 9`: Piece counts (white on board, white in hand, black on board, black in hand)
- Additional fields for game state (remove counts, last mill positions, etc.)

**Important**: Each ring must have exactly 8 characters representing the 8 positions going clockwise around that ring.

See `MULTI_RULE_PUZZLES.md` for complete FEN specification.

## Exporting Your Puzzle

### Using the App

1. Go to **Puzzles → Custom Puzzles**
2. Long-press on your puzzle or tap the menu icon
3. Select **"Export for Contribution"**
4. Choose export location
5. A JSON file will be created with all puzzle data

### Export Format

The exported JSON file contains:

```json
{
  "version": "1.0",
  "puzzle": {
    "id": "custom_uuid_here",
    "title": "The Windmill Combination",
    "description": "White to play and force a win in 5 moves",
    "fen": "***************OO*X* w p 5 9 0 []",
    "solution": ["d1-d2", "f7-d7", "d2-f2"],
    "category": "combination",
    "difficulty": "hard",
    "ruleVariantId": "standard_9mm",
    "tags": ["windmill", "sacrifice"],
    "author": "YourName",
    "source": "Original composition",
    "createdAt": "2025-01-15T10:30:00Z",
    "metadata": {
      "timesAttempted": 0,
      "successRate": 0,
      "averageTime": 0
    }
  }
}
```

## Submission Process

### Method 1: GitHub (Recommended)

1. **Fork the Repository**
   - Go to https://github.com/calcitem/Sanmill
   - Click "Fork" to create your own copy

2. **Add Your Puzzle**
   - Place your exported JSON file in:
     ```
     src/ui/flutter_app/assets/puzzles/contributed/
     ```
   - Follow naming convention: `author_puzzlename.json`
   - Example: `john_windmill_trap.json`

3. **Create Pull Request**
   - Commit your puzzle file
   - Create a Pull Request with:
     - Title: `[Puzzle] Your Puzzle Title`
     - Description: Brief explanation of the puzzle
     - Include any relevant context or sources

4. **Review Process**
   - Maintainers will review your puzzle
   - May request changes or clarifications
   - Once approved, it will be merged

### Method 2: Issue Submission

If you're not familiar with GitHub:

1. Go to https://github.com/calcitem/Sanmill/issues
2. Click "New Issue"
3. Use template: "Puzzle Contribution"
4. Paste your exported JSON
5. Add any additional context

### Method 3: Email

For bulk submissions or special cases:

- Email: [project maintainer email]
- Subject: "Sanmill Puzzle Contribution"
- Attach exported JSON file(s)
- Include brief description

## Review Criteria

Your puzzle will be evaluated on:

### 1. **Correctness** ✓
- Solution is accurate and forced
- No dual solutions or errors
- FEN notation is valid
- Position is legal

### 2. **Quality** ✓
- Instructive or entertaining
- Natural-looking position
- Appropriate difficulty rating
- Clear tactical theme

### 3. **Originality** ✓
- Not a duplicate of existing puzzles
- If from a game, proper attribution provided
- Original compositions especially welcome

### 4. **Metadata Completeness** ✓
- All required fields filled
- Accurate categorization
- Meaningful title and description
- Proper attribution

### 5. **Technical Standards** ✓
- Valid JSON format
- Follows naming conventions
- Includes all required fields
- Compatible with current rule variant

## Attribution

### Your Credit

All accepted puzzles will credit the contributor:

- **In-App**: Puzzle author shown in details
- **Database**: Author field preserved
- **Leaderboard**: Contributor recognition
- **Documentation**: Contributors list in project

### License

By submitting puzzles, you agree to:

- **Puzzle content** licensed under **CC BY-SA 4.0** (Creative Commons Attribution-ShareAlike 4.0 International)
  - This allows free use, sharing, and adaptation
  - Requires attribution to you as the author
  - Derivative works must use the same license
- Allow modification for quality/compatibility within the app
- Grant perpetual usage rights to the project
- Maintain attribution to your username

**Note:** The Sanmill application code remains under GPL-3.0-or-later, but puzzle data uses the more permissive CC BY-SA 4.0 license, following industry best practices for chess/game content (similar to Lichess, Chess Tactics databases, etc.).

### Third-Party Positions

If using positions from games or studies:

- **Historical Games**: Provide game details (players, event, date)
- **Studies**: Credit original composer
- **Books**: Cite source publication
- **Public Domain**: Note if position is classical/traditional

## Frequently Asked Questions

### Q: How many puzzles can I submit?

**A**: There's no limit! Submit as many quality puzzles as you'd like. Bulk submissions (10+ puzzles) are welcome via GitHub PR.

### Q: Can I submit puzzles for different rule variants?

**A**: Absolutely! We welcome puzzles for all supported variants:
- Nine Men's Morris (standard_9mm)
- Twelve Men's Morris (twelve_mens_morris)
- Russian Mill (russian_mill)
- Morabaraba (morabaraba)
- Cham Gonu (cham_gonu)

### Q: What if I'm not sure about the difficulty rating?

**A**: Make your best guess based on the guidelines. Reviewers will adjust if needed. Consider:
- Number of moves in solution
- Complexity of calculation
- Whether moves are forced or require finding
- Presence of surprising moves

### Q: Can I submit unfinished games as puzzles?

**A**: Not recommended. Puzzles should have clear solutions. If a game position has multiple continuations, it's not suitable as a puzzle unless one continuation is clearly superior.

### Q: How long does the review process take?

**A**: Typically 1-2 weeks, but may vary based on submission volume. Complex puzzles or large batches may take longer.

### Q: Can I update a puzzle after submission?

**A**: Yes! If you find an error or want to improve metadata, submit a correction via GitHub issue or PR.

### Q: Will all submitted puzzles be accepted?

**A**: Most quality puzzles are accepted, but some may be rejected if they:
- Have errors or dual solutions
- Duplicate existing puzzles
- Don't meet quality standards
- Contain inappropriate content

We'll provide feedback on rejected puzzles and may suggest improvements.

### Q: Can I contribute puzzle sets or themed collections?

**A**: Yes! Themed collections (e.g., "Famous Endgames", "Trap Series") are welcome. Submit all puzzles in the collection with a note explaining the theme.

### Q: How do I test my puzzle before submitting?

**A**: Best practices:
1. Solve it yourself multiple times
2. Share with friends to test difficulty
3. Check all alternative moves
4. Use the app's hint system to verify it works correctly
5. Ensure the FEN loads properly

### Q: What if someone else already submitted a similar puzzle?

**A**: Small variations are fine if they teach different concepts. However, exact duplicates will be rejected. Check existing puzzles before submitting.

### Q: Can I get recognition for my contributions?

**A**: Yes! Contributors are:
- Listed in the project's CONTRIBUTORS file
- Credited in each puzzle's metadata
- Potentially featured in release notes for significant contributions

## Quality Checklist

Before submitting, verify:

- [ ] Position is legal and can be reached in a real game
- [ ] Solution is correct and forced
- [ ] No alternative solutions of equal quality exist
- [ ] Difficulty rating is accurate
- [ ] All required metadata is complete
- [ ] FEN notation is valid
- [ ] Title is descriptive and appropriate
- [ ] Description clearly states the objective
- [ ] Category and tags are accurate
- [ ] Proper attribution is included
- [ ] Exported JSON file is valid
- [ ] Puzzle has been tested

## Examples

### Example 1: Simple Mill Trap (Easy)

```json
{
  "version": "1.0",
  "puzzle": {
    "id": "custom_basic_mill_trap_001",
    "title": "Basic Mill Trap",
    "description": "White to play and form a mill, winning a piece",
    "initialPosition": "**O****X*******O*X*O* w p 4 7 0 []",
    "solutionMoves": [["a4-d4"]],
    "optimalMoveCount": 1,
    "category": "formMill",
    "difficulty": "easy",
    "ruleVariantId": "standard_9mm",
    "author": "JohnDoe",
    "tags": ["mill", "beginner_friendly"],
    "version": 1,
    "createdDate": "2025-01-15T10:30:00Z"
  }
}
```

### Example 2: Complex Endgame (Expert)

```json
{
  "version": "1.0",
  "puzzle": {
    "id": "custom_endgame_masterpiece_001",
    "title": "Endgame Masterpiece",
    "description": "White to play and win despite material equality",
    "initialPosition": "O***X***O***X***O***X*** w m 45 0 6 []",
    "solutionMoves": [["a1-a4", "d1-a1", "a4-a1", "d7-d4", "a1-d1"]],
    "optimalMoveCount": 5,
    "category": "endgame",
    "difficulty": "expert",
    "ruleVariantId": "standard_9mm",
    "author": "JohnDoe",
    "hint": "Look for forcing moves that restrict opponent options",
    "tags": ["endgame_study", "forced_moves"],
    "rating": 2200,
    "version": 1,
    "createdDate": "2025-01-15T10:30:00Z"
  }
}
```

## Support

Need help creating or submitting puzzles?

- **Documentation**: See `MULTI_RULE_PUZZLES.md` for technical details
- **GitHub Issues**: Ask questions or report problems
- **Community**: Join discussions about puzzle creation

## Thank You!

Your contributions help make Sanmill better for everyone. We appreciate your time and creativity in building our puzzle collection!

Happy puzzle creating! 🧩
