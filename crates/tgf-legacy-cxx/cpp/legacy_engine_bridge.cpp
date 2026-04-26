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
#include "stack.h"
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

void legacy_position_set_fen(LegacyPosition &pos, rust::Str fen)
{
    const std::string fenStr = to_string(fen);
    pos.pos.set(fenStr);
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

namespace {

uint64_t legacy_perft_impl(Position &pos, int32_t depth)
{
    if (depth <= 0 || pos.get_phase() == Phase::gameOver) {
        return 1;
    }
    MoveList<LEGAL> ml(pos);
    if (ml.size() == 0) {
        return 1;
    }
    uint64_t nodes = 0;
    Sanmill::Stack<Position> ss;
    for (const auto &m : ml) {
        ss.push(pos);
        pos.do_move(m);
        nodes += legacy_perft_impl(pos, depth - 1);
        pos.undo_move(ss);
    }
    return nodes;
}

} // namespace

uint64_t legacy_position_perft(const LegacyPosition &pos, int32_t depth)
{
    Position copy = pos.pos;
    return legacy_perft_impl(copy, depth);
}
