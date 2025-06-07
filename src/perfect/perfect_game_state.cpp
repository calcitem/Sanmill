// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_game_state.cpp

#include "perfect_api.h"
#include "perfect_game_state.h"
#include "perfect_errors.h"
#include <sstream>
#include <algorithm>
#include <vector>
#include <charconv>

class Player;
class GameState;
class CMove;

GameState::GameState(const GameState &s)
{
    board = s.board;
    phase = s.phase;
    setStoneCount = s.setStoneCount;
    stoneCount = s.stoneCount;
    kle = s.kle;
    sideToMove = s.sideToMove;
    moveCount = s.moveCount;
    over = s.over;
    winner = s.winner;
    block = s.block;
    lastIrrev = s.lastIrrev;
}

int GameState::get_future_piece_count(int p)
{
    return stoneCount[p] + Rules::maxKSZ - setStoneCount[p];
}

// Sets the state for Setup Mode: the placed stones are unchanged, but we switch
// to phase 2.
void GameState::init_setup()
{
    moveCount = 10; // Nearly all the same, just don't be too small, see other
                    // comments
    over = false;
    // Winner can be undefined, as over = False
    block = false;
    lastIrrev = 0;
}

void GameState::make_move(CMove *M)
{
    if (M == nullptr) {
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "M is null");
        return;
    }

    check_invariants();
    check_valid_move(M);

    moveCount++;

    SetPiece *sk = dynamic_cast<SetPiece *>(M);
    MovePiece *mk = dynamic_cast<MovePiece *>(M);
    RemovePiece *lk = dynamic_cast<RemovePiece *>(M);

    if (sk != nullptr) {
        board[sk->to] = sideToMove;
        setStoneCount[sideToMove]++;
        stoneCount[sideToMove]++;
        lastIrrev = 0;
    } else if (mk != nullptr) {
        board[mk->from] = -1;
        board[mk->to] = sideToMove;
        lastIrrev++;
        if (lastIrrev >= Rules::lastIrrevLimit) {
            over = true;
            winner = -1; // draw
        }
    } else if (lk != nullptr) {
        board[lk->from] = -1;
        stoneCount[1 - sideToMove]--;
        kle = false;
        if (stoneCount[1 - sideToMove] + Rules::maxKSZ -
                setStoneCount[1 - sideToMove] <
            3) {
            over = true;
            winner = sideToMove;
        }
        lastIrrev = 0;
    }

    if ((sk != nullptr && Rules::check_mill(sk->to, *this) > -1 &&
         stoneCount[1 - sideToMove] > 0) ||
        (mk != nullptr && Rules::check_mill(mk->to, *this) > -1 &&
         stoneCount[1 - sideToMove] > 0)) {
        kle = true;
    } else {
        sideToMove = 1 - sideToMove;
        if (setStoneCount[0] == Rules::maxKSZ &&
            setStoneCount[1] == Rules::maxKSZ && phase == 1)
            phase = 2;
        if (!Rules::can_move(*this)) {
            over = true;
            block = true;
            winner = 1 - sideToMove;
            if (rule.boardFullAction == BoardFullAction::agreeToDraw &&
                stoneCount[0] == 12 && stoneCount[1] == 12) {
                winner = -1;
            }
        }
    }

    delete M;

    check_invariants();
}

void GameState::check_valid_move(CMove *M)
{
    // Hard to ensure that the 'over and winner = -1' case never occurs. For
    // example, the WithTaking case of PerfectPlayer.MakeMoveInState is tricky,
    // because the previous make_move may have already made it a draw.
    assert(!over || winner == -1);

    SetPiece *sk = dynamic_cast<SetPiece *>(M);
    MovePiece *mk = dynamic_cast<MovePiece *>(M);
    RemovePiece *lk = dynamic_cast<RemovePiece *>(M);

    if (sk != nullptr) {
        assert(phase == 1);
        assert(board[sk->to] == -1);
    }
    if (mk != nullptr) {
        assert(board[mk->from] == sideToMove);
        assert(board[mk->to] == -1);
    }
    if (lk != nullptr) {
        assert(kle);
        assert(board[lk->from] == 1 - sideToMove);
    }
}

void GameState::check_invariants()
{
    assert(setStoneCount[0] >= 0);
    assert(setStoneCount[0] <= Rules::maxKSZ);
    assert(setStoneCount[1] >= 0);
    assert(setStoneCount[1] <= Rules::maxKSZ);
    assert(phase == 1 || (phase == 2 && setStoneCount[0] == Rules::maxKSZ &&
                          setStoneCount[1] == Rules::maxKSZ));
}

