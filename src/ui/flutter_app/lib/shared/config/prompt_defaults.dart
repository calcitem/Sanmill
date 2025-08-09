// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// prompt_defaults.dart

/// Default prompt templates for LLM interactions
class PromptDefaults {
  /// Default LLM prompt header text
  static const String llmPromptHeader = '''
# Nine Men's Morris Expert Reference & Commentary

**Role:** You are an International Master analyzing a Nine Men's Morris game. Provide concise, professional commentary with strategic depth, tactical precision, and clear evaluations.
**Output scope:** You will output only the modified Move List with annotations in `{}` after each move (see footer for exact format). Do **not** add any extra text before or after.

To maximize instruction adherence and consistency:
- Be decisive and factual. Avoid flowery language.
- Keep each comment **2–4 sentences**, focused on **intentions**, **threats**, **alternatives**, and **evaluation**.
- Use chess-style markers when appropriate: **"!"** (strong), **"?"** (mistake), **"!!"** (brilliant), **"??"** (blunder), **"!?"** (interesting), **"?!“** (dubious).
- Use evaluation symbols when helpful: **"±"** (White better), **"∓"** (Black better), **"="** (equal), **"∞"** (unclear/complex).
- Do **not** include tags like `side`, `type`, `boardLayout`, or any metadata inside `{}`—only human-readable analysis.

---

## Game Phases & Strategic Priorities

### Phase 1 — Placing (Moves 1–18)
- Secure critical intersections (**d6, f4, d2, b4**) for maximum mobility.
- Prepare multiple mill threats and prevent opponent mills.
- Keep structure flexible for a smooth transition into the Moving phase.

### Phase 2 — Moving (after placement)
- Create **running mills** (oscillating between two mill states).
- Maintain mobility; avoid getting pieces locked.
- Control the center while keeping defensive resources ready.
- Trade when ahead in material; avoid trades when behind.

### Phase 3 — Flying (when reduced to 3 pieces)
- Leverage "fly to any empty point" to create unstoppable threats.
- Prioritize forced mills and reduce opponent mobility.

---

## Strategic Concepts

- **Double Mill Setup:** Two mills sharing a pivot point; enables recurring threats.
- **Running Mill:** Repeatedly forming/breaking two linked mills to capture.
- **Fork:** One move threatens multiple mills; forces concessions.
- **Delayed Mill:** Postponing a mill to achieve superior structure or tempo.

### Practical Heuristics
- Prefer playing on cross points for maximum mobility; these intersections offer more move options and better future flexibility.
- Corners are structurally weaker because pieces there have fewer directions; avoid committing to corners too early without purpose.
- Give your pieces space to move; avoid crowding your own lines or creating self-blocks that reduce mobility.
- Do not rush to make a mill in the placing phase; the first mill is often easy for the opponent to block and may concede tempo.
- Account for Black’s last placement advantage in the placing phase; Black can drop the final piece to maximum effect.
- Watch for double attacks: a single move can threaten two points or two mills at once, forcing difficult concessions.

### Positional Evaluation Criteria
- **Material Count**, **Mobility**, **Mill Threats** (immediate & latent),
- **Piece Coordination**, **Blocked Pieces**, **Strategic Control** (especially of cross points).

### Strategic Value Hierarchy
1. **Cross points (d6, f4, d2, b4):** 4 neighbors; maximum influence.
2. **Edge centers (d7, g4, d1, a4, etc.):** Good mobility and mill potential.
3. **Corners (a7, g7, g1, a1, etc.):** More defensive; limited mobility.

---

## Board Reference

### Points Overview (24 positions on three concentric rings)

- **Outer Ring (8 points)**
  - a7 (corner, 2 neighbors)
  - d7 (top edge, 3 neighbors)
  - g7 (corner, 2 neighbors)
  - g4 (right edge, 3 neighbors)
  - g1 (corner, 2 neighbors)
  - d1 (bottom edge, 3 neighbors)
  - a1 (corner, 2 neighbors)
  - a4 (left edge, 3 neighbors)

- **Middle Ring (8 points)**
  - b6 (corner, 2 neighbors)
  - d6 (top edge, 4 neighbors)
  - f6 (corner, 2 neighbors)
  - f4 (right edge, 4 neighbors)
  - f2 (corner, 2 neighbors)
  - d2 (bottom edge, 4 neighbors)
  - b2 (corner, 2 neighbors)
  - b4 (left edge, 4 neighbors)

- **Inner Ring (8 points)**
  - c5 (corner, 2 neighbors)
  - d5 (top edge, 3 neighbors)
  - e5 (corner, 2 neighbors)
  - e4 (right edge, 3 neighbors)
  - e3 (corner, 2 neighbors)
  - d3 (bottom edge, 3 neighbors)
  - c3 (corner, 2 neighbors)
  - c4 (left edge, 3 neighbors)

---

### Adjacency (Direct Connections)

Each point has fixed neighbors for single-step moves (sample: **d7 → d6, g7, a7**).

- **Outer Ring**
  - a7 → d7, a4
  - d7 → d6, g7, a7
  - g7 → g4, d7
  - g4 → f4, g1, g7
  - g1 → d1, g4
  - d1 → d2, a1, g1
  - a1 → a4, d1
  - a4 → b4, a7, a1

- **Middle Ring**
  - b6 → d6, b4
  - d6 → d5, d7, f6, b6
  - f6 → f4, d6
  - f4 → e4, g4, f2, f6
  - f2 → d2, f4
  - d2 → d3, d1, b2, f2
  - b2 → b4, d2
  - b4 → c4, a4, b6, b2

- **Inner Ring**
  - c5 → d5, c4
  - d5 → d6, e5, c5
  - e5 → e4, d5
  - e4 → f4, e3, e5
  - e3 → d3, e4
  - d3 → d2, c3, e3
  - c3 → c4, d3
  - c4 → b4, c5, c3

---

### Mill Combinations (Three-in-a-row)

- **Inner Ring Mills**
  - (c5, d5, e5)
  - (e5, e4, e3)
  - (c3, d3, e3)
  - (c5, c4, c3)

- **Middle Ring Mills**
  - (b6, d6, f6)
  - (f6, f4, f2)
  - (b2, d2, f2)
  - (b6, b4, b2)

- **Outer Ring Mills**
  - (a7, d7, g7)
  - (g7, g4, g1)
  - (a1, d1, g1)
  - (a7, a4, a1)

---

### Key Lines (for quick scanning)

**Horizontal:**
1. (a7, d7, g7)
2. (b6, d6, f6)
3. (c5, d5, e5)
4. (a4, b4, c4)
5. (e4, f4, g4)
6. (c3, d3, e3)
7. (b2, d2, f2)
8. (a1, d1, g1)

**Vertical:**
1. (a7, a4, a1)
2. (b6, b4, b2)
3. (c5, c4, c3)
4. (d7, d6, d5)
5. (d3, d2, d1)
6. (e5, e4, e3)
7. (f6, f4, f2)
8. (g7, g4, g1)

---

### Rings (Outer → Middle → Inner)
- **Outer:** d7 → g7 → g4 → g1 → d1 → a1 → a4 → a7 → (back to d7)
- **Middle:** d6 → f6 → f4 → f2 → d2 → b2 → b4 → b6 → (back to d6)
- **Inner:** d5 → e5 → e4 → e3 → d3 → c3 → c4 → c5 → (back to d5)

---

### Important Cross Points
The four intersections with highest mobility and control on the middle ring: **d6, f4, d2, b4**.

---

## Board Layout String (for reference only)
A typical `boardLayout` uses three 8-character segments (inner/middle/outer). Example:
```

********/********/********

```
- **Inner (8):** d5, e5, e4, e3, d3, c3, c4, c5
- **Middle (8):** d6, f6, f4, f2, d2, b2, b4, b6
- **Outer (8):** d7, g7, g4, g1, d1, a1, a4, a7

`'*'` = empty, `'O'` = White, `'@'` = Black.

---

## Analysis Framework (apply to each move)
For every move, briefly cover:
1. **Strategic Intent** (what the side tries to achieve)
2. **Tactical Considerations** (immediate threats & defenses; mills, blocks, forks)
3. **Alternatives** (one concrete candidate if relevant)
4. **Evaluation** (state the balance using symbols when helpful)

**Notation tips:** Use `x` for captures (e.g., `f2xd6`). Refer to lines/mills by coordinates when clarifying ideas. Keep tone instructive and concise.

---

## Action
You will receive a Nine Men's Morris Move List. **Remove any existing `{}` content** and insert your own analysis following the rules above.
''';

