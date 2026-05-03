// SPDX-License-Identifier: GPL-3.0-or-later
// `Workbench` / `Evaluator` / `Game` trait implementations for the
// CRTP search-hot-path types — `MillWorkbench`, `MillEvaluator`, and
// `MillGame`.  Hosting these here keeps `rules/mod.rs` focused on
// state / configuration rather than search-side wiring.

use tgf_core::{Action, ActionList, Evaluator, Game, GameRules, GameStateSnapshot, Workbench};

use super::evaluation::{
    gameover_value, mills_pieces_count_difference, mobility_diff, remove_move_score,
    should_consider_mobility, should_focus_on_blocking_paths, surrounded_pieces_count,
};
use super::fen::position_key;
use super::move_priority::{
    is_star_square, RATING_BLOCK_ONE_MILL, RATING_ONE_MILL, RATING_STAR_SQUARE,
};
use super::potential_mills_count_at;
use super::types::MillActionKind;
use super::{
    MillEvaluator, MillFormationActionInPlacingPhase, MillGame, MillPhase, MillRules,
    MillWorkbench, MILL_TERMINAL_WIN_SCORE,
};

impl Workbench for MillWorkbench {
    fn snapshot(&self) -> GameStateSnapshot {
        self.rules.encode(self.state.clone())
    }

    fn key(&self) -> u64 {
        position_key(&self.state)
    }

    fn side_to_move(&self) -> i8 {
        self.state.side_to_move
    }

    fn is_terminal(&self) -> bool {
        self.state.phase == MillPhase::GameOver
    }

    fn do_move(&mut self, a: Action) {
        self.undo_stack.push(self.state.clone());
        let next = self.rules.apply(&self.snapshot(), a);
        self.state = MillRules::decode(&next);
    }

    fn undo_move(&mut self) {
        if let Some(prev) = self.undo_stack.pop() {
            self.state = prev;
        }
    }
}

impl Evaluator<MillWorkbench> for MillEvaluator {
    /// Static evaluator translated from `src/evaluate.cpp::Evaluation::value`
    /// in the legacy C++ engine.
    ///
    /// The constants are scaled to the same units as `VALUE_EACH_PIECE`
    /// (`PieceValue = 5`) and `VALUE_MATE = 80`, so search scores stay
    /// numerically compatible with the legacy `MTDF` aspiration windows.
    /// A perspective swap at the end mirrors C++ "value from the side to
    /// move" convention.
    fn score(wb: &MillWorkbench) -> i32 {
        const VALUE_EACH_PIECE: i32 = 5;
        const VALUE_MATE: i32 = 80;
        const VALUE_DRAW: i32 = 0;

        let state = &wb.state;
        let options = &wb.rules.options;
        let mut value: i32 = 0;

        let removals_diff =
            i32::from(state.pending_removals[0]) - i32::from(state.pending_removals[1]);
        let in_hand_diff = i32::from(state.pieces_in_hand[0]) - i32::from(state.pieces_in_hand[1]);
        let on_board_diff =
            i32::from(state.pieces_on_board[0]) - i32::from(state.pieces_on_board[1]);
        let action_is_remove = state.pending_removals[0] > 0 || state.pending_removals[1] > 0;

        match state.phase {
            MillPhase::Ready => {}
            MillPhase::Placing
                if matches!(
                    options.mill_formation_action_in_placing_phase,
                    MillFormationActionInPlacingPhase::RemovalBasedOnMillCounts
                ) =>
            {
                if action_is_remove {
                    value += VALUE_EACH_PIECE * removals_diff;
                } else {
                    value += mills_pieces_count_difference(state, options);
                }
            }
            MillPhase::Placing | MillPhase::Moving => {
                if should_consider_mobility(options) {
                    value += mobility_diff(state, options);
                }
                if !should_focus_on_blocking_paths(state, options) {
                    value += VALUE_EACH_PIECE * in_hand_diff;
                    value += VALUE_EACH_PIECE * on_board_diff;
                    if action_is_remove {
                        value += VALUE_EACH_PIECE * removals_diff;
                    }
                }
            }
            MillPhase::GameOver => {
                value = gameover_value(state, options, VALUE_MATE, VALUE_DRAW);
            }
        }

        if state.side_to_move == 1 {
            value = -value;
        }
        value
    }
}

impl Game for MillGame {
    type Workbench = MillWorkbench;
    type Evaluator = MillEvaluator;

    fn build_workbench(&self, snap: &GameStateSnapshot) -> Self::Workbench {
        let rules = MillRules::new(self.options.clone());
        let state = MillRules::decode(snap);
        MillWorkbench {
            rules,
            state,
            undo_stack: Vec::new(),
        }
    }

    fn generate_legal(wb: &Self::Workbench, out: &mut ActionList<256>) {
        wb.rules.legal_actions(&wb.snapshot(), out);
    }

    fn generate_legal_ctx(
        wb: &Self::Workbench,
        out: &mut ActionList<256>,
        ctx: &tgf_core::MoveOrderContext,
    ) {
        wb.rules.legal_actions_ctx(&wb.state, out, ctx);
    }