#if defined(_WIN32)
#pragma warning(push)
#pragma warning(disable : 4127)
#endif
// Called when applying a free setup. It sets over and checks whether the
// position is valid. Returns "" if valid, reason str otherwise. Also called
// when pasting a position.
std::string GameState::set_over_and_check_valid_setup()
{
    assert(!over && !block);

    // Validity checks:
    // Note: this should be before setting over, because we will deny applying
    // the setup if the state is not valid, and we want to maintain the 'Not
    // over and Not block' invariants.

    int toBePlaced0 = Rules::maxKSZ - setStoneCount[0];
    if (stoneCount[0] + toBePlaced0 > Rules::maxKSZ) {
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT,
                       "Too many white stones (on the board + to be placed). "
                       "Please remove some white stones from the board and/or "
                       "decrease the number of white stones to be placed.");
        return "Too many white stones (on the board + to be placed). Please "
               "remove some white stones from the board and/or decrease the "
               "number of white stones to be placed.";
    }
    int toBePlaced1 = Rules::maxKSZ - setStoneCount[1];
    if (stoneCount[1] + toBePlaced1 > Rules::maxKSZ) {
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT,
                       "Too many black stones (on the board + to be placed). "
                       "Please remove some black stones from the board and/or "
                       "decrease the number of black stones to be placed.");
        return "Too many black stones (on the board + to be placed). Please "
               "remove some black stones from the board and/or decrease the "
               "number of black stones to be placed.";
    }

    assert(!(phase == 1 && toBePlaced0 == 0 && toBePlaced1 == 0));
    assert(!(phase == 2 && (toBePlaced0 > 0 || toBePlaced1 > 0)));

    if (ruleVariant != (int)Wrappers::Constants::Variants::lask &&
        !Wrappers::Constants::extended) {
        if (phase == 1) {
            if (toBePlaced0 !=
                toBePlaced1 - (((sideToMove == 0) ^ kle) ? 0 : 1)) {
                SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT,
                               "If Black is to move in the placement phase, "
                               "then the number of black stones to be placed "
                               "should be one more than the number of white "
                               "stones to placed. If White is to move in the "
                               "placement phase, then the number of white and "
                               "black stones to be placed should be equal. "
                               "(Except in a stone taking position, where "
                               "these conditions are reversed.)\n\nNote: The "
                               "Lasker variant (and the extended solutions) "
                               "doesn't have these constraints.\n\nNote: You "
                               "can switch the side to move by the \"Switch "
                               "STM\" button in position setup mode.");
                return "If Black is to move in the placement phase, then the "
                       "number of black stones to be placed should be one more "
                       "than the number of white stones to placed. If White is "
                       "to move in the placement phase, then the number of "
                       "white and black stones to be placed should be equal. "
                       "(Except in a stone taking position, where these "
                       "conditions are reversed.)\n\nNote: The Lasker variant "
                       "(and the extended solutions) doesn't have these "
                       "constraints.\n\nNote: You can switch the side to move "
                       "by the \"Switch STM\" button in position setup mode.";
            }
        } else {
            if (phase != 2) {
                SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "Phase is "
                                                                   "not 2");
                return "Phase is not 2";
            }
            if (toBePlaced0 != 0 || toBePlaced1 != 0) {
                SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "toBePlaced0"
                                                                   " or "
                                                                   "toBePlaced1"
                                                                   " is not 0");
                return "toBePlaced0 or toBePlaced1 is not 0";
            }
        }
    }

    if (kle && stoneCount[1 - sideToMove] == 0) {
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "A position where "
                                                           "the opponent "
                                                           "doesn't have any "
                                                           "stones cannot be a "
                                                           "stone taking "
                                                           "position.");
        return "A position where the opponent doesn't have any stones cannot "
               "be a stone taking position.";
    }

    // Set over if needed:
    bool whiteLose = false, blackLose = false;
    if (stoneCount[0] + Rules::maxKSZ - setStoneCount[0] < 3) {
        whiteLose = true;
    }
    if (stoneCount[1] + Rules::maxKSZ - setStoneCount[1] < 3) {
        blackLose = true;
    }
    if (whiteLose || blackLose) {
        over = true;
        if (whiteLose && blackLose) {
            winner = -1; // draw
        } else {
            if (whiteLose) {
                winner = 1;
            } else {
                assert(blackLose);
                winner = 0;
            }
        }
    }
    if (!kle && !Rules::can_move(*this)) { // can_move doesn't handle the
                                           // kle case. However, we should
                                           // always have a move in kle, see
                                           // the validity check above.
        over = true;
        block = true;
        winner = 1 - sideToMove;
        if (rule.boardFullAction == BoardFullAction::agreeToDraw &&
            stoneCount[0] == 12 && stoneCount[1] == 12) {
            winner = -1;
        }
    }

    // Even though lastIrrev is always 0 while in free setup mode, it can be
    // non-0 when pasting
    if (lastIrrev >= Rules::lastIrrevLimit) {
        over = true;
        winner = -1;
    }

    return "";
}
#if defined(_WIN32)
#pragma warning(pop)
#endif