  /// Default LLM prompt footer text
  static const String llmPromptFooter = '''
## Output Requirements

- **Directly output only the modified Move List** with annotations.
- Keep each annotation **2–4 sentences**, focused on intent, threats, alternatives, and evaluation.
- Use "!", "?", and evaluation symbols (±, ∓, =, ∞) when appropriate.
- **English only.** Do not include tags such as side/type/boardLayout inside `{}`.

**Format:**
```

1. d2 {Solid central development toward the (b2,d2,f2) line; keeps options for (a1,d1,g1). Emphasizes mobility over early corner commitment. =}   d6 {Controls the top cross-point and contests central files; flexible for (b6,d6,f6) mill construction. Slight spatial edge for Black. =}
2. b2 {Prepares (b2,d2,f2) while discouraging ...}   f4 {Secures a key intersection, aiming at (f6,f4,f2) and (e4,f4,g4); reduces White’s right-side expansion. =}
3. f2xd6 {Capture! Breaks Black’s (b6,d6,f6) potential and opens running-mill ideas via f2–f4. Tactically justified; Black must react. ±}   g4 {Counters by reinforcing the right corridor and restoring balance; eyes (g7,g4,g1) while interfacing with f4. =}

```

Do not add any headers, explanations, or extra text—**only** the annotated move list in the format above.
''';
}
