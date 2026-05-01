// SPDX-License-Identifier: GPL-3.0-or-later
// Transitional C++ facade used by the Rust cxx bridge.

#include "tgf-legacy-cxx/cpp/legacy_engine_bridge.h"

#include <cassert>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "bitboard.h"
#include "mills.h"
#include "movegen.h"
#include "option.h"
#include "rule.h"
#include "stack.h"
#include "uci.h"

std::vector<Key> posKeyHistory;

namespace UCI {

std::string square(Square s)
{
    static const char *squareToStandard[SQUARE_EXT_NB] = {
        "",   "",   "",   "",   "",   "",   "",   "",
        "d5", "e5", "e4", "e3", "d3", "c3", "c4", "c5",
        "d6", "f6", "f4", "f2", "d2", "b2", "b4", "b6",
        "d7", "g7", "g4", "g1", "d1", "a1", "a4", "a7",
        "",   "",   "",   "",   "",   "",   "",   ""};
    return squareToStandard[s];
}

std::string move(Move m)
{
    if (m == MOVE_NONE) {
        return "none";
    }

    if (m == MOVE_NULL) {
        return "0000";
    }

    const Square to = to_sq(m);
    const std::string toStr = square(to);

    if (m < 0) {
        return "x" + toStr;
    }
    if (m & 0x7f00) {
        const Square from = from_sq(m);
        return square(from) + "-" + toStr;
    }
    return toStr;
}

Move to_move(Position *pos, const std::string &str)
{
    for (const auto &m : MoveList<LEGAL>(*pos)) {
        if (str == move(m)) {
            return m;
        }
    }
    return MOVE_NONE;
}

} // namespace UCI

namespace {

std::once_flag g_initOnce;

std::string to_string(rust::Str s)
{
    return std::string(s.data(), s.size());
}

const char *start_fen_for_piece_count()
{
    switch (rule.pieceCount) {
    case 9:
        return "********/********/******** w p p 0 9 0 9 0 0 0 0 0 0 0 0 1";
    case 10:
        return "********/********/******** w p p 0 10 0 10 0 0 0 0 0 0 0 0 1";
    case 11:
        return "********/********/******** w p p 0 11 0 11 0 0 0 0 0 0 0 0 1";
    case 12:
        return "********/********/******** w p p 0 12 0 12 0 0 0 0 0 0 0 0 1";
    default:
        assert(false && "unsupported Mill piece count");
        return "";
    }
}

void initialise_position(Position &pos, int32_t ruleIdx)
{
    set_rule(ruleIdx);
    Mills::adjacent_squares_init();
    Mills::mill_table_init();
    pos.set(start_fen_for_piece_count());
    pos.start();
}

} // namespace

void legacy_initialize_once()
{
    std::call_once(g_initOnce, [] {
        Bitboards::init();
        Position::init();
        gameOptions.setShufflingEnabled(false);
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
    // Once the game is over the C++ MoveList<LEGAL> still generates the
    // moves that *would* have been legal at the previous ply.  The Rust
    // facade promises an empty set for terminal positions, so short-
    // circuit here to keep the two engines in lock-step.
    if (pos.pos.get_phase() == Phase::gameOver) {
        return rust::String("");
    }
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

bool legacy_get_shuffling_enabled()
{
    return gameOptions.getShufflingEnabled();
}
