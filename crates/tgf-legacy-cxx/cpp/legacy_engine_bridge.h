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
rust::String legacy_position_legal_actions(const LegacyPosition &pos);
int32_t legacy_position_phase(const LegacyPosition &pos);
int32_t legacy_position_side_to_move(const LegacyPosition &pos);
