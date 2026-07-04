// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

//! Thin re-export of the shared NMM_LLM `human_db.sqlite` codec.
//!
//! The actual `state_key` <-> FEN conversion lives in
//! `tgf_mill::human_db_codec` so the FRB Human Database lookup, the mining
//! frontier seeding, and the patch packer's behavior weighting all share
//! one coordinate-convention implementation.

pub(crate) use tgf_mill::human_db_codec::{fen_from_state_key, stable_hash};
