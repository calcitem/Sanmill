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

// perfect_player.cpp

#include "perfect_adaptor.h"
#include "perfect_api.h"
#include "perfect_player.h"
#include "perfect_game_state.h"
#include "perfect_move.h"
#include "perfect_rules.h"

#include "perfect_wrappers.h"

#include <bitset>
#include <cassert>   // for assert
#include <cstdint>   // for int64_t
#include <cstdlib>   // for std::exit
#include <exception> // for std::exception
#include <fstream>
#include <iostream>
#include <iostream> // for std::cerr
#include <map>
#include <mutex>
#include <random>
#include <stdexcept>
#include <stdexcept> // for std::out_of_range
#include <string>
#include <vector>

#include "option.h"

class GameState;

std::map<Wrappers::WID, Wrappers::WSector> Sectors::sectors;
bool Sectors::created = false;

std::map<Wrappers::WID, Wrappers::WSector> Sectors::getSectors()
{
    try {
        if (!created) {
            Wrappers::Init::init_sym_lookuptables();
            Wrappers::Init::init_sec_vals();
            // sectors.clear();

            for (int w = 0; w <= Rules::maxKSZ; ++w) {
                for (int b = 0; b <= Rules::maxKSZ; ++b) {
                    for (int wf = 0; wf <= Rules::maxKSZ; ++wf) {
                        for (int bf = 0; bf <= Rules::maxKSZ; ++bf) {
                            std::string fname =
                                Rules::variantName + "_" + std::to_string(w) +
                                "_" + std::to_string(b) + "_" +
                                std::to_string(wf) + "_" + std::to_string(bf) +
                                ".sec" + Wrappers::Constants::fname_suffix;
                            // std::cout << "Looking for database file " <<
                            // fname << std::endl;
                            Wrappers::WID _id(w, b, wf, bf);
#ifdef _WIN32
                            std::ifstream file(sec_val_path + "\\" + fname);
#else
                            std::ifstream file(sec_val_path + "/" + fname);
#endif
                            if (file.good()) {
                                sectors.emplace(_id, Wrappers::WSector(_id));
                            }
                        }
                    }
                }
            }
            created = true;
        }
        return sectors;
    } catch (std::exception &ex) {
        if (dynamic_cast<std::out_of_range *>(&ex)) {
            throw;
        }
        std::cerr << "An error happened in " << __func__ << "\n"
                  << ex.what() << std::endl;
        throw std::runtime_error(std::string("An error happened in ") +
                                 __func__ + ": " + ex.what());
    }
}

bool Sectors::hasDatabase()
{
    return getSectors().size() > 0;
}

// The object is informed to enter the specified game
void Player::enter(Game *_g)
{
    g = _g;
}

// The object is informed to exit from the game
void Player::quit()
{
    if (g == nullptr)
        return;
    g = nullptr;
}

PerfectPlayer::PerfectPlayer()
{
    assert(Sectors::hasDatabase());
    secs = Sectors::getSectors();
}

void PerfectPlayer::enter(Game *_g)
{
    Player::enter(_g);
}

Wrappers::WSector *PerfectPlayer::getSec(GameState s)
{
    try {
        if (s.kle)
            return nullptr;

        Wrappers::WID id_val(s.stoneCount[0], s.stoneCount[1],
                             Rules::maxKSZ - s.setStoneCount[0],
                             Rules::maxKSZ - s.setStoneCount[1]);

        if (s.sideToMove == 1) {
            id_val.negate();
        }

        auto iter = secs.find(id_val);
        if (iter == secs.end()) {
            throw std::runtime_error("Key not found in secs");
        }
        return &(iter->second);

    } catch (std::exception &ex) {
        if (typeid(ex) == typeid(std::out_of_range))
            throw;
        std::cerr << "An error happened in " << __func__ << "\n"
                  << ex.what() << std::endl;
        throw std::runtime_error(std::string("An error happened in ") +
                                 __func__ + ": " + ex.what());
    }
    return nullptr;
}

