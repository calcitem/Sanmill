// SPDX-License-Identifier: GPL-3.0-or-later

#include "perfect_trap_db.h"

#include "perfect_common.h"     // mask24
#include "perfect_game_state.h" // GameState
// no additional STL includes required

#include <cstdio>
#include <cstring>
#include <filesystem>

namespace {

// TrapDB on-disk format:
// - 8 bytes magic: "TRAPDB2\0"
// - 4 bytes little-endian uint32: record_count
// - records[record_count]:
//   struct TrapRecord {
//     uint32 whiteBits;  // 24-bit white piece positions
//     uint32 blackBits;  // 24-bit black piece positions
//     uint8  side;       // side to move: 0=white, 1=black
//     uint8  WF;         // white stones remaining to place (0..9)
//     uint8  BF;         // black stones remaining to place (0..9)
//     uint8  mask;       // TrapMask bitset (SelfMillLoss | BlockMillLoss)
//     int8   wdl;        // WDL value: -1=loss, 0=draw, +1=win
//     int16  steps;      // Distance to Mate/Draw, -1=unknown
//   }

constexpr const char *kMagic = "TRAPDB2\0"; // 8 bytes including NUL

struct TrapRecDisk
{
    uint32_t wBits;
    uint32_t bBits;
    uint8_t side;
    uint8_t WF;
    uint8_t BF;
    uint8_t mask;
};

inline bool fread_exact(void *dst, size_t size, FILE *f)
{
    return std::fread(dst, 1, size, f) == size;
}

} // namespace

namespace TrapDB {

std::unordered_map<uint64_t, uint8_t> s_traps;
std::unordered_map<uint64_t, int8_t> s_trap_wdl;
std::unordered_map<uint64_t, int16_t> s_trap_steps;
/*
uint64_t trap_make_key(uint32_t whiteBits, uint32_t blackBits, uint8_t
sideToMove, uint8_t whiteFree, uint8_t blackFree)
{
    uint64_t key = 0;
    key |= (uint64_t)(whiteBits & (uint32_t)mask24);
    key |= (uint64_t)(blackBits & (uint32_t)mask24) << 24;
    key |= (uint64_t)(sideToMove & 1) << 48;
    key |= (uint64_t)(whiteFree & 31) << 49;
    key |= (uint64_t)(blackFree & 31) << 54;
    return key;
}
*/
bool load_from_directory(const std::string &dirPath)
{
    s_traps.clear();
    s_trap_wdl.clear();
    s_trap_steps.clear();

    std::filesystem::path p(dirPath);
#ifdef _WIN32
    p /= "std_traps.sec2";
#else
    p /= "std_traps.sec2";
#endif

    FILE *f = nullptr;
    if (FOPEN(&f, p.string().c_str(), "rb") != 0 || !f) {
        return false;
    }

    char magic[8];
    if (!fread_exact(magic, sizeof(magic), f)) {
        fclose(f);
        return false;
    }
    if (std::memcmp(magic, kMagic, sizeof(magic)) != 0) {
        fclose(f);
        return false;
    }

    uint32_t count = 0;
    if (!fread_exact(&count, sizeof(count), f)) {
        fclose(f);
        return false;
    }

    // Read trap records in new format: TrapRecDisk + WDL + steps
    for (uint32_t i = 0; i < count; ++i) {
        TrapRecDisk rec {};
        if (!fread_exact(&rec, sizeof(rec), f)) {
            fclose(f);
            s_traps.clear();
            s_trap_wdl.clear();
            s_trap_steps.clear();
            return false;
        }

        // Read WDL field (required in new format)
        int8_t wdl = 0;
        if (!fread_exact(&wdl, sizeof(wdl), f)) {
            fclose(f);
            s_traps.clear();
            s_trap_wdl.clear();
            s_trap_steps.clear();
            return false;
        }

        // Read steps field (required in new format)
        int16_t steps = -1;
        if (!fread_exact(&steps, sizeof(steps), f)) {
            fclose(f);
            s_traps.clear();
            s_trap_wdl.clear();
            s_trap_steps.clear();
            return false;
        }

        const uint64_t key = trap_make_key(rec.wBits, rec.bBits, rec.side,
                                           rec.WF, rec.BF);

        // Store trap data (merge if duplicate keys exist)
        auto trap_it = s_traps.find(key);
        if (trap_it == s_traps.end()) {
            s_traps.emplace(key, rec.mask);
            s_trap_wdl.emplace(key, wdl);
            s_trap_steps.emplace(key, steps);
        } else {
            // Merge masks and prefer stronger WDL
            trap_it->second |= rec.mask;
            if (wdl > s_trap_wdl[key]) {
                s_trap_wdl[key] = wdl;
                s_trap_steps[key] = steps;
            }
        }
    }

    fclose(f);
    return !s_traps.empty();
}

bool has_trap_db()
{
    return !s_traps.empty();
}
/*
uint8_t get_trap_mask(const GameState &s)
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
    const uint64_t key = make_key(wBits, bBits, stm, WF, BF);
    auto it = s_traps.find(key);
    if (it == s_traps.end())
        return Trap_None;
    return it->second;
}
*/
size_t size()
{
    return s_traps.size();
}

} // namespace TrapDB
