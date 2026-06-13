// SPDX-License-Identifier: GPL-3.0-or-later
// Perfect-database lookup for Mill positions (Nine Men's Morris std only).

use tgf_core::Action;
use tgf_mill::{MillRules, MillVariantOptions};

use crate::games::mill::action_codec::action_to_uci_str;

/// Query the vendored perfect database for a legal action matching the
/// current position.  Returns `None` when the DB is unavailable, the
/// variant is not std 9-piece, or no legal action matches the DB token.
///
/// The board-to-bitboard encoding and node-to-perfect-index mapping live in
/// `perfect_db::best_move_token_for_state`; this wrapper only matches the
/// returned token against the caller's legal action list via the shared
/// `tgf_mill::MillUciCodec`.
pub(crate) fn try_perfect_best_action(
    snapshot: &tgf_core::GameStateSnapshot,
    options: &MillVariantOptions,
    legal: &[Action],
) -> Option<Action> {
    let state = MillRules::decode_snapshot(*snapshot);
    let token = perfect_db::best_move_token_for_state(&state, options, snapshot.side_to_move)?;

    legal
        .iter()
        .copied()
        .find(|action| action_to_uci_str(*action) == token)
}
