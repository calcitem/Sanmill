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

#include <bitset>
#include <cassert>   // for assert
#include <cstdint>   // for int64_t
#include <cstdlib>   // for std::exit
#include <exception> // for std::exception
#include <fstream>
#include <iostream>
#include <iostream> // for std::cerr
#include <map>
#include <mutex> // for std::mutex and std::lock_guard
#include <random>
#include <stdexcept>
#include <stdexcept> // for std::out_of_range
#include <string>
#include <vector>

#include "MalomSolutionAccess.h"
#include "PerfectPlayer.h"
#include "Player.h"
#include "game_state.h"
#include "move.h"
#include "rules.h"

#include "wrappers.h"

class GameState;

std::map<Wrappers::WID, Wrappers::WSector> Sectors::sectors;
bool Sectors::created = false;

std::map<Wrappers::WID, Wrappers::WSector> Sectors::getSectors()
{
    try {
        if (!created) {
            Wrappers::Init::init_sym_lookuptables();
            Wrappers::Init::init_sec_vals();

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
                            std::ifstream file(sec_val_path + "\\" + fname);
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
        std::cerr << "An error happened in getSectors\n"
                  << ex.what() << std::endl;
        exit(1);
    }
}

bool Sectors::hasDatabase()
{
    return getSectors().size() > 0;
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
        std::cerr << "An error happened in getSec\n" << ex.what() << std::endl;
        std::exit(1);
    }
    return nullptr;
}

std::string PerfectPlayer::toHumanReadableEval(Wrappers::gui_eval_elem2 e)
{
    try {
        return e.toString();
    } catch (std::exception &ex) {
        std::cerr << "An error happened in toHumanReadableEval\n"
                  << ex.what() << std::endl;
        std::exit(1);
    }
}

int PerfectPlayer::futureKorongCount(const GameState &s)
{
    return s.stoneCount[s.sideToMove] + Rules::maxKSZ -
           s.setStoneCount[s.sideToMove]; // TODO: refactor to call to
                                          // futureStoneCount
}

bool PerfectPlayer::makesMill(const GameState &s, int hon, int hov)
{
    GameState s2 = s;
    if (hon != -1)
        s2.T[hon] = -1;
    s2.T[hov] = s.sideToMove;
    return -1 != Rules::malome(hov, s2);
}

bool PerfectPlayer::isMill(const GameState &s, int m)
{
    return -1 != Rules::malome(m, s);
}

std::vector<ExtMove> PerfectPlayer::setMoves(const GameState &s)
{
    std::vector<ExtMove> r;
    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == -1) {
            r.push_back(ExtMove {i, i, CMoveType::SetMove, makesMill(s, -1, i),
                                 false, 0});
        }
    }
    return r;
}

std::vector<ExtMove> PerfectPlayer::slideMoves(const GameState &s)
{
    std::vector<ExtMove> r;
    for (int i = 0; i < 24; ++i) {
        for (int j = 0; j < 24; ++j) {
            if (s.T[i] == s.sideToMove && s.T[j] == -1 &&
                (futureKorongCount(s) == 3 || Rules::boardGraph[i][j])) {
                r.push_back(ExtMove {i, j, CMoveType::SlideMove,
                                     makesMill(s, i, j), false, 0});
            }
        }
    }
    return r;
}

// m has a withTaking step, where takeHon is not filled out. This function
// creates a list, the elements of which are copies of m supplemented with one
// possible removal each.
std::vector<ExtMove> PerfectPlayer::withTakingMoves(const GameState &s,
                                                    ExtMove &m)
{
    std::vector<ExtMove> r;
    bool everythingInMill = true;
    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && !isMill(s, i)) {
            everythingInMill = false;
        }
    }

    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && (!isMill(s, i) || everythingInMill)) {
            ExtMove m2 = m;
            m2.takeHon = i;
            r.push_back(m2);
        }
    }
    return r;
}

std::vector<ExtMove> PerfectPlayer::onlyTakingMoves(const GameState &s)
{
    // there's some copy-paste code here
    std::vector<ExtMove> r;
    bool everythingInMill = true;
    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && !isMill(s, i)) {
            everythingInMill = false;
        }
    }

    for (int i = 0; i < 24; ++i) {
        if (s.T[i] == 1 - s.sideToMove && (!isMill(s, i) || everythingInMill)) {
            r.push_back(ExtMove {0, 0, CMoveType::SlideMove, false, true,
                                 i}); // Assuming default values for hon and hov
        }
    }
    return r;
}

