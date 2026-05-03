// SPDX-License-Identifier: GPL-3.0-or-later
// Mill three-in-a-row line tables.
//
// These are pure data: the standard 16 mill lines, the 20-line variant
// for boards with diagonal connections, plus the three capture-line
// families (square edges, cross, diagonal) consumed by the custodian /
// intervention / leap detection helpers in `super::captures` (still
// in `mod.rs` for now).

/// Standard 16 three-in-a-row lines covering the eight outer/middle
/// edges plus the four cross spokes.
pub(super) const STANDARD_MILL_LINES: &[[usize; 3]] = &[
    [0, 1, 2],
    [2, 3, 4],
    [4, 5, 6],
    [6, 7, 0],
    [8, 9, 10],
    [10, 11, 12],
    [12, 13, 14],
    [14, 15, 8],
    [16, 17, 18],
    [18, 19, 20],
    [20, 21, 22],
    [22, 23, 16],
    [1, 9, 17],
    [3, 11, 19],
    [5, 13, 21],
    [7, 15, 23],
];

/// Diagonal-board variant: standard 16 lines plus four corner diagonals.
pub(super) const DIAGONAL_MILL_LINES: &[[usize; 3]] = &[
    [0, 1, 2],
    [2, 3, 4],
    [4, 5, 6],
    [6, 7, 0],
    [8, 9, 10],
    [10, 11, 12],
    [12, 13, 14],
    [14, 15, 8],
    [16, 17, 18],
    [18, 19, 20],
    [20, 21, 22],
    [22, 23, 16],
    [1, 9, 17],
    [3, 11, 19],
    [5, 13, 21],
    [7, 15, 23],
    [0, 8, 16],
    [18, 10, 2],
    [6, 14, 22],
    [20, 12, 4],
];

/// Capture lines along the outer/middle/inner square edges.
pub(super) const CAPTURE_SQUARE_EDGE_LINES: &[[usize; 3]] = &[
    [0, 1, 2],
    [8, 9, 10],
    [16, 17, 18],
    [22, 21, 20],
    [14, 13, 12],
    [6, 5, 4],
    [0, 7, 6],
    [8, 15, 14],
    [16, 23, 22],
    [18, 19, 20],
    [10, 11, 12],
    [2, 3, 4],
];

/// Capture lines along the four cross spokes (orthogonal triples
/// crossing the centre seams).
pub(super) const CAPTURE_CROSS_LINES: &[[usize; 3]] =
    &[[7, 15, 23], [19, 11, 3], [1, 9, 17], [21, 13, 5]];

/// Diagonal three-point lines (middle index `[1]`) matching
/// `MillTopology::diagonal_line_groups` / C++ 12MM diagonal rules.
pub(super) const CAPTURE_DIAGONAL_LINES: &[[usize; 3]] =
    &[[0, 8, 16], [18, 10, 2], [6, 14, 22], [20, 12, 4]];
