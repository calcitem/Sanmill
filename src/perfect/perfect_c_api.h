// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// Ensure project global config is visible as required
#include "../../include/config.h"

#ifdef _WIN32
#  define PD_API __declspec(dllexport)
#else
#  define PD_API
#endif

extern "C" {

// Initialize the standard Nine Men's Perfect DB (std, 9 pieces)
// db_path: directory containing std_*.sec2 and std.secval
// Returns 1 for success, 0 for failure
PD_API int pd_init_std(const char* db_path);

// Deinitialize and release resources
PD_API void pd_deinit();

// Evaluate a position using Perfect DB
// Input:
// - whiteBits, blackBits: 24-bit bitboard (bit i corresponds to perfect index i)
// - whiteStonesToPlace, blackStonesToPlace: Number of stones remaining in hand
// - playerToMove: 0 = White moves, 1 = Black moves
// - onlyStoneTaking: Non-zero indicates capturing
// Output:
// - outWdl: 1 = win, 0 = draw, -1 = loss
// - outSteps: Number of steps to reach the result, -1 if unknown
// Returns 1 if successful (database valid), 0 otherwise
PD_API int pd_evaluate(int whiteBits,
                       int blackBits,
                       int whiteStonesToPlace,
                       int blackStonesToPlace,
                       int playerToMove,
                       int onlyStoneTaking,
                       int* outWdl,
                       int* outSteps);

// Query a best move and return an engine-style token string
// Output format: "a1" (place), "a1-a4" (move), "xg7" (remove)
// Returns 1 for success, 0 for failure
PD_API int pd_best_move(int whiteBits,
                        int blackBits,
                        int whiteStonesToPlace,
                        int blackStonesToPlace,
                        int playerToMove,
                        int onlyStoneTaking,
                        char* outBuf,
                        int outBufLen);

}


