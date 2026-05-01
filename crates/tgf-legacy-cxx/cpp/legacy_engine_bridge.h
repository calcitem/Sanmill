// SPDX-License-Identifier: GPL-3.0-or-later
// Transitional C++ facade used by the Rust cxx bridge.
//
// Keep this header deliberately small: it exposes only stable, coarse-grained
// operations needed by Phase 2.  All rule logic remains in the mature C++
// engine.

#pragma once

#include <memory>

#include "rust/cxx.h"
#include "position.h"

struct LegacyPosition
{
    Position pos;
};

void legacy_initialize_once();
std::unique_ptr<LegacyPosition> legacy_new_position(int32_t rule_idx);
rust::String legacy_position_fen(const LegacyPosition &pos);
bool legacy_position_apply_uci(LegacyPosition &pos, rust::Str move_uci);
void legacy_position_set_fen(LegacyPosition &pos, rust::Str fen);
rust::String legacy_position_legal_actions(const LegacyPosition &pos);
int32_t legacy_position_phase(const LegacyPosition &pos);
int32_t legacy_position_side_to_move(const LegacyPosition &pos);

/// Game-neutral perft over the legacy C++ engine.  Counts the number of
/// leaves of the legal-action tree at the given depth: depth 0 returns 1,
/// depth 1 returns the number of immediately legal actions, and deeper
/// levels follow the standard chess perft contract.
uint64_t legacy_position_perft(const LegacyPosition &pos, int32_t depth);

/// Returns the current value of gameOptions.shufflingEnabled.
/// Used by the oracle generator to assert the invariant that shuffling
/// is disabled before any oracle data is collected.
bool legacy_get_shuffling_enabled();
