// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Perfect Database position indexing.
//!
//! The indexing space is the database's fixed 24-bit perfect-index order, not
//! the `tgf-mill` node order. Keep coordinate conversion at the `mill` module
//! boundary so rules and gameplay continue to use the Rust/TGF representation.

mod hash;
pub mod symmetry;

pub use hash::{PerfectHasher, binom, collapse, next_choose, uncollapse};
