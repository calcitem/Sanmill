// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023-2025 The Sanmill developers (see AUTHORS file)
//
// See our webpage (and the paper linked from there):
// http://compalg.inf.elte.hu/~ggevay/mills/index.php
//
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include "perfect_api.h"
#include "option.h"
#include "perfect_game_state.h"
#include "perfect_player.h"

#if defined(__APPLE__)
#include <unistd.h>
#else
#include <filesystem>
#endif

extern int perfect_init();

PerfectPlayer *MalomSolutionAccess::perfectPlayer = nullptr;
std::exception *MalomSolutionAccess::lastError = nullptr;

int MalomSolutionAccess::get_best_move(int whiteBitboard, int blackBitboard,
                                       int whiteStonesToPlace,
                                       int blackStonesToPlace, int playerToMove,
                                       bool onlyStoneTaking, Value &value,
                                       const Move &refMove)
{
    initialize_if_needed();

    GameState s;

    const int W = 0;
    const int B = 1;

    if ((whiteBitboard & blackBitboard) != 0) {
        throw std::invalid_argument("whiteBitboard and blackBitboard shouldn't "
                                    "have any overlap");
    }

    for (int i = 0; i < 24; i++) {
        if ((whiteBitboard & (1 << i)) != 0) {
            s.board[i] = W;
            s.stoneCount[W] += 1;
        }
        if ((blackBitboard & (1 << i)) != 0) {
            s.board[i] = B;
            s.stoneCount[B] += 1;
        }
    }

    s.phase = ((whiteStonesToPlace == 0 && blackStonesToPlace == 0) ? 2 : 1);
    must_be_between("whiteStonesToPlace", whiteStonesToPlace, 0, Rules::maxKSZ);
    must_be_between("blackStonesToPlace", blackStonesToPlace, 0, Rules::maxKSZ);
    s.setStoneCount[W] = Rules::maxKSZ - whiteStonesToPlace;
    s.setStoneCount[B] = Rules::maxKSZ - blackStonesToPlace;
    s.kle = onlyStoneTaking;
    must_be_between("playerToMove", playerToMove, 0, 1);
    s.sideToMove = playerToMove;
    s.moveCount = 10;

    if (s.get_future_piece_count(W) > Rules::maxKSZ) {
        throw std::invalid_argument("Number of stones in whiteBitboard + "
                                    "whiteStonesToPlace > " +
                                    std::to_string(Rules::maxKSZ));
    }
    if (s.get_future_piece_count(B) > Rules::maxKSZ) {
        throw std::invalid_argument("Number of stones in blackBitboard + "
                                    "blackStonesToPlace > " +
                                    std::to_string(Rules::maxKSZ));
    }

    std::string errorMsg = s.set_over_and_check_valid_setup();
    if (errorMsg != "") {
        throw std::invalid_argument(errorMsg);
    }
    if (s.over) {
        throw std::invalid_argument("Game is already over.");
    }

    s.lastIrrev = 0;

    int ret = 0;

    try {
        ret = perfectPlayer
                  ->chooseRandom(perfectPlayer->get_good_moves(s, value),
                                 refMove)
                  .toBitBoard();
    } catch (std::out_of_range &) {
        throw std::runtime_error("We don't have a database entry for this "
                                 "position. This can happen either if the "
                                 "database is corrupted (missing files), or "
                                 "sometimes when the position is not reachable "
                                 "from the starting position.");
    }

    // TODO: Considering the performance-critical aspect of our applications,
    // it is advised to reconsider the frequent invocation of
    // deinitialize_if_needed() within each get_best_move call. Such a practice
    // necessitates the re-initialization by initialize_if_needed() at every
    // function start, leading to significant performance overheads. An
    // optimized approach for initialization and deinitialization processes
    // should be explored to mitigate these costs.
    // https://github.com/ggevay/malom/pull/3#discussion_r1349745071
    deinitialize_if_needed();

    return ret;
}

