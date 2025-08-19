// SPDX-License-Identifier: GPL-3.0-or-later

#include "perfect_c_api.h"

#include "perfect_api.h"
#include "perfect_adaptor.h"
#include "perfect_common.h"
#include "perfect_errors.h"
#include "perfect_game_state.h"
#include "perfect_wrappers.h"
#include "option.h"

#include <cstring>

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
}
