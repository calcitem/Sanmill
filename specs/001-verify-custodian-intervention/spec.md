# Feature Specification: Verify Custodian and Intervention Rule Implementation

**Feature Branch**: `001-verify-custodian-intervention`
**Created**: 2025-10-06
**Status**: Draft
**Input**: User description: "近期代码在 positioni.cpp、position.dart、movegen.cpp 等文件新增了 custodian 和 intervention 相关规则实现..."

## Execution Flow (main)
```
1. Parse user description from Input
   → Identified: verification of custodian/intervention rule implementation
2. Extract key concepts from description
   → Actors: game engine, players
   → Actions: capture via custodian, capture via intervention, mill formation
   → Data: game position, FEN notation, capture targets, piece counts
   → Constraints: rule combinations, move legality, FEN consistency
3. For each unclear aspect:
   → All critical ambiguities resolved via clarification session
4. Fill User Scenarios & Testing section
   → User flows identified: rule verification scenarios
5. Generate Functional Requirements
   → All requirements are testable via automated tests
6. Identify Key Entities
   → Game position, capture rules, FEN state
7. Run Review Checklist
   → Spec has uncertainties (marked above)
   → No implementation details (tech-neutral)
8. Return: SUCCESS (spec ready for planning)
```

---

## ⚡ Quick Guidelines
- ✅ Focus on WHAT users need and WHY
- ❌ Avoid HOW to implement (no tech stack, APIs, code structure)
- 👥 Written for business stakeholders, not developers

---

## Clarifications

### Session 2025-10-06
- Q: When custodian and intervention both trigger on the same move (geometrically possible scenario), what should the system behavior be? → A: Allow player to choose which rule to apply. Player's first capture selection determines which rule is applied. Custodian and intervention targets never overlap, so no priority between them exists. Both may overlap with mill targets (handled by existing mill combination logic).
- Q: When FEN import encounters conflicting capture markers (both `c:` and `i:` simultaneously), how should the system respond? → A: Accept both and let player choose on next capture
- Q: When FEN import detects that a custodian/intervention target piece is missing from the board (corrupted state), what should happen? → A: Reject entire FEN import as invalid
- Q: When `mayRemoveMultiple=false` is configured and a player forms multiple mills simultaneously, how should the system behave? → A: Allow only 1 capture total (ignore additional mills). However, if custodian or intervention also triggers, player may choose alternative capture method. If player selects intervention, they must capture second piece following intervention rule requirements (same-line endpoint).
- Q: When FEN export occurs and `pieceToRemoveCount` exceeds the number of opponent pieces remaining on the board, what should the system do? → A: Export exact `pieceToRemoveCount` value (allow inconsistency)

---

## User Scenarios & Testing *(mandatory)*

### Primary User Story
The game engine implements custodian and intervention capture rules alongside traditional mill-based captures. Players need these rules to work correctly in all combinations (custodian alone, intervention alone, custodian+mill, intervention+mill) with proper capture targeting, move legality validation, and FEN notation consistency for game replay.

### Acceptance Scenarios

1. **Given** custodian rule is triggered (piece placed at line endpoint, opponent piece in middle), **When** no mill is formed, **Then** system MUST only allow capturing the sandwiched piece and mark all other pieces as illegal capture targets

2. **Given** intervention rule is triggered (piece placed at line center, opponent pieces at both ends), **When** no mill is formed, **Then** system MUST only allow capturing the two endpoint pieces and force second capture to be the other endpoint piece on same line

3. **Given** player forms mill and triggers custodian in same turn, **When** player selects custodian target first, **Then** system MUST prevent subsequent mill captures

4. **Given** player forms mill and triggers custodian in same turn, **When** player selects non-custodian target (mill capture), **Then** system MUST only allow remaining mill captures without adding custodian capture opportunities

5. **Given** player forms mill and triggers intervention in same turn, **When** player selects intervention target first, **Then** system MUST force second capture to be the other endpoint on same line and prevent mill captures

