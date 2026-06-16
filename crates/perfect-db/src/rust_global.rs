// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Process-global Rust-native Perfect Database handle.
//!
//! The default build can still delegate to the C++ oracle. This module is the
//! migration handle that lets Rust-only builds, tests, and future call sites
//! exercise the Rust loader with the same process-lifetime shape.

use std::sync::{LazyLock, Mutex};

use crate::database::{
    BoxDatabaseProvider, Database, DatabaseError, DatabaseOptions, DatabaseProvider,
    DatabaseVariant, FileDatabaseProvider, PerfectOutcome, PerfectQuery,
};
use crate::mill::{
    PerfectMoveChoice, best_move_choice_for_query_with_database, best_move_choice_with_database,
    evaluate_state_outcome_with_database, evaluate_state_with_database,
};
use tgf_core::GameStateSnapshot;
use tgf_mill::rules::MillState;
use tgf_mill::{MillRules, MillVariantOptions};

static RUST_DATABASE: LazyLock<Mutex<Option<Database<BoxDatabaseProvider>>>> =
    LazyLock::new(|| Mutex::new(None));

pub fn init_rust_database(db_path: &str) -> Result<(), DatabaseError> {
    init_rust_database_variant(db_path, DatabaseVariant::STANDARD)
}

pub fn init_rust_database_variant(
    db_path: &str,
    variant: DatabaseVariant,
) -> Result<(), DatabaseError> {
    init_rust_database_variant_with_options(db_path, variant, DatabaseOptions::default())
}

pub fn init_rust_database_with_options(
    db_path: &str,
    options: DatabaseOptions,
) -> Result<(), DatabaseError> {
    init_rust_database_variant_with_options(db_path, DatabaseVariant::STANDARD, options)
}

pub fn init_rust_database_variant_with_options(
    db_path: &str,
    variant: DatabaseVariant,
    options: DatabaseOptions,
) -> Result<(), DatabaseError> {
    init_rust_database_from_provider_variant_with_options(
        FileDatabaseProvider::new(db_path),
        variant,
        options,
    )
}

pub fn init_rust_database_from_provider(
    provider: impl DatabaseProvider + Send + Sync + 'static,
) -> Result<(), DatabaseError> {
    init_rust_database_from_provider_variant(provider, DatabaseVariant::STANDARD)
}

pub fn init_rust_database_from_provider_variant(
    provider: impl DatabaseProvider + Send + Sync + 'static,
    variant: DatabaseVariant,
) -> Result<(), DatabaseError> {
    init_rust_database_from_provider_variant_with_options(
        provider,
        variant,
        DatabaseOptions::default(),
    )
}

pub fn init_rust_database_from_provider_with_options(
    provider: impl DatabaseProvider + Send + Sync + 'static,
    options: DatabaseOptions,
) -> Result<(), DatabaseError> {
    init_rust_database_from_provider_variant_with_options(
        provider,
        DatabaseVariant::STANDARD,
        options,
    )
}

pub fn init_rust_database_from_provider_variant_with_options(
    provider: impl DatabaseProvider + Send + Sync + 'static,
    variant: DatabaseVariant,
    options: DatabaseOptions,
) -> Result<(), DatabaseError> {
    let database =
        Database::open_variant_with_options(BoxDatabaseProvider::new(provider), variant, options)?;
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

pub fn loaded_sector_count_rust_database() -> Option<usize> {
    RUST_DATABASE
        .lock()
        .expect("Rust Perfect DB global mutex must not be poisoned")
        .as_ref()
        .map(Database::loaded_sector_count)
}

pub fn loaded_variant_rust_database() -> Option<DatabaseVariant> {
    RUST_DATABASE
        .lock()
        .expect("Rust Perfect DB global mutex must not be poisoned")
        .as_ref()
        .map(Database::variant)
}

pub fn evaluate_rust_database(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    side_to_move: u8,
    only_stone_taking: bool,
) -> Result<Option<(i32, i32)>, DatabaseError> {
    let query = PerfectQuery::new(
        white_bits,
        black_bits,
        white_in_hand,
        black_in_hand,
        side_to_move,
        only_stone_taking,
    );
    let Some(result) = with_rust_database(|database| database.evaluate(query))? else {
        return Ok(None);
    };
    Ok(result)
}

pub fn evaluate_outcome_rust_database(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    side_to_move: u8,
    only_stone_taking: bool,
) -> Result<Option<PerfectOutcome>, DatabaseError> {
    let query = PerfectQuery::new(
        white_bits,
        black_bits,
        white_in_hand,
        black_in_hand,
        side_to_move,
        only_stone_taking,
    );
    let Some(result) = with_rust_database(|database| database.evaluate_outcome(query))? else {
        return Ok(None);
    };
    Ok(result)
}

pub fn best_move_choice_rust_database(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    side_to_move: u8,
    only_stone_taking: bool,
) -> Result<Option<PerfectMoveChoice>, DatabaseError> {
    let query = PerfectQuery::new(
        white_bits,
        black_bits,
        white_in_hand,
        black_in_hand,
        side_to_move,
        only_stone_taking,
    );
    let options = MillVariantOptions::default();
    let rules = MillRules::new(options.clone());
    let Some(result) = with_rust_database(|database| {
        best_move_choice_for_query_with_database(database, &rules, &options, query)
    })?
    else {
        return Ok(None);
    };
    Ok(result)
}

pub fn best_move_token_rust_database(
    white_bits: u32,
    black_bits: u32,
    white_in_hand: u8,
    black_in_hand: u8,
    side_to_move: u8,
    only_stone_taking: bool,
) -> Result<Option<String>, DatabaseError> {
    Ok(best_move_choice_rust_database(
        white_bits,
        black_bits,
        white_in_hand,
        black_in_hand,
        side_to_move,
        only_stone_taking,
    )?
    .map(|choice| choice.token))
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
    f: impl FnOnce(&mut Database<BoxDatabaseProvider>) -> Result<T, DatabaseError>,
) -> Result<Option<T>, DatabaseError> {
    let mut slot = RUST_DATABASE
        .lock()
        .expect("Rust Perfect DB global mutex must not be poisoned");
    let Some(database) = slot.as_mut() else {
        return Ok(None);
    };
    f(database).map(Some)
}
