// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Safe Rust wrapper around the vendored C++ Perfect Database (`pd_*` C API).

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};

pub mod database;
pub mod file_format;
pub mod index;
mod mill;
pub use mill::{best_move_token_for_state, evaluate_state_for, evaluate_state_with_database};

static INITIALIZED: AtomicBool = AtomicBool::new(false);

unsafe extern "C" {
    fn pd_init_std(db_path: *const c_char) -> i32;
    fn pd_deinit();
    fn pd_evaluate(
        white_bits: i32,
        black_bits: i32,
        white_stones_to_place: i32,
        black_stones_to_place: i32,
        player_to_move: i32,
        only_stone_taking: i32,
        out_wdl: *mut i32,
        out_steps: *mut i32,
    ) -> i32;
    fn pd_best_move(
        white_bits: i32,
        black_bits: i32,
        white_stones_to_place: i32,
        black_stones_to_place: i32,
        player_to_move: i32,
        only_stone_taking: i32,
        out_buf: *mut c_char,
        out_buf_len: i32,
    ) -> i32;
}

/// Initialize the standard Nine Men's Morris perfect database from `db_path`.
pub fn init(db_path: &str) -> bool {
    let Ok(path) = CString::new(db_path) else {
        return false;
    };
    let ok = unsafe { pd_init_std(path.as_ptr()) != 0 };
    INITIALIZED.store(ok, Ordering::SeqCst);
    ok
}

/// Release perfect-database resources.
pub fn deinit() {
    unsafe { pd_deinit() };
    INITIALIZED.store(false, Ordering::SeqCst);
}

/// Returns whether [init] succeeded for the current process.
pub fn is_initialized() -> bool {
    INITIALIZED.load(Ordering::SeqCst)
}

/// Evaluate a position. Returns `(wdl, steps)` where `wdl` is 1=win, 0=draw, -1=loss.
pub fn evaluate(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    player_to_move: u8,
    only_stone_taking: bool,
) -> Option<(i32, i32)> {
    if !is_initialized() {
        return None;
    }
    let mut wdl = 0_i32;
    let mut steps = 0_i32;
    let ok = unsafe {
        pd_evaluate(
            white_bits as i32,
            black_bits as i32,
            i32::from(white_in_hand),
            i32::from(black_in_hand),
            i32::from(player_to_move),
            i32::from(only_stone_taking),
            &mut wdl,
            &mut steps,
        )
    };
    if ok == 0 { None } else { Some((wdl, steps)) }
}

/// Query the perfect-database best move as a notation token (`a4`, `a1-a4`, `xg7`).
pub fn best_move_token(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    player_to_move: u8,
    only_stone_taking: bool,
) -> Option<String> {
    if !is_initialized() {
        return None;
    }
    let mut buf = vec![0_i8; 32];
    let ok = unsafe {
        pd_best_move(
            white_bits as i32,
            black_bits as i32,
            i32::from(white_in_hand),
            i32::from(black_in_hand),
            i32::from(player_to_move),
            i32::from(only_stone_taking),
            buf.as_mut_ptr(),
            buf.len() as i32,
        )
    };
    if ok == 0 {
        return None;
    }
    let cstr = unsafe { CStr::from_ptr(buf.as_ptr()) };
    Some(cstr.to_string_lossy().into_owned())
}
