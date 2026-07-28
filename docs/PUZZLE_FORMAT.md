# Puzzle Format Specification

This document describes the puzzle format used in Sanmill for storing and sharing puzzles.

## Format Version

**Current Version:** 1.0

## Overview

Sanmill uses a structured JSON format for puzzles that supports:
- Multiple solution paths with explicit side-to-move information
- Puzzle pack metadata for collections
- Localization support
- Move-level comments for annotations

## Format Structure

### Top-Level Export Format

```json
{
  "formatVersion": "1.0",
  "exportedBy": {
    "appName": "Sanmill",
    "platform": "android"
  },
  "exportDate": "2025-12-28T10:30:00.000Z",
  "puzzleCount": 5,
  "metadata": {
    // Puzzle pack metadata (optional)
  },
  "reviewBatches": [
    // Optional embedded-review provenance records
  ],
  "puzzles": [
    // Array of puzzle objects
  ]
}
```

### Embedded Review Batches (Optional)

An application build may embed certified candidates before editorial
approval. Such a package must set `metadata.isOfficial` to `false`, give each
candidate a `review-status:expert-pending` and `review-batch:<id>` tag, and
retain a top-level record linking the batch to its selector evidence:

```json
{
  "id": "engine-blunder-review-selected-30",
  "status": "expert-pending",
  "puzzleCount": 30,
  "selectionProvenance": {
    "solver": "OR-Tools CP-SAT",
    "status": "OPTIMAL",
    "selectedCandidates": []
  }
}
```

This metadata records selection and review state; it is not game-theoretic
proof. Each included puzzle still requires independent rules-engine and
Perfect DB validation. Once every candidate has an explicit review decision,
the pack may remove or replace the pending tags and publish a non-prerelease
pack version.

More than one pending batch may be embedded. Every pending puzzle must name
exactly one `review-batch:<id>`, that id must occur exactly once in the
top-level `reviewBatches` array, and each recorded `puzzleCount` must match
the number of puzzles carrying the corresponding tag.

### Puzzle Pack Metadata (Optional)

Metadata provides information about a collection of puzzles:

```json
{
  "id": "beginner_tactics_v1",
  "name": "Beginner Tactics",
  "description": "Learn basic mill formations and capturing",
  "author": "John Doe",
  "version": "1.0.0",
  "createdDate": "2025-01-01T00:00:00.000Z",
  "updatedDate": "2025-12-28T00:00:00.000Z",
  "tags": ["beginner", "tactics", "mill-formation"],
  "isOfficial": false,
  "requiredAppVersion": "7.1.0",
  "ruleVariantId": "standard_9mm",
  "coverImage": "path/to/image.png",
  "website": "https://example.com"
}
```

### Puzzle Object Format

```json
{
  "id": "puzzle_001",
  "title": "Form Your First Mill",
  "description": "Place three pieces in a row to form a mill",
  "category": "formMill",
  "difficulty": "beginner",
  "initialPosition": "NNNNNNNNNNNNNNNNNNNNNNNN/xxoxxxxx/0/0/b w 9 9 0",
  "solutions": [
    {
      "moves": [
        {
          "notation": "a1",
          "side": "white",
          "comment": "Start by placing at the corner"
        },
        {
          "notation": "d1",
          "side": "black"
        },
        {
          "notation": "d4",
          "side": "white",
          "comment": "Building towards a mill"
        },
        {
          "notation": "d7",
          "side": "black"
        },
        {
          "notation": "a7",
          "side": "white",
          "comment": "Complete the mill!"
        }
      ],
      "description": "Main solution",
      "isOptimal": true
    }
  ],
  "hint": "Try forming a mill on the outer ring",
  "completionMessage": "Great job! You formed a mill by placing three pieces in a row. This is the fundamental tactic in Mill games.",
  "tags": ["mill-formation", "beginner"],
  "isCustom": false,
  "author": "Sanmill Team",
  "createdDate": "2025-01-01T00:00:00.000Z",
  "version": 1,
  "rating": 800,
  "ruleVariantId": "standard_9mm",
  "titleLocalizationKey": "puzzle_first_mill_title",
  "descriptionLocalizationKey": "puzzle_first_mill_desc",
  "hintLocalizationKey": "puzzle_first_mill_hint",
  "completionMessageLocalizationKey": "puzzle_first_mill_completion"
}
```

## Field Specifications

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier for the puzzle |
| `title` | string | Display name of the puzzle |
| `description` | string | Objective and context |
| `category` | enum | Type of puzzle (see Categories) |
| `difficulty` | enum | Difficulty level (see Difficulties) |
| `initialPosition` | string | Starting position in FEN-like notation |
| `solutions` | array | Array of solution objects |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `hint` | string | Textual hint for solving |
| `completionMessage` | string | Message shown after completing the puzzle |
| `tags` | array | String tags for filtering |
| `isCustom` | boolean | User-created puzzle (default: false) |
| `author` | string | Creator's name |
| `createdDate` | ISO8601 | Creation timestamp |
| `version` | integer | Format version (default: 1) |
| `rating` | integer | ELO-style difficulty rating |
| `ruleVariantId` | string | Rule set identifier |
| `provenance` | object | Optional replay evidence for a source game |
| `*LocalizationKey` | string | L10n key for internationalization |

### Solution Object

| Field | Type | Description |
|-------|------|-------------|
| `moves` | array | Array of PuzzleMove objects |
| `description` | string | Optional solution description |
| `isOptimal` | boolean | Whether this line achieves the shortest accepted solution |

### PuzzleMove Object