6. **Given** player forms mill and triggers intervention in same turn, **When** player selects non-intervention target (mill capture), **Then** system MUST only allow remaining mill captures without adding intervention capture opportunities

7. **Given** `mayRemoveMultiple=false` configuration, **When** player triggers any capture combination, **Then** system MUST NOT pre-add capture counts to `pieceToRemoveCount` and execute only the chosen capture mode's required count

8. **Given** game position with custodian/intervention state, **When** position is exported to FEN notation with `c:`/`i:`/`p:` markers, **Then** FEN MUST accurately represent capture targets and counts

9. **Given** FEN notation with `c:`/`i:`/`p:` markers, **When** FEN is imported, **Then** game state MUST restore capture targets and counts exactly

10. **Given** player completes one remove action in multi-remove sequence, **When** position is exported to FEN mid-sequence, **Then** FEN MUST reflect updated capture targets and decremented counts or cleared state if complete

### Edge Cases
- **Custodian + Intervention Simultaneous Trigger**: When both custodian and intervention trigger on same move, player chooses which rule to apply via first capture selection. Custodian and intervention targets never overlap (different geometric patterns). Both may overlap with mill targets.
- **Conflicting FEN Capture Markers**: When FEN contains both `c:` and `i:` markers simultaneously, system accepts both and allows player to choose which rule to apply on next capture move.
- **Missing Capture Target on FEN Import**: When FEN import detects custodian/intervention target piece is missing from board (corrupted state), system rejects entire FEN as invalid.
- **mayRemoveMultiple=false with Multi-Mill Formation**: When `mayRemoveMultiple=false` and player forms multiple mills, allow only 1 capture total (ignore additional mills). If custodian/intervention also triggers, player may choose alternative capture method. Choosing intervention requires second capture following intervention rules (same-line endpoint).
- **pieceToRemoveCount Exceeds Opponent Pieces**: When FEN export occurs and `pieceToRemoveCount` exceeds remaining opponent pieces, system exports exact `pieceToRemoveCount` value (inconsistency allowed).

## Requirements *(mandatory)*

### Functional Requirements

**Custodian Rule (Standalone)**
- **FR-001**: System MUST identify custodian capture when piece is placed at three-point line endpoint with opponent piece in middle position
- **FR-002**: System MUST mark sandwiched opponent piece as the only legal capture target when custodian triggers without mill
- **FR-003**: System MUST mark all non-sandwiched pieces as illegal capture targets when custodian is active
- **FR-004**: System MUST allow capturing from opponent's mill pieces when custodian rule applies (regardless of mill-protection configuration)

**Intervention Rule (Standalone)**
- **FR-005**: System MUST identify intervention capture when piece is placed at three-point line center with opponent pieces at both endpoints
- **FR-006**: System MUST mark both endpoint opponent pieces as legal capture targets when intervention triggers without mill
- **FR-007**: System MUST force second capture to be the other endpoint piece on same line after first intervention capture
- **FR-008**: System MUST mark all non-endpoint pieces as illegal capture targets when intervention is active
- **FR-009**: System MUST allow capturing from opponent's mill pieces when intervention rule applies (regardless of mill-protection configuration)

**Mill + Custodian Combination**
- **FR-010**: System MUST allow player to choose capture mode (mill or custodian) when both are available
- **FR-011**: System MUST prevent mill captures after custodian target is selected
- **FR-012**: System MUST NOT add custodian capture opportunities to `pieceToRemoveCount` when mill capture is chosen first
- **FR-013**: System MUST execute only remaining mill captures when mill mode is chosen over custodian

**Mill + Intervention Combination**
- **FR-014**: System MUST allow player to choose capture mode (mill or intervention) when both are available
- **FR-015**: System MUST force second capture to same-line endpoint and prevent mill captures after intervention target is selected
- **FR-016**: System MUST NOT add intervention capture opportunities to `pieceToRemoveCount` when mill capture is chosen first
- **FR-017**: System MUST execute only remaining mill captures when mill mode is chosen over intervention

