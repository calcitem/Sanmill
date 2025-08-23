// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_player.cpp

#include "perfect_adaptor.h"
#include "perfect_api.h"
#include "perfect_player.h"
#include "perfect_errors.h"
#include "perfect_game_state.h"
#include "perfect_move.h"
#include "perfect_rules.h"

#include "perfect_wrappers.h"
#include "perfect_trap_db.h"

#include <algorithm>
#include <bitset>
#include <cassert> // for assert
#include <cstdint> // for int64_t
#include <cstdlib> // for std::exit
#include <fstream>
#include <iostream>
#include <iostream> // for std::cerr
#include <map>
#include <mutex>
#include <random>
#include <sstream>
#include <string>
#include <vector>

#include "option.h"
#include "misc.h"

class GameState;

std::map<Wrappers::WID, Wrappers::WSector> Sectors::sectors;
bool Sectors::created = false;

std::map<Wrappers::WID, Wrappers::WSector> Sectors::get_sectors()
{
    if (!created) {
        Wrappers::Init::init_symmetry_lookup_tables();
        Wrappers::Init::init_sec_vals();
        // sectors.clear();

        for (int w = 0; w <= Rules::maxKSZ; ++w) {
            for (int b = 0; b <= Rules::maxKSZ; ++b) {
                for (int whiteFree = 0; whiteFree <= Rules::maxKSZ;
                     ++whiteFree) {
                    for (int blackFree = 0; blackFree <= Rules::maxKSZ;
                         ++blackFree) {
                        std::string fileName = Rules::variantName + "_" +
                                               std::to_string(w) + "_" +
                                               std::to_string(b) + "_" +
                                               std::to_string(whiteFree) + "_" +
                                               std::to_string(blackFree) +
                                               ".sec" +
                                               Wrappers::Constants::fname_suffix;
                        // std::cout << "Looking for database file " <<
                        // fileName << std::endl;
                        Wrappers::WID _id(w, b, whiteFree, blackFree);
#ifdef _WIN32
                        std::ifstream file(secValPath + "\\" + fileName);
#else
                        std::ifstream file(secValPath + "/" + fileName);
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
}

bool Sectors::has_database()
{
    return get_sectors().size() > 0;
}

// The object is informed to enter the specified game
void Player::enter_game(Game *_g)
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
    // Allow running with trap-only DB (no sectors present)
    secs = Sectors::get_sectors();
}

void PerfectPlayer::enter_game(Game *_g)
{
    Player::enter_game(_g);
}

Wrappers::WSector *PerfectPlayer::get_sector(GameState s)
{
    if (s.kle)
        return nullptr;

    Wrappers::WID id_val(s.stoneCount[0], s.stoneCount[1],
                         Rules::maxKSZ - s.setStoneCount[0],
                         Rules::maxKSZ - s.setStoneCount[1]);

    if (s.sideToMove == 1) {
        id_val.negate_id();
    }

    auto iter = secs.find(id_val);
    if (iter == secs.end()) {
        SET_ERROR_CODE(PerfectErrors::PE_DATABASE_NOT_FOUND, "Key not found in "
                                                             "secs");
        return nullptr;
    }
    return &(iter->second);
}

std::string PerfectPlayer::to_human_readable_eval(Wrappers::gui_eval_elem2 e)
{
    return e.to_string();
}

int PerfectPlayer::get_future_piece_count(const GameState &s)
{
    return s.stoneCount[s.sideToMove] + Rules::maxKSZ -
           s.setStoneCount[s.sideToMove]; // TODO: refactor to call to
                                          // get_future_piece_count
}

bool PerfectPlayer::makes_mill(const GameState &s, int from, int to)
{
    GameState s2 = s;
    if (from != -1)
        s2.board[from] = -1;
    s2.board[to] = s.sideToMove;
    return -1 != Rules::check_mill(to, s2);
}

bool PerfectPlayer::isMill(const GameState &s, int m)
{
    return -1 != Rules::check_mill(m, s);
}

std::vector<AdvancedMove> PerfectPlayer::set_moves(const GameState &s)
{
    std::vector<AdvancedMove> r;
    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == -1) {
            r.push_back(AdvancedMove {i, i, CMoveType::SetMove,
                                      makes_mill(s, -1, i), false, 0});
        }
    }
    return r;
}

std::vector<AdvancedMove> PerfectPlayer::slide_moves(const GameState &s)
{
    std::vector<AdvancedMove> r;
    for (int i = 0; i < 24; ++i) {
        for (int j = 0; j < 24; ++j) {
            if (s.board[i] == s.sideToMove && s.board[j] == -1 &&
                (get_future_piece_count(s) == 3 || Rules::boardGraph[i][j])) {
                r.push_back(AdvancedMove {i, j, CMoveType::SlideMove,
                                          makes_mill(s, i, j), false, 0});
            }
        }
    }
    return r;
}

// m has a withTaking step, where takeHon is not filled out. This function
// creates a list, the elements of which are copies of m supplemented with one
// possible removal each.
std::vector<AdvancedMove> PerfectPlayer::with_taking_moves(const GameState &s,
                                                           AdvancedMove &m)
{
    std::vector<AdvancedMove> r;
    bool everythingInMill = true;
    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 1 - s.sideToMove && !isMill(s, i)) {
            everythingInMill = false;
        }
    }

    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 1 - s.sideToMove &&
            (!isMill(s, i) || everythingInMill)) {
            AdvancedMove m2 = m;
            m2.takeHon = i;
            r.push_back(m2);
        }
    }
    return r;
}

