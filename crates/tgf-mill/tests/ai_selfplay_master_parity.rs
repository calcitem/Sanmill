// SPDX-License-Identifier: AGPL-3.0-or-later
// Regression tests pinning Rust engine move choices to the master C++ engine
// under standard rules, Thinking-Time = 0 (fixed depth), shuffling off.
//
// The tests below pin the behaviours that DO match master move-for-move:
// placing-phase choices, skill 1-8 default deterministic self-play, ignored
// skill 9-15 full-depth self-play, repetition adjudication, and move ordering.

use tgf_core::{Game, GameRules, MoveOrderAlgorithm, MoveOrderContext, Workbench};
use tgf_mill::{
    MillBoardFullAction, MillEvalWeights, MillFormationActionInPlacingPhase, MillGame, MillRules,
    MillUciCodec, MillVariantOptions,
};
use tgf_search::{SearchPolicy, Searcher};

fn apply_line(rules: &MillRules, snap: &mut tgf_core::GameStateSnapshot, moves: &[&str]) {
    for uci in moves {
        let action = MillUciCodec::decode_action(snap, uci).expect(uci);
        *snap = rules.apply(snap, action);
    }
}

fn legacy_game(options: MillVariantOptions) -> MillGame {
    let mut game = MillGame::new(options);
    game.set_eval_weights(MillEvalWeights::LEGACY);
    game
}

fn legacy_game_with_repetition_history(
    options: MillVariantOptions,
    root_repetition_history: Vec<u64>,
) -> MillGame {
    let mut game = MillGame::new_with_repetition_history(options, root_repetition_history);
    game.set_eval_weights(MillEvalWeights::LEGACY);
    game
}

fn root_search_move_order(snap: &tgf_core::GameStateSnapshot) -> Vec<String> {
    use tgf_core::{Game, SearchActionList};
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let game = legacy_game(MillVariantOptions::default());
    let wb = game.build_workbench(snap);
    let mut moves = SearchActionList::new();
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
    mtdf_search_at_skill_with_options(
        snap,
        shuffling,
        depth,
        skill_level,
        MillVariantOptions::default(),
    )
}

fn mtdf_search_at_skill_with_options(
    snap: &tgf_core::GameStateSnapshot,
    shuffling: bool,
    depth: i32,
    skill_level: u8,
    options: MillVariantOptions,
) -> (String, i32) {
    let (best, score, _nodes) =
        mtdf_search_at_skill_with_options_and_nodes(snap, shuffling, depth, skill_level, options);
    (best, score)
}

fn mtdf_search_at_skill_with_options_and_nodes(
    snap: &tgf_core::GameStateSnapshot,
    shuffling: bool,
    depth: i32,
    skill_level: u8,
    options: MillVariantOptions,
) -> (String, i32, u64) {
    let game = legacy_game(options);
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
        result.nodes,
    )
}

fn mtdf_search_with_root_history(
    snap: &tgf_core::GameStateSnapshot,
    root_repetition_history: Vec<u64>,
    options: MillVariantOptions,
    depth: i32,
    skill_level: u8,
) -> (String, i32) {
    let game = legacy_game_with_repetition_history(options, root_repetition_history);
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level,
        shuffling: false,
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
    use tgf_core::{Game, SearchActionList};
    let options = MillVariantOptions::default();
    let game = legacy_game(options);
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let mut wb = game.build_workbench(snap);
    let mut moves = SearchActionList::new();
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

// Regenerate the hardcoded self-play expectations with:
//
//   python3 tools/update_selfplay_expectations.py --source master --write
//
// Use `--source current --write` only when deliberately blessing a new Rust
// engine baseline after a search or move-ordering change that is expected to
// alter self-play sequences.
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

const MASTER_GO_SKILL4_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6", "b2", "f2",
    "g7", "g1", "a4-a1", "d3-c3", "c4-c5", "c3-d3", "c5-c4", "d5-c5", "a1-a4", "c5-d5", "c4-c5",
    "b4-c4", "b2-b4", "d1-a1", "e4-e3", "a1-d1", "a4-a1", "d5-e5", "c5-d5", "e5-e4", "d5-e5",
    "c4-c5",
];