std::string PerfectPlayer::toHumanReadableEval(Wrappers::gui_eval_elem2 e)
{
    try {
        return e.toString();
    } catch (std::exception &ex) {
        std::cerr << "An error happened in " << __func__ << "\n"
                  << ex.what() << std::endl;
        throw std::runtime_error(std::string("An error happened in ") +
                                 __func__ + ": " + ex.what());
    }
}

int PerfectPlayer::futurePieceCount(const GameState &s)
{
    return s.stoneCount[s.sideToMove] + Rules::maxKSZ -
           s.setStoneCount[s.sideToMove]; // TODO: refactor to call to
                                          // futureStoneCount
}

bool PerfectPlayer::makesMill(const GameState &s, int from, int to)
{
    GameState s2 = s;
    if (from != -1)
        s2.T[from] = -1;
    s2.T[to] = s.sideToMove;
    return -1 != Rules::malome(to, s2);
}

bool PerfectPlayer::isMill(const GameState &s, int m)
{
    return -1 != Rules::malome(m, s);
}

std::vector<AdvancedMove> PerfectPlayer::setMoves(const GameState &s)
{
    std::vector<AdvancedMove> r;
    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == -1) {
            r.push_back(AdvancedMove {i, i, CMoveType::SetMove,
                                      makesMill(s, -1, i), false, 0});
        }
    }
    return r;
}

std::vector<AdvancedMove> PerfectPlayer::slideMoves(const GameState &s)
{
    std::vector<AdvancedMove> r;
    for (int i = 0; i < 24; ++i) {
        for (int j = 0; j < 24; ++j) {
            if (s.T[i] == s.sideToMove && s.T[j] == -1 &&
                (futurePieceCount(s) == 3 || Rules::boardGraph[i][j])) {
                r.push_back(AdvancedMove {i, j, CMoveType::SlideMove,
                                          makesMill(s, i, j), false, 0});
            }
        }
    }
    return r;
}

// m has a withTaking step, where takeHon is not filled out. This function
// creates a list, the elements of which are copies of m supplemented with one
// possible removal each.
std::vector<AdvancedMove> PerfectPlayer::withTakingMoves(const GameState &s,
                                                         AdvancedMove &m)
{
    std::vector<AdvancedMove> r;
    bool everythingInMill = true;
    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && !isMill(s, i)) {
            everythingInMill = false;
        }
    }

    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && (!isMill(s, i) || everythingInMill)) {
            AdvancedMove m2 = m;
            m2.takeHon = i;
            r.push_back(m2);
        }
    }
    return r;
}

std::vector<AdvancedMove> PerfectPlayer::onlyTakingMoves(const GameState &s)
{
    // there's some copy-paste code here
    std::vector<AdvancedMove> r;
    bool everythingInMill = true;
    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && !isMill(s, i)) {
            everythingInMill = false;
        }
    }

    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && (!isMill(s, i) || everythingInMill)) {
            r.push_back(AdvancedMove {0, 0, CMoveType::SlideMove, false, true,
                                      i}); // Assuming default values for from
                                           // and to
        }
    }
    return r;
}

#ifdef _MSC_VER
#pragma warning(push)
#pragma warning(disable : 4127)
#pragma warning(push)
#pragma warning(disable : 6285)
#endif

std::vector<AdvancedMove> PerfectPlayer::getMoveList(const GameState &s)
{
    std::vector<AdvancedMove> ms0, ms;
    if (!s.kle) {
        if (ruleVariant == (int)Wrappers::Constants::Variants::std ||
            ruleVariant == (int)Wrappers::Constants::Variants::mora) {
            if (s.setStoneCount[s.sideToMove] < Rules::maxKSZ) {
                ms0 = setMoves(s);
            } else {
                ms0 = slideMoves(s);
            }
        } else { // Lasker
            ms0 = slideMoves(s);
            if (s.setStoneCount[s.sideToMove] < Rules::maxKSZ) {
                std::vector<AdvancedMove> setMovesResult = setMoves(s);
                ms0.insert(ms0.end(), setMovesResult.begin(),
                           setMovesResult.end());
            }
        }

        for (size_t i = 0; i < ms0.size(); ++i) {
            if (!ms0[i].withTaking) {
                ms.push_back(ms0[i]);
            } else {
                std::vector<AdvancedMove> withTakingMovesResult =
                    withTakingMoves(s, ms0[i]);
                ms.insert(ms.end(), withTakingMovesResult.begin(),
                          withTakingMovesResult.end());
            }
        }
    } else { // kle
        ms = onlyTakingMoves(s);
    }
    return ms;
}

