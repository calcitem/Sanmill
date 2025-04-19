// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// prompt_defaults.dart

/// Default prompt templates for LLM interactions
class PromptDefaults {
  /// Default LLM prompt header text
  static const String llmPromptHeader = '''
Nine Men's Morris:

---

## Points Overview

There are 24 positions on the board, arranged across three concentric rings (outer, middle, inner). Each point belongs to one ring and has a specific location:

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

## Adjacency (Direct Connections)

Each point is connected to specific neighbors. For example:

> d7 → d6, g7, a7

Use the lists below to determine legal single-step moves:

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

## Mill Combinations (Three in a Row)

A "mill" is formed when three of your pieces occupy any of these triplets:

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

## Key Lines

### Horizontal Lines

1. (a7, d7, g7)
2. (b6, d6, f6)
3. (c5, d5, e5)
4. (a4, b4, c4)
5. (e4, f4, g4)
6. (c3, d3, e3)
7. (b2, d2, f2)
8. (a1, d1, g1)

### Vertical Lines

1. (a7, a4, a1)
2. (b6, b4, b2)
3. (c5, c4, c3)
4. (d7, d6, d5)
5. (d3, d2, d1)
6. (e5, e4, e3)
7. (f6, f4, f2)
8. (g7, g4, g1)

---

## Rings (Outer → Middle → Inner)

- **Outer Ring**: d7 → g7 → g4 → g1 → d1 → a1 → a4 → a7 → (back to d7)
- **Middle Ring**: d6 → f6 → f4 → f2 → d2 → b2 → b4 → b6 → (back to d6)
- **Inner Ring**: d5 → e5 → e4 → e3 → d3 → c3 → c4 → c5 → (back to d5)

---

## Important Cross Points

On the middle ring, these four intersections are especially crucial for mobility and control:

- **d6, f4, d2, b4**

They allow varied connections and are often central to strategic maneuvers.

---

## Notes on the Board Layout String

A typical `boardLayout` is shown by three 8-character segments (one segment per ring), for example:

```
********/********/********
```
- **First 8 characters**: Inner Ring in order (d5, e5, e4, e3, d3, c3, c4, c5)
- **Second 8 characters**: Middle Ring in order (d6, f6, f4, f2, d2, b2, b4, b6)
- **Third 8 characters**: Outer Ring in order (d7, g7, g4, g1, d1, a1, a4, a7)

Here, `'*'` indicates an empty point, `'O'` a white piece, `'@'` a black piece, etc.

---

## Action

Please comment on the Nine Men's Morris Move List below. Add comments after each move using {} to express your own opinions. Please note that you should first clear the original {} and then fill in your own. The comments are all to indicate your intentions:    
''';

  /// Default LLM prompt footer text
  static const String llmPromptFooter = '''
Please directly output the modified Move List

The format is as follows:

```
1.    d2 {Blabla}   d6 {Blabla}
2.    b2 {Blabla}   f4 {Blabla}
3.    f2xd6 {Blabla} d6 {Blabla}
```

Do not use side type boardLayout or other tags in the {Blabla} part.
''';
}
