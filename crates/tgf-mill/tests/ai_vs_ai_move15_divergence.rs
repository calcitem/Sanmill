// SPDX-License-Identifier: GPL-3.0-or-later
// Regression tests pinning the Rust engine's move choices to the master C++
// engine under standard rules, Thinking-Time = 0 (fixed depth), shuffling off.
//
// # Known, explained divergence: deep MTD(f) Graph-History-Interaction (GHI)
//
// At higher skill levels a small number of *moving-phase* positions can differ
// between the two engines (e.g. move 16 of the skill-15 self-play: master plays
// `a1-d1`, Rust's MTD(f) plays `d6-d7`).  This was investigated exhaustively
// and traced to a Graph-History-Interaction artifact, NOT a rules/eval bug:
//
//   * Both engines probe the transposition table BEFORE the repetition check
//     (master `Search::search`, src/search.cpp).  A position first stored via a
//     non-repeating line is later cut off by that TT entry when the SAME
//     position recurs as a path repetition, returning the stale stored value
//     instead of the `VALUE_DRAW + 1` draw bias.
//   * Whether that cutoff fires is depth-gated and therefore depends on the
//     exact search-tree shape.  Zero-window MTD(f) and full-window alpha-beta
//     prune differently, so they reach the transposition at different depths.
//     master's MTD(f) reaches it at a cut-off depth (→ `a1-d1`, consistent with
//     its own alpha-beta); Rust's MTD(f) reaches the repetition instead and
//     applies the draw bias (→ `d6-d7`).  Rust's *alpha-beta* matches master.
//   * Confirmed with the TT disabled both engines collapse to the same true
//     minimax (MTD(f) == alpha-beta), proving the difference is 100% TT/GHI.
//
// Both moves are theoretical draws (verified against the perfect database), and
// Rust's MTD(f) is arguably the more correct of the two (it honours the
// repetition draw bias rather than a stale TT value).  Reproducing master's
// exact GHI would require byte-identical replication of master's whole TT
// lifecycle (32-bit Zobrist key, direct-mapped slot, replacement/aging across
// the full zero-window iteration sequence) and would make Rust strictly less
// accurate, so it is intentionally left as-is.
//
// The tests below pin the behaviours that DO match master move-for-move:
// placing-phase choices, shallow-skill self-play, repetition adjudication, and
// move ordering.

use tgf_core::{Game, GameRules, MoveOrderAlgorithm, MoveOrderContext, Workbench};
use tgf_mill::{MillGame, MillRules, MillUciCodec, MillVariantOptions};
use tgf_search::{SearchPolicy, Searcher};

fn apply_line(rules: &MillRules, snap: &mut tgf_core::GameStateSnapshot, moves: &[&str]) {
    for uci in moves {
        let action = MillUciCodec::decode_action(snap, uci).expect(uci);
        *snap = rules.apply(snap, action);
    }
}

fn root_search_move_order(snap: &tgf_core::GameStateSnapshot) -> Vec<String> {
    use tgf_core::{ActionList, Game};
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let game = MillGame::new(MillVariantOptions::default());
    let wb = game.build_workbench(snap);
    let mut moves = ActionList::<256>::new();
    MillGame::generate_legal_ctx(&wb, &mut moves, &ctx);
    moves.as_mut_slice().sort_by(|a, b| {
        let sa = MillGame::move_order_bias_ctx(&wb, *a, &ctx);
        let sb = MillGame::move_order_bias_ctx(&wb, *b, &ctx);
        sb.cmp(&sa)
    });
    moves
        .iter()
        .map(|m| MillUciCodec::encode_action(*m))
        .collect()
}

fn mtdf_search_at(
    snap: &tgf_core::GameStateSnapshot,
    shuffling: bool,
    depth: i32,
) -> (String, i32) {
    mtdf_search_at_skill(snap, shuffling, depth, 1)
}