const MASTER_GO_SKILL5_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "d5", "d3", "e4", "f6", "f2", "b2", "b6", "g7",
    "a7", "c3", "d5-c5", "c3-c4", "e4-e5", "c4-c3", "d6-d5", "xd3", "c3-d3", "c5-c4", "f6-d6",
    "c4-c5", "xf4", "b4-c4", "e5-e4", "d6-f6", "f2-f4", "xd3", "b2-b4", "e4-e5", "xd1", "f6-d6",
    "e5-e4", "xc4", "b4-c4", "f4-f6", "c4-c3", "c5-c4", "c3-d3", "c4-c3", "d3-e3", "c3-d3",
];

const MASTER_GO_SKILL6_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6", "b2", "f2",
    "g7", "g1", "a4-a1", "d3-c3", "a1-a4", "c3-d3", "a4-a1", "d3-e3", "a1-a4", "d1-a1", "c4-c5",
    "b4-c4", "b2-b4", "d5-e5", "c5-d5", "e3-d3", "e4-e3", "e5-e4", "d5-e5", "a1-d1", "e5-d5",
    "c4-c5",
];

const MASTER_GO_SKILL7_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "d3", "f6", "e3", "f2", "xe3",
    "e3", "e5", "c3", "xe5", "c4", "g4-g1", "d7-a7", "g1-g4", "d5-e5", "g4-g7", "b4-b6", "g7-g4",
    "e5-d5", "a4-b4", "d1-g1", "b4-a4", "b6-b4", "e4-e5", "f4-e4", "g4-f4", "g1-d1", "d2-b2",
    "d1-d2", "d6-d7", "d5-d6",
];

const MASTER_GO_SKILL8_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "g7", "g1", "a1", "a7",
    "f6", "e5", "c4-c5", "d3-c3", "c5-c4", "c3-d3", "c4-c5", "d3-e3", "c5-c4", "d5-c5", "d6-d5",
    "d7-d6", "g7-d7", "e3-d3", "c4-c3", "c5-c4", "e4-e3", "e5-e4", "d5-e5", "c4-c5", "c3-c4",
    "c5-d5",
];

const MASTER_GO_SKILL9_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "d3", "g7", "a7", "a1", "c4", "g1",
    "xd6", "d6", "c3", "c4-c5", "b4-c4", "d3-e3", "c3-d3", "e4-e5", "f4-e4", "d6-b6", "d5-d6",
    "e5-d5", "c4-b4", "c5-c4", "d3-c3", "e3-d3", "e4-e3", "c4-c5", "c3-c4", "d3-c3", "e3-d3",
    "d5-e5", "d3-e3",
];

const MASTER_GO_SKILL10_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "f6", "b6", "b2", "f2", "e3", "e5",
    "c5", "d3", "a4-a7", "d1-a1", "c5-c4", "a1-d1", "a7-a4", "d5-c5", "a4-a7", "d1-a1", "a7-a4",
    "d7-a7", "g4-g1", "a7-d7", "g1-d1", "c5-d5", "c4-c5", "d7-g7", "c5-c4", "g7-g4", "c4-c5",
    "g4-g1",
];

const MASTER_GO_SKILL11_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "f6", "b6", "b2", "f2", "d5", "g7", "a7", "a1",
    "g1", "e5", "d5-c5", "b4-c4", "c5-d5", "b6-b4", "d2-d3", "f2-d2", "d3-e3", "c4-c5", "e3-d3",
    "b4-b6", "d3-e3", "c5-c4", "e3-d3", "e5-e4", "b2-b4", "c4-c5", "d3-c3", "c5-c4", "d5-e5",
    "e4-e3",
];

const MASTER_GO_SKILL12_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d3", "f6", "b6", "b2", "f2", "e4", "d5", "c3", "c4",
    "c5", "d1", "e4-e3", "d5-e5", "c5-d5", "e5-e4", "d5-e5", "c4-c5", "c3-c4", "c5-d5", "c4-c5",
    "d3-c3", "c5-c4", "d5-c5", "e3-d3", "c5-d5", "c4-c5", "c3-c4", "d3-c3", "e4-e3", "c3-d3",
    "c4-c3",
];

const MASTER_GO_SKILL13_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "d5", "d3", "f6", "b6", "b2", "f2", "e5", "c5",
    "c3", "e4", "g4-g7", "d1-g1", "g7-g4", "d7-a7", "c3-c4", "d3-c3", "a4-a1", "a7-d7", "a1-a4",
    "c3-d3", "a4-a7", "g1-d1", "a7-a4", "d3-c3", "a4-a7", "e4-e3", "e5-e4", "c3-d3", "a7-a4",
    "d3-c3",
];

