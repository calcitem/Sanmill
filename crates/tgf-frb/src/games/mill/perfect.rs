// SPDX-License-Identifier: GPL-3.0-or-later
// Perfect-database lookup for Mill positions.
//
// The native database backend reads database files from the local platform and
// selects std/lask/mora from the active MillVariantOptions. WebAssembly keeps
// Perfect DB unavailable while preserving the public FRB surface.

#[cfg(not(target_arch = "wasm32"))]
use std::sync::Mutex;

#[cfg(not(target_arch = "wasm32"))]
use once_cell::sync::Lazy;
use tgf_core::{Action, GameStateSnapshot};
#[cfg(not(target_arch = "wasm32"))]
use tgf_core::{Game, GameRules};
use tgf_mill::MillVariantOptions;
#[cfg(not(target_arch = "wasm32"))]
use tgf_mill::{MillActionKind, MillGame, MillRules};

#[cfg(not(target_arch = "wasm32"))]
use crate::games::mill::action_codec::action_to_uci_str;
#[cfg(not(target_arch = "wasm32"))]
use crate::games::mill::search::mill_searcher_default;

/// Depth of the heuristic-search fallback used for moves with no perfect
/// database entry.  Mirrors the legacy C++ `runAnalyze` shallow search depth.
#[cfg(not(target_arch = "wasm32"))]
const FALLBACK_SEARCH_DEPTH: i32 = 4;