// Helper function to safely parse an integer from a string
bool safe_stoi(const std::string &s, int &out)
{
    auto result = std::from_chars(s.data(), s.data() + s.size(), out);
    return result.ec == std::errc();
}

// to paste from clipboard
std::string GameState::to_string()
{
    std::stringstream s;
    for (int i = 0; i < 24; i++) {
        s << board[i] << ",";
    }
    s << sideToMove << "," << 0 << "," << 0 << "," << phase << ","
      << setStoneCount[0] << "," << setStoneCount[1] << "," << stoneCount[0]
      << "," << stoneCount[1] << "," << (kle ? "True" : "False") << ","
      << moveCount << "," << lastIrrev;
    return s.str();
}

void GameState::fromString(const std::string &s)
{
    // Reset state before parsing
    board.assign(24, -1);
    stoneCount.assign(2, 0);
    setStoneCount.assign(2, 0);
    phase = 1;
    kle = false;
    sideToMove = 0;
    moveCount = 0;
    over = false;
    winner = 0;
    block = false;
    lastIrrev = 0;

    std::vector<std::string> ss;
    std::string temp;
    std::stringstream strStream(s);

    // split by commas (to match to_string() format)
    while (std::getline(strStream, temp, ',')) {
        ss.push_back(temp);
    }

    if (ss.size() < 35) { // Need at least 35 elements for the basic format
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "Invalid number of "
                                                           "tokens in input "
                                                           "string");
        return;
    }

    // Parse the format produced by to_string():
    // board[0-23], sideToMove, 0, 0, phase, setStoneCount[0], setStoneCount[1],
    // stoneCount[0], stoneCount[1], kle_str, moveCount, lastIrrev

    // Parse board positions (elements 0-23)
    for (int i = 0; i < 24; i++) {
        int value;
        if (!safe_stoi(ss[i], value)) {
            SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT,
                           "Failed to parse "
                           "board position " +
                               std::to_string(i));
            return;
        }
        if (value == 0) {
            board[i] = 0;
            stoneCount[0]++;
        } else if (value == 1) {
            board[i] = 1;
            stoneCount[1]++;
        } else if (value == -1) {
            board[i] = -1;
        } else {
            SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT,
                           "Invalid board "
                           "value at position " +
                               std::to_string(i));
            return;
        }
    }

    // Parse other fields
    if (!safe_stoi(ss[24], sideToMove) || // sideToMove
        !safe_stoi(ss[27], phase) || // phase (skip ss[25], ss[26] which are 0)
        !safe_stoi(ss[28], setStoneCount[0]) || // setStoneCount[0]
        !safe_stoi(ss[29], setStoneCount[1]) || // setStoneCount[1]
        !safe_stoi(ss[32], moveCount)) {        // moveCount
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "Failed to parse "
                                                           "one or more "
                                                           "integer fields "
                                                           "from string");
        return;
    }

    // Note: stoneCount[0] and stoneCount[1] are already calculated from board
    // positions But verify they match ss[30] and ss[31]
    int expectedStoneCount0, expectedStoneCount1;
    if (!safe_stoi(ss[30], expectedStoneCount0) ||
        !safe_stoi(ss[31], expectedStoneCount1)) {
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "Failed to parse "
                                                           "stone count "
                                                           "fields");
        return;
    }

    if (stoneCount[0] != expectedStoneCount0 ||
        stoneCount[1] != expectedStoneCount1) {
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_ARGUMENT, "Stone count "
                                                           "mismatch: "
                                                           "calculated vs "
                                                           "provided");
        return;
    }

    // Parse kle field (ss[32] is "True" or "False")
    kle = (ss[32] == "True" || ss[32] == "true");

    // Parse lastIrrev if available (ss[34])
    if (ss.size() > 34) {
        if (!safe_stoi(ss[34], lastIrrev)) {
            lastIrrev = 0; // Default value if parse fails
        }
    }

    std::string validation_error = set_over_and_check_valid_setup();
    if (!validation_error.empty()) {
        SET_ERROR_CODE(PerfectErrors::PE_INVALID_GAME_STATE, validation_error);
        return;
    }

    check_invariants();
}

// Constructor now calls the fromString method
GameState::GameState(const std::string &s)
{
    fromString(s);
}