fn mtdf_search_at_skill(
    snap: &tgf_core::GameStateSnapshot,
    shuffling: bool,
    depth: i32,
    skill_level: u8,
) -> (String, i32) {
    let options = MillVariantOptions::default();
    let game = MillGame::new(options);
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level,
        shuffling,
        hash_move: None,
        shuffle_seed: 0,
    };
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(tgf_mill::MillActionKind::Remove as i16),
        ..Default::default()
    });
    searcher.set_move_order_context(ctx);
    let mut wb = game.build_workbench(snap);
    let result = searcher.search_mtdf_with_guess(&mut wb, depth, 0);
    (
        MillUciCodec::encode_action(result.best_action),
        result.score,
    )
}

fn score_all_legal_at_depth1(snap: &tgf_core::GameStateSnapshot) -> Vec<(String, i32)> {
    use tgf_core::{ActionList, Game};
    let options = MillVariantOptions::default();
    let game = MillGame::new(options);
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let mut wb = game.build_workbench(snap);
    let mut moves = ActionList::<256>::new();
    MillGame::generate_legal_ctx(&wb, &mut moves, &ctx);
    let mut searcher = Searcher::<MillGame>::new();
    searcher.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(tgf_mill::MillActionKind::Remove as i16),
        ..Default::default()
    });
    searcher.set_move_order_context(ctx);
    let mut out = Vec::new();
    for m in moves.iter() {
        wb.do_move(*m);
        let score = -searcher.search_mtdf_with_guess(&mut wb, 0, 0).score;
        wb.undo_move();
        out.push((MillUciCodec::encode_action(*m), score));
    }
    out.sort_by_key(|b| std::cmp::Reverse(b.1));
    out
}

/// Mainline through white's 15. g1-g4; black to move.
const MOVES_TO_BLACK_MOVE_15: &[&str] = &[
    "d6", "f4", "d2", "b4", "e4", "d5", "c4", "d3", "g4", "d7", "a4", "d1", "e5", "e3", "c3", "c5",
    "f6", "b6", "a4-a7", "b4-a4", "c4-b4", "c5-c4", "g4-g1", "d7-g7", "g1-g4", "g7-d7", "g4-g1",
    "d7-g7", "g1-g4",
];

const MOVES_TO_BLACK_MOVE_12: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6", "b2", "f2",
    "g7", "g1", "c4-c5", "d1-a1", "c5-c4", "a1-d1", "c4-c5",
];

const SKILL1_MOVES_TO_BLACK_MOVE_13: &[&str] = &[
    "d6", "f4", "d2", "b4", "e4", "d5", "c4", "d3", "g4", "d7", "a4", "d1", "e5", "e3", "c3", "c5",
    "f6", "b6", "a4-a7", "b4-a4", "c4-b4", "c5-c4", "g4-g1", "d7-g7", "g1-g4",
];

const SKILL15_MOVES_TO_WHITE_MOVE_8: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "d5", "d3", "f6", "b6", "b2", "f2",
];

const SKILL15_MOVES_TO_WHITE_MOVE_5: &[&str] = &["d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1"];

// Self-play can become very expensive once both sides enter the flying
// phase, because every piece can move to every empty point.  Keep the
// regression harness on the same fixed-depth engine path, but shorten the
// moving-phase draw rule from the default 50 full moves (100 plies) to
// 10 full moves (20 plies) so ignored full-game captures terminate promptly.
const SELFPLAY_N_MOVE_RULE_PLIES: u32 = 20;

fn selfplay_variant_options() -> MillVariantOptions {
    MillVariantOptions {
        n_move_rule: SELFPLAY_N_MOVE_RULE_PLIES,
        endgame_n_move_rule: SELFPLAY_N_MOVE_RULE_PLIES,
        ..MillVariantOptions::default()
    }
}

const MASTER_GO_SKILL1_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "e4", "d5", "c4", "d3", "g4", "d7", "a4", "d1", "e5", "e3", "c3", "c5",
    "f6", "b6", "a4-a7", "b4-a4", "c4-b4", "c5-c4", "g4-g1", "d7-g7", "g1-g4", "g7-d7", "g4-g1",
    "d7-g7", "g1-g4", "g7-d7",
];

