/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef POSITION_H_INCLUDED
#define POSITION_H_INCLUDED

#include <cassert>
#include <deque>
#include <memory> // For std::unique_ptr
#include <string>
#include <vector>

#include "types.h"
#include "rule.h"
#include "stack.h"

/// StateInfo struct stores information needed to restore a Position object to
/// its previous state when we retract a move. Whenever a move is made on the
/// board (by calling Position::do_move), a StateInfo object must be passed.

struct StateInfo
{
    // Copied when making a move
    int    rule50 {0};
    int    pliesFromNull;

    // Not copied when making a move (will be recomputed anyhow)
    Key        key;
};


/// Position class stores information regarding the board representation as
/// pieces, side to move, hash keys, castling info, etc. Important methods are
/// do_move() and undo_move(), used by the search to update node info when
/// traversing the search tree.
class Thread;

class Position
{
public:
    static void init();

    Position();

    Position(const Position &) = delete;
    Position &operator=(const Position &) = delete;

    // FEN string input/output
    Position &set(const std::string &fenStr, Thread *th);
    const std::string fen() const;

    // Position representation
    Piece piece_on(Square s) const;
    Color color_on(Square s) const;
    bool empty(Square s) const;
    template<PieceType Pt> int count(Color c) const;

    // Properties of moves
    bool legal(Move m) const;
    bool pseudo_legal(const Move m) const;
    Piece moved_piece(Move m) const;

    // Doing and undoing moves
    void do_move(Move m);
    void undo_move(Move m);
    void undo_move(Sanmill::Stack<Position> &ss);
    void do_null_move();
    void undo_null_move();

    // Accessing hash keys
    Key key() const;
    Key key_after(Move m) const;
    void construct_key();
    Key revert_key(Square s);
    Key update_key(Square s);
    Key update_key_misc();

    // Other properties of the position
    Color side_to_move() const;
    int game_ply() const;
    Thread *this_thread() const;
    bool is_draw(int ply) const;
    bool has_game_cycle(int ply) const;
    bool has_repeated() const;
    int rule50_count() const;

    // Position consistency check, for debugging
    bool pos_is_ok() const;
    void flip();

    /// Mill Game

    int set_position(const struct Rule *rule);

    Piece *get_board();
    Square current_square() const;
    enum Phase get_phase() const;
    enum Action get_action() const;
    const char *cmd_line() const;

    int get_mobility_diff(bool includeFobidden);

    bool reset();
    bool start();
    bool resign(Color loser);
    bool command(const char *cmd);
    void update();
    void update_score();
    bool check_gameover_condition();
    void remove_ban_stones();
    void set_side_to_move(Color c);
  
    void change_side_to_move();
    Color get_winner() const;
    void set_gameover(Color w, GameOverReason reason);

    void mirror(std::vector <std::string> &cmdlist, bool cmdChange = true);
    void turn(std::vector <std::string> &cmdlist, bool cmdChange = true);
    void rotate(std::vector <std::string> &cmdlist, int degrees, bool cmdChange = true);

    void create_mill_table();
    int add_mills(Square s);
    int in_how_many_mills(Square s, Color c, Square squareSelected = SQ_0);
    bool is_all_in_mills(Color c);

    int surrounded_empty_squares_count(Square s, bool includeFobidden);
    void surrounded_pieces_count(Square s, int &nOurPieces, int &nTheirPieces, int &nBanned, int &nEmpty);
    bool is_all_surrounded() const;

    static void print_board();

    int pieces_on_board_count();
    int pieces_in_hand_count();

    int pieces_count_on_board(Color c);
    int pieces_count_in_hand(Color c);

    int piece_count_need_remove();

    static bool is_star_square(Square s);

// private:
      // Initialization helpers (used while setting up a position)
    void set_state(StateInfo *si) const;

    // Other helpers
    bool select_piece(Square s);
    bool select_piece(File file, Rank rank);

    void put_piece(Piece pc, Square s);
    bool put_piece(File file, Rank rank);
    bool put_piece(Square s, bool updateCmdlist = false);

    bool remove_piece(File file, Rank rank);
    bool remove_piece(Square s, bool updateCmdlist = false);

    bool move_piece(File f1, Rank r1, File f2, Rank r2);
    bool move_piece(Square from, Square to);
    bool undo_move_piece(Square from, Square to);

    // Data members
    Piece board[SQUARE_NB];
    Bitboard byTypeBB[PIECE_TYPE_NB];
    // TODO: [0] is sum of Black and White
    int pieceCountInHand[COLOR_NB]{ 0, 12, 12 }; // TODO
    int pieceCountOnBoard[COLOR_NB]{ 0, 0, 0 };
    int pieceCountNeedRemove{ 0 };
    int gamePly { 0 };
    Color sideToMove { NOCOLOR };
    Thread *thisThread;
    StateInfo st;
    StateInfo tmpSt;    // TODO

