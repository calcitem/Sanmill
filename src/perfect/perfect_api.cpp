// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_api.cpp

#include "perfect_api.h"
#include "option.h"
#include "perfect_errors.h"
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

// Error-code based implementation (no exceptions for performance)
int MalomSolutionAccess::get_best_move(int whiteBitboard, int blackBitboard,
                                       int whiteStonesToPlace,
                                       int blackStonesToPlace, int playerToMove,
                                       bool onlyStoneTaking, Value &value,
                                       const Move &refMove)
{
    using namespace PerfectErrors;

    clearError();

    if (!initialize_if_needed()) {
        return 0; // Error already set by initialize_if_needed
    }

    GameState s;
    const int W = 0;
    const int B = 1;

    // Check for bitboard overlap
    if ((whiteBitboard & blackBitboard) != 0) {
        SET_ERROR_AND_RETURN(PE_INVALID_ARGUMENT,
                             "whiteBitboard and blackBitboard shouldn't have "
                             "any overlap",
                             0);
    }

    // Set up board state
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

    // Range checks using error system
    if (!checkRange("whiteStonesToPlace", whiteStonesToPlace, 0,
                    Rules::maxKSZ) ||
        !checkRange("blackStonesToPlace", blackStonesToPlace, 0,
                    Rules::maxKSZ) ||
        !checkRange("playerToMove", playerToMove, 0, 1)) {
        return 0; // Error already set by checkRange
    }

    s.setStoneCount[W] = Rules::maxKSZ - whiteStonesToPlace;
    s.setStoneCount[B] = Rules::maxKSZ - blackStonesToPlace;
    s.kle = onlyStoneTaking;
    s.sideToMove = playerToMove;
    s.moveCount = 10;

    // Validate stone counts
    if (s.get_future_piece_count(W) > Rules::maxKSZ) {
        SET_ERROR_AND_RETURN(PE_INVALID_ARGUMENT,
                             "Number of stones in whiteBitboard + "
                             "whiteStonesToPlace > " +
                                 std::to_string(Rules::maxKSZ),
                             0);
    }
    if (s.get_future_piece_count(B) > Rules::maxKSZ) {
        SET_ERROR_AND_RETURN(PE_INVALID_ARGUMENT,
                             "Number of stones in blackBitboard + "
                             "blackStonesToPlace > " +
                                 std::to_string(Rules::maxKSZ),
                             0);
    }

    // Check game state validity
    std::string errorMsg = s.set_over_and_check_valid_setup();
    if (errorMsg != "") {
        SET_ERROR_AND_RETURN(PE_INVALID_ARGUMENT, errorMsg, 0);
    }
    if (s.over) {
        SET_ERROR_AND_RETURN(PE_GAME_OVER, "Game is already over.", 0);
    }

    s.lastIrrev = 0;

    // Get the best move - this may fail if database entry not found
    int ret = get_move_from_database(s, value, refMove);
    if (ret == 0 && hasError()) {
        return 0; // Error already set by get_move_from_database
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

// Helper function for initialization without exceptions
bool MalomSolutionAccess::initialize_if_needed()
{
    using namespace PerfectErrors;

    if (perfectPlayer != nullptr) {
        return true;
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

        SET_ERROR_MESSAGE(PE_DATABASE_NOT_FOUND, "Database files not found in "
                                                 "the current working "
                                                 "directory (" +
                                                     currentPath + ")");
        return false;
    }

    perfectPlayer = new PerfectPlayer();
    return true;
}

// Helper function to get move from database without exceptions
int MalomSolutionAccess::get_move_from_database(const GameState &s,
                                                Value &value,
                                                const Move &refMove)
{
    using namespace PerfectErrors;

    if (perfectPlayer == nullptr) {
        SET_ERROR_CODE(PE_RUNTIME_ERROR, "Perfect player not initialized");
        return 0;
    }

    // Get good moves from database - no exceptions expected
    std::vector<AdvancedMove> goodMoves = perfectPlayer->get_good_moves(s,
                                                                        value);

    if (goodMoves.empty()) {
        SET_ERROR_CODE(PE_RUNTIME_ERROR, "No good moves found in database");
        return 0;
    }

    // Use chooseRandom to select the best move - no exceptions expected
    AdvancedMove bestMove = perfectPlayer->chooseRandom(goodMoves, refMove);

    // Convert to bitboard format and return
    return bestMove.toBitBoard();
}

// Evaluation method without exceptions
PerfectEvaluation
MalomSolutionAccess::get_detailed_evaluation(const GameState &gameState)
{
    using namespace PerfectErrors;

    if (perfectPlayer == nullptr) {
        SET_ERROR_CODE(PE_RUNTIME_ERROR, "Perfect player not initialized");
        return PerfectEvaluation(); // Invalid result
    }

    // Get detailed evaluation from perfect player - no exceptions expected
    auto evalResult = perfectPlayer->evaluate(gameState);

    if (hasError()) {
        // If evaluate() set an error through the error code system
        return PerfectEvaluation(); // Invalid result
    }

    std::string evalStr = evalResult.to_string();

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
        } else if (firstChar == 'D' ||
                   evalStr.find("NTESC") != std::string::npos) {
            gameValue = VALUE_DRAW; // Draw
        }

        // Extract step count from the complex format: "..., (key1, key2)"
        size_t lastParen = evalStr.rfind('(');
        if (lastParen != std::string::npos) {
            size_t commaPos = evalStr.find(',', lastParen);
            size_t closePos = evalStr.find(')', lastParen);
            if (commaPos != std::string::npos &&
                closePos != std::string::npos && commaPos < closePos) {
                std::string stepSub = evalStr.substr(commaPos + 1,
                                                     closePos - commaPos - 1);
                // Trim whitespace
                stepSub.erase(0, stepSub.find_first_not_of(" \t"));
                stepSub.erase(stepSub.find_last_not_of(" \t") + 1);
                // Extract integer using regex to avoid invalid characters
                std::smatch m;
                if (std::regex_search(stepSub, m, std::regex("-?\\d+"))) {
                    // Use safe string conversion without exceptions
                    // Parse integer manually to avoid std::stoi exceptions
                    const std::string &numStr = m.str();
                    stepCount = 0;
                    bool negative = false;
                    size_t start = 0;

                    if (!numStr.empty() && numStr[0] == '-') {
                        negative = true;
                        start = 1;
                    }

                    for (size_t i = start; i < numStr.length(); ++i) {
                        if (numStr[i] >= '0' && numStr[i] <= '9') {
                            stepCount = stepCount * 10 + (numStr[i] - '0');
                        } else {
                            stepCount = -1; // Invalid character found
                            break;
                        }
                    }

                    if (negative && stepCount != -1) {
                        stepCount = -stepCount;
                    }
                    debugPrintf("Parsed step count: %d from string: '%s'\n",
                                stepCount, stepSub.c_str());
                }
            }
        }
    }

    return PerfectEvaluation(gameValue, stepCount);
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

PerfectEvaluation MalomSolutionAccess::get_detailed_evaluation(
    int whiteBitboard, int blackBitboard, int whiteStonesToPlace,
    int blackStonesToPlace, int playerToMove, bool onlyStoneTaking)
{
    using namespace PerfectErrors;

    clearError(); // Clear any previous errors

    // Initialize without exceptions for performance
    if (!initialize_if_needed()) {
        return PerfectEvaluation(); // Invalid result - error already set
    }

    if (perfectPlayer == nullptr) {
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

    gameState.phase = ((whiteStonesToPlace == 0 && blackStonesToPlace == 0) ?
                           2 :
                           1);
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

    // Use the evaluation method without exceptions
    PerfectEvaluation result = get_detailed_evaluation(gameState);

    deinitialize_if_needed();

    return result;
}

namespace PerfectAPI {
Value getValue(const Position &pos)
{
    using namespace PerfectErrors;

    clearError(); // Clear any previous errors

    // Convert position to perfect database format
    int whiteBitboard = 0;
    int blackBitboard = 0;

    for (int i = 0; i < 24; i++) {
        auto c = color_of(pos.board[from_perfect_square(i)]);
        if (c == WHITE) {
            whiteBitboard |= 1 << i;
        } else if (c == BLACK) {
            blackBitboard |= 1 << i;
        }
    }

    int whiteStonesToPlace = pos.piece_in_hand_count(WHITE);
    int blackStonesToPlace = pos.piece_in_hand_count(BLACK);
    int playerToMove = pos.side_to_move() == WHITE ? 0 : 1;
    bool onlyStoneTaking = (pos.piece_to_remove_count(pos.side_to_move()) > 0);

    // Use move retrieval without exceptions
    Value value = VALUE_NONE;
    Move refMove = MOVE_NONE;

    int moveResult = MalomSolutionAccess::get_best_move(
        whiteBitboard, blackBitboard, whiteStonesToPlace, blackStonesToPlace,
        playerToMove, onlyStoneTaking, value, refMove);

    // Check for errors in the database lookup
    if (moveResult == 0 && hasError()) {
        // Database lookup failed - return VALUE_NONE to fall back to
        // traditional search
        return VALUE_NONE;
    }

    // Adjust evaluation based on current player's perspective if needed
    if (pos.side_to_move() == BLACK && value != VALUE_DRAW &&
        value != VALUE_NONE) {
        // The perfect database returns values from white's perspective
        // If it's black to move, we need to negate for the current position
        // analysis
        value = -value;
    }

    return (value != VALUE_NONE) ? value : VALUE_NONE;
}

PerfectEvaluation getDetailedEvaluation(const Position &position)
{
    using namespace PerfectErrors;

    clearError(); // Clear any previous errors

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
    bool onlyStoneTaking = (position.piece_to_remove_count(
                                position.side_to_move()) > 0);

    // Use the detailed evaluation method without exceptions
    PerfectEvaluation result = MalomSolutionAccess::get_detailed_evaluation(
        whiteBitboard, blackBitboard, whiteStonesToPlace, blackStonesToPlace,
        playerToMove, onlyStoneTaking);

    // Adjust evaluation based on current player's perspective if needed
    if (result.isValid && position.side_to_move() == BLACK &&
        result.value != VALUE_DRAW) {
        // The perfect database returns values from white's perspective
        // If it's black to move, we need to negate for the current position
        // analysis
        result.value = -result.value;
    }

    return result;
}
} // namespace PerfectAPI
