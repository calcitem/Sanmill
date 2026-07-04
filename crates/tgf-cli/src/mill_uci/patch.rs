// SPDX-License-Identifier: AGPL-3.0-or-later
// Lightweight error-patch runtime for the Mill UCI adapter.
//
// Mirrors the Flutter/FRB "Avoid traps" path: after search (and any
// perfect-database override) the engine may replace its chosen move with the
// patch's safe reply when `patch_avoid_traps` is enabled and a patch file is
// loaded.

use std::sync::{LazyLock, Mutex};

use perfect_db::patch::PatchLookup;
use tgf_core::{Action, GameStateSnapshot};
use tgf_mill::{MillRules, MillVariantOptions};
use tgf_search::SearchResult;

use super::board::action_to_uci;

static PATCH: LazyLock<Mutex<PatchState>> = LazyLock::new(|| Mutex::new(PatchState::default()));

/// The most recent `position` command line, kept verbatim so trace rows
/// can be joined offline against a harness's per-game move list (the
/// moves token sequence is the join key; no rules replay needed).
static POSITION_CONTEXT: LazyLock<Mutex<String>> = LazyLock::new(|| Mutex::new(String::new()));

/// Record the raw `position ...` command for trace attribution.
pub(super) fn set_position_context(line: &str) {
    let mut context = POSITION_CONTEXT
        .lock()
        .expect("position context mutex must not be poisoned");
    line.clone_into(&mut context);
}

#[derive(Default)]
struct PatchState {
    path: Option<String>,
    avoid_traps: bool,
    make_traps: bool,
    loaded_path: Option<String>,
    lookup: Option<PatchLookup>,
}

/// Copy the engine configuration into the process-wide patch runtime and
/// reload the patch file when the path changes.
pub(super) fn sync_runtime(path: &Option<String>, avoid_traps: bool, make_traps: bool) {
    let mut state = PATCH.lock().expect("UCI patch mutex must not be poisoned");
    state.path = path.clone().filter(|path| !path.is_empty());
    state.avoid_traps = avoid_traps;
    state.make_traps = make_traps;
    reload_if_needed(&mut state);
}

pub(super) fn apply_patch_avoid_traps_result(
    result: &mut SearchResult,
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
) {
    let mut patch = PATCH.lock().expect("UCI patch mutex must not be poisoned");
    if !patch.avoid_traps || result.best_action.is_none() {
        return;
    }
    let Some(lookup) = patch.lookup.as_mut() else {
        return;
    };
    let rules = MillRules::new(options.clone());
    let Some(corrected) = lookup.correct_action(&rules, options, state, result.best_action) else {
        return;
    };
    let same = action_to_uci(result.best_action).as_deref() == action_to_uci(corrected).as_deref();
    if !same {
        result.best_action = corrected;
        println!("info string aimovetype=patch");
    }
}

/// Trap score (0..=255) of the position reached by playing `action` from
/// `state`, or `None` when no patch is loaded. Thin lock wrapper around
/// [`PatchLookup::trap_score_after_action`] -- the v4 unified entry point
/// (same-side filter, parent nibbles, child-entry fallback) -- used by the
/// "make traps" perfect-database tie-break to rank candidate replies.
pub(super) fn trap_score_after_action(
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
    action: Action,
) -> Option<u8> {
    let mut patch = PATCH.lock().expect("UCI patch mutex must not be poisoned");
    let lookup = patch.lookup.as_mut()?;
    let rules = MillRules::new(options.clone());
    lookup.trap_score_after_action(&rules, options, state, action)
}

/// Database-free "make traps" (see `PatchLookup::trap_aware_action`): when
/// enabled and the current position has a patch entry, replace a proven
/// value-preserving best move with the proven sibling whose resulting
/// position carries a strictly higher trap score. The perfect-database
/// tie-break variant supersedes this at the call site when the DB is on.
///
/// The baseline in the emitted trace is exactly `result.best_action` as it
/// stands here -- the move this engine WOULD have played with make-traps
/// off (search result plus any avoid-traps correction), not a re-search
/// approximation.
pub(super) fn apply_patch_make_traps_result(
    result: &mut SearchResult,
    options: &MillVariantOptions,
    state: &GameStateSnapshot,
) {
    let mut patch = PATCH.lock().expect("UCI patch mutex must not be poisoned");
    if !patch.make_traps || result.best_action.is_none() {
        return;
    }
    let Some(lookup) = patch.lookup.as_mut() else {
        return;
    };
    let rules = MillRules::new(options.clone());
    let baseline = result.best_action;
    if let Some(better) = lookup.trap_aware_action(&rules, options, state, baseline) {
        let detail = lookup.last_switch_detail();
        result.best_action = better;
        println!("info string aimovetype=patchtrap");
        trace_switch(&rules, state, baseline, better, detail);
    }
}

