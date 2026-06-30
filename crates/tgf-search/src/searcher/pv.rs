// SPDX-License-Identifier: AGPL-3.0-or-later
// Principal-variation reconstruction from opt-in TT move hints.

use tgf_core::{Action, Game, SearchActionList, Workbench};

use super::Searcher;

impl<G: Game> Searcher<G> {
    /// Reconstruct a principal variation by following legal TT moves from
    /// the current workbench position.
    ///
    /// This is intentionally read-only with respect to the searcher's TT and
    /// only works when the searcher was built with TT move storage enabled.
    /// Default production searchers keep that storage disabled, so ordinary
    /// search performance and event shape are unchanged.
    pub fn principal_variation(&self, wb: &mut G::Workbench, max_plies: usize) -> Vec<Action> {
        if max_plies == 0 || !self.tt.tt_move_enabled() {
            return Vec::new();
        }

        let mut line = Vec::<Action>::new();
        let mut seen_keys = Vec::<u64>::new();
        for _ in 0..max_plies {
            if wb.is_terminal() {
                break;
            }
            let key = wb.key();
            if key == 0 || seen_keys.contains(&key) {
                break;
            }
            seen_keys.push(key);

            let Some(action) = self
                .tt
                .probe_tt_move_at_age(key, self.tt_age)
                .and_then(G::unpack_tt_action)
            else {
                break;
            };

            let mut legal = SearchActionList::new();
            G::generate_legal_ctx(wb, &mut legal, &self.options.move_order_context);
            if !legal.contains(&action) {
                break;
            }

            wb.do_move(action);
            line.push(action);
        }

        for _ in 0..line.len() {
            wb.undo_move();
        }
        line
    }
}