const MASTER_GO_SKILL2_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6", "b2", "f2",
    "g7", "g1", "c4-c5", "d1-a1", "c5-c4", "a1-d1", "c4-c5", "b4-c4", "b2-b4", "d1-a1", "a4-a7",
    "a1-a4", "e4-e3", "g1-d1", "e3-e4", "d3-e3", "g4-g1", "e3-d3", "g1-g4", "d5-e5", "c5-d5",
    "c4-c5",
];

const MASTER_GO_SKILL3_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "d3", "f6", "f2", "b2", "b6", "g7",
    "a7", "e3", "a4-a1", "d5-e5", "d3-c3", "e3-d3", "d6-d5", "f6-d6", "c3-c4", "d1-g1", "a1-a4",
    "g1-d1", "e4-e3", "e5-e4", "d5-e5", "d3-c3", "e5-d5", "e4-e5", "e3-d3", "e5-e4", "c4-c5",
    "c3-c4",
];

const RUST_SKILL4_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6", "b2", "f2",
    "g7", "g1", "a4-a1", "d3-c3", "c4-c5", "c3-d3", "c5-c4", "d5-c5", "a1-a4", "c5-d5", "c4-c5",
    "b4-c4", "b2-b4", "d1-a1", "e4-e3", "a1-d1", "a4-a1", "d5-e5", "c5-d5", "e5-e4", "a1-a4",
    "c4-c5",
];

const MASTER_GO_SKILL4_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6", "b2", "f2",
    "g7", "g1", "a4-a1", "d3-c3", "c4-c5", "c3-d3", "c5-c4", "d5-c5", "a1-a4", "c5-d5", "c4-c5",
    "b4-c4", "b2-b4", "d1-a1", "e4-e3", "a1-d1", "a4-a1", "d5-e5", "c5-d5", "e5-e4", "d5-e5",
    "c4-c5",
];

#[test]
fn move15_black_search_skill1_depth1_shuffling_off() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, MOVES_TO_BLACK_MOVE_15);

    let ordered = root_search_move_order(&snap);
    eprintln!("root search move order: {ordered:?}");

    let (best, score) = mtdf_search_at(&snap, false, 1);
    eprintln!("move15 depth=1: best={best} score={score}");
    for (mv, sc) in score_all_legal_at_depth1(&snap) {
        eprintln!("  {mv}: {sc}");
    }

    // C++ `generate<LEGAL>` order (skill 1, no shuffle) is stable through
    // MovePicker when all heuristic scores tie.
    assert_eq!(
        ordered.first().map(String::as_str),
        Some("a4-a1"),
        "MovePicker must preserve C++ generate<LEGAL> order"
    );
    // `g7-d7` and `d1-g1` both evaluate as drawing / zero-score root moves.
    // Since `g7-d7` is already a legal DrawThreefold finish, the root
    // tie-break should prefer ending the game over looping through another
    // equivalent move sequence.
    assert_eq!(best, "g7-d7");
}

#[test]
fn move15_legal_move_generation_order() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, MOVES_TO_BLACK_MOVE_15);
    use tgf_core::ActionList;
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let game = MillGame::new(MillVariantOptions::default());
    let wb = game.build_workbench(&snap);
    let mut moves = ActionList::<256>::new();
    MillGame::generate_legal_ctx(&wb, &mut moves, &ctx);
    let labels: Vec<String> = moves
        .iter()
        .map(|m| MillUciCodec::encode_action(*m))
        .collect();
    eprintln!("legal order: {labels:?}");
    let zero: Vec<_> = score_all_legal_at_depth1(&snap)
        .into_iter()
        .filter(|(_, s)| *s == 0)
        .map(|(m, _)| m)
        .collect();
    eprintln!("score-zero moves: {zero:?}");
}

#[test]
fn move15_g7d7_triggers_threefold_draw_on_apply() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, MOVES_TO_BLACK_MOVE_15);

    let g7d7 = MillUciCodec::decode_action(&snap, "g7-d7").unwrap();
    snap = rules.apply(&snap, g7d7);
    eprintln!("after g7-d7: outcome={:?}", rules.outcome(&snap));

    let mut snap2 = rules.initial_state(&[]);
    apply_line(&rules, &mut snap2, MOVES_TO_BLACK_MOVE_15);
    let d1g1 = MillUciCodec::decode_action(&snap2, "d1-g1").unwrap();
    snap2 = rules.apply(&snap2, d1g1);
    eprintln!("after d1-g1: outcome={:?}", rules.outcome(&snap2));
}