#[cfg(not(target_arch = "wasm32"))]
static PERFECT_DB_PATH: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn init_database_path(path: String) -> bool {
    let supported = match perfect_db::supported_variants(&path) {
        Ok(supported) => supported,
        Err(_) => return false,
    };
    if supported.is_empty() {
        return false;
    }

    *PERFECT_DB_PATH
        .lock()
        .expect("FRB Perfect DB path mutex must not be poisoned") = Some(path.clone());

    if supported
        .find(perfect_db::database::DatabaseVariant::STANDARD)
        .is_some()
    {
        return perfect_db::init_variant(&path, perfect_db::database::DatabaseVariant::STANDARD);
    }

    perfect_db::deinit();
    true
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn init_database_path(_path: String) -> bool {
    false
}

#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn deinit_database() {
    *PERFECT_DB_PATH
        .lock()
        .expect("FRB Perfect DB path mutex must not be poisoned") = None;
    perfect_db::deinit();
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn deinit_database() {}

#[cfg(not(target_arch = "wasm32"))]
fn ensure_database_for_options(options: &MillVariantOptions) -> bool {
    let Some(variant) = perfect_db::database::DatabaseVariant::from_mill_options(options) else {
        return false;
    };

    if perfect_db::is_initialized() && perfect_db::loaded_variant_rust_database() == Some(variant) {
        return true;
    }

    let Some(path) = PERFECT_DB_PATH
        .lock()
        .expect("FRB Perfect DB path mutex must not be poisoned")
        .clone()
    else {
        return false;
    };

    if perfect_db::is_initialized() {
        perfect_db::deinit();
    }
    perfect_db::init_variant(&path, variant)
}

/// Query the perfect database for a legal action matching the
/// current position.  Returns `None` when the DB is unavailable, the
/// variant has no matching database assets, or no legal action matches the DB
/// token.
///
/// The board-to-bitboard encoding and node-to-perfect-index mapping live in
/// `perfect_db::best_move_token_for_state`; this wrapper only matches the
/// returned token against the caller's legal action list via the shared
/// `tgf_mill::MillUciCodec`.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn try_perfect_best_action(
    snapshot: &tgf_core::GameStateSnapshot,
    options: &MillVariantOptions,
    legal: &[Action],
    ordering: perfect_db::PerfectMoveOrdering,
) -> Option<Action> {
    if !ensure_database_for_options(options) {
        return None;
    }
    let state = MillRules::decode_snapshot(*snapshot);
    let token = perfect_db::best_move_token_for_state_with_ordering(
        &state,
        options,
        snapshot.side_to_move,
        ordering,
    )?;

    legal
        .iter()
        .copied()
        .find(|action| action_to_uci_str(*action) == token)
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn try_perfect_best_action(
    _snapshot: &GameStateSnapshot,
    _options: &MillVariantOptions,
    _legal: &[Action],
    _ordering: perfect_db::PerfectMoveOrdering,
) -> Option<Action> {
    None
}

/// Verdict for a single analysed move, expressed from the perspective of the
/// side that is to move in the position being analysed.
pub(crate) struct MoveEval {
    /// Mill UCI notation token for the move (`"a4"`, `"a1-a4"`, `"xg7"`).
    pub mv: String,
    /// `"win"` / `"draw"` / `"loss"` (perfect database) or
    /// `"advantage"` / `"disadvantage"` (heuristic-search fallback).
    pub outcome: &'static str,
    /// Win/draw/loss value (1 / 0 / -1) for database verdicts, or the raw
    /// heuristic score for the fallback, from the analysing side's view.
    pub value: i32,
    /// Distance-to-conversion step count, or a negative value when the
    /// database does not expose one (always negative for the fallback).
    pub steps: i32,
}

/// Full analysis result: one verdict per legal move plus the detected trap
/// moves (empty unless trap detection ran and found any).
pub(crate) struct AnalysisReport {
    pub moves: Vec<MoveEval>,
    pub traps: Vec<String>,
}

/// Per-move working data retained for trap detection.  Only moves with a
/// definitive perfect-database verdict participate, matching the legacy C++
/// behaviour where trap awareness is gated on the database.
#[cfg(not(target_arch = "wasm32"))]
struct TrapCandidate {
    token: String,
    to: usize,
    from: Option<usize>,
    /// Database value from the analysing side's view (1 / 0 / -1).
    value: i32,
}

/// Analyse every legal move in `snapshot`.
///
/// Each move is applied and the resulting position is evaluated: first against
/// the perfect database (win/draw/loss + step count), and — when the database
/// has no entry — with a shallow heuristic search (advantage/disadvantage).
/// All verdicts are converted back to the perspective of the side to move in
/// `snapshot` (mirroring the legacy C++ `runAnalyze`: an evaluation relative to
/// the side to move *after* the move is negated once whenever the move flips
/// the side to move).
///
/// When `trap_awareness` is set, aggressive moves (those that complete or block
/// a mill) whose database verdict is worse than an available alternative are
/// reported as traps.
#[cfg(not(target_arch = "wasm32"))]
pub(crate) fn analyze_position(
    snapshot: &GameStateSnapshot,
    options: &MillVariantOptions,
    trap_awareness: bool,
) -> AnalysisReport {
    let database_available = ensure_database_for_options(options);
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());
    let root_side = snapshot.side_to_move;

    let mut legal = tgf_core::ActionList::<256>::default();
    rules.legal_actions(snapshot, &mut legal);

    let mut moves = Vec::new();
    let mut trap_candidates: Vec<TrapCandidate> = Vec::new();
    let mut has_win = false;
    let mut has_draw = false;
    let mut has_loss = false;

    for action in legal.as_slice().iter().copied() {
        let next = rules.apply(snapshot, action);
        let token = action_to_uci_str(action);
        let next_state = MillRules::decode_snapshot(next);

        if database_available
            && let Some((wdl, steps)) =
                perfect_db::evaluate_state_for(&next_state, options, next.side_to_move)
        {
            // Convert the database value to the analysing side's perspective.
            let value = if next.side_to_move != root_side {
                -wdl
            } else {
                wdl
            };
            let outcome = match value {
                v if v > 0 => {
                    has_win = true;
                    "win"
                }
                v if v < 0 => {
                    has_loss = true;
                    "loss"
                }
                _ => {
                    has_draw = true;
                    "draw"
                }
            };

            if let Some(to) = node_in_range(action.to_node) {
                let from = if action.kind_tag == MillActionKind::Move as i16 {
                    node_in_range(action.from_node)
                } else {
                    None
                };
                trap_candidates.push(TrapCandidate {
                    token: token.clone(),
                    to,
                    from,
                    value,
                });
            }

            moves.push(MoveEval {
                mv: token,
                outcome,
                value,
                steps,
            });
        } else {
            // No database entry: fall back to a shallow heuristic search, as
            // the legacy C++ `runAnalyze` did for positions outside the DB.
            let mut wb = game.build_workbench(&next);
            let mut searcher = mill_searcher_default();
            let result = searcher.search(&mut wb, FALLBACK_SEARCH_DEPTH);
            let score = if next.side_to_move != root_side {
                -result.score
            } else {
                result.score
            };
            moves.push(MoveEval {
                mv: token,
                outcome: if score >= 0 {
                    "advantage"
                } else {
                    "disadvantage"
                },
                value: score,
                steps: -1,
            });
        }
    }

    let traps = if trap_awareness {
        detect_traps(
            &rules,
            snapshot,
            root_side,
            &trap_candidates,
            (has_win, has_draw, has_loss),
        )
    } else {
        Vec::new()
    };

    AnalysisReport { moves, traps }
}

