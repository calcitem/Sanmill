// SPDX-License-Identifier: GPL-3.0-or-later
// Transitional C++ facade used by the Rust cxx bridge.

#include "tgf-legacy-cxx/cpp/legacy_engine_bridge.h"

#include <mutex>
#include <sstream>
#include <string>

#include "bitboard.h"
#include "engine_commands.h"
#include "mills.h"
#include "movegen.h"
#include "option.h"
#include "rule.h"
#include "search.h"
#include "uci.h"

namespace {

std::once_flag g_initOnce;

std::string to_string(rust::Str s)
{
    return std::string(s.data(), s.size());
}

void initialise_position(Position &pos, int32_t ruleIdx)
{
    set_rule(ruleIdx);
    Mills::adjacent_squares_init();
    Mills::mill_table_init();
    EngineCommands::init_start_fen();
    pos.set(EngineCommands::StartFEN);
    pos.start();
}

} // namespace

void legacy_initialize_once()
{
    std::call_once(g_initOnce, [] {
        UCI::init(Options);
        Bitboards::init();
        Position::init();
        gameOptions.setShufflingEnabled(false);
        Search::clear();
    });
}

std::unique_ptr<LegacyPosition> legacy_new_position(int32_t rule_idx)
{
    legacy_initialize_once();
    auto handle = std::make_unique<LegacyPosition>();
    initialise_position(handle->pos, rule_idx);
    return handle;
}

rust::String legacy_position_fen(const LegacyPosition &pos)
{
    return rust::String(pos.pos.fen());
}

bool legacy_position_apply_uci(LegacyPosition &pos, rust::Str move_uci)
{
    const std::string move = to_string(move_uci);
    return pos.pos.command(move.c_str());
}

rust::String legacy_position_legal_actions(const LegacyPosition &pos)
{
    std::ostringstream out;
    Position &mutablePos = const_cast<Position &>(pos.pos);
    for (const auto &m : MoveList<LEGAL>(mutablePos)) {
        out << UCI::move(m) << '\n';
    }
    return rust::String(out.str());
}

int32_t legacy_position_phase(const LegacyPosition &pos)
{
    return static_cast<int32_t>(pos.pos.get_phase());
}

int32_t legacy_position_side_to_move(const LegacyPosition &pos)
{
    return static_cast<int32_t>(pos.pos.side_to_move());
}