    /// Mill Game
    Color them { NOCOLOR };
    Color winner;
    GameOverReason gameoverReason { NO_REASON };

    enum Phase phase {PHASE_NONE};
    enum Action action;

    int score[COLOR_NB] { 0 };
    int score_draw { 0 };

    static const int onBoard[SQUARE_NB];

    // Relate to Rule
    static int millTable[SQUARE_NB][LD_NB][FILE_NB - 1];

    Square currentSquare;
    int nPlayed { 0 };

    char cmdline[64] { '\0' };

    /*
        0x   00     00     00    00    00    00    00    00
           unused unused piece1 square1 piece2 square2 piece3 square3
    */

    uint64_t millList[4];
    int millListSize { 0 };

    /*
        0x   00    00
            square1  square2
        Placing:0x00??,?? is place location
        Moving:0x__??,__ is from,?? is to
        Removing:0xFF??,?? is neg

        31 ----- 24 ----- 25
        | \       |      / |
        |  23 -- 16 -- 17  |
        |  | \    |   / |  |
        |  |  15 08 09  |  |
        30-22-14    10-18-26
        |  |  13 12 11  |  |
        |  | /    |   \ |  |
        |  21 -- 20 -- 19  |
        | /       |     \  |
        29 ----- 28 ----- 27
    */
    Move move { MOVE_NONE };
};

extern std::ostream &operator<<(std::ostream &os, const Position &pos);

inline Color Position::side_to_move() const
{
    return sideToMove;
}

inline Piece Position::piece_on(Square s) const
{
    assert(is_ok(s));
    return board[s];
}

inline bool Position::empty(Square s) const
{
    return piece_on(s) == NO_PIECE;
}

inline Piece Position::moved_piece(Move m) const
{
    return piece_on(from_sq(m));
}

template<PieceType Pt> inline int Position::count(Color c) const
{
    if (Pt == ON_BOARD) {
        return pieceCountOnBoard[c];
    } else if (Pt == IN_HAND) {
        return pieceCountInHand[c];
    }

    return 0;
}

inline Key Position::key() const
{
    return st.key;
}

inline void Position::construct_key()
{
    st.key = 0;
}

inline int Position::game_ply() const
{
    return gamePly;
}

inline int Position::rule50_count() const
{
    return st.rule50;
}

inline Thread *Position::this_thread() const
{
    return thisThread;
}

inline bool Position::select_piece(File f, Rank r)
{
    return select_piece(make_square(f, r));
}

#if 0
inline void Position::put_piece(Piece pc, Square s)
{
    // TODO: put_piece

    board[s] = pc;
    byTypeBB[ALL_PIECES] |= s;
    byTypeBB[type_of(pc)] |= s;
    byColorBB[color_of(pc)] |= s;
    index[s] = pieceCount[pc]++;
    pieceList[pc][index[s]] = s;
    pieceCount[make_piece(color_of(pc), ALL_PIECES)]++;
}
#endif

inline bool Position::put_piece(File f, Rank r)
{
    bool ret = put_piece(make_square(f, r), true);

    if (ret) {
        update_score();
    }

    return ret;
}

inline bool Position::move_piece(File f1, Rank r1, File f2, Rank r2)
{
    return move_piece(make_square(f1, r1), make_square(f2, r2));
}

inline bool Position::remove_piece(File f, Rank r)
{
    bool ret = remove_piece(make_square(f, r), true);

    if (ret) {
        update_score();
    }

    return ret;
}

inline bool Position::undo_move_piece(Square from, Square to)
{
    return move_piece(to, from);    // TODO
}

inline bool Position::move_piece(Square from, Square to)
{
#if 0
    // index[from] is not updated and becomes stale. This works as long as index[]
    // is accessed just by known occupied squares.
    Piece pc = board[from];
    Bitboard fromTo = from | to;
    byTypeBB[ALL_PIECES] ^= fromTo;
    byTypeBB[type_of(pc)] ^= fromTo;
    byColorBB[color_of(pc)] ^= fromTo;
    board[from] = NO_PIECE;
    board[to] = pc;
    index[to] = index[from];
    pieceList[pc][index[to]] = to;
#endif

    if (select_piece(from)) {
        return put_piece(to);
    }

    return false;
}


/// Mill Game

inline Piece *Position::get_board()
{
    return (Piece *)board;
}

inline Square Position::current_square() const
{
    return currentSquare;
}

inline enum Phase Position::get_phase() const
{
    return phase;
}

inline enum Action Position::get_action() const
{
    return action;
}

inline const char *Position::cmd_line() const
{
    return cmdline;
}

inline int Position::pieces_count_on_board(Color c)
{
    return pieceCountOnBoard[c];
}

inline int Position::pieces_count_in_hand(Color c)
{
    return pieceCountInHand[c];
}

inline int Position::piece_count_need_remove()
{
    return pieceCountNeedRemove;
}

#endif // #ifndef POSITION_H_INCLUDED
