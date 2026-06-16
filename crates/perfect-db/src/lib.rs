// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Safe Rust wrapper around the Perfect Database.

#[cfg(feature = "cpp-oracle")]
use std::ffi::{CStr, CString};
#[cfg(feature = "cpp-oracle")]
use std::os::raw::c_char;
use std::sync::atomic::{AtomicBool, Ordering};

pub mod database;
pub mod file_format;
pub mod index;
mod mill;
mod rust_global;
pub use mill::{
    PerfectMoveChoice, best_move_choice_for_query_with_database, best_move_choice_with_database,
    best_move_token_for_state, best_move_token_with_database, evaluate_state_for,
    evaluate_state_outcome_with_database, evaluate_state_with_database,
    snapshot_from_perfect_query,
};
pub use rust_global::{
    best_move_choice_for_rust_database, best_move_choice_rust_database,
    best_move_token_rust_database, deinit_rust_database, evaluate_outcome_rust_database,
    evaluate_rust_database, evaluate_state_for_rust_database,
    evaluate_state_outcome_for_rust_database, init_rust_database, init_rust_database_from_provider,
    is_rust_database_initialized,
};

static INITIALIZED: AtomicBool = AtomicBool::new(false);
#[cfg(feature = "cpp-oracle")]
static USE_RUST_BACKEND: AtomicBool = AtomicBool::new(false);
#[cfg(not(feature = "cpp-oracle"))]
static USE_RUST_BACKEND: AtomicBool = AtomicBool::new(true);

#[cfg(feature = "cpp-oracle")]
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
    if is_rust_backend_enabled() {
        let ok = rust_global::init_rust_database(db_path).is_ok();
        if !ok {
            rust_global::deinit_rust_database();
        }
        INITIALIZED.store(ok, Ordering::SeqCst);
        return ok;
    }

    let ok = init_cpp_database(db_path);
    INITIALIZED.store(ok, Ordering::SeqCst);
    ok
}

/// Release perfect-database resources.
pub fn deinit() {
    if is_rust_backend_enabled() {
        rust_global::deinit_rust_database();
    } else {
        deinit_cpp_database();
    }
    INITIALIZED.store(false, Ordering::SeqCst);
}

/// Returns whether [init] succeeded for the current process.
pub fn is_initialized() -> bool {
    INITIALIZED.load(Ordering::SeqCst)
}

/// Select whether the stable process-global API delegates to the Rust loader.
///
/// The default is `false`, keeping the current C++ wrapper as the oracle.
/// Enable this before calling [`init`] to exercise the Rust-native backend
/// through the same public API surface.
pub fn set_rust_backend_enabled(enabled: bool) {
    assert!(
        enabled || cfg!(feature = "cpp-oracle"),
        "C++ Perfect DB oracle backend is not compiled"
    );
    USE_RUST_BACKEND.store(enabled, Ordering::SeqCst);
}

pub fn is_rust_backend_enabled() -> bool {
    USE_RUST_BACKEND.load(Ordering::SeqCst)
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
    if is_rust_backend_enabled() {
        return rust_global::evaluate_rust_database(
            white_bits,
            black_bits,
            white_in_hand,
            black_in_hand,
            player_to_move,
            only_stone_taking,
        )
        .unwrap_or_else(|err| panic!("Rust Perfect DB evaluate failed: {err}"));
    }

    evaluate_cpp_database(
        white_bits,
        black_bits,
        white_in_hand,
        black_in_hand,
        player_to_move,
        only_stone_taking,
    )
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
    if is_rust_backend_enabled() {
        return rust_global::best_move_token_rust_database(
            white_bits,
            black_bits,
            white_in_hand,
            black_in_hand,
            player_to_move,
            only_stone_taking,
        )
        .unwrap_or_else(|err| panic!("Rust Perfect DB best move failed: {err}"));
    }

    best_move_token_cpp_database(
        white_bits,
        black_bits,
        white_in_hand,
        black_in_hand,
        player_to_move,
        only_stone_taking,
    )
}

#[cfg(feature = "cpp-oracle")]
fn init_cpp_database(db_path: &str) -> bool {
    let Ok(path) = CString::new(db_path) else {
        return false;
    };
    unsafe { pd_init_std(path.as_ptr()) != 0 }
}

#[cfg(not(feature = "cpp-oracle"))]
fn init_cpp_database(_db_path: &str) -> bool {
    panic!("C++ Perfect DB oracle backend is not compiled");
}

#[cfg(feature = "cpp-oracle")]
fn deinit_cpp_database() {
    unsafe { pd_deinit() };
}

#[cfg(not(feature = "cpp-oracle"))]
fn deinit_cpp_database() {
    panic!("C++ Perfect DB oracle backend is not compiled");
}

#[cfg(feature = "cpp-oracle")]
fn evaluate_cpp_database(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    player_to_move: u8,
    only_stone_taking: bool,
) -> Option<(i32, i32)> {
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

#[cfg(not(feature = "cpp-oracle"))]
fn evaluate_cpp_database(
    _white_bits: u32,
    _black_bits: u32,
    _white_in_hand: u8,
    _black_in_hand: u8,
    _player_to_move: u8,
    _only_stone_taking: bool,
) -> Option<(i32, i32)> {
    panic!("C++ Perfect DB oracle backend is not compiled");
}

#[cfg(feature = "cpp-oracle")]
fn best_move_token_cpp_database(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    player_to_move: u8,
    only_stone_taking: bool,
) -> Option<String> {
    let mut buf = vec![0 as c_char; 32];
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

#[cfg(not(feature = "cpp-oracle"))]
fn best_move_token_cpp_database(
    _white_bits: u32,
    _black_bits: u32,
    _white_in_hand: u8,
    _black_in_hand: u8,
    _player_to_move: u8,
    _only_stone_taking: bool,
) -> Option<String> {
    panic!("C++ Perfect DB oracle backend is not compiled");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{LazyLock, Mutex, MutexGuard};

    fn db_path() -> &'static str {
        concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../src/ui/flutter_app/assets/databases"
        )
    }

    fn stable_api_test_lock() -> MutexGuard<'static, ()> {
        static LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));
        LOCK.lock()
            .expect("stable Perfect DB API test lock must not be poisoned")
    }

    #[test]
    fn stable_api_can_delegate_to_rust_backend() {
        let _guard = stable_api_test_lock();
        set_rust_backend_enabled(true);
        assert!(init(db_path()));
        assert!(is_initialized());
        assert_eq!(evaluate(0, 0, 9, 9, 0, false), Some((0, 2)));
        assert!(best_move_token(0, 0, 9, 9, 0, false).is_some_and(|token| !token.is_empty()));
        deinit();
        assert!(!is_initialized());
        #[cfg(feature = "cpp-oracle")]
        set_rust_backend_enabled(false);
    }

    #[test]
    fn stable_api_rust_backend_reports_missing_database() {
        let _guard = stable_api_test_lock();
        set_rust_backend_enabled(true);
        assert!(!init(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../src/ui/flutter_app/assets/missing-perfect-db"
        )));
        assert!(!is_initialized());
        assert_eq!(evaluate(0, 0, 9, 9, 0, false), None);
        deinit();
        #[cfg(feature = "cpp-oracle")]
        set_rust_backend_enabled(false);
    }
}
