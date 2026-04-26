// SPDX-License-Identifier: GPL-3.0-or-later
// Transitional cxx::bridge wrapping the mature C++ Sanmill engine.
//
// Phase 2 deliberately keeps all game logic in C++ and exposes a small typed
// Rust facade.  Later phases replace these calls with native Rust
// implementations one subsystem at a time.

#[cxx::bridge]
mod ffi {
    unsafe extern "C++" {
        include!("tgf-legacy-cxx/cpp/legacy_engine_bridge.h");

        type LegacyPosition;

        fn legacy_initialize_once();
        fn legacy_new_position(rule_idx: i32) -> UniquePtr<LegacyPosition>;
        fn legacy_position_fen(pos: &LegacyPosition) -> String;
        fn legacy_position_apply_uci(pos: Pin<&mut LegacyPosition>, move_uci: &str) -> bool;
        fn legacy_position_legal_actions(pos: &LegacyPosition) -> String;
        fn legacy_position_phase(pos: &LegacyPosition) -> i32;
        fn legacy_position_side_to_move(pos: &LegacyPosition) -> i32;
    }
}

/// A Rust-owned wrapper around the C++ Position object.
pub struct LegacyKernel {
    inner: cxx::UniquePtr<ffi::LegacyPosition>,
}

// The legacy C++ Position is accessed only behind a Mutex in tgf-frb during
// Phase 2.  It is not internally thread-safe, but moving the owning UniquePtr
// between threads is safe as long as callers serialize access externally.
unsafe impl Send for LegacyKernel {}

impl LegacyKernel {
    /// Create a fresh Nine Men's Morris position by default (`rule_idx = 0`).
    pub fn new(rule_idx: i32) -> Self {
        ffi::legacy_initialize_once();
        Self {
            inner: ffi::legacy_new_position(rule_idx),
        }
    }

    /// Current C++ FEN string.
    pub fn fen(&self) -> String {
        ffi::legacy_position_fen(&self.inner)
    }

    /// Apply a UCI-style move (`d7`, `d7-g7`, `xa1`, ...).
    pub fn apply_uci(&mut self, move_uci: &str) -> bool {
        ffi::legacy_position_apply_uci(self.inner.pin_mut(), move_uci)
    }

    /// Legal actions in UCI notation, one per line.
    pub fn legal_actions(&self) -> Vec<String> {
        ffi::legacy_position_legal_actions(&self.inner)
            .lines()
            .filter(|s| !s.is_empty())
            .map(ToOwned::to_owned)
            .collect()
    }

    /// Raw C++ Phase enum value.
    pub fn phase_tag(&self) -> i32 {
        ffi::legacy_position_phase(&self.inner)
    }

    /// Raw C++ Color enum value.
    pub fn side_to_move(&self) -> i32 {
        ffi::legacy_position_side_to_move(&self.inner)
    }
}

impl Default for LegacyKernel {
    fn default() -> Self {
        Self::new(0)
    }
}