    /// MovePicker-style move ordering bonus translated from
    /// `src/movepick.cpp::score()`.  Combines mill formation, mill blocking,
    /// star-square opening preference, and capture-target preference.  The
    /// numeric weights match `RATING_*` constants in `src/types.h`; killer /
    /// history / TT bonuses are still applied in `Searcher::move_score`.
    ///
    /// # Note on master's "score-negation" bug (Diff 17)
    ///
    /// Master `src/movepick.cpp:152-154` runs after the per-move scoring
    /// loop:
    /// ```cpp
    ///     if (!pos.shouldFocusOnBlockingPaths()) {
    ///         cur->value = -cur->value;
    ///     }
    /// ```
    /// At that point `cur` already equals `endMoves` (the for-loop
    /// post-incremented past the last entry), so the negation lands on
    /// the one-past-end placeholder slot rather than reversing every
    /// move's value.  This is a master bug noted in
    /// SEARCH_DIFF_REPORT.md (Diff 4.2) -- effectively master never
    /// reverses the score, identical to the Rust port (which simply
    /// returns the positive score here).  No code change needed; this
    /// comment documents the alignment so future readers do not
    /// reintroduce a literal port of the buggy negation.
    #[inline]
    fn move_order_bias_ctx(
        wb: &Self::Workbench,
        action: Action,
        ctx: &tgf_core::MoveOrderContext,
    ) -> i32 {
        let to = action.to_node as usize;
        if to >= 24 {
            return 0;
        }
        let state = &wb.state;
        let options = &wb.rules.options;
        let kind = action.kind_tag;

        if kind == MillActionKind::Remove as i16 {
            return remove_move_score(state, options, to);
        }

        if kind != MillActionKind::Place as i16 && kind != MillActionKind::Move as i16 {
            return 0;
        }

        let side = state.side_to_move;
        let opponent = side ^ 1;
        let from = if kind == MillActionKind::Move as i16 {
            Some(action.from_node as usize)
        } else {
            None
        };

        let our_mills = potential_mills_count_at(state, options, to, side, from) as i32;
        let mut score = 0_i32;
        if our_mills > 0 {
            score += RATING_ONE_MILL * our_mills;
        } else if state.phase == MillPhase::Placing && !options.may_move_in_placing_phase {
            let their_mills = potential_mills_count_at(state, options, to, opponent, from) as i32;
            score += RATING_BLOCK_ONE_MILL * their_mills;
        } else if state.phase == MillPhase::Moving
            || (state.phase == MillPhase::Placing && options.may_move_in_placing_phase)
        {
            let their_mills = potential_mills_count_at(state, options, to, opponent, from) as i32;
            if their_mills > 0 {
                let (_, theirs, _) = surrounded_pieces_count(state, options, to);
                let parity_match = if to.is_multiple_of(2) {
                    theirs == 3
                } else {
                    theirs == 2
                };
                if parity_match {
                    score += RATING_BLOCK_ONE_MILL * their_mills;
                }
            }
        }

        if state.phase == MillPhase::Placing
            && side == 1
            && state.board.iter().filter(|&&p| p == 2).count() < 2
            && (options.has_diagonal_lines || ctx.algorithm == tgf_core::MoveOrderAlgorithm::Mcts)
            && is_star_square(options, to)
        {
            score += RATING_STAR_SQUARE;
        }

        score
    }

    /// Mill terminal-score for the searcher.  Mirrors master
    /// `Search::search` (src/search.cpp:142-151) and
    /// `Search::qsearch` (src/search.cpp:60-64), both of which take
    /// `Eval::evaluate(*pos)` and add `+depth` for positive scores
    /// (winning side, prefer faster wins) or subtract `depth` for
    /// negative scores (losing side, prefer slower losses).
    ///
    /// Diff 8 alignment: the Rust mate-distance direction matches
    /// master's `eval += depth` / `eval -= depth` exactly because
    /// both branches accumulate `+distance` toward the absolute value
    /// (Rust's winner-perspective branch returns +MATE+distance and
    /// master's positive eval becomes positive_eval+depth; the loser-
    /// perspective branch returns -MATE-distance which equals
    /// negative_eval-depth in master).  Verified against
    /// SEARCH_DIFF_REPORT.md.
    #[inline]
    fn terminal_score(wb: &Self::Workbench, perspective: i8, depth: i32) -> Option<i32> {
        if wb.state.phase != MillPhase::GameOver {
            return None;
        }
        if wb.state.winner == 2 {
            return Some(0);
        }
        let distance = depth.max(0);
        if wb.state.winner == perspective {
            Some(MILL_TERMINAL_WIN_SCORE + distance)
        } else {
            Some(-MILL_TERMINAL_WIN_SCORE - distance)
        }
    }

    // Mill does NOT override `root_short_circuit_draw` (default `None`).
    //
    // Master `SearchEngine::executeSearch` (src/search_engine.cpp:432-453)
    // emits a "draw" bestmove string before iterative deepening when
    //   posKeyHistory.size() >= rule.nMoveRule    -> return 50
    //   is_three_endgame && posKeyHistory >= endgameNMoveRule -> return 10
    //   threefoldRepetitionRule && has_game_cycle() -> return 3
    // so the UI sees an immediate draw.
    //
    // Mill on the Rust side reaches the same end state through a
    // different but equivalent path:
    //   * `MillRules::apply` -> `bump_ply_since_capture` ->
    //     `maybe_draw_by_n_move_rule` flips `phase = GameOver` and
    //     `winner = 2` (draw) the moment the threshold fires;
    //   * `MillRules::set_from_fen` runs `check_if_game_is_over` after
    //     parsing so an imported FEN past the threshold also lands in
    //     GameOver;
    //   * `MillRules::apply` likewise marks the threefold-repetition
    //     terminal via `push_key_and_check_threefold` (see
    //     `rules/transitions.rs`).
    //
    // The searcher's `terminal_score` then sees GameOver / winner==2
    // and returns score 0 without entering the search loop, which is
    // observationally identical to master's "return draw bestmove"
    // path.  Adding a Mill-side override of `root_short_circuit_draw`
    // would only produce a redundant detection at the same boundary.
}
