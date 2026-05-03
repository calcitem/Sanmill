// SPDX-License-Identifier: GPL-3.0-or-later
// Mill-specific notation adapter for the FRB layer.
//
// The implementation lives in `tgf_mill::MillUciCodec`; this file
// keeps the `action_to_uci_str` helper as the FRB-side entry point so
// the EngineEvent factory does not depend on a `&dyn NotationCodec`
// at every call site.

use tgf_core::Action;
use tgf_mill::MillUciCodec;

/// Convert a Mill `Action` to its UCI move string.  Returns an empty
/// string for `Action::NONE` or any unknown kind so the caller can
/// splice the result directly into log messages without branching.
pub(crate) fn action_to_uci_str(action: Action) -> String {
    MillUciCodec::encode_action(action)
}
