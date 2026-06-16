// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Process-global Rust-native Perfect Database handle.
//!
//! The current public API still delegates to the C++ wrapper. This module is
//! the migration handle that lets tests and future call sites exercise the
//! Rust loader with the same process-lifetime shape.

use std::sync::{LazyLock, Mutex};

use crate::database::{Database, DatabaseError, FileDatabaseProvider, PerfectOutcome};
use crate::mill::{
    PerfectMoveChoice, best_move_choice_with_database, evaluate_state_outcome_with_database,
    evaluate_state_with_database,
};
use tgf_core::GameStateSnapshot;
use tgf_mill::rules::MillState;
use tgf_mill::{MillRules, MillVariantOptions};

static RUST_DATABASE: LazyLock<Mutex<Option<Database<FileDatabaseProvider>>>> =
    LazyLock::new(|| Mutex::new(None));

pub fn init_rust_database(db_path: &str) -> Result<(), DatabaseError> {
    let database = Database::open(FileDatabaseProvider::new(db_path))?;
    let mut slot = RUST_DATABASE
        .lock()
        .expect("Rust Perfect DB global mutex must not be poisoned");
    *slot = Some(database);
    Ok(())
}

pub fn deinit_rust_database() {
    let mut slot = RUST_DATABASE
        .lock()
        .expect("Rust Perfect DB global mutex must not be poisoned");
    *slot = None;
}

pub fn is_rust_database_initialized() -> bool {
    RUST_DATABASE
        .lock()
        .expect("Rust Perfect DB global mutex must not be poisoned")
        .is_some()
}

pub fn evaluate_state_for_rust_database(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Result<Option<(i32, i32)>, DatabaseError> {
    let Some(result) = with_rust_database(|database| {
        evaluate_state_with_database(database, state, options, side_to_move)
    })?
    else {
        return Ok(None);
    };
    Ok(result)
}

pub fn evaluate_state_outcome_for_rust_database(
    state: &MillState,
    options: &MillVariantOptions,
    side_to_move: i8,
) -> Result<Option<PerfectOutcome>, DatabaseError> {
    let Some(result) = with_rust_database(|database| {
        evaluate_state_outcome_with_database(database, state, options, side_to_move)
    })?
    else {
        return Ok(None);
    };
    Ok(result)
}

pub fn best_move_choice_for_rust_database(
    rules: &MillRules,
    snap: &GameStateSnapshot,
    options: &MillVariantOptions,
) -> Result<Option<PerfectMoveChoice>, DatabaseError> {
    let Some(result) = with_rust_database(|database| {
        best_move_choice_with_database(database, rules, snap, options)
    })?
    else {
        return Ok(None);
    };
    Ok(result)
}

fn with_rust_database<T>(
    f: impl FnOnce(&mut Database<FileDatabaseProvider>) -> Result<T, DatabaseError>,
) -> Result<Option<T>, DatabaseError> {
    let mut slot = RUST_DATABASE
        .lock()
        .expect("Rust Perfect DB global mutex must not be poisoned");
    let Some(database) = slot.as_mut() else {
        return Ok(None);
    };
    f(database).map(Some)
}