| Field | Type | Description |
|-------|------|-------------|
| `notation` | string | Move in algebraic notation |
| `side` | enum | "white" or "black" |
| `comment` | string | Optional move annotation |

### Replay Provenance Object

A puzzle tagged `source:replay-backed` carries a `provenance` object:

```json
{
  "kind": "human-game-replay",
  "corpus": "HumanDB raw human games (anonymised PlayOK sample)",
  "databaseSha256": "64 lowercase hexadecimal characters",
  "sourceGameSha256": "64 lowercase hexadecimal characters",
  "sourceLogicalPly": 39,
  "replayHistory": ["a7", "d7", "g7", "d6", "a7-a4"],
  "recordedTurn": "e5-e4xd1",
  "presentationTransform": 0,
  "transformModel": "sanmill-ring16-v1",
  "positionGames": 1,
  "recordedTurnGames": 1
}
```

| Field | Type | Description |
|-------|------|-------------|
| `kind` | string | Currently `human-game-replay` |
| `corpus` | string | Non-identifying source corpus label |
| `databaseSha256` | string | SHA-256 of the HumanDB annotation snapshot |
| `sourceGameSha256` | string | SHA-256 of the exact source JSONL game row |
| `sourceLogicalPly` | integer | One-based complete logical turn at the puzzle root |
| `replayHistory` | array | Complete transformed full-turn history before the root |
| `recordedTurn` | string | Legal transformed human turn that missed the win |
| `presentationTransform` | integer | Deterministic presentation transform in `0..15` |
| `transformModel` | string | Currently `sanmill-ring16-v1` |
| `positionGames` | integer | HumanDB sample count for the annotated position |
| `recordedTurnGames` | integer | HumanDB sample count for the recorded turn |

`sourceLogicalPly` must equal `replayHistory.length + 1`. Player names and
account identifiers must not be included. The production rules engine must
legally replay the history and recorded turn, and the replayed root must match
`initialPosition`.

For compact offline packs, `solution-display:principal-variation` means each
equally shortest first turn is represented by one deterministic line. Perfect
DB still proves the root and classifies every legal first turn; the stored line
is the human-readable main variation against a defence that delays defeat,
not a serialised copy of the complete proof tree.

### Logical-Turn Counting

Mill-forming actions and their compulsory `x…` removal tokens are stored as
separate `PuzzleMove` objects so that the line can be replayed exactly. They
belong to one complete logical turn, however, and the removal does not add to
the public **Win in N** value or to player move statistics. **Win in N** counts
non-removal turns by the solving side.

All lines tied for the shortest accepted distance should use
`isOptimal: true`. If a pack also records a slower forced-win line, it must use
`isOptimal: false`; when the puzzle has an explicitly optimal line, Sanmill
acknowledges the slower win but does not mark the puzzle complete.

## Categories

- `formMill` - Form a mill in N moves
- `capturePieces` - Capture N pieces
- `winGame` - Win the game in N moves
- `defend` - Defend against opponent's threats
- `findBestMove` - Find the best move in a complex position
- `endgame` - Endgame puzzles
- `opening` - Opening phase tactics
- `mixed` - Mixed/combined tactics

## Difficulties

- `beginner` - Beginner level
- `easy` - Simple tactical patterns
- `medium` - Requires some experience
- `hard` - Challenging puzzles
- `expert` - Very difficult puzzles
- `master` - Extremely challenging puzzles

## Validation Rules

### Required Validations

1. **FEN Format**: Must be valid Sanmill FEN notation
2. **Non-Empty Solutions**: At least one solution required
3. **Title Length**: 3-100 characters
4. **Description**: At least 10 characters

### Best Practices

1. **Optimal Solutions**: Mark every equally shortest solution as
   `isOptimal: true`
2. **Side Sequence**: Turns alternate between sides, except that a compulsory
   removal immediately follows the mill-forming action with the same `side`
3. **Comments**: Use comments sparingly, for key moves only
4. **Attribution**: Include author name for custom puzzles
5. **Tags**: Use descriptive, lowercase tags
6. **Position Source**: Use `source:composed` when no legal replay witness is
   claimed, or `source:replay-backed` only when provenance includes a replay
   accepted by the current rules engine

## Export File Naming

### Standard Exports

Format: `sanmill_puzzles_<timestamp>.sanmill_puzzles`

Example: `sanmill_puzzles_1735390800000.sanmill_puzzles`

### Contribution Exports

Format: `<author>_<title>.json`

Example: `john_doe_first_mill.json`

## Checksums and Integrity

Future versions may include SHA-256 checksums for file integrity verification:

```json
{
  "formatVersion": "1.1",
  "checksum": {
    "algorithm": "SHA256",
    "value": "a3f2..."
  },
  ...
}
```

## Localization Keys

When providing localization keys, follow this naming convention:

- Title: `puzzle_<id>_title`
- Description: `puzzle_<id>_desc`
- Hint: `puzzle_<id>_hint`
- Completion Message: `puzzle_<id>_completion`

Example:

```json
{
  "id": "first_mill_001",
  "titleLocalizationKey": "puzzle_first_mill_001_title",
  "descriptionLocalizationKey": "puzzle_first_mill_001_desc",
  "hintLocalizationKey": "puzzle_first_mill_001_hint",
  "completionMessageLocalizationKey": "puzzle_first_mill_001_completion"
}
```

## Further Reading

- [Puzzle Contribution Guide](PUZZLE_CONTRIBUTION_GUIDE.md) - How to contribute puzzles
- [FEN Notation Spec](FEN_NOTATION.md) - FEN format details
- [API Documentation](API.md) - Programmatic puzzle access

---

**Document Version:** 1.0  
**Last Updated:** December 2025  
**Status:** Current