int MalomSolutionAccess::get_best_move_no_exception(
    int whiteBitboard, int blackBitboard, int whiteStonesToPlace,
    int blackStonesToPlace, int playerToMove, bool onlyStoneTaking,
    Value &value, const Move &refMove)
{
    try {
        lastError = nullptr;
        return get_best_move(whiteBitboard, blackBitboard, whiteStonesToPlace,
                             blackStonesToPlace, playerToMove, onlyStoneTaking,
                             value, refMove);
    } catch (std::exception &e) {
        lastError = &e;
        return 0;
    }
}

std::string MalomSolutionAccess::get_last_error()
{
    if (lastError == nullptr) {
        return "No error";
    }
    return lastError->what();
}

void MalomSolutionAccess::initialize_if_needed()
{
    if (perfectPlayer != nullptr) {
        return;
    }

    perfect_init();

    secValPath = gameOptions.getPerfectDatabasePath();

    Rules::init_rules();
    set_variant_stripped();

    if (!Sectors::has_database()) {
        std::string currentPath;

#if defined(__APPLE__)
        char buffer[PATH_MAX];
        if (getcwd(buffer, sizeof(buffer)) != NULL) {
            currentPath = buffer;
        } else {
            currentPath = "Unknown";
        }
#else
        currentPath = std::filesystem::current_path().string();
#endif

        throw std::runtime_error("Database files not found in the current "
                                 "working directory (" +
                                 currentPath + ")");
    }
    perfectPlayer = new PerfectPlayer();
}

void MalomSolutionAccess::deinitialize_if_needed()
{
    if (perfectPlayer == nullptr) {
        return;
    }

    Rules::cleanup_rules();

    delete perfectPlayer;

    perfectPlayer = nullptr;
}

void MalomSolutionAccess::must_be_between(std::string paramName, int value,
                                          int min, int max)
{
    if (value < min || value > max) {
        throw std::out_of_range(paramName + " must be between " +
                                std::to_string(min) + " and " +
                                std::to_string(max));
    }
}

void MalomSolutionAccess::set_variant_stripped()
{
    switch (ruleVariant) {
    case (int)Wrappers::Constants::Variants::std:
        std::memcpy(Rules::millPos, Rules::stdLaskerMillPos,
                    sizeof(Rules::stdLaskerMillPos));
        std::memcpy(Rules::invMillPos, Rules::stdLaskerInvMillPos,
                    sizeof(Rules::stdLaskerInvMillPos));
        std::memcpy(Rules::boardGraph, Rules::stdLaskerBoardGraph,
                    sizeof(Rules::stdLaskerBoardGraph));
        std::memcpy(Rules::aLBoardGraph, Rules::stdLaskerALBoardGraph,
                    sizeof(Rules::stdLaskerALBoardGraph));
        Rules::maxKSZ = 9;
        Rules::variantName = "std";
        break;
    case (int)Wrappers::Constants::Variants::lask:
        std::memcpy(Rules::millPos, Rules::stdLaskerMillPos,
                    sizeof(Rules::stdLaskerMillPos));
        std::memcpy(Rules::invMillPos, Rules::stdLaskerInvMillPos,
                    sizeof(Rules::stdLaskerInvMillPos));
        std::memcpy(Rules::boardGraph, Rules::stdLaskerBoardGraph,
                    sizeof(Rules::stdLaskerBoardGraph));
        std::memcpy(Rules::aLBoardGraph, Rules::stdLaskerALBoardGraph,
                    sizeof(Rules::stdLaskerALBoardGraph));
        Rules::maxKSZ = 10;
        Rules::variantName = "lask";
        break;
    case (int)Wrappers::Constants::Variants::mora:
        std::memcpy(Rules::millPos, Rules::moraMillPos,
                    sizeof(Rules::moraMillPos));
        std::memcpy(Rules::invMillPos, Rules::moraInvMillPos,
                    sizeof(Rules::moraInvMillPos));
        std::memcpy(Rules::boardGraph, Rules::moraBoardGraph,
                    sizeof(Rules::moraBoardGraph));
        std::memcpy(Rules::aLBoardGraph, Rules::moraALBoardGraph,
                    sizeof(Rules::moraALBoardGraph));
        Rules::maxKSZ = 12;
        Rules::variantName = "mora";
        break;
    }

    if (Wrappers::Constants::extended) {
        Rules::maxKSZ = 12;
    }
}
