// Malom, a Nine Men's Morris (and variants) player and solver program.
// Copyright(C) 2007-2016  Gabor E. Gevay, Gabor Danner
// Copyright (C) 2023 The Sanmill developers (see AUTHORS file)
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

#include <cassert>
#include <list>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "MalomSolutionAccess.h"
#include "PerfectPlayer.h"
#include "Player.h"
#include "game_state.h"
#include "move.h"
#include "rules.h"

class Player;
class GameState;
class CMove;

GameState::GameState(const GameState &s)
{
    T = s.T;
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

int GameState::futureStoneCount(int p)
{
    return stoneCount[p] + Rules::maxKSZ - setStoneCount[p];
}

// Sets the state for Setup Mode: the placed stones are unchanged, but we switch
// to phase 2.
void GameState::initSetup()
{
    moveCount = 10; // Nearly all the same, just don't be too small, see other
                    // comments
    over = false;
    // Winner can be undefined, as over = False
    block = false;
    lastIrrev = 0;
}

void GameState::makeMove(CMove *M)
{
    if (M == nullptr) {
        throw std::invalid_argument("M is null");
    }

    checkInvariants();
    checkValidMove(M);

    moveCount++;

    SetKorong *sk = dynamic_cast<SetKorong *>(M);
    MoveKorong *mk = dynamic_cast<MoveKorong *>(M);
    LeveszKorong *lk = dynamic_cast<LeveszKorong *>(M);

    if (sk != nullptr) {
        T[sk->hov] = sideToMove;
        setStoneCount[sideToMove]++;
        stoneCount[sideToMove]++;
        lastIrrev = 0;
    } else if (mk != nullptr) {
        T[mk->hon] = -1;
        T[mk->hov] = sideToMove;
        lastIrrev++;
        if (lastIrrev >= Rules::lastIrrevLimit) {
            over = true;
            winner = -1; // draw
        }
    } else if (lk != nullptr) {
        T[lk->hon] = -1;
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

    if ((sk != nullptr && Rules::malome(sk->hov, *this) > -1 &&
         stoneCount[1 - sideToMove] > 0) ||
        (mk != nullptr && Rules::malome(mk->hov, *this) > -1 &&
         stoneCount[1 - sideToMove] > 0)) {
        kle = true;
    } else {
        sideToMove = 1 - sideToMove;
        if (setStoneCount[0] == Rules::maxKSZ &&
            setStoneCount[1] == Rules::maxKSZ && phase == 1)
            phase = 2;
        if (!Rules::youCanMove(*this)) {
            over = true;
            block = true;
            winner = 1 - sideToMove;
            if (Wrappers::Constants::FBD && stoneCount[0] == 12 &&
                stoneCount[1] == 12) {
                winner = -1;
            }
        }
    }

    delete M;

    checkInvariants();
}

void GameState::checkValidMove(CMove *M)
{
    // Hard to ensure that the 'over and winner = -1' case never occurs. For
    // example, the WithTaking case of PerfectPlayer.MakeMoveInState is tricky,
    // because the previous makeMove may have already made it a draw.
    assert(!over || winner == -1);

    SetKorong *sk = dynamic_cast<SetKorong *>(M);
    MoveKorong *mk = dynamic_cast<MoveKorong *>(M);
    LeveszKorong *lk = dynamic_cast<LeveszKorong *>(M);

    if (sk != nullptr) {
        assert(phase == 1);
        assert(T[sk->hov] == -1);
    }
    if (mk != nullptr) {
        assert(T[mk->hon] == sideToMove);
        assert(T[mk->hov] == -1);
    }
    if (lk != nullptr) {
        assert(kle);
        assert(T[lk->hon] == 1 - sideToMove);
    }
}

void GameState::checkInvariants()
{
    assert(setStoneCount[0] >= 0);
    assert(setStoneCount[0] <= Rules::maxKSZ);
    assert(setStoneCount[1] >= 0);
    assert(setStoneCount[1] <= Rules::maxKSZ);
    assert(phase == 1 || (phase == 2 && setStoneCount[0] == Rules::maxKSZ &&
                          setStoneCount[1] == Rules::maxKSZ));
}

// Called when applying a free setup. It sets over and checks whether the
// position is valid. Returns "" if valid, reason str otherwise. Also called
// when pasting a position.
std::string GameState::setOverAndCheckValidSetup()
{
    assert(!over && !block);

    // Validity checks:
    // Note: this should be before setting over, because we will deny applying
    // the setup if the state is not valid, and we want to maintain the 'Not
    // over and Not block' invariants.

    int toBePlaced0 = Rules::maxKSZ - setStoneCount[0];
    if (stoneCount[0] + toBePlaced0 > Rules::maxKSZ) {
        return "Too many white stones (on the board + to be placed). Please "
               "remove some white stones from the board and/or decrease the "
               "number of white stones to be placed.";
    }
    int toBePlaced1 = Rules::maxKSZ - setStoneCount[1];
    if (stoneCount[1] + toBePlaced1 > Rules::maxKSZ) {
        return "Too many black stones (on the board + to be placed). Please "
               "remove some black stones from the board and/or decrease the "
               "number of black stones to be placed.";
    }

    assert(!(phase == 1 && toBePlaced0 == 0 && toBePlaced1 == 0));
    assert(!(phase == 2 && (toBePlaced0 > 0 || toBePlaced1 > 0)));

    if (Wrappers::Constants::variant !=
            (int)Wrappers::Constants::Variants::lask &&
        !Wrappers::Constants::extended) {
        if (phase == 1) {
            if (toBePlaced0 !=
                toBePlaced1 - ((sideToMove == 0) ^ kle ? 0 : 1)) {
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
            assert(phase == 2);
            assert(toBePlaced0 == 0 && toBePlaced1 == 0);
        }
    }

    if (kle && stoneCount[1 - sideToMove] == 0) {
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
    if (!kle && !Rules::youCanMove(*this)) { // youCanMove doesn't handle the
                                             // kle case. However, we should
                                             // always have a move in kle, see
                                             // the validity check above.
        over = true;
        block = true;
        winner = 1 - sideToMove;
        if (Wrappers::Constants::FBD && stoneCount[0] == 12 &&
            stoneCount[1] == 12) {
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

// to paste from clipboard
GameState::GameState(const std::string &s)
{
    std::vector<std::string> ss;
    std::string temp;
    std::stringstream strStream(s);

    // split by commas
    while (std::getline(strStream, temp, ',')) {
        ss.push_back(temp);
    }

    try {
        if (ss[33] == "malom" || ss[34] == "malom" || ss[35] == "malom" ||
            ss[37] == "malom2") { // you need to be able to interpret older
                                  // formats as well
            for (int i = 0; i < 24; i++) {
                T[i] = std::stoi(ss[i]);
            }
            sideToMove = std::stoi(ss[24]);
            phase = std::stoi(ss[27]);
            setStoneCount[0] = std::stoi(ss[28]);
            setStoneCount[1] = std::stoi(ss[29]);
            stoneCount[0] = std::stoi(ss[30]);
            stoneCount[1] = std::stoi(ss[31]);
            kle = (ss[32] == "True" || ss[32] == "true");
            moveCount = (ss[33] != "malom") ? std::stoi(ss[33]) : 10;
            lastIrrev = ((ss[33] != "malom") && (ss[34] != "malom")) ?
                            std::stoi(ss[34]) :
                            0;

            // ensure correct count of stones
            int count0 = std::count(T.begin(), T.end(), 0);
            int count1 = std::count(T.begin(), T.end(), 1);
            if (stoneCount[0] != count0 || stoneCount[1] != count1) {
                throw InvalidGameStateException("Number of stones is "
                                                "incorrect.");
            }
        } else {
            throw std::invalid_argument("Invalid Format");
        }
    } catch (InvalidGameStateException &ex) {
        throw ex;
    } catch (std::exception &ex) {
        throw std::invalid_argument("Invalid Format");
    }
}

// for clipboard
std::string GameState::toString()
{
    std::stringstream s;
    for (int i = 0; i < 24; i++) {
        s << T[i] << ",";
    }
    s << sideToMove << "," << 0 << "," << 0 << "," << phase << ","
      << setStoneCount[0] << "," << setStoneCount[1] << "," << stoneCount[0]
      << "," << stoneCount[1] << "," << (kle ? "True" : "False") << ","
      << moveCount << "," << lastIrrev;
    return s.str();
}

const char *InvalidGameStateException::what() const noexcept
{
    return mymsg.c_str();
}