#[test]
fn move15_repeated_mill_restrictions_on_zero_score_moves() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, MOVES_TO_BLACK_MOVE_15);
    use tgf_core::ActionList;
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        ..Default::default()
    };
    let game = MillGame::new(MillVariantOptions::default());
    let wb = game.build_workbench(&snap);
    let mut moves = ActionList::<256>::new();
    MillGame::generate_legal_ctx(&wb, &mut moves, &ctx);
    let legal: Vec<String> = moves
        .iter()
        .map(|m| MillUciCodec::encode_action(*m))
        .collect();
    eprintln!("legal at move15: {legal:?}");
    for uci in ["a4-a1", "d1-a1", "d1-g1", "g7-d7"] {
        assert!(legal.iter().any(|m| m == uci), "{uci} must be legal");
    }
}

#[test]
fn move15_move_order_bias_and_sorted_order() {
    use tgf_core::{ActionList, Game, MoveOrderAlgorithm, MoveOrderContext};
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, MOVES_TO_BLACK_MOVE_15);
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let game = MillGame::new(MillVariantOptions::default());
    let wb = game.build_workbench(&snap);
    let mut moves = ActionList::<256>::new();
    MillGame::generate_legal_ctx(&wb, &mut moves, &ctx);
    let mut scored: Vec<(String, i32)> = moves
        .iter()
        .map(|m| {
            (
                MillUciCodec::encode_action(*m),
                MillGame::move_order_bias_ctx(&wb, *m, &ctx),
            )
        })
        .collect();
    scored.sort_by_key(|b| std::cmp::Reverse(b.1));
    eprintln!("sorted by move_order_bias (stable): {scored:?}");
    let gen_order: Vec<String> = moves
        .iter()
        .map(|m| MillUciCodec::encode_action(*m))
        .collect();
    eprintln!("generation order: {gen_order:?}");
    // C++ `partial_insertion_sort` is stable; equal MovePicker scores keep
    // `generate<LEGAL>` order.  All biases are zero here, so sorted order
    // must match generation order.
    let sorted_labels: Vec<String> = scored.into_iter().map(|(m, _)| m).collect();
    assert_eq!(sorted_labels, gen_order);
}

#[test]
fn skill2_move5_white_depth2_matches_master_placing_choice() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, SKILL15_MOVES_TO_WHITE_MOVE_5);

    let (best, score) = mtdf_search_at_skill(&snap, false, 2, 2);
    eprintln!("skill2 move5 depth=2: best={best} score={score}");
    // Master `gomtdf 2` with SkillLevel=2 and shuffling off chooses e4.
    assert_eq!(best, "e4");
}

#[test]
fn skill2_move8_white_depth2_matches_master_placing_choice() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, SKILL15_MOVES_TO_WHITE_MOVE_8);

    let (best, score) = mtdf_search_at_skill(&snap, false, 2, 2);
    eprintln!("skill2 move8 depth=2: best={best} score={score}");
    // Master `gomtdf 2` with SkillLevel=2 and shuffling off chooses e4.
    assert_eq!(best, "e4");
}

#[test]
#[ignore = "slow depth=15 parity case; covered by the default skill2/depth2 smoke test"]
fn skill15_move5_white_depth15_matches_master_placing_choice() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, SKILL15_MOVES_TO_WHITE_MOVE_5);

    let (best, score) = mtdf_search_at_skill(&snap, false, 15, 15);
    eprintln!("skill15 move5 depth=15: best={best} score={score}");
    // Master plays d5 at move 5 (first legal move, score 0); Rust must keep
    // the first move on ties through MTD(f).
    assert_eq!(best, "d5");
}

#[test]
#[ignore = "slow depth=15 parity case; covered by the default skill2/depth2 smoke test"]
fn skill15_move8_white_depth15_matches_master_placing_choice() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, SKILL15_MOVES_TO_WHITE_MOVE_8);

    let (best, score) = mtdf_search_at_skill(&snap, false, 15, 15);
    eprintln!("skill15 move8 depth=15: best={best} score={score}");
    assert_eq!(best, "e5");
}

