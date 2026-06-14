// SPDX-License-Identifier: GPL-3.0-or-later
// Probe the AI-vs-AI divergence at move 15 (black to play after 15. g1-g4).
// Master ends 15. ... g7-d7 1/2-1/2; Rust branch reported ... d1-g1.

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
    let options = MillVariantOptions::default();
    let game = MillGame::new(options);
    let ctx = MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
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
    // Threefold-repetition terminals score a neutral 0 (Stockfish-style
    // symmetric draw), so `g7-d7` (which forces an immediate threefold
    // draw) ties at 0 with the heuristic-0 quiet moves and does NOT win.
    // Depth-1 MTD(f) keeps the first 0-scoring move in C++ generate<LEGAL>
    // order, which is `d1-g1`.  master's recorded `15. ... g7-d7 1/2-1/2`
    // comes from its executeSearch root `has_game_cycle()` draw
    // short-circuit, not from search preferring the move, so we do not
    // mirror it here.
    assert_eq!(best, "d1-g1");
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