#[cfg(target_arch = "wasm32")]
pub(crate) fn analyze_position(
    _snapshot: &GameStateSnapshot,
    _options: &MillVariantOptions,
    _trap_awareness: bool,
) -> AnalysisReport {
    AnalysisReport {
        moves: Vec::new(),
        traps: Vec::new(),
    }
}

/// Detect trap moves among `candidates` (perfect-database-backed moves).
///
/// Mirrors the legacy C++ `runAnalyze` trap pass: skip detection entirely when
/// every move shares the same verdict (all draws or all losses), then flag any
/// aggressive move (one completing or blocking a mill) whose verdict is worse
/// than an available alternative.
#[cfg(not(target_arch = "wasm32"))]
fn detect_traps(
    rules: &MillRules,
    snapshot: &GameStateSnapshot,
    root_side: i8,
    candidates: &[TrapCandidate],
    verdicts: (bool, bool, bool),
) -> Vec<String> {
    let (has_win, has_draw, has_loss) = verdicts;
    let all_draw = !has_win && has_draw && !has_loss;
    let all_loss = !has_win && has_loss && !has_draw;
    if all_draw || all_loss || !(0..2).contains(&root_side) {
        return Vec::new();
    }

    let opponent = 1 - root_side;
    let state = MillRules::decode_snapshot(*snapshot);

    let mut traps = Vec::new();
    for candidate in candidates {
        let our_mills =
            rules.potential_mills_count(&state, candidate.to, root_side, candidate.from);
        let their_mills =
            rules.potential_mills_count(&state, candidate.to, opponent, candidate.from);
        let aggressive = our_mills > 0 || their_mills > 0;
        if !aggressive {
            continue;
        }
        // Worse choice: a loss while a win or draw exists, or a draw while a
        // win exists.
        let worse =
            (candidate.value < 0 && (has_win || has_draw)) || (candidate.value == 0 && has_win);
        if worse {
            traps.push(candidate.token.clone());
        }
    }
    traps
}