#ifdef _MSC_VER
#pragma warning(pop)
#pragma warning(pop)
#endif

GameState PerfectPlayer::makeMoveInState(const GameState &s, AdvancedMove &m)
{
    GameState s2(s);
    if (!m.onlyTaking) {
        if (m.moveType == CMoveType::SetMove) {
            s2.makeMove(new SetPiece(m.to));
        } else {
            s2.makeMove(new MovePiece(m.from, m.to));
        }
        if (m.withTaking)
            s2.makeMove(new RemovePiece(m.takeHon));
    } else {
        s2.makeMove(new RemovePiece(m.takeHon));
    }
    return s2;
}

// Assuming gui_eval_elem2 and getSec functions are defined somewhere
Wrappers::gui_eval_elem2 PerfectPlayer::moveValue(const GameState &s,
                                                  AdvancedMove &m)
{
    try {
        return eval(makeMoveInState(s, m)).undo_negate(getSec(s));
    } catch (const std::exception &ex) {
        std::cerr << "An error happened in " << __func__ << "\n"
                  << ex.what() << std::endl;
        throw std::runtime_error(std::string("An error happened in ") +
                                 __func__ + ": " + ex.what());
    }
}

template <typename T, typename K>
std::vector<T> PerfectPlayer::allMaxBy(std::function<K(T)> f,
                                       const std::vector<T> &l, K minValue,
                                       Value &value)
{
    std::vector<T> r;

    // TODO: Right? Ref: https://github.com/ggevay/malom/pull/3
    if (gameOptions.getAlgorithm() != 4 ||
        (gameOptions.getAlgorithm() == 4 &&
         gameOptions.getAiIsLazy() == true)) {
        bool foundW = false;
        bool foundD = false;

        for (auto &m : l) {
            K e = f(m);
            std::string eStr = e.toString();

            if (eStr[0] == 'W') {
                if (!foundW) {
                    r.clear();
                    foundW = true;
                }
                r.push_back(m);
            } else if (!foundW && eStr[0] != 'L') {
                if (!foundD) {
                    r.clear();
                    foundD = true;
                }
                r.push_back(m);
            } else if (!foundW && !foundD && eStr[0] == 'L') {
                r.push_back(m);
            }
        }
    } else {
        K ma = minValue;
        for (auto &m : l) {
            K e = f(m);
            if (e > ma) {
                ma = e;
                r.clear();
                r.push_back(m);
            } else if (e == ma) {
                r.push_back(m);
            }
        }
    }

    char e = f(r.at(0)).toString().at(0);

    if (e == 'L') {
        value = -VALUE_MATE;
    } else if (e == 'W') {
        value = VALUE_MATE;
    } else {
        value = VALUE_DRAW;
    }

    return r;
}

