// SPDX-License-Identifier: GPL-3.0-or-later
// Regression coverage for the opening reply the AI plays after the human
// opens on a cross point (d2).  Mirrors the FRB MTD(f) dispatch used by the
// Flutter app: standard 9MM rules, SkillLevel 1, infinite think time
// (move_time_ms = 0 => fixed depth 1), shuffling toggled by the user.
//
// Two porting regressions from the master C++ engine were fixed here and are
// pinned by these tests:
//
//   * MTD(f) recovered the root best move from the transposition table after
//     the zero-window bound loop.  The converging fail-low (all-node) probe
//     stores the first-ordered move with an Upper bound, clobbering the
//     genuinely best move, so the AI returned d5 instead of d6 and ignored
//     the mobility-aware evaluator.  Master keeps a persistent `bestMove`
//     reference updated only on `value > alpha`; the Rust port now does too.
//
//   * The static evaluator already ranks the cross / "star" points highest
//     (d6/f4/b4), so the search must prefer them.  With shuffling off the
//     deterministic reply is d6; with shuffling on the reply still stays on a
//     star square -- it never wanders to an arbitrary point.

use tgf_core::{
    Action, ActionList, Evaluator, Game, GameRules, MoveOrderAlgorithm, MoveOrderContext, Workbench,
};
use tgf_mill::{
    MillActionKind, MillEvaluator, MillGame, MillRules, MillUciCodec, MillVariantOptions,
};
use tgf_search::{SearchPolicy, Searcher};

/// Remaining cross / "star" squares after white has taken d2.  Without
/// diagonal lines these are the four degree-4 intersections d6/f4/d2/b4; d2
/// is occupied, leaving d6/f4/b4.
const STAR_SQUARES: [&str; 3] = ["d6", "f4", "b4"];

fn place(node: i16) -> Action {
    Action {
        kind_tag: MillActionKind::Place as i16,
        from_node: -1,
        to_node: node,
        aux: -1,
        payload_bits: 0,
    }
}

/// Build a fresh searcher configured exactly like the FRB Mill dispatch
/// (`spawn_mill_engine_config_event_stream`): qsearch remove policy + the
/// supplied move-order context, no time limit.
fn configured_searcher(ctx: MoveOrderContext) -> Searcher<MillGame> {
    let mut s = Searcher::<MillGame>::new();
    s.set_policy(SearchPolicy {
        quiescence_kind_tag: Some(MillActionKind::Remove as i16),
        ..Default::default()
    });
    s.set_move_order_context(ctx);
    s
}

/// Move-order context matching the default app engine knobs (MTD(f), Skill 1).
fn ctx_for(shuffling: bool, seed: u64) -> MoveOrderContext {
    MoveOrderContext {
        algorithm: MoveOrderAlgorithm::Mtdf,
        skill_level: 1,
        shuffling,
        hash_move: None,
        shuffle_seed: seed,
    }
}

/// Position after the human (white) opens on d2 = dense node 13.  Black to
/// move; standard 9MM rules with the default mobility-aware evaluator.
fn position_after_white_d2() -> (MillGame, tgf_core::GameStateSnapshot) {
    let options = MillVariantOptions::default();
    assert!(!options.has_diagonal_lines, "standard rules: no diagonals");
    assert!(
        options.consider_mobility,
        "mobility eval drives star preference"
    );
    let rules = MillRules::new(options.clone());
    let game = MillGame::new(options);
    let snap = rules.apply(&rules.initial_state(&[]), place(13));
    (game, snap)
}

/// A few varied, non-zero seeds standing in for the production time seed.
fn seeds() -> impl Iterator<Item = u64> {
    (0..32u64).map(|i| (i + 1).wrapping_mul(0x9E37_79B9_7F4A_7C15) ^ (i << 17))
}

#[test]
fn mtdf_skill1_shuffling_off_answers_d2_with_d6_deterministically() {
    let (game, snap) = position_after_white_d2();
    for seed in seeds() {
        let mut searcher = configured_searcher(ctx_for(false, seed));
        let mut wb = game.build_workbench(&snap);
        let result = searcher.search_mtdf_with_guess(&mut wb, 1, 0);
        assert_eq!(
            MillUciCodec::encode_action(result.best_action),
            "d6",
            "MTD(f) with shuffling off must deterministically answer d2 with d6 (seed {seed})",
        );
    }
}

#[test]
fn mtdf_skill1_shuffling_on_only_plays_star_squares() {
    let (game, snap) = position_after_white_d2();
    for seed in seeds() {
        let mut searcher = configured_searcher(ctx_for(true, seed));
        let mut wb = game.build_workbench(&snap);
        let result = searcher.search_mtdf_with_guess(&mut wb, 1, 0);
        let mv = MillUciCodec::encode_action(result.best_action);
        assert!(
            STAR_SQUARES.contains(&mv.as_str()),
            "MTD(f) with shuffling on must stay on a star square, got {mv} (seed {seed})",
        );
    }
}

#[test]
fn plain_alpha_beta_skill1_answers_d2_with_d6() {
    let (game, snap) = position_after_white_d2();
    let mut searcher = configured_searcher(ctx_for(false, 0));
    let mut wb = game.build_workbench(&snap);
    let result = searcher.search(&mut wb, 1);
    assert_eq!(MillUciCodec::encode_action(result.best_action), "d6");
}

#[test]
fn evaluator_ranks_star_squares_above_every_other_reply() {
    let (game, snap) = position_after_white_d2();
    let ctx = ctx_for(false, 0);
    let mut wb = game.build_workbench(&snap);
    let mut moves = ActionList::<256>::new();
    MillGame::generate_legal_ctx(&wb, &mut moves, &ctx);

    let mut best_non_star = i32::MIN;
    let mut star_values: Vec<(String, i32)> = Vec::new();
    for m in moves.iter() {
        wb.do_move(*m);
        // `MillEvaluator::score` is from the side-to-move (white) perspective
        // after black has replied, so black's value is its negation.
        let black_value = -MillEvaluator::score(&wb);
        wb.undo_move();
        let label = MillUciCodec::encode_action(*m);
        if STAR_SQUARES.contains(&label.as_str()) {
            star_values.push((label, black_value));
        } else {
            best_non_star = best_non_star.max(black_value);
        }
    }

    assert_eq!(
        star_values.len(),
        3,
        "expected exactly d6/f4/b4 as star replies"
    );
    for (label, value) in star_values {
        assert!(
            value > best_non_star,
            "star square {label} (value {value}) must outrank every non-star reply \
             (best non-star {best_non_star})",
        );
    }
}