std::vector<AdvancedMove> PerfectPlayer::only_taking_moves(const GameState &s)
{
    // there's some copy-paste code here
    std::vector<AdvancedMove> r;
    bool everythingInMill = true;
    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 1 - s.sideToMove && !isMill(s, i)) {
            everythingInMill = false;
        }
    }

    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 1 - s.sideToMove &&
            (!isMill(s, i) || everythingInMill)) {
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

std::vector<AdvancedMove> PerfectPlayer::get_move_list(const GameState &s)
{
    std::vector<AdvancedMove> ms0, ms;
    if (!s.kle) {
        if (ruleVariant == (int)Wrappers::Constants::Variants::std ||
            ruleVariant == (int)Wrappers::Constants::Variants::mora) {
            if (s.setStoneCount[s.sideToMove] < Rules::maxKSZ) {
                ms0 = set_moves(s);
            } else {
                ms0 = slide_moves(s);
            }
        } else { // Lasker
            ms0 = slide_moves(s);
            if (s.setStoneCount[s.sideToMove] < Rules::maxKSZ) {
                std::vector<AdvancedMove> setMovesResult = set_moves(s);
                ms0.insert(ms0.end(), setMovesResult.begin(),
                           setMovesResult.end());
            }
        }

        for (size_t i = 0; i < ms0.size(); ++i) {
            if (!ms0[i].withTaking) {
                ms.push_back(ms0[i]);
            } else {
                std::vector<AdvancedMove> withTakingMovesResult =
                    with_taking_moves(s, ms0[i]);
                ms.insert(ms.end(), withTakingMovesResult.begin(),
                          withTakingMovesResult.end());
            }
        }
    } else { // kle
        ms = only_taking_moves(s);
    }
    return ms;
}

#ifdef _MSC_VER
#pragma warning(pop)
#pragma warning(pop)
#endif

GameState PerfectPlayer::make_move_in_state(const GameState &s, AdvancedMove &m)
{
    GameState s2(s);
    if (!m.onlyTaking) {
        if (m.moveType == CMoveType::SetMove) {
            s2.make_move(new SetPiece(m.to));
            if (PerfectErrors::hasError()) {
                return s2;
            }
        } else {
            s2.make_move(new MovePiece(m.from, m.to));
            if (PerfectErrors::hasError()) {
                return s2;
            }
        }
        if (m.withTaking) {
            s2.make_move(new RemovePiece(m.takeHon));
            if (PerfectErrors::hasError()) {
                return s2;
            }
        }
    } else {
        s2.make_move(new RemovePiece(m.takeHon));
        if (PerfectErrors::hasError()) {
            return s2;
        }
    }
    return s2;
}

// Assuming gui_eval_elem2 and get_sector functions are defined somewhere
Wrappers::gui_eval_elem2 PerfectPlayer::move_value(const GameState &s,
                                                   AdvancedMove &m)
{
    GameState s2 = make_move_in_state(s, m);
    if (PerfectErrors::hasError()) {
        return Wrappers::gui_eval_elem2::min_value(nullptr);
    }
    auto val = evaluate(s2);
    if (PerfectErrors::hasError()) {
        return Wrappers::gui_eval_elem2::min_value(nullptr);
    }
    return val.undo_negate(get_sector(s));
}

template <typename T, typename K>
std::vector<T> PerfectPlayer::get_all_max_by(std::function<K(T)> f,
                                             const std::vector<T> &l,
                                             K minValue, Value &value)
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
            std::string eStr = e.to_string();

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

    char e = (r.empty() ? 'L' : f(r[0]).to_string()[0]);

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
std::vector<AdvancedMove> PerfectPlayer::get_good_moves(const GameState &s,
                                                        Value &value)
{
    return get_all_max_by(
        std::function<Wrappers::gui_eval_elem2(AdvancedMove)>(
            [this, &s](AdvancedMove m) { return move_value(s, m); }),
        get_move_list(s), Wrappers::gui_eval_elem2::min_value(get_sector(s)),
        value);
}
#else
std::vector<AdvancedMove> PerfectPlayer::get_good_moves(const GameState &s,
                                                        Value &value)
{
    auto moveList = get_move_list(s);
    std::cout << "Move list size: " << moveList.size() << std::endl;

    std::function<Wrappers::gui_eval_elem2(AdvancedMove)> evalFunction =
        [this, &s](AdvancedMove m) {
            auto value = move_value(s, m);
            std::cout << "Evaluating move from " << m.from << " to " << m.to
                      << " with score: " << value.to_string() << std::endl;
            return value;
        };

    auto bestMoves = get_all_max_by(
        evalFunction, moveList,
        Wrappers::gui_eval_elem2::min_value(get_sector(s)), value);

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

int PerfectPlayer::get_ngma_after_move(const GameState &s, AdvancedMove &m)
{
    return get_num_good_moves(make_move_in_state(s, m));
}

void PerfectPlayer::send_move_to_gui(AdvancedMove m)
{
    if (!m.onlyTaking) {
        if (m.moveType == CMoveType::SetMove) {
            g->make_move(new SetPiece(m.to));
            if (PerfectErrors::hasError()) {
                std::cerr << "Error in send_move_to_gui (SetPiece): "
                          << PerfectErrors::getLastErrorMessage() << std::endl;
                return;
            }
        } else {
            g->make_move(new MovePiece(m.from, m.to));
            if (PerfectErrors::hasError()) {
                std::cerr << "Error in send_move_to_gui (MovePiece): "
                          << PerfectErrors::getLastErrorMessage() << std::endl;
                return;
            }
        }
    } else {
        g->make_move(new RemovePiece(m.takeHon));
        if (PerfectErrors::hasError()) {
            std::cerr << "Error in send_move_to_gui (RemovePiece): "
                      << PerfectErrors::getLastErrorMessage() << std::endl;
            return;
        }
    }
}

int PerfectPlayer::get_num_good_moves(const GameState &s)
{
    if (get_future_piece_count(s) < 3)
        return 0; // Assuming get_future_piece_count function is defined
    auto ma = Wrappers::gui_eval_elem2::min_value(get_sector(s)); // Assuming
                                                                  // get_sector
                                                                  // function is
                                                                  // defined
    AdvancedMove mh;
    int c = 0;
    for (auto &m : get_move_list(s)) {
        auto e = move_value(s, m);
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

Wrappers::gui_eval_elem2 PerfectPlayer::evaluate(GameState s)
{
    std::lock_guard<std::mutex> lock(evalLock);

    if (s.kle) {
        return Wrappers::gui_eval_elem2::min_value(nullptr);
    }

    if (get_future_piece_count(s) < 3) {
        return Wrappers::gui_eval_elem2::virt_loss_val();
    }

    // If we have a trap DB and it marks this position as a trap leading to
    // loss, return a decisively losing evaluation immediately to steer move
    // selection.
    if (TrapDB::has_trap_db()) {
        const uint8_t mask = TrapDB::get_trap_mask(s);
        if (mask & (TrapDB::Trap_SelfMillLoss | TrapDB::Trap_BlockMillLoss)) {
            // Represent strong loss. Keep steps unknown; consumers only need
            // WDL.
            return Wrappers::gui_eval_elem2::virt_loss_val();
        }
    }

    Wrappers::WSector *sec = get_sector(s);
    if (PerfectErrors::hasError()) {
        return Wrappers::gui_eval_elem2::min_value(nullptr);
    }
    if (sec == nullptr) {
        SET_ERROR_CODE(PerfectErrors::PE_RUNTIME_ERROR, "get_sector returned "
                                                        "null without setting "
                                                        "an error");
        return Wrappers::gui_eval_elem2::min_value(nullptr);
    }

    // Manually calculate the board hash value (re-instating logic from a
    // previous version)
    int64_t board_hash = 0;
    for (int i = 0; i < 24; ++i) {
        if (s.board[i] == 0) { // White stone
            board_hash |= (1LL << i);
        } else if (s.board[i] == 1) { // Black stone
            board_hash |= (1LL << (i + 24));
        }
    }

    // Negate board if it's black's turn
    if (s.sideToMove == 1) {
        board_hash = negate_board(board_hash);
    }

    // Use the WSector's hash method to get the correct index
    int hash_index = sec->hash(board_hash).first;
    if (PerfectErrors::hasError()) {
        return Wrappers::gui_eval_elem2::min_value(nullptr);
    }

    // Get the raw evaluation and then convert it to the required wrapper type
    eval_elem2 raw_eval = sec->s->get_eval(hash_index);
    return Wrappers::gui_eval_elem2(raw_eval, sec->s);
}

bool PerfectPlayer::blocks_opponent_mill(const GameState &s,
                                         const AdvancedMove &m)
{
    if (m.onlyTaking)
        return false;
    GameState before = s;
    GameState after = make_move_in_state(s, const_cast<AdvancedMove &>(m));
    if (PerfectErrors::hasError()) {
        PerfectErrors::clearError();
        return false;
    }
    GameState sOpp = before;
    sOpp.sideToMove = 1 - before.sideToMove;
    int cntBefore = 0;
    for (auto &mm : get_move_list(sOpp)) {
        if (mm.withTaking)
            cntBefore++;
    }
    if (cntBefore == 0)
        return false;
    GameState sOppAfter = after;
    sOppAfter.sideToMove = 1 - after.sideToMove;
    int cntAfter = 0;
    for (auto &mm : get_move_list(sOppAfter)) {
        if (mm.withTaking)
            cntAfter++;
    }
    return cntAfter < cntBefore;
}

int64_t PerfectPlayer::negate_board(int64_t a)
{
    return ((a & mask24) << 24) | ((a & (mask24 << 24)) >> 24);
}

AdvancedMove PerfectPlayer::get_best_move_trap_aware(const GameState &s,
                                                     const Move &refMove,
                                                     Value &value)
{
    using namespace PerfectErrors;

    // Generate all legal moves from current position
    std::vector<AdvancedMove> allMoves = get_move_list(s);
    if (allMoves.empty()) {
        SET_ERROR_CODE(PE_RUNTIME_ERROR, "No legal moves available");
        return AdvancedMove {};
    }

    // Read the current trap mask for the side to move
    const uint8_t curMask = TrapDB::has_trap_db() ? TrapDB::get_trap_mask(s) :
                                                    0;

    // Send trap information to GUI via UCI info command
    if (curMask != TrapDB::Trap_None && TrapDB::has_trap_db()) {
        std::ostringstream trapInfo;
        trapInfo << "info trap detected";

        if (curMask & TrapDB::Trap_SelfMillLoss) {
            trapInfo << " selfmill";
        }
        if (curMask & TrapDB::Trap_BlockMillLoss) {
            trapInfo << " blockmill";
        }

        // Add WDL and steps information if available
        int8_t trapWdl = TrapDB::get_trap_wdl(s);
        int16_t trapSteps = TrapDB::get_trap_steps(s);

        if (trapWdl != 0) {
            trapInfo << " wdl " << static_cast<int>(trapWdl);
        }
        if (trapSteps > 0) {
            trapInfo << " steps " << trapSteps;
        }

        sync_cout << trapInfo.str() << sync_endl;
    }

    // Step 1: filter out self-trap moves based on the current mask
    std::vector<AdvancedMove> safeMoves;
    safeMoves.reserve(allMoves.size());
    for (auto m : allMoves) {
        bool isSelfTrap = false;

        // Self-mill-loss traps: avoid forming a mill if the mask says so
        if ((curMask & TrapDB::Trap_SelfMillLoss) && m.withTaking) {
            isSelfTrap = true;
        }

        // Block-mill-loss traps: avoid moves that reduce opponent's mill-making
        // if mask says so
        if (!isSelfTrap && (curMask & TrapDB::Trap_BlockMillLoss) &&
            blocks_opponent_mill(s, m)) {
            isSelfTrap = true;
        }

        if (!isSelfTrap) {
            safeMoves.push_back(m);
        }
    }

    if (safeMoves.empty()) {
        // No safe moves remain. As a fallback, pick from all moves
        // to ensure the engine remains functional under zugzwang-like
        // conditions, even if the policy cannot avoid a trap.
        const bool shuffleAll = gameOptions.getShufflingEnabled();
        return shuffleAll ? chooseRandom(allMoves, refMove) : allMoves.front();
    }

    // Step 2: among safe moves, prefer those that create a trap for the
    // opponent Use a struct to track both move and its priority (steps to force
    // trap)
    struct TrapMove
    {
        AdvancedMove move;
        int16_t steps;  // Step count to reach trap result
        bool isWinTrap; // true if trap leads to win, false if draw

        TrapMove(const AdvancedMove &m, int16_t s, bool w)
            : move(m)
            , steps(s)
            , isWinTrap(w)
        { }
    };

    std::vector<TrapMove> oppTrapMoves; // All moves that create opponent traps

    for (auto m : safeMoves) {
        GameState s2 = make_move_in_state(s, m);
        if (hasError()) {
            clearError();
            continue;
        }
        // After our move, it's opponent to move in s2. If s2 has any trap flags
        // for the side to move (the opponent), then this move creates a trap.
        const uint8_t oppMask = TrapDB::has_trap_db() ?
                                    TrapDB::get_trap_mask(s2) :
                                    0;
        if (oppMask != TrapDB::Trap_None) {
            // Determine theoretical value of s2 for prioritizing trap-creating
            // moves
            bool isWin = false;
            bool isDraw = true;
            int stepCount = -1; // For move prioritization based on forcing
                                // speed

            // First check if we have WDL and steps from TrapDB for the opponent
            // position
            if (TrapDB::has_trap_db()) {
                int8_t trapWdl = TrapDB::get_trap_wdl(s2);
                int16_t trapSteps = TrapDB::get_trap_steps(s2);

                if (trapWdl == 1) { // Win for opponent = Loss for us = Good
                                    // trap
                    isWin = true;
                    isDraw = false;
                    stepCount = trapSteps;
                } else if (trapWdl == 0) { // Draw for opponent = Neutral trap
                    isWin = false;
                    isDraw = true;
                    stepCount = trapSteps;
                } else if (trapWdl == -1) { // Loss for opponent = Win for us =
                                            // Excellent trap
                    isWin = true;
                    isDraw = false;
                    stepCount = trapSteps;
                }
            }

            // Fallback to Perfect DB evaluation if TrapDB doesn't have this
            // position
            if (stepCount == -1 && Sectors::has_database()) {
                auto e2 = evaluate(s2);
                std::string str = e2.to_string();
                if (!str.empty()) {
                    char c = str[0];
                    if (c == 'W') {
                        isWin = true;
                        isDraw = false;
                    } else if (c == 'D' || c == '0' || c == 'N') {
                        isWin = false;
                        isDraw = true;
                    } else if (c == 'L') {
                        isWin = false;
                        isDraw = false;
                    }
                }
            }

            // Add this trap-creating move to our collection with step-based
            // priority
            if (isWin || isDraw) { // Only collect moves that don't lead to
                                   // immediate loss
                oppTrapMoves.emplace_back(m, stepCount, isWin);
            }
        }
    }

    const bool shuffle = gameOptions.getShufflingEnabled();

    // Step 2a: Sort trap moves by priority if we have step information
    if (!oppTrapMoves.empty()) {
        // Sort by priority: win traps first, then by fewer steps (faster
        // forcing)
        std::sort(oppTrapMoves.begin(), oppTrapMoves.end(),
                  [](const TrapMove &a, const TrapMove &b) {
                      // Primary: win traps beat draw traps
                      if (a.isWinTrap != b.isWinTrap) {
                          return a.isWinTrap > b.isWinTrap;
                      }
                      // Secondary: among same trap type, prefer faster forcing
                      // (fewer steps) Handle unknown steps (-1) by treating
                      // them as worst (highest value)
                      int16_t aSteps = (a.steps == -1) ? 32767 : a.steps;
                      int16_t bSteps = (b.steps == -1) ? 32767 : b.steps;
                      return aSteps < bSteps;
                  });

        // Set appropriate value based on best trap type found
        value = oppTrapMoves[0].isWinTrap ? VALUE_MAKE_TRAP_WIN :
                                            VALUE_MAKE_TRAP_DRAW;

        if (shuffle) {
            // If shuffling, pick randomly from moves with the same priority as
            // the best
            std::vector<AdvancedMove> samePriorityMoves;
            bool bestIsWin = oppTrapMoves[0].isWinTrap;
            int16_t bestSteps = oppTrapMoves[0].steps;

            for (const auto &trapMove : oppTrapMoves) {
                if (trapMove.isWinTrap == bestIsWin &&
                    trapMove.steps == bestSteps) {
                    samePriorityMoves.push_back(trapMove.move);
                } else {
                    break; // Since sorted, we can stop at first different
                           // priority
                }
            }
            return chooseRandom(samePriorityMoves, refMove);
        } else {
            return oppTrapMoves[0].move;
        }
    }

    // Step 3: no trap can be created. Fall back to the Perfect DB selection if
    // available.
    if (Sectors::has_database()) {
        Value dummy = VALUE_ZERO;
        std::vector<AdvancedMove> best = get_all_max_by(
            std::function<Wrappers::gui_eval_elem2(AdvancedMove)>(
                [this, &s](AdvancedMove mEval) {
                    return move_value(s, mEval);
                }),
            safeMoves, Wrappers::gui_eval_elem2::min_value(get_sector(s)),
            dummy);

        if (best.empty()) {
            SET_ERROR_CODE(PE_RUNTIME_ERROR, "Perfect DB selection failed on "
                                             "safe moves");
            return shuffle ? chooseRandom(safeMoves, refMove) :
                             safeMoves.front();
        }
        value = dummy;
        return chooseRandom(best, refMove);
    }

    // No sectors: pick among safe moves by policy (value stays intact)
    return shuffle ? chooseRandom(safeMoves, refMove) : safeMoves.front();
}
