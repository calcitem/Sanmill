// SPDX-License-Identifier: AGPL-3.0-or-later
// Lightweight "error patch" lookup for Mill positions.
//
// Unlike the Perfect Database (`perfect.rs`), the patch file is small
// enough to bundle as a Flutter asset and is fully self-contained (see
// `perfect_db::patch`'s module docs): it never touches the multi-gigabyte
// `.sec2` sector files it was mined from. Two independent runtime
// behaviors consume it:
//   - "Avoid traps": correct the engine/book/human-DB's chosen action when
//     the patch says it throws away value.
//   - "Make traps": among several already-safe candidate replies, prefer
//     the one whose resulting position has the highest trap score.
// Both are opt-in switches (default off) -- see `docs/` for the design.

#[cfg(not(target_arch = "wasm32"))]
use std::sync::Mutex;

#[cfg(not(target_arch = "wasm32"))]
use once_cell::sync::Lazy;
#[cfg(not(target_arch = "wasm32"))]
use tgf_core::GameRules;
use tgf_core::{Action, GameStateSnapshot};
use tgf_mill::MillVariantOptions;
#[cfg(not(target_arch = "wasm32"))]
use tgf_mill::{MillRules, rules::MillState};

#[cfg(not(target_arch = "wasm32"))]
static PATCH: Lazy<Mutex<Option<perfect_db::patch::PatchLookup>>> = Lazy::new(|| Mutex::new(None));

pub(crate) struct PatchStatus {
    pub loaded: bool,
    pub entry_count: u32,
    pub error: String,
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn init_patch_path(path: String) -> bool {
    let bytes = match std::fs::read(&path) {
        Ok(bytes) => bytes,
        Err(e) => {
            *PATCH.lock().expect("FRB patch mutex must not be poisoned") = None;
            let _ = e;
            return false;
        }
    };
    match perfect_db::patch::PatchLookup::open(&bytes) {
        Ok(lookup) => {
            *PATCH.lock().expect("FRB patch mutex must not be poisoned") = Some(lookup);
            true
        }
        Err(_) => {
            *PATCH.lock().expect("FRB patch mutex must not be poisoned") = None;
            false
        }
    }
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn init_patch_path(_path: String) -> bool {
    false
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn patch_status() -> PatchStatus {
    let guard = PATCH.lock().expect("FRB patch mutex must not be poisoned");
    match guard.as_ref() {
        Some(lookup) => PatchStatus {
            loaded: true,
            entry_count: lookup.entry_count() as u32,
            error: String::new(),
        },
        None => PatchStatus {
            loaded: false,
            entry_count: 0,
            error: "no patch loaded".to_owned(),
        },
    }
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn patch_status() -> PatchStatus {
    PatchStatus {
        loaded: false,
        entry_count: 0,
        error: "patch lookup is unavailable on web".to_owned(),
    }
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn deinit_patch() {
    *PATCH.lock().expect("FRB patch mutex must not be poisoned") = None;
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn deinit_patch() {}

/// If the patch has an entry for `snapshot` and `chosen` is not the
/// recorded safe reply, return the legal action that is. `None` when no
/// patch is loaded, the position has no entry, or `chosen` is already safe.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn try_patch_correction(
    snapshot: &GameStateSnapshot,
    options: &MillVariantOptions,
    chosen: Action,
) -> Option<Action> {
    let mut guard = PATCH.lock().expect("FRB patch mutex must not be poisoned");
    let lookup = guard.as_mut()?;
    let rules = MillRules::new(options.clone());
    lookup.correct_action(&rules, options, snapshot, chosen)
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn try_patch_correction(
    _snapshot: &GameStateSnapshot,
    _options: &MillVariantOptions,
    _chosen: Action,
) -> Option<Action> {
    None
}

/// Trap score (0..=255) of the position reached by playing `action` from
/// `snapshot`, or `None` when no patch is loaded or the resulting position
/// has no entry. Used by "make traps" mode to rank candidate replies.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn trap_score_after_action(
    snapshot: &GameStateSnapshot,
    options: &MillVariantOptions,
    action: Action,
) -> Option<u8> {
    let mut guard = PATCH.lock().expect("FRB patch mutex must not be poisoned");
    let lookup = guard.as_mut()?;
    let rules = MillRules::new(options.clone());
    let child = rules.apply(snapshot, action);
    let state: MillState = MillRules::decode_snapshot(child);
    lookup.trap_score_for_state(&state, options)
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn trap_score_after_action(
    _snapshot: &GameStateSnapshot,
    _options: &MillVariantOptions,
    _action: Action,
) -> Option<u8> {
    None
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use perfect_db::patch::{EngineFingerprint, PackAlgorithm, PatchFile};
    use tgf_core::{ActionList, GameRules};

    fn asset_secval() -> Vec<u8> {
        std::fs::read(
            std::path::Path::new(concat!(
                env!("CARGO_MANIFEST_DIR"),
                "/../../src/ui/flutter_app/assets/databases"
            ))
            .join("std.secval"),
        )
        .unwrap()
    }

    fn empty_patch_bytes() -> Vec<u8> {
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
                top_k: 3,
                epsilon: 0.15,
            },
            secval_bytes: asset_secval(),
            sectors: vec![],
            mid_removal_records: vec![],
        };
        let mut buf = Vec::new();
        patch.write_to(&mut buf, 3).unwrap();
        buf
    }

    #[test]
    fn init_status_deinit_round_trip() {
        deinit_patch();
        assert!(!patch_status().loaded);

        let dir = std::env::temp_dir();
        let path = dir.join(format!(
            "sanmill_frb_patch_test_{}.mill_patch",
            std::process::id()
        ));
        std::fs::write(&path, empty_patch_bytes()).unwrap();

        assert!(init_patch_path(path.to_string_lossy().into_owned()));
        let status = patch_status();
        assert!(status.loaded);
        assert_eq!(status.entry_count, 0);

        deinit_patch();
        assert!(!patch_status().loaded);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn correction_and_trap_score_are_none_without_a_loaded_patch() {
        deinit_patch();
        let options = MillVariantOptions::default();
        let rules = MillRules::new(options.clone());
        let snap = rules.initial_state(&[]);
        let mut actions = ActionList::<256>::new();
        rules.legal_actions(&snap, &mut actions);
        let action = actions.as_slice()[0];

        assert_eq!(try_patch_correction(&snap, &options, action), None);
        assert_eq!(trap_score_after_action(&snap, &options, action), None);
    }
}
