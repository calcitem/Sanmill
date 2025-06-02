// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_api.cpp

#include "perfect_api.h"
#include "option.h"
#include "perfect_game_state.h"
#include "perfect_player.h"
#include "perfect_adaptor.h"

#include <cctype>
#include <string>
#include <regex>

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

PerfectEvaluation MalomSolutionAccess::get_detailed_evaluation(int whiteBitboard, int blackBitboard,
                                                              int whiteStonesToPlace, int blackStonesToPlace,
                                                              int playerToMove, bool onlyStoneTaking)
{
    try {
        MalomSolutionAccess::initialize_if_needed();
        
        if (MalomSolutionAccess::perfectPlayer == nullptr) {
            return PerfectEvaluation(); // Invalid result
        }

        // Create GameState for perfect database query
        GameState gameState;
        
        const int W = 0;
        const int B = 1;

        // Validate input parameters
        if ((whiteBitboard & blackBitboard) != 0) {
            return PerfectEvaluation(); // Invalid: overlapping bitboards
        }

        // Set up board state
        for (int i = 0; i < 24; i++) {
            if ((whiteBitboard & (1 << i)) != 0) {
                gameState.board[i] = W;
                gameState.stoneCount[W] += 1;
            }
            if ((blackBitboard & (1 << i)) != 0) {
                gameState.board[i] = B;
                gameState.stoneCount[B] += 1;
            }
        }

        gameState.phase = ((whiteStonesToPlace == 0 && blackStonesToPlace == 0) ? 2 : 1);
        gameState.setStoneCount[W] = Rules::maxKSZ - whiteStonesToPlace;
        gameState.setStoneCount[B] = Rules::maxKSZ - blackStonesToPlace;
        gameState.kle = onlyStoneTaking;
        gameState.sideToMove = playerToMove;
        gameState.moveCount = 10;
        gameState.lastIrrev = 0;

        // Validate game state
        std::string errorMsg = gameState.set_over_and_check_valid_setup();
        if (errorMsg != "" || gameState.over) {
            return PerfectEvaluation(); // Invalid result
        }
#if 0
        // If we are in a stone-removal (KLE) sub-position the DB does
        // not provide a stable evaluation for the main move – skip with
        // fallback and avoid assert in PerfectPlayer::evaluate().
        if (onlyStoneTaking) {
            // We cannot compute a meaningful step count here; return invalid so caller falls back.
            MalomSolutionAccess::deinitialize_if_needed();
            return PerfectEvaluation();
        }
#endif

        // Get detailed evaluation from perfect player and parse it directly
        std::string evalStr = MalomSolutionAccess::perfectPlayer->evaluate(gameState).to_string();
        
        // Debug: Log the evaluation string format
        debugPrintf("Perfect DB evaluation string: '%s'\n", evalStr.c_str());
        
        Value gameValue = VALUE_NONE;
        int stepCount = -1;
        
        // Parse evaluation string format: "W, (228, 75)" where 75 is the step count
        if (!evalStr.empty()) {
            char firstChar = evalStr[0];
            
            // Determine game outcome
            if (firstChar == 'W') {
                gameValue = VALUE_MATE; // Win
            } else if (firstChar == 'L') {
                gameValue = -VALUE_MATE; // Loss
            } else if (firstChar == 'D' || evalStr.find("NTESC") != std::string::npos) {
                gameValue = VALUE_DRAW; // Draw
            }
            
            // Extract step count from the complex format: "..., (key1, key2)"
            size_t lastParen = evalStr.rfind('(');
            if (lastParen != std::string::npos) {
                size_t commaPos = evalStr.find(',', lastParen);
                size_t closePos = evalStr.find(')', lastParen);
                if (commaPos != std::string::npos && closePos != std::string::npos && commaPos < closePos) {
                    std::string stepSub = evalStr.substr(commaPos + 1, closePos - commaPos - 1);
                    // Trim whitespace
                    stepSub.erase(0, stepSub.find_first_not_of(" \t"));
                    stepSub.erase(stepSub.find_last_not_of(" \t") + 1);
                    // Extract integer using regex to avoid invalid characters
                    std::smatch m;
                    if (std::regex_search(stepSub, m, std::regex("-?\\d+"))) {
                        try {
                            stepCount = std::stoi(m.str());
                            debugPrintf("Parsed step count: %d from string: '%s'\n", stepCount, stepSub.c_str());
                        } catch (...) {
                            stepCount = -1;
                        }
                    }
                }
            }
        }
        
        MalomSolutionAccess::deinitialize_if_needed();
        
        return PerfectEvaluation(gameValue, stepCount);
        
    } catch (const std::exception&) {
        return PerfectEvaluation(); // Invalid result on any error
    }
}

namespace PerfectAPI {
Value getValue(const Position &pos)
{
    try {
        // Create a dummy move to receive the result
        Move perfectMove = MOVE_NONE;

        // Call perfect_search to get evaluation from the database
        // This function handles all the conversion from Position to the format
        // used by Perfect AI
        Value value = perfect_search(&pos, perfectMove);

        // Check if we got a valid value from the perfect database
        if (value != VALUE_UNKNOWN) {
            return value;
        }

        // If we couldn't get a valid value, return VALUE_NONE to fall back to
        // traditional search in the calling function
        return VALUE_NONE;
    } catch (const std::exception &) {
        // If any error occurs during database access, return VALUE_NONE
        return VALUE_NONE;
    }
}

PerfectEvaluation getDetailedEvaluation(const Position &position)
{
    try {
        // Convert position to perfect database format
        int whiteBitboard = 0;
        int blackBitboard = 0;

        for (int i = 0; i < 24; i++) {
            auto c = color_of(position.board[from_perfect_square(i)]);
            if (c == WHITE) {
                whiteBitboard |= 1 << i;
            } else if (c == BLACK) {
                blackBitboard |= 1 << i;
            }
        }

        int whiteStonesToPlace = position.piece_in_hand_count(WHITE);
        int blackStonesToPlace = position.piece_in_hand_count(BLACK);
        int playerToMove = position.side_to_move() == WHITE ? 0 : 1;
        bool onlyStoneTaking = (position.piece_to_remove_count(position.side_to_move()) > 0);

        // Use the new detailed evaluation method
        PerfectEvaluation result = MalomSolutionAccess::get_detailed_evaluation(
            whiteBitboard, blackBitboard,
            whiteStonesToPlace, blackStonesToPlace,
            playerToMove, onlyStoneTaking);

        // Adjust evaluation based on current player's perspective if needed
        if (result.isValid && position.side_to_move() == BLACK && result.value != VALUE_DRAW) {
            // The perfect database returns values from white's perspective
            // If it's black to move, we need to negate for the current position analysis
            result.value = -result.value;
        }

        return result;
        
    } catch (const std::exception &) {
        // If any error occurs during database access, return invalid result
        return PerfectEvaluation();
    }
}
} // namespace PerfectAPI