#pragma warning(push)
#pragma warning(disable : 4127)
#pragma warning(push)
#pragma warning(disable : 6285)
std::vector<ExtMove> PerfectPlayer::getMoveList(const GameState &s)
{
    std::vector<ExtMove> ms0, ms;
    if (!s.kle) {
        if (Wrappers::Constants::variant ==
                (int)Wrappers::Constants::Variants::std ||
            Wrappers::Constants::variant ==
                (int)Wrappers::Constants::Variants::mora) {
            if (s.setStoneCount[s.sideToMove] < Rules::maxKSZ) {
                ms0 = setMoves(s);
            } else {
                ms0 = slideMoves(s);
            }
        } else { // Lasker
            ms0 = slideMoves(s);
            if (s.setStoneCount[s.sideToMove] < Rules::maxKSZ) {
                std::vector<ExtMove> setMovesResult = setMoves(s);
                ms0.insert(ms0.end(), setMovesResult.begin(),
                           setMovesResult.end());
            }
        }

        for (size_t i = 0; i < ms0.size(); ++i) {
            if (!ms0[i].withTaking) {
                ms.push_back(ms0[i]);
            } else {
                std::vector<ExtMove> withTakingMovesResult = withTakingMoves(
                    s, ms0[i]);
                ms.insert(ms.end(), withTakingMovesResult.begin(),
                          withTakingMovesResult.end());
            }
        }
    } else { // kle
        ms = onlyTakingMoves(s);
    }
    return ms;
}
#pragma warning(pop)
#pragma warning(pop)

GameState PerfectPlayer::makeMoveInState(const GameState &s, ExtMove &m)
{
    GameState s2(s);
    if (!m.onlyTaking) {
        if (m.moveType == CMoveType::SetMove) {
            s2.makeMove(new SetKorong(m.hov));
        } else {
            s2.makeMove(new MoveKorong(m.hon, m.hov));
        }
        if (m.withTaking)
            s2.makeMove(new LeveszKorong(m.takeHon));
    } else {
        s2.makeMove(new LeveszKorong(m.takeHon));
    }
    return s2;
}

// Assuming gui_eval_elem2 and getSec functions are defined somewhere
Wrappers::gui_eval_elem2 PerfectPlayer::moveValue(const GameState &s,
                                                  ExtMove &m)
{
    try {
        return eval(makeMoveInState(s, m)).undo_negate(getSec(s));
    } catch (const std::exception &ex) {
        std::cerr << "Exception in MoveValue\n" << ex.what() << std::endl;
        std::exit(1);
    }
}

template <typename T, typename K>
std::vector<T> PerfectPlayer::allMaxBy(std::function<K(T)> f,
                                       const std::vector<T> &l, K minValue)
{
    std::vector<T> r;
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
    return r;
}

// Assuming the definition of gui_eval_elem2::min_value function
std::vector<ExtMove> PerfectPlayer::goodMoves(const GameState &s)
{
    return allMaxBy(std::function<Wrappers::gui_eval_elem2(ExtMove)>(
                        [this, &s](ExtMove m) { return moveValue(s, m); }),
                    getMoveList(s),
                    Wrappers::gui_eval_elem2::min_value(getSec(s)));
}

int PerfectPlayer::NGMAfterMove(const GameState &s, ExtMove &m)
{
    return numGoodMoves(makeMoveInState(s, m)); 
}

template <typename T>
T PerfectPlayer::chooseRandom(const std::vector<T> &l)
{
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<> dis(0, static_cast<int>(l.size() - 1));
    return l[dis(gen)];
}

void PerfectPlayer::sendMoveToGUI(ExtMove m)
{
    if (!m.onlyTaking) {
        if (m.moveType == CMoveType::SetMove) {
            g->makeMove(new SetKorong(m.hov));
        } else {
            g->makeMove(new MoveKorong(m.hon, m.hov));
        }
    } else {
        g->makeMove(new LeveszKorong(m.takeHon)); 
    }
}

void PerfectPlayer::toMove(const GameState &s)
{
    try {
        ExtMove mh = chooseRandom(goodMoves(s));
        sendMoveToGUI(mh);
    } catch (const std::out_of_range &) {
        sendMoveToGUI(chooseRandom(getMoveList(s)));
    } catch (const std::exception &ex) {
        std::cerr << "Exception in toMove\n" << ex.what() << std::endl;
        std::exit(1);
    }
}

int PerfectPlayer::numGoodMoves(const GameState &s)
{
    if (futureKorongCount(s) < 3)
        return 0; // Assuming futureKorongCount function is defined
    auto ma = Wrappers::gui_eval_elem2::min_value(getSec(s)); // Assuming getSec
                                                              // function is
                                                              // defined
    ExtMove mh;
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
    ExtMove m;
    double val;
};

// const double WRGMInf = 2; // Is this good?

std::mutex evalLock;

Wrappers::gui_eval_elem2 PerfectPlayer::eval(GameState s)
{
    try {
        std::lock_guard<std::mutex> lock(evalLock);
        assert(!s.kle); // Assuming s has a boolean member kle

        Wrappers::WID id(s.stoneCount[0], s.stoneCount[1],
                         Rules::maxKSZ - s.setStoneCount[0],
                         Rules::maxKSZ - s.setStoneCount[1]);

        if (futureKorongCount(s) < 3)
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
            id.negate();
        }

        auto it = secs.find(id);
        if (it == secs.end()) {
            throw std::runtime_error("Key not found in map");
        }

        Wrappers::WSector &sec = it->second;

        return sec.hash(a).second;
    } catch (const std::exception &ex) {
        if (typeid(ex) == typeid(std::out_of_range))
            throw;
        std::cerr << "Exception in Eval\n" << ex.what() << std::endl;
        std::exit(1);
    }
}

int64_t PerfectPlayer::boardNegate(int64_t a)
{
    return ((a & mask24) << 24) | ((a & (mask24 << 24)) >> 24);
}