const MASTER_GO_SKILL14_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "f6", "b6", "b2", "f2", "e3", "e5",
    "c5", "d3", "c5-c4", "d5-c5", "a4-a7", "c5-d5", "a7-a4", "d1-a1", "a4-a7", "a1-a4", "c4-c5",
    "d3-c3", "c5-c4", "d5-c5", "e3-d3", "a4-a1", "a7-a4", "c5-d5", "c4-c5", "c3-c4", "d3-c3",
    "a1-d1",
];

const MASTER_GO_SKILL15_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "d5", "d3", "f6", "b6", "b2", "f2", "e5", "c5",
    "c3", "e4", "c3-c4", "d3-c3", "a4-a1", "d1-g1", "a1-a4", "c3-d3", "c4-c3", "d7-a7", "c3-c4",
    "g1-d1", "c4-c3", "a7-d7", "a4-a7", "d3-e3", "c3-c4", "e3-d3", "g4-g1", "d3-c3", "a7-a4",
    "c3-d3",
];

const MASTER_GO_SKILL15_N30_ENDGAME20_FULL_GAME: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "d5", "d3", "f6", "b6", "b2", "f2", "e5", "c5",
    "c3", "e4", "c3-c4", "d3-c3", "a4-a1", "d1-g1", "a1-a4", "c3-d3", "c4-c3", "d7-a7", "c3-c4",
    "d3-c3", "a4-a1", "a7-a4", "a1-d1", "a4-a1", "d2-d3", "f2-d2", "d6-d7", "b6-d6", "d7-a7",
    "a1-a4", "a7-d7", "e4-e3", "e5-e4", "a4-a7", "e4-e5", "e3-e4", "d3-e3", "c3-d3", "d7-g7",
    "a7-d7",
];

const SKILL15_N30_ENDGAME20_MOVES_TO_BLACK_MOVE_20: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "d5", "d3", "f6", "b6", "b2", "f2", "e5", "c5",
    "c3", "e4", "c3-c4", "d3-c3", "a4-a1", "d1-g1", "a1-a4", "c3-d3", "c4-c3", "d7-a7", "c3-c4",
    "d3-c3", "a4-a1", "a7-a4", "a1-d1", "a4-a1", "d2-d3", "f2-d2", "d6-d7", "b6-d6", "d7-a7",
    "a1-a4", "a7-d7",
];

const SKILL4_MOVES_TO_N_MOVE_FLOOR_TAIL: &[&str] = &[
    "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6", "b2", "f2",
    "g7", "g1", "a4-a1", "d3-c3", "c4-c5", "c3-d3", "c5-c4", "d5-c5", "a1-a4", "c5-d5", "c4-c5",
    "b4-c4", "b2-b4", "d1-a1", "e4-e3", "a1-d1", "a4-a1", "d5-e5", "c5-d5", "e5-e4",
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
    use tgf_core::SearchActionList;
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        hash_move: None,
        shuffle_seed: 0,
    };
    let game = legacy_game(MillVariantOptions::default());
    let wb = game.build_workbench(&snap);
    let mut moves = SearchActionList::new();
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
    use tgf_core::SearchActionList;
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling: false,
        ..Default::default()
    };
    let game = legacy_game(MillVariantOptions::default());
    let wb = game.build_workbench(&snap);
    let mut moves = SearchActionList::new();
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
    use tgf_core::{Game, MoveOrderAlgorithm, MoveOrderContext, SearchActionList};
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
    let game = legacy_game(MillVariantOptions::default());
    let wb = game.build_workbench(&snap);
    let mut moves = SearchActionList::new();
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
#[ignore = "slow depth=14 node-count parity case; run when auditing master search statistics"]
fn skill15_move5_white_depth14_matches_master_node_count() {
    let rules = MillRules::default();
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, &["d6", "f4", "d2", "b4"]);

    let (best, score, nodes) = mtdf_search_at_skill_with_options_and_nodes(
        &snap,
        false,
        14,
        15,
        MillVariantOptions::default(),
    );

    assert_eq!(best, "f6");
    assert_eq!(score, 2);
    assert_eq!(nodes, 19_397_250);
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
    faithful_selfplay_opts(
        skill_level,
        max_plies,
        selfplay_variant_options(),
        false,
        false,
    )
}

fn move_vec(moves: &[&str]) -> Vec<String> {
    moves.iter().map(|m| (*m).to_owned()).collect()
}

fn assert_selfplay_full_game(skill_level: u8, expected: &[&str]) -> Vec<String> {
    assert_selfplay_full_game_with_options(skill_level, expected, selfplay_variant_options())
}

