// SPDX-License-Identifier: GPL-3.0-or-later

#include "perfect_c_api.h"

#include "perfect_api.h"
#include "perfect_adaptor.h"
#include "perfect_common.h"
#include "perfect_errors.h"
#include "perfect_game_state.h"
#include "perfect_wrappers.h"
#include "perfect_sector.h"
#include "perfect_hash.h"
#include "option.h"

#include <cstring>
#include <map>

// We keep a tiny init flag to avoid double init/deinit in the same process
static bool g_pd_inited = false;

extern "C" {

PD_API int pd_init_std(const char *db_path)
{
    using namespace PerfectErrors;
    clearError();

    if (!db_path || !*db_path)
        return 0;

    // Configure rule variant to std (9 pieces)
    // perfect_init() + MalomSolutionAccess::initialize_if_needed() will read
    // globals but we also ensure gameOptions are set
    gameOptions.setPerfectDatabasePath(std::string(db_path));
    gameOptions.setUsePerfectDatabase(true);

    // perfect_init() will set up variant by rule.pieceCount
    // Ensure rule is std
    set_rule(0); // RULES[0] is Nine Men's Morris

    // Initialize internal DB structures through MalomSolutionAccess
    if (!MalomSolutionAccess::initialize_if_needed())
        return 0;

    g_pd_inited = true;
    return 1;
}

PD_API void pd_deinit()
{
    if (!g_pd_inited)
        return;
    MalomSolutionAccess::deinitialize_if_needed();
    g_pd_inited = false;
}

static inline int to_wdl(Value v)
{
    if (v == VALUE_DRAW || v == VALUE_ZERO)
        return 0;
    if (v > 0)
        return 1;
    if (v < 0)
        return -1;
    return 0;
}

PD_API int pd_evaluate(int whiteBits, int blackBits, int whiteStonesToPlace,
                       int blackStonesToPlace, int playerToMove,
                       int onlyStoneTaking, int *outWdl, int *outSteps)
{
    using namespace PerfectErrors;
    clearError();

    if (!g_pd_inited)
        return 0;

    if (!outWdl || !outSteps)
        return 0;

    PerfectEvaluation r = MalomSolutionAccess::get_detailed_evaluation(
        whiteBits, blackBits, whiteStonesToPlace, blackStonesToPlace,
        playerToMove, onlyStoneTaking != 0);

    if (!r.isValid)
        return 0;

    *outWdl = to_wdl(r.value);
    *outSteps = r.stepCount;
    return 1;
}

PD_API int pd_best_move(int whiteBits, int blackBits, int whiteStonesToPlace,
                        int blackStonesToPlace, int playerToMove,
                        int onlyStoneTaking, char *outBuf, int outBufLen)
{
    using namespace PerfectErrors;
    clearError();
    if (!g_pd_inited)
        return 0;
    if (!outBuf || outBufLen <= 4)
        return 0;

    // Ask C++ API for a best move bitboard
    Value v = VALUE_UNKNOWN;
    Move ref = MOVE_NONE;
    int bb = MalomSolutionAccess::get_best_move(
        whiteBits, blackBits, whiteStonesToPlace, blackStonesToPlace,
        playerToMove, onlyStoneTaking != 0, v, ref);
    if (bb == 0 && hasError())
        return 0;

    auto popcnt = [](unsigned int x) {
        unsigned int c = 0;
        while (x) {
            x &= (x - 1);
            ++c;
        }
        return (int)c;
    };

    const int cnt = popcnt((unsigned int)bb);
    const unsigned int us = (playerToMove == 0 ? (unsigned int)whiteBits :
                                                 (unsigned int)blackBits);
    const unsigned int them = (playerToMove == 0 ? (unsigned int)blackBits :
                                                   (unsigned int)whiteBits);

    int fromIdx = -1, toIdx = -1, remIdx = -1;
    for (int i = 0; i < 24; ++i) {
        unsigned int mask = 1U << i;
        if (!(bb & mask))
            continue;
        bool usHas = (us & mask) != 0;
        bool themHas = (them & mask) != 0;
        bool emptyBefore = !usHas && !themHas;
        if (cnt == 1) {
            if (emptyBefore) {
                toIdx = i;
            } else if (themHas) {
                remIdx = i;
            } else if (usHas) {
                // should not happen for single change
                fromIdx = i;
            }
        } else {
            if (usHas)
                fromIdx = i;
            else if (emptyBefore)
                toIdx = i;
            else if (themHas)
                remIdx = i;
        }
    }

    auto idx_to_token = [](int idx) -> std::string {
        // Map perfect index -> Square -> token as in UCI::square
        const char *map[40] = {"",   "",   "",   "",   "",   "",   "",   "",
                               "d5", "e5", "e4", "e3", "d3", "c3", "c4", "c5",
                               "d6", "f6", "f4", "f2", "d2", "b2", "b4", "b6",
                               "d7", "g7", "g4", "g1", "d1", "a1", "a4", "a7",
                               "",   "",   "",   "",   "",   "",   "",   ""};
        auto sq = from_perfect_square((uint32_t)idx);
        if (sq < 0 || sq >= 40)
            return std::string();
        return std::string(map[sq]);
    };

    std::string token;
    if (cnt == 1) {
        if (toIdx >= 0) {
            token = idx_to_token(toIdx);
        } else if (remIdx >= 0) {
            token = std::string("x") + idx_to_token(remIdx);
        }
    } else if (cnt == 2) {
        if (fromIdx >= 0 && toIdx >= 0 && remIdx < 0) {
            token = idx_to_token(fromIdx) + std::string("-") +
                    idx_to_token(toIdx);
        } else if (fromIdx < 0 && toIdx >= 0 && remIdx >= 0) {
            // place + remove -> return place only
            token = idx_to_token(toIdx);
        }
    } else if (cnt == 3) {
        // move + remove -> return move token
        if (fromIdx >= 0 && toIdx >= 0) {
            token = idx_to_token(fromIdx) + std::string("-") +
                    idx_to_token(toIdx);
        }
    }

    if (token.empty())
        return 0;
    if ((int)token.size() + 1 > outBufLen)
        return 0;
    std::strncpy(outBuf, token.c_str(), outBufLen);
    outBuf[outBufLen - 1] = '\0';
    return 1;
}

// Structure for maintaining sector iteration state
struct SectorIteratorState
{
    Sector *sector;
    Hash *hash;
    int current_index;
    int total_count;
    Id sector_id;
    bool is_valid;

    SectorIteratorState()
        : sector(nullptr)
        , hash(nullptr)
        , current_index(0)
        , total_count(0)
        , is_valid(false)
    { }
};

// Global table for managing sector iterator handles
static std::map<int, SectorIteratorState> g_sector_handles;
static int g_next_handle_id = 1;

PD_API int pd_open_sector(int W, int B, int WF, int BF)
{
    using namespace PerfectErrors;
    clearError();

    if (!g_pd_inited)
        return 0;

    // Create sector ID
    Id sector_id;
    sector_id.W = W;
    sector_id.B = B;
    sector_id.WF = WF;
    sector_id.BF = BF;

    // Get or create sector
    Sector *sector = sectors(sector_id);
    if (!sector) {
        // Try to create new sector
        sector = new Sector(sector_id);
        if (!sector) {
            return 0;
        }
        sectors(sector_id) = sector;
    }

    // Ensure hash is allocated
    if (!sector->hash) {
        sector->allocate_hash();
    }

    if (!sector->hash || !sector->hash->is_initialized()) {
        return 0;
    }

    // Create iterator state
    SectorIteratorState state;
    state.sector = sector;
    state.hash = sector->hash;
    state.current_index = 0;
    state.total_count = sector->hash->hash_count;
    state.sector_id = sector_id;
    state.is_valid = true;

    // Assign handle
    int handle = g_next_handle_id++;
    g_sector_handles[handle] = state;

    return handle;
}

PD_API int pd_close_sector(int handle)
{
    auto it = g_sector_handles.find(handle);
    if (it != g_sector_handles.end()) {
        g_sector_handles.erase(it);
        return 1; // Success
    }
    return 0; // Handle not found
}

PD_API int pd_sector_count(int handle)
{
    auto it = g_sector_handles.find(handle);
    if (it == g_sector_handles.end() || !it->second.is_valid) {
        return 0;
    }
    return it->second.total_count;
}

PD_API int pd_sector_next(int handle, int *outWhiteBits, int *outBlackBits,
                          int *outWdl, int *outSteps)
{
    using namespace PerfectErrors;
    clearError();

    auto it = g_sector_handles.find(handle);
    if (it == g_sector_handles.end() || !it->second.is_valid) {
        return 0;
    }

    SectorIteratorState &state = it->second;

    if (!outWhiteBits || !outBlackBits || !outWdl || !outSteps) {
        return 0;
    }

    // Use a loop instead of recursion to avoid stack overflow
    while (state.current_index < state.total_count) {
        // Get the board state from inverse hash
        board b = state.hash->inverse_hash(state.current_index);

        // Check if inverse_hash operation was successful
        // (assuming inverse_hash returns a special value or sets an error flag
        // on error)
        if (!state.hash || state.current_index >= state.total_count) {
            state.current_index++;
            continue;
        }

        // Extract bitboards from board representation (board format: low 24
        // bits = white, high 24 bits = black)
        const uint32_t local_mask24 = 0xFFFFFF;
        int whiteBits = (int)(b & local_mask24);         // Low 24 bits
        int blackBits = (int)((b >> 24) & local_mask24); // High 24 bits

        // Get evaluation from sector (handle symmetry correctly)
        eval_elem_sym2 eval_sym = state.sector->get_eval_inner(
            state.current_index);

        // Handle symmetry cases like in perfect_hash.cpp
        if (eval_sym.cas() != eval_elem_sym2::Sym) {
            // Direct conversion is safe
            eval_elem2 eval(eval_sym);

            // Handle different evaluation types correctly
            if (eval.cas() == eval_elem2::Val) {
                // This is a value (WDL + steps)
                val v = eval.value();

                // Convert to WDL and steps
                *outWdl = 0; // Draw by default
                if (v.key1 > 0) {
                    *outWdl = 1; // Win
                } else if (v.key1 < 0) {
                    *outWdl = -1; // Loss
                }

                *outSteps = v.key2; // Steps to result
            } else {
                // This is a count - not a game result
                // For training purposes, we might want to skip count
                // entries or handle them differently
                *outWdl = 0;   // Neutral
                *outSteps = 0; // No steps info
            }

            // Found a valid non-symmetric position
            *outWhiteBits = whiteBits;
            *outBlackBits = blackBits;

            // Advance to next position for next call
            state.current_index++;

            return 1; // Success
        } else {
            // This position has symmetry - skip it and continue with the
            // loop Instead of recursion, we continue the loop
            state.current_index++;
            continue; // Skip this symmetric position and try the next one
        }
    }

    // Reached end of iteration
    return 0;
}
}
