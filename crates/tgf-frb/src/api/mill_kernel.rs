// SPDX-License-Identifier: AGPL-3.0-or-later
// Mill-specific FRB kernel API.
//
// Every entry point declared here is exclusively meaningful for
// Mill-flavoured kernels: it constructs / decorates a `MillRules`
// session through the `tgf_core::GameKernel` registry plus Mill's
// `variant_extras` blob.  Keeping these out of `crate::api::kernel`
// makes the latter a genuinely game-neutral CRUD surface that future
// games (Othello / Checkers / …) can ship in parallel.
//
// Dart side: imported from `lib/src/rust/api/mill_kernel.dart` after
// `flutter_rust_bridge_codegen generate`.

use std::sync::Arc;

use tgf_core::{Action, ActionList, GameKernel, GameRules};
use tgf_mill::{MillPhase, MillRules, MillVariantOptions as NativeMillVariantOptions};

use super::kernel::{TgfAction, TgfSnapshot};
use crate::api::simple::{
    EngineEvent, MillAnalysisReport, MillEngineConfig, MillMoveAnalysis, MillVariantOptions,
    spawn_kernel_search_error, spawn_mill_engine_config_event_stream, spawn_mill_pvs_event_stream,
};
use crate::frb_generated::StreamSink;
use crate::games::mill::{perfect, search, variant_extras};
use crate::session_registry::{insert_kernel, with_kernel};

/// Create a Mill kernel with explicit variant options.  Use this once
/// the Flutter `RuleSettings` model is mapped through
/// `MillVariantOptionsMapper`.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_create_mill(variant: MillVariantOptions) -> Result<u32, String> {
    let native: NativeMillVariantOptions = variant.into();
    let rules: Arc<dyn GameRules> = Arc::new(MillRules::new(native.clone()));
    let kernel = GameKernel::new(rules, &[]);
    let id = insert_kernel(kernel);
    variant_extras::attach(id, native);
    Ok(id)
}

/// PVS search over the kernel's **current** Mill position, using the
/// same variant options as [tgf_kernel_create_mill].
///
/// Streams the same [EngineEvent] sequence as
/// [crate::api::simple::native_mill_search_events]: one `info` event
/// per IDS depth, then `bestMove` + `stopped`.
pub fn tgf_kernel_mill_search_events(handle: u32, depth: i32, sink: StreamSink<EngineEvent>) {
    let game_id = match with_kernel(handle, |k| k.game_id().to_owned()) {
        Ok(id) => id,
        Err(e) => {
            spawn_kernel_search_error(e, sink);
            return;
        }
    };
    if game_id != "mill" {
        spawn_kernel_search_error(format!("kernel game_id is {game_id}, expected mill"), sink);
        return;
    }

    let (snapshot, history) =
        match with_kernel(handle, |k| (k.snapshot(), k.history_snapshots().to_vec())) {
            Ok(state) => state,
            Err(e) => {
                spawn_kernel_search_error(e, sink);
                return;
            }
        };

    let options = variant_extras::options_for(handle);
    let root_repetition_history = MillRules::repetition_history_from_snapshots(&snapshot, &history);
    let root_position_resets_repetition =
        MillRules::root_position_resets_repetition_from_snapshots(&snapshot, &history);
    spawn_mill_pvs_event_stream(
        snapshot,
        root_repetition_history,
        root_position_resets_repetition,
        options,
        depth,
        sink,
    );
}

/// Full-config search over the kernel's **current** Mill position.
///
/// Accepts a [`MillEngineConfig`] that controls algorithm, depth, time
/// limit and lazy-search behaviour.  Preferred over
/// [tgf_kernel_mill_search_events] for production use once the Flutter
/// side has migrated to the typed config.
pub fn tgf_kernel_mill_search_events_with_config(
    handle: u32,
    config: MillEngineConfig,
    sink: StreamSink<EngineEvent>,
) {
    let game_id = match with_kernel(handle, |k| k.game_id().to_owned()) {
        Ok(id) => id,
        Err(e) => {
            spawn_kernel_search_error(e, sink);
            return;
        }
    };
    if game_id != "mill" {
        spawn_kernel_search_error(format!("kernel game_id is {game_id}, expected mill"), sink);
        return;
    }
    let (snapshot, history) =
        match with_kernel(handle, |k| (k.snapshot(), k.history_snapshots().to_vec())) {
            Ok(state) => state,
            Err(e) => {
                spawn_kernel_search_error(e, sink);
                return;
            }
        };
    let options = variant_extras::options_for(handle);
    let root_repetition_history = MillRules::repetition_history_from_snapshots(&snapshot, &history);
    let root_position_resets_repetition =
        MillRules::root_position_resets_repetition_from_snapshots(&snapshot, &history);
    spawn_mill_engine_config_event_stream(
        snapshot,
        root_repetition_history,
        root_position_resets_repetition,
        options,
        config,
        sink,
    );
}