/// `TGF_PATCH_TRACE_DIR`: when set, every database-free make-traps switch
/// appends one JSONL row to `<dir>/patchtrap_<pid>.jsonl` (one file per
/// engine process, so parallel H2H workers never interleave writes). The
/// row carries the structural fields; DB value verification is done
/// offline against the strong database by the trace verifier, which keeps
/// the engine free of any external-database dependency.
fn trace_switch(
    rules: &MillRules,
    state: &GameStateSnapshot,
    baseline: tgf_core::Action,
    steering: tgf_core::Action,
    detail: Option<perfect_db::patch::TrapSwitchDetail>,
) {
    static TRACE_DIR: LazyLock<Option<String>> = LazyLock::new(|| {
        std::env::var("TGF_PATCH_TRACE_DIR")
            .ok()
            .filter(|dir| !dir.trim().is_empty())
    });
    let Some(dir) = TRACE_DIR.as_ref() else {
        return;
    };
    let detail = detail.expect("a switch must have recorded its detail");
    let mill_state = MillRules::decode_snapshot(*state);
    let fen = rules.export_fen(&mill_state);
    let position_context = POSITION_CONTEXT
        .lock()
        .expect("position context mutex must not be poisoned")
        .clone();
    // Ply from the position command's move list (the harness drives every
    // search with `position startpos moves ...`).
    let ply = position_context
        .split_once(" moves ")
        .map(|(_, moves)| moves.split_whitespace().count())
        .unwrap_or(0);
    let row = serde_json::json!({
        "parent_fen": fen,
        "side_to_move": state.side_to_move,
        "ply": ply,
        "parent_key": detail.parent_key,
        "baseline_action": action_to_uci(baseline),
        "steering_action": action_to_uci(steering),
        "baseline_nibble": detail.baseline_nibble,
        "steering_nibble": detail.steering_nibble,
        "position_moves": position_context.split_once(" moves ").map(|(_, m)| m).unwrap_or(""),
    });
    let path = std::path::Path::new(dir).join(format!("patchtrap_{}.jsonl", std::process::id()));
    if let Ok(mut file) = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        use std::io::Write;
        let _ = writeln!(file, "{row}");
    }
}

fn reload_if_needed(state: &mut PatchState) {
    let Some(path) = state.path.as_ref() else {
        state.loaded_path = None;
        state.lookup = None;
        return;
    };
    if state.loaded_path.as_deref() == Some(path.as_str()) && state.lookup.is_some() {
        return;
    }
    let bytes = match std::fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) => {
            state.loaded_path = None;
            state.lookup = None;
            println!("info string patch load failed: {error}");
            return;
        }
    };
    match PatchLookup::open(&bytes) {
        Ok(lookup) => {
            let entry_count = lookup.entry_count();
            state.loaded_path = Some(path.clone());
            state.lookup = Some(lookup);
            println!("info string patch loaded entries={entry_count}");
        }
        Err(error) => {
            state.loaded_path = None;
            state.lookup = None;
            println!("info string patch parse failed: {error}");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use perfect_db::patch::{EngineFingerprint, PackAlgorithm, PatchFile};

    fn empty_patch_bytes() -> Vec<u8> {
        let secval_bytes = std::fs::read(
            std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
                .join("../../src/ui/flutter_app/assets/databases/std.secval"),
        )
        .expect("bundled std.secval for patch tests");
        let patch = PatchFile {
            variant_byte: 0,
            fingerprint: EngineFingerprint {
                algorithm: PackAlgorithm::Mtdf,
                skill_level: 30,
                depth_override: 0,
                near_optimal_margin: 0,
                consider_mobility: true,
                focus_on_blocking_paths: false,
                draw_on_human_experience: true,
                ai_is_lazy: false,
                top_k: 1,
                epsilon: 0.0,
            },
            secval_bytes,
            sectors: Vec::new(),
            mid_removal_records: Vec::new(),
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        buf
    }

    #[test]
    fn patch_path_loads_and_avoid_traps_stays_off_by_default() {
        let dir =
            std::env::temp_dir().join(format!("sanmill_uci_patch_test_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("empty.mill_patch");
        std::fs::write(&path, empty_patch_bytes()).unwrap();

        {
            let mut state = PATCH.lock().expect("patch mutex");
            *state = PatchState::default();
        }

        sync_runtime(&Some(path.to_string_lossy().into_owned()), false, false);
        {
            let state = PATCH.lock().expect("patch mutex");
            assert!(state.lookup.is_some());
            assert!(!state.avoid_traps);
            assert!(!state.make_traps);
        }

        sync_runtime(&Some(path.to_string_lossy().into_owned()), true, true);
        {
            let state = PATCH.lock().expect("patch mutex");
            assert!(state.avoid_traps);
            assert!(state.make_traps);
        }
    }
}
