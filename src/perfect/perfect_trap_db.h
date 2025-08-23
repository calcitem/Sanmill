// SPDX-License-Identifier: GPL-3.0-or-later
// Trap DB: lightweight database to avoid common pitfalls without full sectors

#ifndef PERFECT_TRAP_DB_H_INCLUDED
#define PERFECT_TRAP_DB_H_INCLUDED

#include <cstdint>
#include <string>
#include <unordered_map>

#include "perfect_game_state.h"
#include "perfect_common.h"

namespace TrapDB {

extern std::unordered_map<uint64_t, uint8_t> s_traps;
// For trap-only independence, also store theoretical WDL for the side-to-move
// in the trapped position: -1 = loss, 0 = draw, +1 = win.
extern std::unordered_map<uint64_t, int8_t> s_trap_wdl;
// Store the number of steps to reach the WDL result (Distance to Mate/Draw).
// Positive values indicate steps to win/draw, negative values indicate steps to
// loss. 0 or unavailable steps are stored as -1 (unknown).
extern std::unordered_map<uint64_t, int16_t> s_trap_steps;

// Bitmask flags for trap types
enum TrapMask : uint8_t {
    Trap_None = 0,
    Trap_SelfMillLoss = 1 << 0, // Forming a mill here loses; alternatives
                                // draw/win
    Trap_BlockMillLoss = 1 << 1 // Blocking opponent's mill here loses;
                                // alternatives draw/win
};

// Load trap database from given directory. Looks for file named
// "std_traps.sec2". Returns true on success.
bool load_from_directory(const std::string &dirPath);

// Returns true if trap DB is loaded and non-empty.
bool has_trap_db();

// Utility to build a compact 64-bit key for maps (also used by builder).
// Layout (LSB..MSB):
//  0..23  whiteBits (24 bits)
// 24..47  blackBits (24 bits)
//    48   sideToMove (0=white, 1=black)
// 49..53  whiteFree (WF, 0..31)
// 54..58  blackFree (BF, 0..31)
inline uint64_t trap_make_key(uint32_t whiteBits, uint32_t blackBits,
                              uint8_t sideToMove, uint8_t whiteFree,
                              uint8_t blackFree)
{
    uint64_t key = 0;
    key |= (uint64_t)(whiteBits & (uint32_t)mask24);
    key |= (uint64_t)(blackBits & (uint32_t)mask24) << 24;
    key |= (uint64_t)(sideToMove & 1) << 48;
    key |= (uint64_t)(whiteFree & 31) << 49;
    key |= (uint64_t)(blackFree & 31) << 54;
    return key;
}

// Query trap mask for a position key computed from GameState fields.
// Returns Trap_None if not present.
inline uint8_t get_trap_mask(const GameState &s)
{
    // Build white/black 24-bit bitboards from GameState
    uint32_t wBits = 0, bBits = 0;
    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 0) {
            wBits |= (1u << i);
        } else if (s.board[i] == 1) {
            bBits |= (1u << i);
        }
    }

    // For standard 9-men's morris trap DB, WF/BF are derived from set counts.
    const int maxK = 9;
    int wf_tmp = maxK - s.setStoneCount[0];
    int bf_tmp = maxK - s.setStoneCount[1];
    if (wf_tmp < 0)
        wf_tmp = 0;
    if (bf_tmp < 0)
        bf_tmp = 0;
    const uint8_t WF = static_cast<uint8_t>(s.phase == 2 ? 0 : wf_tmp);
    const uint8_t BF = static_cast<uint8_t>(s.phase == 2 ? 0 : bf_tmp);
    const uint8_t stm = static_cast<uint8_t>(s.sideToMove & 1);
    const uint64_t key = trap_make_key(wBits, bBits, stm, WF, BF);
    auto it = s_traps.find(key);
    if (it == s_traps.end())
        return Trap_None;
    return it->second;
}

// Query WDL for the side-to-move at this position: -1=loss, 0=draw, +1=win.
// Returns 0 if unknown (treated as draw preference-wise).
inline int8_t get_trap_wdl(const GameState &s)
{
    uint32_t wBits = 0, bBits = 0;
    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 0) {
            wBits |= (1u << i);
        } else if (s.board[i] == 1) {
            bBits |= (1u << i);
        }
    }
    const int maxK = 9;
    int wf_tmp = maxK - s.setStoneCount[0];
    int bf_tmp = maxK - s.setStoneCount[1];
    if (wf_tmp < 0)
        wf_tmp = 0;
    if (bf_tmp < 0)
        bf_tmp = 0;
    const uint8_t WF = static_cast<uint8_t>(s.phase == 2 ? 0 : wf_tmp);
    const uint8_t BF = static_cast<uint8_t>(s.phase == 2 ? 0 : bf_tmp);
    const uint8_t stm = static_cast<uint8_t>(s.sideToMove & 1);
    const uint64_t key = trap_make_key(wBits, bBits, stm, WF, BF);
    auto it = s_trap_wdl.find(key);
    if (it == s_trap_wdl.end())
        return 0;
    return it->second;
}

// Query step count for the side-to-move at this position (Distance to
// Mate/Draw). Returns -1 if unknown or not available.
inline int16_t get_trap_steps(const GameState &s)
{
    uint32_t wBits = 0, bBits = 0;
    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 0) {
            wBits |= (1u << i);
        } else if (s.board[i] == 1) {
            bBits |= (1u << i);
        }
    }
    const int maxK = 9;
    int wf_tmp = maxK - s.setStoneCount[0];
    int bf_tmp = maxK - s.setStoneCount[1];
    if (wf_tmp < 0)
        wf_tmp = 0;
    if (bf_tmp < 0)
        bf_tmp = 0;
    const uint8_t WF = static_cast<uint8_t>(s.phase == 2 ? 0 : wf_tmp);
    const uint8_t BF = static_cast<uint8_t>(s.phase == 2 ? 0 : bf_tmp);
    const uint8_t stm = static_cast<uint8_t>(s.sideToMove & 1);
    const uint64_t key = trap_make_key(wBits, bBits, stm, WF, BF);
    auto it = s_trap_steps.find(key);
    if (it == s_trap_steps.end())
        return -1;
    return it->second;
}

// Expose internal map size for diagnostics.
size_t size();

} // namespace TrapDB

// Build trap DB from full perfect DB located at secValPath directory
// Returns true on success
bool build_trap_db_to_file(const std::string &outFile);

#endif // PERFECT_TRAP_DB_H_INCLUDED
