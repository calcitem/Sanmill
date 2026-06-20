// SPDX-License-Identifier: GPL-3.0-or-later
// Mill-specific FRB adapter helpers.
//
// The FRB-public functions (`tgf_kernel_create_mill`, `native_mill_*`,
// the search event streams, setup-position editors, FEN import/export,
// etc.) still live under `crate::api::*` so the generated Dart files
// stay backwards compatible.  Everything that is NOT part of the FRB
// surface — search-thread spawn helpers, action ↔ UCI codecs, runtime
// configuration types passed across the FRB layer, and per-handle
// extras storage — lives here so the `crate::api::*` modules carry no
// Mill-specific implementation details.

pub(crate) mod action_codec;
pub(crate) mod human_db;
pub(crate) mod perfect;
pub(crate) mod search;
pub(crate) mod variant_extras;