/// Convert an action node field to a board index, or `None` when out of range.
#[cfg(not(target_arch = "wasm32"))]
fn node_in_range(node: i16) -> Option<usize> {
    if (0..24).contains(&node) {
        Some(node as usize)
    } else {
        None
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::{LazyLock, Mutex, MutexGuard};
    use std::time::{SystemTime, UNIX_EPOCH};
    use tgf_core::BoardTopology;
    use tgf_mill::{MillPhase, default_mill_topology};

    fn db_path() -> &'static str {
        concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../src/ui/flutter_app/assets/databases"
        )
    }

    fn perfect_db_test_lock() -> MutexGuard<'static, ()> {
        static LOCK: LazyLock<Mutex<()>> = LazyLock::new(|| Mutex::new(()));
        LOCK.lock()
            .expect("FRB Perfect DB test lock must not be poisoned")
    }

    fn set_piece_by_label(state: &mut tgf_mill::rules::MillState, label: &str, owner: i8) {
        let topo = default_mill_topology();
        let node = topo
            .node_from_label(label)
            .unwrap_or_else(|| panic!("missing node label {label}"));
        state.set_piece(node, owner);
    }

    fn endgame_moving_snapshot(
        rules: &MillRules,
        options: &MillVariantOptions,
    ) -> GameStateSnapshot {
        let mut state = rules.setup_empty();
        for label in ["a4", "d7", "g1"] {
            set_piece_by_label(&mut state, label, 1);
        }
        for label in ["g7", "d1", "b4"] {
            set_piece_by_label(&mut state, label, 2);
        }
        state.recompute_aux(options);
        state.set_pieces_in_hand([0, 0], options);
        state.set_phase(MillPhase::Moving);
        state.set_side_to_move(0);
        rules.encode_state(state)
    }

    fn morabaraba_options() -> MillVariantOptions {
        MillVariantOptions {
            piece_count: 12,
            has_diagonal_lines: true,
            ..MillVariantOptions::default()
        }
    }

    fn lasker_options() -> MillVariantOptions {
        MillVariantOptions {
            piece_count: 10,
            may_move_in_placing_phase: true,
            ..MillVariantOptions::default()
        }
    }

    fn write_lasker_only_database() -> PathBuf {
        let unique = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock must be after UNIX_EPOCH")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "sanmill-frb-lasker-perfect-db-{}-{unique}",
            std::process::id()
        ));
        fs::create_dir(&path).expect("temporary Lasker DB directory must be created");
        fs::write(
            path.join("lask.secval"),
            "virt_loss_val: -1\nvirt_win_val: 1\n2\n0 0 10 10 0\n0 1 10 9 0\n",
        )
        .expect("temporary Lasker secval must be written");
        path
    }

    #[test]
    fn perfect_best_action_uses_rust_database_for_endgame_moving_sector() {
        let _guard = perfect_db_test_lock();
        deinit_database();
        assert!(perfect_db::init(db_path()));

        let rules = MillRules::default();
        let options = MillVariantOptions::default();
        let snapshot = endgame_moving_snapshot(&rules, &options);
        let mut legal = tgf_core::ActionList::<256>::default();
        rules.legal_actions(&snapshot, &mut legal);

        let action = try_perfect_best_action(
            &snapshot,
            &options,
            legal.as_slice(),
            perfect_db::PerfectMoveOrdering::LegacyWdl,
        )
        .expect("covered endgame moving sector must return a perfect action");
        assert!(legal.as_slice().contains(&action));
        assert!(tgf_mill::MillUciCodec::encode_action(action).contains('-'));

        deinit_database();
    }

    #[test]
    fn perfect_best_action_returns_none_when_rust_database_sector_is_missing() {
        let _guard = perfect_db_test_lock();
        deinit_database();
        assert!(perfect_db::init(db_path()));

        let rules = MillRules::default();
        let options = MillVariantOptions::default();
        let snapshot = rules.no_mill_moving_phase_snapshot();
        let mut legal = tgf_core::ActionList::<256>::default();
        rules.legal_actions(&snapshot, &mut legal);

        assert!(
            try_perfect_best_action(
                &snapshot,
                &options,
                legal.as_slice(),
                perfect_db::PerfectMoveOrdering::LegacyWdl,
            )
            .is_none()
        );

        deinit_database();
    }

    #[test]
    fn perfect_best_action_syncs_morabaraba_database_from_saved_path() {
        let _guard = perfect_db_test_lock();
        deinit_database();
        assert!(init_database_path(db_path().to_owned()));
        assert_eq!(
            perfect_db::loaded_variant_rust_database(),
            Some(perfect_db::database::DatabaseVariant::STANDARD)
        );

        let options = morabaraba_options();
        let rules = MillRules::new(options.clone());
        let snapshot = rules.initial_state(&[]);
        let mut legal = tgf_core::ActionList::<256>::default();
        rules.legal_actions(&snapshot, &mut legal);

        let action = try_perfect_best_action(
            &snapshot,
            &options,
            legal.as_slice(),
            perfect_db::PerfectMoveOrdering::LegacyWdl,
        )
        .expect("covered Morabaraba opening sector must return a perfect action");
        assert!(legal.as_slice().contains(&action));
        assert_eq!(
            perfect_db::loaded_variant_rust_database(),
            Some(perfect_db::database::DatabaseVariant::MORABARABA)
        );

        deinit_database();
    }

    #[test]
    fn perfect_best_action_syncs_lasker_database_from_saved_path() {
        let _guard = perfect_db_test_lock();
        let path = write_lasker_only_database();
        deinit_database();
        assert!(init_database_path(path.display().to_string()));
        assert_eq!(perfect_db::loaded_variant_rust_database(), None);

        let options = lasker_options();
        let rules = MillRules::new(options.clone());
        let snapshot = rules.initial_state(&[]);
        let mut legal = tgf_core::ActionList::<256>::default();
        rules.legal_actions(&snapshot, &mut legal);

        assert!(
            try_perfect_best_action(
                &snapshot,
                &options,
                legal.as_slice(),
                perfect_db::PerfectMoveOrdering::LegacyWdl,
            )
            .is_none()
        );
        assert_eq!(
            perfect_db::loaded_variant_rust_database(),
            Some(perfect_db::database::DatabaseVariant::LASKER)
        );

        deinit_database();
        fs::remove_dir_all(path).expect("temporary Lasker DB directory must be removable");
    }
}