fn assert_selfplay_full_game_with_options(
    skill_level: u8,
    expected: &[&str],
    options: MillVariantOptions,
) -> Vec<String> {
    let actual = faithful_selfplay_opts(skill_level, 400, options, false, false);
    let expected = move_vec(expected);
    assert_eq!(actual, expected);
    actual
}

fn assert_deterministic_selfplay_full_game(skill_level: u8, expected: &[&str]) -> Vec<String> {
    let first = assert_selfplay_full_game(skill_level, expected);
    let second = assert_selfplay_full_game(skill_level, expected);
    assert_eq!(second, first);
    first
}

fn variant_options(mut edit: impl FnMut(&mut MillVariantOptions)) -> MillVariantOptions {
    let mut options = selfplay_variant_options();
    edit(&mut options);
    options
}

fn assert_selfplay_variant_prefix(
    name: &str,
    skill_level: u8,
    max_plies: usize,
    options: MillVariantOptions,
    expected: &[&str],
) {
    let actual = faithful_selfplay_opts(skill_level, max_plies, options, false, false);
    assert_eq!(
        actual,
        move_vec(expected),
        "{name} self-play prefix drifted"
    );
}

fn faithful_selfplay_opts(
    skill_level: u8,
    max_plies: usize,
    options: MillVariantOptions,
    persist_tt: bool,
    use_alpha_beta: bool,
) -> Vec<String> {
    use tgf_mill::{EngineRuntimeOptions, recommended_search_depth};

    let rules = MillRules::new(options.clone());
    let game = legacy_game(options.clone());
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
fn selfplay_skill1_time0_shuffling_off_matches_master_go_full_game() {
    assert_deterministic_selfplay_full_game(1, MASTER_GO_SKILL1_FULL_GAME);
}

#[test]
fn selfplay_skill2_time0_shuffling_off_matches_master_go_full_game() {
    assert_deterministic_selfplay_full_game(2, MASTER_GO_SKILL2_FULL_GAME);
}

#[test]
fn selfplay_skill3_time0_shuffling_off_matches_master_go_full_game() {
    assert_deterministic_selfplay_full_game(3, MASTER_GO_SKILL3_FULL_GAME);
}

#[test]
fn skill4_tail_n_move_override_keeps_master_mtdf_choice() {
    let options = selfplay_variant_options();
    let rules = MillRules::new(options.clone());
    let mut snap = rules.initial_state(&[]);
    apply_line(&rules, &mut snap, SKILL4_MOVES_TO_N_MOVE_FLOOR_TAIL);

    let (best, score) = mtdf_search_at_skill_with_options(&snap, false, 4, 4, options);

    assert_eq!(best, "d5-e5");
    assert_eq!(score, 0);
}

#[test]
#[ignore = "slow depth=15 parity case; mirrors Flutter NMove=30/EndgameNMove=20 diagnostics"]
fn skill15_n30_endgame20_black_move20_matches_master() {
    let options = MillVariantOptions {
        n_move_rule: 30,
        endgame_n_move_rule: 20,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options.clone());
    let mut snap = rules.initial_state(&[]);
    apply_line(
        &rules,
        &mut snap,
        SKILL15_N30_ENDGAME20_MOVES_TO_BLACK_MOVE_20,
    );

    let (best, score) = mtdf_search_at_skill_with_options(&snap, false, 15, 15, options);

    assert_eq!(best, "e4-e3");
    assert_eq!(score, 0);
}

#[test]
#[ignore = "slow depth=15 parity case; verifies Flutter kernel-history search path"]
fn skill15_n30_endgame20_kernel_history_black_move20_matches_master() {
    use std::sync::Arc;
    use tgf_core::GameKernel;

    let options = MillVariantOptions {
        n_move_rule: 30,
        endgame_n_move_rule: 20,
        ..MillVariantOptions::default()
    };
    let rules = MillRules::new(options.clone());
    let mut kernel = GameKernel::new(Arc::new(rules.clone()), &[]);
    for uci in SKILL15_N30_ENDGAME20_MOVES_TO_BLACK_MOVE_20 {
        let action = MillUciCodec::decode_action(&kernel.snapshot(), uci).expect(uci);
        kernel.apply(action).expect("legal self-play move");
    }
    let snapshot = kernel.snapshot();
    let root_repetition_history =
        MillRules::repetition_history_from_snapshots(&snapshot, kernel.history_snapshots());

    let (best, score) =
        mtdf_search_with_root_history(&snapshot, root_repetition_history, options, 15, 15);

    assert_eq!(best, "e4-e3");
    assert_eq!(score, 0);
}

#[test]
fn selfplay_skill4_time0_shuffling_off_matches_master_go_full_game() {
    assert_deterministic_selfplay_full_game(4, MASTER_GO_SKILL4_FULL_GAME);
}

#[test]
fn selfplay_skill5_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(5, MASTER_GO_SKILL5_FULL_GAME);
}

