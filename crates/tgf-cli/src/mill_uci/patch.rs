// SPDX-License-Identifier: AGPL-3.0-or-later
// Lightweight error-patch runtime for the Mill UCI adapter.
//
// Mirrors the Flutter/FRB "Avoid traps" path: after search (and any
// perfect-database override) the engine may replace its chosen move with the
// patch's safe reply when `patch_avoid_traps` is enabled and a patch file is
// loaded.

use std::sync::{LazyLock, Mutex};

use perfect_db::patch::PatchLookup;
use tgf_core::GameStateSnapshot;
use tgf_mill::{MillRules, MillVariantOptions};
use tgf_search::SearchResult;

use super::board::action_to_uci;

static PATCH: LazyLock<Mutex<PatchState>> = LazyLock::new(|| Mutex::new(PatchState::default()));

#[derive(Default)]
struct PatchState {
    path: Option<String>,
    avoid_traps: bool,
    loaded_path: Option<String>,
    lookup: Option<PatchLookup>,
}

/// Copy the engine configuration into the process-wide patch runtime and
/// reload the patch file when the path changes.
pub(super) fn sync_runtime(path: &Option<String>, avoid_traps: bool) {
    let mut state = PATCH.lock().expect("UCI patch mutex must not be poisoned");
    state.path = path.clone().filter(|path| !path.is_empty());
    state.avoid_traps = avoid_traps;
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

        sync_runtime(&Some(path.to_string_lossy().into_owned()), false);
        {
            let state = PATCH.lock().expect("patch mutex");
            assert!(state.lookup.is_some());
            assert!(!state.avoid_traps);
        }

        sync_runtime(&Some(path.to_string_lossy().into_owned()), true);
        {
            let state = PATCH.lock().expect("patch mutex");
            assert!(state.avoid_traps);
        }
    }
}