// ---------------------------------------------------------------------------
// Setup-position editing API
//
// Design note: the legacy C++/Dart Position::action tri-state (place /
// select / remove) is intentionally absent here.  The native board
// editor cycles the owner value on each tap via setup_set_piece(node,
// owner) — one call covers all edit intents.  A
// tgf_kernel_setup_set_action function is not needed and is not
// planned (see docs/FRAMEWORK_API.md §"Setup-position editing API").
// ---------------------------------------------------------------------------

/// Clear the board associated with a Mill kernel handle and reset all
/// pieces, returning the fresh empty snapshot.  History and redo stacks
/// are cleared.
///
/// This is the entry point for the Flutter setup-position flow: call
/// `tgf_kernel_setup_clear` first, then `tgf_kernel_setup_set_piece` for
/// each piece, then `tgf_kernel_setup_finish` to transition to a
/// playable state.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_clear(handle: u32) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let empty_state = rules.setup_empty();
        let snapshot = rules.encode_state(empty_state);
        kernel.replace_state(snapshot);
        Ok(TgfSnapshot::from_snap(kernel.snapshot()))
    })?
}

/// Set or clear a single piece at `node` for a Mill kernel in setup
/// mode.
///
/// `owner`: `1` = first player (White), `2` = second player (Black),
/// any other value = clear the square.
///
/// Call `tgf_kernel_setup_clear` before the first `set_piece` to start
/// with a blank board, then `tgf_kernel_setup_finish` when editing is
/// complete.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_set_piece(
    handle: u32,
    node: i32,
    owner: i32,
) -> Result<TgfSnapshot, String> {
    if !(0..24).contains(&node) {
        return Err(format!(
            "setup_set_piece node out of range: {node}; expected Rust node 0..23"
        ));
    }
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let mut state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        state.set_piece(node as u16, owner as i8);
        state.recompute_aux(&options);
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Set the side to move for a Mill kernel in setup mode.
///
/// `side`: `0` = first player (White), `1` = second player (Black).
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_set_side(handle: u32, side: i32) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let mut state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        state.set_side_to_move(side.clamp(0, 1) as i8);
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Finish the setup-position editing flow.
///
/// Determines whether the resulting board is in placing or moving
/// phase based on whether any pieces remain in hand, recomputes
/// auxiliary fields, and replaces the kernel state.  After this call
/// the kernel can be used for normal play (legal actions, apply,
/// search).
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_setup_finish(handle: u32) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("setup is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options.clone());
        let mut state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        state.recompute_aux(&options);
        // Determine phase: placing if either side still has pieces in
        // hand, moving otherwise — but check for an immediate GameOver
        // when either side would have fewer than pieces_at_least_count
        // pieces on board (mirrors C++ `check_if_game_is_over` at
        // position-setup boundaries).
        if state.pieces_in_hand()[0] > 0 || state.pieces_in_hand()[1] > 0 {
            state.set_phase(MillPhase::Placing);
        } else if let Some(winner) = state.check_pieces_at_least(&options) {
            state.set_phase(MillPhase::GameOver);
            state.set_winner(winner);
            state.set_outcome_reason_fewer_than_threshold();
        } else {
            state.set_phase(MillPhase::Moving);
        }
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Load a Mill board position from a FEN string.
///
/// Accepts node-id Mill FENs marked with `ids:nodes`, plus legacy square-id
/// FENs at import boundaries.  Returns the new snapshot on success, or an
/// error string on parse failure.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_set_from_fen(handle: u32, fen: String) -> Result<TgfSnapshot, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("set_from_fen is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options);
        let state = rules.set_from_fen(&fen)?;
        let new_snap = rules.encode_state(state);
        kernel.replace_state(new_snap);
        Ok(TgfSnapshot::from_snap(new_snap))
    })?
}