#[test]
fn selfplay_skill6_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(6, MASTER_GO_SKILL6_FULL_GAME);
}

#[test]
fn selfplay_skill7_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(7, MASTER_GO_SKILL7_FULL_GAME);
}

#[test]
fn selfplay_skill8_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(8, MASTER_GO_SKILL8_FULL_GAME);
}

#[test]
#[ignore = "slow variant parity audit; run after rule or search changes"]
fn variant_selfplay_skill2_prefixes_match_master() {
    assert_selfplay_variant_prefix(
        "removal_based_on_mill_counts",
        2,
        30,
        variant_options(|options| {
            options.mill_formation_action_in_placing_phase =
                MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts;
        }),
        &[
            "d6", "f4", "d2", "b4", "d7", "d5", "g4", "d1", "a4", "e4", "d3", "c4", "f6", "b6",
            "b2", "f2", "e5", "g7", "xb2", "xb4", "d3-e3", "c4-b4", "e3-d3", "e4-e3", "e5-e4",
            "b4-c4", "a4-b4", "c4-c3", "d7-a7", "g7-d7",
        ],
    );
    assert_selfplay_variant_prefix(
        "twelve_mens_board_full_first_second_remove",
        2,
        30,
        variant_options(|options| {
            options.piece_count = 12;
            options.board_full_action = MillBoardFullAction::FirstAndSecondPlayerRemovePiece;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6",
            "b2", "f2", "g7", "g1", "a1", "a7", "e5", "e3", "c3", "c5", "xb4", "xb2", "c4-b4",
            "c5-c4", "b4-b2", "b6-b4",
        ],
    );
    assert_selfplay_variant_prefix(
        "custodian_capture",
        2,
        30,
        variant_options(|options| {
            options.custodian_capture.enabled = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "e4", "a4", "c4", "e5", "e3", "c3", "c5", "d7", "d5",
            "d1", "d3", "f6", "f2", "d2-b2", "b4-b6", "b2-d2", "b6-b4", "d6-b6", "b4-b2", "xd2",
            "d7-d6", "xb2", "f2-d2", "b6-b4", "d2-b2",
        ],
    );
    assert_selfplay_variant_prefix(
        "intervention_capture",
        2,
        30,
        variant_options(|options| {
            options.intervention_capture.enabled = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6",
            "b2", "f2", "g7", "g1", "c4-c5", "b4-c4", "b2-b4", "d3-e3", "a4-a7", "e3-d3", "a7-a4",
            "d3-e3", "a4-a1", "e3-d3", "a1-a4",
        ],
    );
    assert_selfplay_variant_prefix(
        "leap_capture",
        2,
        30,
        variant_options(|options| {
            options.leap_capture.enabled = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6",
            "b2", "f2", "g7", "a7", "a4-a1", "d3-c3", "a1-g1", "xd1", "c3-c5", "xc4", "g1-d1",
            "c5-c4", "d1-g1", "xc4", "d5-e5", "g1-d1",
        ],
    );
}

#[test]
#[ignore = "slow transition-heavy variant parity audit; run after rule or search changes"]
fn variant_selfplay_skill6_transition_prefixes_match_master() {
    assert_selfplay_variant_prefix(
        "hand_remove_opponent_turn_transition",
        6,
        80,
        variant_options(|options| {
            options.mill_formation_action_in_placing_phase =
                MillFormationActionInPlacingPhase::RemoveOpponentsPieceFromHandThenOpponentsTurn;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6",
            "b2", "f2", "g7", "g1", "a4-a1", "d3-c3", "a1-a4", "c3-d3", "a4-a1", "d3-e3", "a1-a4",
            "d1-a1", "c4-c5", "b4-c4", "b2-b4", "d5-e5", "c5-d5", "e3-d3", "e4-e3", "e5-e4",
            "d5-e5", "a1-d1", "e5-d5", "c4-c5",
        ],
    );
    assert_selfplay_variant_prefix(
        "mark_delay_remove_transition",
        6,
        80,
        variant_options(|options| {
            options.mill_formation_action_in_placing_phase =
                MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6",
            "b2", "f2", "g7", "g1", "a4-a1", "d3-c3", "a1-a4", "c3-d3", "a4-a1", "d3-e3", "a1-a4",
            "d1-a1", "c4-c5", "b4-c4", "b2-b4", "d5-e5", "c5-d5", "e3-d3", "e4-e3", "e5-e4",
            "d5-e5", "a1-d1", "e5-d5", "c4-c5",
        ],
    );
    assert_selfplay_variant_prefix(
        "twelve_mens_stop_two_empty_transition",
        6,
        80,
        variant_options(|options| {
            options.piece_count = 12;
            options.stop_placing_when_two_empty_squares = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6",
            "b2", "f2", "g7", "g1", "a7", "a1", "xc4", "c4", "e5", "c5", "c4-c3", "d3-e3", "c3-d3",
            "b4-c4", "b2-b4", "c4-c3", "c5-c4", "xd7", "d5-c5", "d6-d5", "b6-d6", "a7-d7", "d6-b6",
            "d7-d6",
        ],
    );
    assert_selfplay_variant_prefix(
        "twelve_mens_mark_delay_transition",
        6,
        80,
        variant_options(|options| {
            options.piece_count = 12;
            options.mill_formation_action_in_placing_phase =
                MillFormationActionInPlacingPhase::MarkAndDelayRemovingPieces;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "f6", "b6",
            "b2", "f2", "g7", "g1", "a1", "a7", "e5", "e3", "c5", "c3", "xc5", "c4-c5", "c3-c4",
        ],
    );
    assert_selfplay_variant_prefix(
        "defender_first_removal_based_transition",
        6,
        80,
        variant_options(|options| {
            options.is_defender_move_first = true;
            options.mill_formation_action_in_placing_phase =
                MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts;
        }),
        &[
            "d6", "f4", "d2", "b4", "d7", "d5", "g4", "d1", "a4", "e4", "d3", "c4", "f6", "b6",
            "b2", "g1", "f2", "a1", "xa4", "xc4", "a1-a4", "d7-g7", "a4-a1", "xg4", "g7-g4",
            "a1-a4", "d3-c3", "a4-a1", "xg4", "c3-c4", "g1-g4", "xc4", "d6-d7", "b6-d6", "d2-d3",
            "g4-g1", "xd3", "b2-d2", "d5-c5", "d7-g7", "g1-g4", "xd2", "g7-g1", "e4-e5", "g1-d5",
            "e5-e4", "xf2",
        ],
    );
}

#[test]
#[ignore = "slow variant parity audit; run after rule or search changes"]
fn variant_selfplay_skill8_deep_prefixes_match_master() {
    assert_selfplay_variant_prefix(
        "removal_based_on_mill_counts_deep",
        8,
        36,
        variant_options(|options| {
            options.mill_formation_action_in_placing_phase =
                MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts;
        }),
        &[
            "d6", "f4", "d2", "b4", "d7", "d5", "g4", "d1", "a4", "e4", "c4", "f6", "f2", "b2",
            "d3", "g7", "b6", "e3", "xb6", "xb2", "c4-c5", "d5-e5", "xc5", "d2-b2", "d1-d2",
            "d6-d5", "f6-d6", "a4-a7", "b4-b6", "a7-a4", "f4-f6", "xd3", "b2-b4", "f6-f4", "d5-c5",
            "f4-f6",
        ],
    );
    assert_selfplay_variant_prefix(
        "diagonal_removal_based_deep",
        8,
        36,
        variant_options(|options| {
            options.has_diagonal_lines = true;
            options.mill_formation_action_in_placing_phase =
                MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts;
        }),
        &[
            "f6", "f2", "b2", "b6", "g7", "e5", "g1", "g4", "a1", "c3", "d1", "d7", "a7", "a4",
            "d3", "c5", "d2", "d6", "xf2", "xd6", "xb2", "d3-e3", "d7-d6", "d2-f2", "xe5", "c5-c4",
            "e3-e4", "b6-c5", "xe4", "f2-f4", "c4-b4", "g1-f2", "xb4", "g4-g1", "g7-d7", "a4-b4",
        ],
    );
    assert_selfplay_variant_prefix(
        "custodian_intervention_multi_deep",
        8,
        60,
        variant_options(|options| {
            options.custodian_capture.enabled = true;
            options.intervention_capture.enabled = true;
            options.may_remove_multiple = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "g7", "g1", "a1", "a7", "f6", "b6",
            "b2", "d5", "xd6", "d6", "xd5", "xd7", "d5", "g7-d7", "b4-c4", "b2-b4", "f4-f2",
            "f6-f4", "d5-e5", "b4-b2", "e5-e4", "d2-d3", "f2-d2", "f4-f2", "xd2", "d1-d2", "xf2",
            "xb2", "a1-d1", "xd2", "e4-f4", "d6-f6", "b6-b4", "d3-e3", "f4-e4", "f6-f4", "b4-b6",
            "f4-f2", "c4-c3", "d7-d6", "a7-d7", "g4-g7", "d7-a7", "d6-d5", "e4-f4", "e3-d3",
            "b6-b4", "f2-d2", "xc3", "a7-d7", "d3-e3", "b4-b6",
        ],
    );
    assert_selfplay_variant_prefix(
        "capture_no_mill_removal_relax_deep",
        8,
        60,
        variant_options(|options| {
            options.custodian_capture.enabled = true;
            options.intervention_capture.enabled = true;
            options.may_remove_from_mills_always = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e5", "c4", "c3", "e4", "d5", "g7",
            "a7", "a1", "e3", "xe4", "e4", "xe3", "xe5", "d6-f6", "b4-b2", "d5-c5", "xc4", "f4-f2",
            "xd2", "f6-d6", "d1-d2", "xc3", "a4-b4", "f2-f4", "c5-c4", "a1-a4", "d6-f6", "d2-d1",
            "c4-c5", "d1-g1", "xg4", "c5-d5", "g7-g4", "xa7", "f6-g7", "e4-e3", "d5-e4", "a4-a7",
            "b4-d1", "b2-d2", "d1-d5", "e3-d3", "e4-d1", "a7-a4", "d5-a1", "f4-f2", "d1-a7", "xd7",
            "g1-d1", "xa7",
        ],
    );
    assert_selfplay_variant_prefix(
        "leap_capture_deep",
        8,
        60,
        variant_options(|options| {
            options.leap_capture.enabled = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "g7", "a7", "a1",
            "g1", "e5", "c5", "f6", "c4-c3", "f6-b6", "xd6", "a4-c4", "xb4", "d1-d3", "xd2",
            "c3-e3", "xd3", "b6-d6", "xc5", "c4-c5", "d6-f6", "e3-d3", "f6-d6", "xg1", "e4-e3",
            "g7-g1", "xg4", "c5-c4", "g1-g4", "c4-c3", "xf4", "d7-g7", "c3-c4", "g7-d7", "xd3",
            "e3-c5", "a1-d1", "c5-a1", "e5-e4", "c4-a4", "xg4", "e4-e3", "a7-e5", "e3-d3", "e5-a7",
            "xd3", "d7-g7", "a1-d7", "d1-a1", "a4-e5",
        ],
    );
    assert_selfplay_variant_prefix(
        "one_time_restrict_repeated_deep",
        8,
        60,
        variant_options(|options| {
            options.one_time_use_mill = true;
            options.restrict_repeated_mills_formation = true;
        }),
        &[
            "d6", "f4", "d2", "b4", "g4", "d7", "a4", "d1", "e4", "d5", "c4", "d3", "g7", "g1",
            "a1", "a7", "f6", "e5", "c4-c5", "d3-c3", "c5-c4", "c3-d3", "c4-c5", "d3-e3", "c5-c4",
            "d5-c5", "d6-d5", "d7-d6", "g7-d7", "e3-d3", "c4-c3", "c5-c4", "e4-e3", "e5-e4",
            "d5-e5", "c4-c5", "c3-c4", "c5-d5",
        ],
    );
}

#[test]
#[ignore = "slow depth=9 parity case; default coverage stops at skill8"]
fn selfplay_skill9_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(9, MASTER_GO_SKILL9_FULL_GAME);
}

#[test]
#[ignore = "slow depth=10 parity case; default coverage stops at skill8"]
fn selfplay_skill10_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(10, MASTER_GO_SKILL10_FULL_GAME);
}

#[test]
#[ignore = "slow depth=11 parity case; default coverage stops at skill8"]
fn selfplay_skill11_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(11, MASTER_GO_SKILL11_FULL_GAME);
}

#[test]
#[ignore = "slow depth=12 parity case; default coverage stops at skill8"]
fn selfplay_skill12_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(12, MASTER_GO_SKILL12_FULL_GAME);
}

#[test]
#[ignore = "slow depth=13 parity case; default coverage stops at skill8"]
fn selfplay_skill13_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(13, MASTER_GO_SKILL13_FULL_GAME);
}

#[test]
#[ignore = "slow depth=14 parity case; default coverage stops at skill8"]
fn selfplay_skill14_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(14, MASTER_GO_SKILL14_FULL_GAME);
}

#[test]
#[ignore = "slow depth=15 parity case; run explicitly for full master parity"]
fn selfplay_skill15_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game(15, MASTER_GO_SKILL15_FULL_GAME);
}

#[test]
#[ignore = "slow depth=15 parity case; mirrors Flutter NMove=30/EndgameNMove=20"]
fn selfplay_skill15_n30_endgame20_time0_shuffling_off_matches_master_go_full_game() {
    assert_selfplay_full_game_with_options(
        15,
        MASTER_GO_SKILL15_N30_ENDGAME20_FULL_GAME,
        MillVariantOptions {
            n_move_rule: 30,
            endgame_n_move_rule: 20,
            ..MillVariantOptions::default()
        },
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
fn faithful_selfplay_skill5_movelist() {
    let moves = faithful_selfplay(5, 400);
    eprintln!("SELFPLAY skill=5 plies={}", moves.len());
    eprintln!("SELFPLAY skill=5 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill6_movelist() {
    let moves = faithful_selfplay(6, 400);
    eprintln!("SELFPLAY skill=6 plies={}", moves.len());
    eprintln!("SELFPLAY skill=6 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill7_movelist() {
    let moves = faithful_selfplay(7, 400);
    eprintln!("SELFPLAY skill=7 plies={}", moves.len());
    eprintln!("SELFPLAY skill=7 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill8_movelist() {
    let moves = faithful_selfplay(8, 400);
    eprintln!("SELFPLAY skill=8 plies={}", moves.len());
    eprintln!("SELFPLAY skill=8 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill9_movelist() {
    let moves = faithful_selfplay(9, 400);
    eprintln!("SELFPLAY skill=9 plies={}", moves.len());
    eprintln!("SELFPLAY skill=9 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill10_movelist() {
    let moves = faithful_selfplay(10, 400);
    eprintln!("SELFPLAY skill=10 plies={}", moves.len());
    eprintln!("SELFPLAY skill=10 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill11_movelist() {
    let moves = faithful_selfplay(11, 400);
    eprintln!("SELFPLAY skill=11 plies={}", moves.len());
    eprintln!("SELFPLAY skill=11 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill12_movelist() {
    let moves = faithful_selfplay(12, 400);
    eprintln!("SELFPLAY skill=12 plies={}", moves.len());
    eprintln!("SELFPLAY skill=12 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill13_movelist() {
    let moves = faithful_selfplay(13, 400);
    eprintln!("SELFPLAY skill=13 plies={}", moves.len());
    eprintln!("SELFPLAY skill=13 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill14_movelist() {
    let moves = faithful_selfplay(14, 400);
    eprintln!("SELFPLAY skill=14 plies={}", moves.len());
    eprintln!("SELFPLAY skill=14 moves: {}", moves.join(" "));
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
    let moves = faithful_selfplay_opts(15, 400, selfplay_variant_options(), true, false);
    eprintln!("SELFPLAY-TT skill=15 plies={}", moves.len());
    eprintln!("SELFPLAY-TT skill=15 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; run explicitly to diff vs master"]
fn faithful_selfplay_skill15_alphabeta_movelist() {
    let moves = faithful_selfplay_opts(15, 400, selfplay_variant_options(), false, true);
    eprintln!("SELFPLAY-AB skill=15 plies={}", moves.len());
    eprintln!("SELFPLAY-AB skill=15 moves: {}", moves.join(" "));
}

#[test]
#[ignore = "self-play ground-truth harness; mirrors Flutter NMove=30/EndgameNMove=20 diagnostics"]
fn faithful_selfplay_skill15_n30_endgame20_movelist() {
    let moves = faithful_selfplay_opts(
        15,
        400,
        MillVariantOptions {
            n_move_rule: 30,
            endgame_n_move_rule: 20,
            ..MillVariantOptions::default()
        },
        false,
        false,
    );
    eprintln!("SELFPLAY-N30E20 skill=15 plies={}", moves.len());
    eprintln!("SELFPLAY-N30E20 skill=15 moves: {}", moves.join(" "));
}