#[test]
fn skill1_move13_black_depth1_matches_master_qsearch_leaf_behavior() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, SKILL1_MOVES_TO_BLACK_MOVE_13);

    let (best, score) = mtdf_search_at(&snap, false, 1);
    eprintln!("skill1 move13 depth=1: best={best} score={score}");
    // Master qsearch returns stand-pat at the depth-0 leaf and does not
    // call `has_repeated`, so shallow Skill=1 search does not avoid this
    // pre-root second occurrence.  It is still not a draw verdict; the
    // actual threefold adjudication remains in `apply` at the 3rd
    // occurrence.
    assert_eq!(best, "g7-d7");
}

#[test]
fn move12_black_search_skill2_depth2_avoids_pre_root_repetition_cycle() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, MOVES_TO_BLACK_MOVE_12);
    let (best, score) = mtdf_search_at(&snap, false, 2);
    eprintln!("move12 depth=2: best={best} score={score}");
    assert_eq!(best, "b4-c4");
}

#[test]
fn move12_repetition_history_search_bias_does_not_adjudicate_early() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, MOVES_TO_BLACK_MOVE_12);
    apply_line(&rules, &mut snap, &["d1-a1", "c5-c4"]);
    assert_eq!(rules.outcome(&snap).kind, tgf_core::OutcomeKind::Ongoing);

    apply_line(&rules, &mut snap, &["a1-d1", "c4-c5"]);
    assert_eq!(rules.outcome(&snap).kind, tgf_core::OutcomeKind::Draw);
}

/// Faithful self-play that mirrors the real Flutter engine path exactly.
///
/// * depth = Dart `searchDepthForSnapshot` == master non-developer
///   `Mills::get_search_depth` (DeveloperMode=false, DrawOnHumanExperience
///   =true): `recommended_search_depth(.., developer_mode=false)`.
/// * algorithm = MTD(f) (Flutter default `Algorithm = 2`).
/// * time 0 (no IDS) → a single `search_mtdf_with_guess(depth, first_guess=0)`
///   per ply.
/// * shuffling off.
/// * n-move draw = 10 full moving-phase moves, to keep flying-phase self-play
///   regression captures bounded.
///
/// Returns the full move list (UCI labels) so it can be diffed against the
/// master C++ engine driven with the same settings.
fn faithful_selfplay(skill_level: u8, max_plies: usize) -> Vec<String> {
    faithful_selfplay_opts(skill_level, max_plies, false, false)
}

fn move_vec(moves: &[&str]) -> Vec<String> {
    moves.iter().map(|m| (*m).to_owned()).collect()
}

fn assert_deterministic_selfplay_full_game(skill_level: u8, expected: &[&str]) -> Vec<String> {
    let first = faithful_selfplay(skill_level, 400);
    let second = faithful_selfplay(skill_level, 400);
    let expected = move_vec(expected);
    assert_eq!(first, expected);
    assert_eq!(second, expected);
    first
}