/// Analyse the kernel's **current** Mill position, returning one verdict per
/// legal move plus any detected trap moves.
///
/// Each move is evaluated against the perfect database (win/draw/loss + step
/// count) or, when the database has no entry, with a shallow heuristic search
/// (advantage/disadvantage).  When `trap_awareness` is set, aggressive moves
/// with a worse database verdict than an available alternative are reported in
/// [`MillAnalysisReport::traps`].  This backs the analysis overlay (the legacy
/// C++ `analyze` UCI command) without mutating the kernel state.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_mill_perfect_db_analyze(
    handle: u32,
    trap_awareness: bool,
) -> Result<MillAnalysisReport, String> {
    let game_id = with_kernel(handle, |k| k.game_id().to_owned())?;
    if game_id != "mill" {
        return Err(format!("kernel game_id is {game_id}, expected mill"));
    }
    let snapshot = with_kernel(handle, |k| k.snapshot())?;
    let options = variant_extras::options_for(handle);
    let report = perfect::analyze_position(&snapshot, &options, trap_awareness);
    Ok(MillAnalysisReport {
        moves: report
            .moves
            .into_iter()
            .map(|e| MillMoveAnalysis {
                mv: e.mv,
                outcome: e.outcome.to_owned(),
                value: e.value,
                steps: e.steps,
            })
            .collect(),
        traps: report.traps,
    })
}

/// Query the perfect database for the best legal action in the kernel's
/// **current** Mill position without running a search or mutating state.
///
/// Returns `None` when the caller disabled the perfect database, the database
/// is unavailable, the active variant is unsupported, or no database-backed
/// legal action exists. This is used by Flutter to validate an advisory move
/// source, such as the Human Database, before applying that move.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_mill_perfect_db_best_action(
    handle: u32,
    config: MillEngineConfig,
) -> Result<Option<TgfAction>, String> {
    let plan: crate::games::mill::search::MillEngineConfigPlan = config.into();
    if !plan.use_perfect_database {
        return Ok(None);
    }

    let game_id = with_kernel(handle, |k| k.game_id().to_owned())?;
    if game_id != "mill" {
        return Err(format!("kernel game_id is {game_id}, expected mill"));
    }

    let snapshot = with_kernel(handle, |k| k.snapshot())?;
    let options = variant_extras::options_for(handle);
    let rules = MillRules::new(options);
    let mut legal = ActionList::<256>::default();
    rules.legal_actions(&snapshot, &mut legal);

    // No search ran for this advisory query, so there is no reference move to
    // prefer; pass NONE and let chooseRandom shuffle among the tied-best DB
    // moves when Shuffling is on (mirrors master perfect_player.h).
    Ok(perfect::try_perfect_best_action_with_ref(
        &snapshot,
        rules.options(),
        legal.as_slice(),
        search::perfect_move_ordering(&plan),
        Action::NONE,
        plan.shuffling,
        search::search_shuffle_seed(),
    )
    .map(TgfAction::from_action))
}

/// "Avoid traps" support: if the lightweight error patch has an entry for
/// the kernel's **current** Mill position and `chosen` is not the recorded
/// safe reply, return the legal action that is. Returns `Ok(None)` when no
/// patch is loaded, the position has no entry, or `chosen` is already safe
/// -- callers should keep `chosen` unchanged in that case.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_mill_patch_correct_action(
    handle: u32,
    chosen: TgfAction,
) -> Result<Option<TgfAction>, String> {
    let game_id = with_kernel(handle, |k| k.game_id().to_owned())?;
    if game_id != "mill" {
        return Err(format!("kernel game_id is {game_id}, expected mill"));
    }
    let snapshot = with_kernel(handle, |k| k.snapshot())?;
    let options = variant_extras::options_for(handle);
    Ok(
        crate::games::mill::patch::try_patch_correction(&snapshot, &options, chosen.into_action())
            .map(TgfAction::from_action),
    )
}

