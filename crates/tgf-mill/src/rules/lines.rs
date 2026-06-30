// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill three-in-a-row line tables.
//
// These are pure data: the standard 16 mill lines, the 20-line variant
// for boards with diagonal connections, plus the three capture-line
// families (square edges, cross, diagonal) consumed by the custodian /
// intervention / leap detection helpers in `super::captures` (still
// in `mod.rs` for now).

/// Standard 16 three-in-a-row lines covering the twelve ring edges plus the
/// four cross spokes.  Nodes use the master-normalized layout (`SQ - 8`):
/// inner, middle, outer rings; each ring starts at 12 o'clock and proceeds
/// clockwise.  Keep this order close to master's line tables because capture
/// helpers rely on `[0]`, `[1]`, `[2]` carrying geometric meaning.
pub(super) const STANDARD_MILL_LINES: &[[usize; 3]] = &[
    [7, 0, 1],
    [1, 2, 3],
    [3, 4, 5],
    [5, 6, 7],
    [15, 8, 9],
    [9, 10, 11],
    [11, 12, 13],
    [13, 14, 15],
    [23, 16, 17],
    [17, 18, 19],
    [19, 20, 21],
    [21, 22, 23],
    [0, 8, 16],
    [2, 10, 18],
    [4, 12, 20],
    [6, 14, 22],
];

/// Diagonal-board variant: standard 16 lines plus four corner diagonals.
pub(super) const DIAGONAL_MILL_LINES: &[[usize; 3]] = &[
    [7, 0, 1],
    [1, 2, 3],
    [3, 4, 5],
    [5, 6, 7],
    [15, 8, 9],
    [9, 10, 11],
    [11, 12, 13],
    [13, 14, 15],
    [23, 16, 17],
    [17, 18, 19],
    [19, 20, 21],
    [21, 22, 23],
    [0, 8, 16],
    [2, 10, 18],
    [4, 12, 20],
    [6, 14, 22],
    [23, 15, 7],
    [1, 9, 17],
    [21, 13, 5],
    [3, 11, 19],
];

/// Capture lines along the outer/middle/inner square edges.
pub(super) const CAPTURE_SQUARE_EDGE_LINES: &[[usize; 3]] = &[
    [23, 16, 17],
    [15, 8, 9],
    [7, 0, 1],
    [5, 4, 3],
    [13, 12, 11],
    [21, 20, 19],
    [23, 22, 21],
    [15, 14, 13],
    [7, 6, 5],
    [1, 2, 3],
    [9, 10, 11],
    [17, 18, 19],
];

/// Capture lines along the four cross spokes (orthogonal triples
/// crossing the centre seams).
pub(super) const CAPTURE_CROSS_LINES: &[[usize; 3]] =
    &[[22, 14, 6], [2, 10, 18], [16, 8, 0], [4, 12, 20]];

/// Diagonal three-point lines (middle index `[1]`) matching
/// `MillTopology::diagonal_line_groups` / C++ 12MM diagonal rules.
pub(super) const CAPTURE_DIAGONAL_LINES: &[[usize; 3]] =
    &[[23, 15, 7], [1, 9, 17], [21, 13, 5], [3, 11, 19]];