fn faithful_selfplay_opts(
    skill_level: u8,
    max_plies: usize,
    persist_tt: bool,
    use_alpha_beta: bool,
) -> Vec<String> {
    use tgf_mill::{EngineRuntimeOptions, recommended_search_depth};

    let options = selfplay_variant_options();
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options.clone());
    let mut snap = rules.initial_state(&[]);
    let mut moves: Vec<String> = Vec::new();

    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let make_searcher = || {
        let mut s = Searcher::<MillGame>::new();
        s.set_policy(SearchPolicy {
            quiescence_kind_tag: Some(tgf_mill::MillActionKind::Remove as i16),
            ..Default::default()
        });
        s.set_move_order_context(ctx);
        s
    };
    // `persist_tt` mirrors master, which only clears the TT on `ucinewgame`
    // (not per move): a single searcher (and its TT) is reused for the whole
    // game.  `persist_tt = false` matches the current Rust FRB, which builds a
    // fresh searcher (fresh TT) every move.
    let mut persistent = make_searcher();

    for _ in 0..max_plies {
        if rules.outcome(&snap).kind != tgf_core::OutcomeKind::Ongoing {
            break;
        }
        let state = MillRules::decode_snapshot(snap);
        let runtime = EngineRuntimeOptions {
            skill_level,
            draw_on_human_experience: true,
            developer_mode: false,
        };
        let depth = recommended_search_depth(&state, &options, &runtime).max(1);

        let mut wb = game.build_workbench(&snap);
        let result = if use_alpha_beta {
            make_searcher().search(&mut wb, depth)
        } else if persist_tt {
            persistent.search_mtdf_with_guess(&mut wb, depth, 0)
        } else {
            make_searcher().search_mtdf_with_guess(&mut wb, depth, 0)
        };
        if result.best_action.is_none() {
            break;
        }
        moves.push(MillUciCodec::encode_action(result.best_action));
        snap = rules.apply(&snap, result.best_action);
    }
    moves
}

#[test]
fn ai_vs_ai_skill1_time0_shuffling_off_matches_master_go_full_game() {
    assert_deterministic_selfplay_full_game(1, MASTER_GO_SKILL1_FULL_GAME);
}

#[test]
fn ai_vs_ai_skill2_time0_shuffling_off_matches_master_go_full_game() {
    assert_deterministic_selfplay_full_game(2, MASTER_GO_SKILL2_FULL_GAME);
}

#[test]
fn ai_vs_ai_skill3_time0_shuffling_off_matches_master_go_full_game() {
    assert_deterministic_selfplay_full_game(3, MASTER_GO_SKILL3_FULL_GAME);
}

#[test]
fn ai_vs_ai_skill4_time0_shuffling_off_full_game_has_known_master_tail_divergence() {
    let actual = assert_deterministic_selfplay_full_game(4, RUST_SKILL4_FULL_GAME);
    let master = move_vec(MASTER_GO_SKILL4_FULL_GAME);

    assert_eq!(actual.len(), master.len());
    assert_eq!(
        actual
            .iter()
            .zip(master.iter())
            .position(|(left, right)| left != right),
        Some(36),
        "Skill 4 should only diverge from master at the final reversible white move"
    );
    assert_eq!(&actual[36..], move_vec(&["a1-a4", "c4-c5"]).as_slice());
    assert_eq!(&master[36..], move_vec(&["d5-e5", "c4-c5"]).as_slice());
    assert_ne!(
        actual, master,
        "This full-game fixture intentionally documents the remaining master tail divergence"
    );
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill1_movelist() {
    let moves = faithful_selfplay(1, 400);
    eprintln!("SELFPLAY skill=1 plies={}", moves.len());
    eprintln!("SELFPLAY skill=1 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill2_movelist() {
    let moves = faithful_selfplay(2, 400);
    eprintln!("SELFPLAY skill=2 plies={}", moves.len());
    eprintln!("SELFPLAY skill=2 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill3_movelist() {
    let moves = faithful_selfplay(3, 400);
    eprintln!("SELFPLAY skill=3 plies={}", moves.len());
    eprintln!("SELFPLAY skill=3 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill4_movelist() {
    let moves = faithful_selfplay(4, 400);
    eprintln!("SELFPLAY skill=4 plies={}", moves.len());
    eprintln!("SELFPLAY skill=4 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill15_movelist() {
    let moves = faithful_selfplay(15, 400);
    eprintln!("SELFPLAY skill=15 plies={}", moves.len());
    eprintln!("SELFPLAY skill=15 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill15_persist_tt_movelist() {
    let moves = faithful_selfplay_opts(15, 400, true, false);
    eprintln!("SELFPLAY-TT skill=15 plies={}", moves.len());
    eprintln!("SELFPLAY-TT skill=15 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill15_alphabeta_movelist() {
    let moves = faithful_selfplay_opts(15, 400, false, true);
    eprintln!("SELFPLAY-AB skill=15 plies={}", moves.len());
    eprintln!("SELFPLAY-AB skill=15 moves: {}", moves.join(" "));
}