/// Database-free "make traps" support: if the lightweight error patch has
/// an entry for the kernel's **current** Mill position and `chosen` is one
/// of its mask-proven value-preserving moves, return the proven sibling
/// whose resulting position carries a strictly higher trap score (the
/// best-known blunder opportunity to hand the opponent). Returns
/// `Ok(None)` when no patch is loaded, the position has no entry, `chosen`
/// is not proven safe, or no sibling beats it -- callers should keep
/// `chosen` unchanged in that case. Unlike
/// [`tgf_kernel_mill_patch_trap_aware_best_action`] this needs no Perfect
/// Database: the proof of which moves are safe is the patch entry itself.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_mill_patch_make_traps_action(
    handle: u32,
    chosen: TgfAction,
) -> Result<Option<TgfAction>, String> {
    let game_id = with_kernel(handle, |k| k.game_id().to_owned())?;
    if game_id != "mill" {
        return Err(format!("kernel game_id is {game_id}, expected mill"));
    }
    let snapshot = with_kernel(handle, |k| k.snapshot())?;
    let options = variant_extras::options_for(handle);
    Ok(crate::games::mill::patch::try_patch_trap_aware_action(
        &snapshot,
        &options,
        chosen.into_action(),
    )
    .map(TgfAction::from_action))
}

/// "Make traps" support: trap score (0..=255) of the position reached by
/// playing `action` from the kernel's **current** Mill position, or `None`
/// when no patch is loaded or the resulting position has no entry.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_mill_patch_trap_score_after(
    handle: u32,
    action: TgfAction,
) -> Result<Option<i32>, String> {
    let game_id = with_kernel(handle, |k| k.game_id().to_owned())?;
    if game_id != "mill" {
        return Err(format!("kernel game_id is {game_id}, expected mill"));
    }
    let snapshot = with_kernel(handle, |k| k.snapshot())?;
    let options = variant_extras::options_for(handle);
    Ok(crate::games::mill::patch::trap_score_after_action(
        &snapshot,
        &options,
        action.into_action(),
    )
    .map(i32::from))
}

/// Query the perfect database for the best legal action, like
/// [`tgf_kernel_mill_perfect_db_best_action`], but when `make_traps` is set
/// and several moves are tied for best, prefer whichever one hands the
/// opponent the highest lightweight-patch trap score instead of shuffling
/// uniformly (see `crate::games::mill::patch`). Every candidate considered
/// is already database-verified equally optimal, so this can never pick a
/// worse move than the plain tied-best pick -- it only reorders among ties.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_mill_patch_trap_aware_best_action(
    handle: u32,
    config: MillEngineConfig,
    make_traps: bool,
) -> Result<Option<TgfAction>, String> {
    let plan: crate::games::mill::search::MillEngineConfigPlan = config.into();
    if !plan.use_perfect_database {
        return Ok(None);
    }

    let game_id = with_kernel(handle, |k| k.game_id().to_owned())?;
    if game_id != "mill" {
        return Err(format!("kernel game_id is {game_id}, expected mill"));
    }

    let snapshot = with_kernel(handle, |k| k.snapshot())?;
    let options = variant_extras::options_for(handle);
    let rules = MillRules::new(options.clone());
    let mut legal = ActionList::<256>::default();
    rules.legal_actions(&snapshot, &mut legal);
    let ordering = search::perfect_move_ordering(&plan);

    if make_traps {
        // Same NONE reference / shuffling / seed as the plain branch below,
        // so the trap-aware pick starts from exactly that baseline and only
        // deviates on a strictly higher trap score.
        return Ok(perfect::try_perfect_best_action_trap_aware(
            &snapshot,
            rules.options(),
            legal.as_slice(),
            ordering,
            Action::NONE,
            plan.shuffling,
            search::search_shuffle_seed(),
        )
        .map(TgfAction::from_action));
    }
    Ok(perfect::try_perfect_best_action_with_ref(
        &snapshot,
        rules.options(),
        legal.as_slice(),
        ordering,
        Action::NONE,
        plan.shuffling,
        search::search_shuffle_seed(),
    )
    .map(TgfAction::from_action))
}

/// Export the current Mill kernel state as a FEN string.
#[flutter_rust_bridge::frb(sync)]
pub fn tgf_kernel_export_fen(handle: u32) -> Result<String, String> {
    let options = variant_extras::options_for(handle);
    with_kernel(handle, |kernel| {
        if kernel.game_id() != "mill" {
            return Err("export_fen is only supported for Mill kernels".to_owned());
        }
        let rules = MillRules::new(options);
        let state = tgf_mill::MillRules::decode_snapshot(kernel.snapshot());
        Ok(rules.export_fen(&state))
    })?
}