#if 1
// Assuming the definition of gui_eval_elem2::min_value function
std::vector<AdvancedMove> PerfectPlayer::goodMoves(const GameState &s,
                                                   Value &value)
{
    return allMaxBy(std::function<Wrappers::gui_eval_elem2(AdvancedMove)>(
                        [this, &s](AdvancedMove m) { return moveValue(s, m); }),
                    getMoveList(s),
                    Wrappers::gui_eval_elem2::min_value(getSec(s)), value);
}
#else
std::vector<AdvancedMove> PerfectPlayer::goodMoves(const GameState &s,
                                                   Value &value)
{
    auto moveList = getMoveList(s);
    std::cout << "Move list size: " << moveList.size() << std::endl;

    std::function<Wrappers::gui_eval_elem2(AdvancedMove)> evalFunction =
        [this, &s](AdvancedMove m) {
            auto value = moveValue(s, m);
            std::cout << "Evaluating move from " << m.from << " to " << m.to
                      << " with score: " << value.toString() << std::endl;
            return value;
        };

    auto bestMoves = allMaxBy(evalFunction, moveList,
                              Wrappers::gui_eval_elem2::min_value(getSec(s)),
                              value);

    std::cout << "Number of best moves: " << bestMoves.size() << std::endl;

#if 0
    // Filter bestMoves based on Mill condition
    std::vector<AdvancedMove> filteredMoves;
    for (const auto &move : bestMoves) {
        if (!isMill(s, move.to)) {
            filteredMoves.push_back(move);
        }
    }

    if (filteredMoves.size() > 0) {
        bestMoves = filteredMoves;
        std::cout << "Number of best moves after filtering: "
                  << bestMoves.size() << std::endl;
    }
#endif

    return bestMoves;
}
#endif

int PerfectPlayer::NGMAfterMove(const GameState &s, AdvancedMove &m)
{
    return numGoodMoves(makeMoveInState(s, m));
}

void PerfectPlayer::sendMoveToGUI(AdvancedMove m)
{
    if (!m.onlyTaking) {
        if (m.moveType == CMoveType::SetMove) {
            g->makeMove(new SetPiece(m.to));
        } else {
            g->makeMove(new MovePiece(m.from, m.to));
        }
    } else {
        g->makeMove(new RemovePiece(m.takeHon));
    }
}

int PerfectPlayer::numGoodMoves(const GameState &s)
{
    if (futurePieceCount(s) < 3)
        return 0; // Assuming futurePieceCount function is defined
    auto ma = Wrappers::gui_eval_elem2::min_value(getSec(s)); // Assuming getSec
                                                              // function is
                                                              // defined
    AdvancedMove mh;
    int c = 0;
    for (auto &m : getMoveList(s)) {
        auto e = moveValue(s, m);
        if (e > ma) {
            ma = e;
            mh = m;
            c = 1;
        } else if (e == ma) {
            c++;
        }
    }
    return c;
}

int cp;

struct MoveValuePair
{
    AdvancedMove m;
    double val;
};

std::mutex evalLock;

Wrappers::gui_eval_elem2 PerfectPlayer::eval(GameState s)
{
    try {
        std::lock_guard<std::mutex> lock(evalLock);
        assert(!s.kle); // Assuming s has a boolean member kle

        Wrappers::WID Id(s.stoneCount[0], s.stoneCount[1],
                         Rules::maxKSZ - s.setStoneCount[0],
                         Rules::maxKSZ - s.setStoneCount[1]);

        if (futurePieceCount(s) < 3)
            return Wrappers::gui_eval_elem2::virt_loss_val();

        int64_t a = 0;
        for (int i = 0; i < 24; ++i) {
            if (s.T[i] == 0) {
                a |= (1ll << i);
            } else if (s.T[i] == 1) {
                a |= (1ll << (i + 24));
            }
        }

        if (s.sideToMove == 1) {
            a = boardNegate(a);
            Id.negate();
        }

        auto it = secs.find(Id);
        if (it == secs.end()) {
            throw std::out_of_range("Database file for the key not found");
        }

        Wrappers::WSector &sec = it->second;

        return sec.hash(a).second;
    } catch (const std::exception &ex) {
        if (typeid(ex) == typeid(std::out_of_range))
            throw;
        std::cerr << "An error happened in " << __func__ << "\n"
                  << ex.what() << std::endl;
        throw std::runtime_error(std::string("An error happened in ") +
                                 __func__ + ": " + ex.what());
    }
}

int64_t PerfectPlayer::boardNegate(int64_t a)
{
    return ((a & mask24) << 24) | ((a & (mask24 << 24)) >> 24);
}