**Custodian + Intervention + Mill Combination**
- **FR-032**: System MUST allow player to choose among all available capture modes (custodian, intervention, mill) when multiple rules trigger simultaneously
- **FR-033**: System MUST determine active capture rule based on player's first capture selection (selecting custodian target activates custodian rule, selecting intervention target activates intervention rule, selecting mill-only target activates mill rule)

**mayRemoveMultiple=false Mode**
- **FR-018**: System MUST NOT pre-increment `pieceToRemoveCount` with capture opportunities when `mayRemoveMultiple=false`
- **FR-019**: System MUST execute only the chosen capture mode's required count when `mayRemoveMultiple=false`
- **FR-020**: System MUST respect chosen capture priority (custodian/intervention over mill or vice versa) throughout capture sequence when `mayRemoveMultiple=false`
- **FR-036**: System MUST allow only 1 capture total when `mayRemoveMultiple=false` and multiple mills form simultaneously (additional mills ignored)
- **FR-037**: System MUST allow player to choose custodian/intervention capture instead of mill when `mayRemoveMultiple=false` and multiple capture modes available
- **FR-038**: System MUST require second intervention capture following intervention rules (same-line endpoint) when player chooses intervention under `mayRemoveMultiple=false` mode

**FEN Notation Consistency**
- **FR-021**: System MUST export custodian state to FEN using `c:` marker with target position identifier
- **FR-022**: System MUST export intervention state to FEN using `i:` marker with target positions identifier
- **FR-023**: System MUST export `pieceToRemoveCount` to FEN using `p:` marker with accurate count
- **FR-024**: System MUST import FEN with `c:`/`i:`/`p:` markers and restore capture state exactly
- **FR-025**: System MUST update FEN capture markers after each remove action in multi-remove sequence
- **FR-026**: System MUST clear FEN capture markers when capture sequence is complete
- **FR-027**: System MUST maintain FEN import/export consistency for round-trip conversion (export then import yields identical state)
- **FR-034**: System MUST accept FEN with both `c:` and `i:` markers simultaneously and preserve both capture opportunities for player selection
- **FR-035**: System MUST reject FEN import as invalid when capture markers reference target pieces that do not exist on the board
- **FR-039**: System MUST export exact `pieceToRemoveCount` value in `p:` marker even when it exceeds remaining opponent pieces on board

**Move Legality Validation**
- **FR-028**: System MUST reject capture moves targeting non-designated pieces when custodian is active
- **FR-029**: System MUST reject capture moves targeting non-designated pieces when intervention is active
- **FR-030**: System MUST reject second intervention capture if target is not the required same-line endpoint
- **FR-031**: System MUST reject capture moves that violate chosen capture mode restrictions

### Key Entities *(include if feature involves data)*

- **Game Position**: Represents current board state with piece locations, active player, rule configurations
  - Attributes: board configuration, piece positions, active rules (custodian/intervention/mill), capture state
  - Relationships: Has capture rules, produces FEN notation

- **Capture Rule State**: Tracks active capture mechanisms and valid targets
  - Attributes: rule type (custodian/intervention/mill), valid target positions, remaining capture count
  - Relationships: Belongs to game position, affects move legality

- **FEN Notation**: Serialized representation of game state including capture markers
  - Attributes: position string, `c:` marker (custodian), `i:` marker (intervention), `p:` marker (piece count)
  - Relationships: Represents game position, enables import/export

---

## Review & Acceptance Checklist
*GATE: Automated checks run during main() execution*

### Content Quality
- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

### Requirement Completeness
- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

---

## Execution Status
*Updated by main() during processing*

- [x] User description parsed
- [x] Key concepts extracted
- [x] Ambiguities marked
- [x] User scenarios defined
- [x] Requirements generated
- [x] Entities identified
- [x] Review checklist passed
- [x] Clarifications completed (5 questions answered)

---
