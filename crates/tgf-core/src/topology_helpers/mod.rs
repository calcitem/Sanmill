// SPDX-License-Identifier: GPL-3.0-or-later
// Reusable [`BoardTopology`] builders.
//
// Concrete games can construct their geometry by composing one of the
// helpers in this module.  Helpers live entirely on the IPC / FRB
// boundary — none of them are used by the search hot path.
//
// Currently provided:
//
//   * [`grid`] — rectangular `rows × cols` boards (Othello, Chess,
//     Gomoku, Go, Checkers).  Configurable connectivity (4-orthogonal,
//     8-king, knight) and label scheme (chess `a1..h8` or generic
//     `(col, row)`).
//   * [`hex`] — six-neighbour hexagonal grids (Hex, Reversi-on-hex).
//   * [`star`] — six-pointed star boards (Halma / Chinese Checkers,
//     121 / 73 / 49 holes).
//   * [`graph`] — generic node + edge builder for irregular boards
//     (军棋, Patolli, Game of Goose).
//
// All builders return `Box<dyn BoardTopology>` so the FRB layer can
// hand them to the kernel as `Arc<dyn BoardTopology>` without leaking
// concrete types.

pub mod grid;

pub use grid::{GridConnectivity, GridLabelScheme, GridTopology, GridTopologyBuilder};
