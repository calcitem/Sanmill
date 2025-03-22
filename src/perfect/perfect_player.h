// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2007-2016 Gabor E. Gevay, Gabor Danner
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// perfect_player.h

#ifndef PERFECT_PERFECT_PLAYER_H_INCLUDED
#define PERFECT_PERFECT_PLAYER_H_INCLUDED

#include "perfect_adaptor.h"
#include "perfect_common.h"
#include "perfect_game.h"
#include "perfect_move.h"
#include "perfect_rules.h"
#include "perfect_sector.h"
#include "perfect_wrappers.h"

#include <bitset>
#include <cassert>   // for assert
#include <cstdint>   // for int64_t
#include <cstdlib>   // for std::exit
#include <exception> // for std::exception
#include <fstream>
#include <functional>
#include <iostream>
#include <iostream>
#include <map>
#include <mutex>
#include <random>
#include <stdexcept>
#include <stdexcept> // for std::out_of_range
#include <string>
#include <vector>

#include "option.h"
#include "types.h"

enum class CMoveType {
    SetMove,
    SlideMove // should be renamed to SlideOrJumpMove
};

struct AdvancedMove
{
    int from, to;
    CMoveType moveType;
    bool withTaking, onlyTaking; // withTaking includes the steps in mill
                                 // closure, onlyTaking only includes removal
    int takeHon;

    Value value {VALUE_DRAW};

    int toBitBoard()
    {
        if (onlyTaking) {
            return 1 << takeHon;
        }
        int ret = 1 << to;
        if (moveType == CMoveType::SlideMove) {
            ret += 1 << from;
        }
        if (withTaking) {
            ret += 1 << takeHon;
        }
        return ret;
    }
};

class Sectors
{
public:
    static std::map<Wrappers::WID, Wrappers::WSector> sectors;
    static bool created;

    static std::map<Wrappers::WID, Wrappers::WSector> get_sectors();

    static bool has_database();
};

class Player
{
protected:
    Game *g {nullptr}; // Assuming Game is a pre-defined class

public:
    Player()
        : g(nullptr)
    { }

    // The object is informed to enter the specified game
    virtual void enter_game(Game *_g);

    // The object is informed to exit from the game
    virtual void quit();

    // Notifies about the opponent's move
    virtual void followMove(CMove *) { } // Assuming Object is a pre-defined
                                         // class or built-in type

    // The object is informed that it is the opponent's turn to move
    virtual void oppToMove(const GameState &) { }

    // Game is over
    virtual void over(const GameState &) { }

    // Cancel thinking
    virtual void cancel_thinking() { }

    // Determine the opponent player
protected:
    Player *opponent()
    {
        return (g->get_player(0) == this) ? g->get_player(1) :
                                            g->get_player(0); // Assuming Game
                                                              // has a
                                                              // get_player
                                                              // function
    }
};

class PerfectPlayer : public Player
{
public:
    std::map<Wrappers::WID, Wrappers::WSector> secs;

    PerfectPlayer();
    virtual ~PerfectPlayer() { }

    void enter_game(Game *_g) override;

    void quit() override { Player::quit(); }

    Wrappers::WSector *get_sector(const GameState s);

    std::string to_human_readable_eval(Wrappers::gui_eval_elem2 e);

    int get_future_piece_count(const GameState &s);

    bool makes_mill(const GameState &s, int from, int to);

    bool isMill(const GameState &s, int m);

    std::vector<AdvancedMove> set_moves(const GameState &s);

    std::vector<AdvancedMove> slide_moves(const GameState &s);

    // m has a withTaking step, where takeHon is not filled out. This function
    // creates a list, the elements of which are copies of m supplemented with
    // one possible removal each.
    std::vector<AdvancedMove> with_taking_moves(const GameState &s,
                                                AdvancedMove &m);

    std::vector<AdvancedMove> only_taking_moves(const GameState &s);

    std::vector<AdvancedMove> get_move_list(const GameState &s);

    GameState make_move_in_state(const GameState &s, AdvancedMove &m);

    // Assuming gui_eval_elem2 and get_sector functions are defined somewhere
    Wrappers::gui_eval_elem2 move_value(const GameState &s, AdvancedMove &m);

    template <typename T, typename K>
    std::vector<T> get_all_max_by(std::function<K(T)> f,
                                  const std::vector<T> &l, K minValue,
                                  Value &value);

    // Assuming the definition of gui_eval_elem2::min_value function
    std::vector<AdvancedMove> get_good_moves(const GameState &s, Value &value);

    int get_ngma_after_move(const GameState &s, AdvancedMove &m);

    template <typename T>
    T chooseRandom(const std::vector<T> &l, const Move &refMove)
    {
        static std::random_device rd;
        static std::mt19937 gen(rd());

        AdvancedMove advMoveRef {};
        auto m = refMove;
        const Square from = from_sq(m);
        const Square to = to_sq(m);

        auto it = l.end();

        if (refMove == MOVE_NONE) {
            goto out;
        }

        if (m < 0) {
            advMoveRef.takeHon = to_perfect_square(to);
        } else if (m & 0x7f00) {
            advMoveRef.from = to_perfect_square(from);
            advMoveRef.to = to_perfect_square(to);
        } else {
            advMoveRef.to = to_perfect_square(to);
        }

        it = std::find_if(l.begin(), l.end(),
                          [&advMoveRef, m](const auto &elem) {
                              if (m < 0) {
                                  return advMoveRef.takeHon == elem.takeHon;
                              } else if (m & 0x7f00) {
                                  return advMoveRef.from == elem.from &&
                                         advMoveRef.to == elem.to;
                              } else {
                                  return advMoveRef.to == elem.to;
                              }
                          });

        // If the reference move is not in the list, we choose a random move.
        if (it == l.end()) {
            goto out;
        } else {
            return *it;
        }

out:
        if (gameOptions.getShufflingEnabled()) {
            std::uniform_int_distribution<> dis(0,
                                                static_cast<int>(l.size() - 1));
            return l[dis(gen)];
        }

        return l[0];
    }

    void send_move_to_gui(AdvancedMove m);

    int get_num_good_moves(const GameState &s);

    int cp;

    struct MoveValuePair
    {
        AdvancedMove m;
        double val;
    };

    Wrappers::gui_eval_elem2 evaluate(GameState s);

    int64_t negate_board(int64_t a);
};

#endif // PERFECT_PLAYER_H_INCLUDED
