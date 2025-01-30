// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// position.h

#ifndef POSITION_H_INCLUDED
#define POSITION_H_INCLUDED

#include <array>
#include <cassert>
#include <deque>
#include <memory> // For std::unique_ptr
#include <set>
#include <string>
#include <vector>

#include "bitboard.h"
#include "option.h"
#include "rule.h"
#include "stack.h"
#include "types.h"
#include "movegen.h"

#ifdef NNUE_GENERATE_TRAINING_DATA
#include <ostream>
#include <sstream>
#include <string>
using std::ostream;
using std::ostringstream;
using std::string;
#endif /* NNUE_GENERATE_TRAINING_DATA */

/// StateInfo struct stores information needed to restore a Position object to
/// its previous state when we retract a move. Whenever a move is made on the
/// board (by calling Position::do_move), a StateInfo object must be passed.

struct StateInfo
{
    // Copied when making a move
    unsigned int rule50 {0};
    int pliesFromNull;

    // Not copied when making a move (will be recomputed anyhow)
    Key key;
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
#if 1
    ~Position()
    {
        // formedMills.at(WHITE).clear();
        // formedMills.at(BLACK).clear();
    }
#endif

    // Position(const Position &) = delete;
    // Position &operator=(const Position &) = delete;

    // FEN string input/output
    Position &set(const std::string &fenStr);
    std::string fen() const;
#ifdef NNUE_GENERATE_TRAINING_DATA
    string Position::nnueGetOpponentGameResult();
    string Position::nnueGetCurSideGameResult(char lastSide, const string &fen);
    void nnueGenerateTrainingFen();
    void nnueWriteTrainingData();
#endif /* NNUE_GENERATE_TRAINING_DATA */

    // Position representation
    Piece piece_on(Square s) const;
    Color color_on(Square s) const;
    bool empty(Square s) const;
    template <PieceType Pt>
    int count(Color c) const;

    // Properties of moves
    bool legal(Move m) const;
    Piece moved_piece(Move m) const;

    // Doing and undoing moves
    void do_move(Move m);
    void undo_move(Sanmill::Stack<Position> &ss);

    // Accessing hash keys
    Key key() const noexcept;
    Key key_after(Move m) const;
    void construct_key();
    Key revert_key(Square s);
    Key update_key(Square s);
    Key update_key_misc();

    // Other properties of the position
    Color side_to_move() const;
    int game_ply() const;
    bool has_game_cycle() const;
    bool has_repeated(Sanmill::Stack<Position> &ss) const;
    unsigned int rule50_count() const;

    /// Mill Game

    Piece *get_board() noexcept;
    Square current_square() const;
    Square last_mill_from_square() const;
    Square last_mill_to_square() const;
    Phase get_phase() const;
    Action get_action() const;
    const char *get_record() const;

    bool reset();
    bool start();
    bool resign(Color loser);
    bool command(const char *cmd);
    void update_score();
    bool check_if_game_is_over();
    void remove_marked_pieces();
    void set_side_to_move(Color c);
    void keep_side_to_move();

    void change_side_to_move();
    Color get_winner() const noexcept;
    void set_gameover(Color w, GameOverReason reason);

    bool is_stalemate_removal();

    void flipBoardHorizontally(std::vector<std::string> &gameMoveList,
                               bool cmdChange = true);
    void turn(std::vector<std::string> &gameMoveList, bool cmdChange = true);
    void rotate(std::vector<std::string> &gameMoveList, int degrees,
                bool cmdChange = true);

    void reset_bb();

    static void create_mill_table();
    int mills_count(Square s);

    // The number of mills that would be closed by the given move.
    int potential_mills_count(Square to, Color c, Square from = SQ_0);
    bool is_all_in_mills(Color c);

    void setFormedMillsBB(uint64_t millsBitmask);

    void surrounded_pieces_count(Square s, int &ourPieceCount,
                                 int &theirPieceCount, int &markedCount,
                                 int &emptyCount) const;
    bool is_all_surrounded(Color c) const;

    static void print_board();

    int piece_on_board_count(Color c) const;
    int piece_in_hand_count(Color c) const;

    bool is_board_empty() const;

    int piece_to_remove_count(Color c) const;

    int get_mobility_diff() const;
    void updateMobility(MoveType mt, Square s);
    // template <typename Mt> void updateMobility(Square from, Square to);
    int calculate_mobility_diff();

    bool shouldFocusOnBlockingPaths() const;
    bool shouldConsiderMobility() const;

    bool is_three_endgame() const;

    static bool is_star_square(Square s);

    static bool bitboard_is_ok();

    // Other helpers
    bool select_piece(Square s);
    bool select_piece(File f, Rank r);

    void put_piece(Piece pc, Square s);
    bool put_piece(File f, Rank r);
    bool put_piece(Square s, bool updateRecord = false);
    bool handle_moving_phase_for_put_piece(Square s, bool updateRecord);

    bool remove_piece(File f, Rank r);
    bool remove_piece(Square s, bool updateRecord = false);

    bool move_piece(File f1, Rank r1, File f2, Rank r2);
    bool move_piece(Square from, Square to);

    int total_mills_count(Color c);
    int mills_pieces_count_difference() const;
    void calculate_removal_based_on_mill_counts();
    bool is_board_full_removal_at_placing_phase_end();
    bool is_adjacent_to(Square s, Color c);

    bool handle_placing_phase_end();

    bool can_move_during_placing_phase() const;

    // Data members
    Piece board[SQUARE_EXT_NB];
    Bitboard byTypeBB[PIECE_TYPE_NB];
    Bitboard byColorBB[COLOR_NB];
    int pieceInHandCount[COLOR_NB] {0, 9, 9};
    int pieceOnBoardCount[COLOR_NB] {0, 0, 0};
    int pieceToRemoveCount[COLOR_NB] {0, 0, 0};
    bool isNeedStalemateRemoval {false};
    bool isStalemateRemoving {false};
    int mobilityDiff {0};
    int gamePly {0};
    Color sideToMove {NOBODY};
    Thread *thisThread {nullptr};
    StateInfo st;

    /// Mill Game
    Color them {NOBODY};
    Color winner;
    GameOverReason gameOverReason {GameOverReason::None};

    Phase phase {Phase::none};
    Action action;

    int score[COLOR_NB] {0};
    int score_draw {0};
    int bestvalue {0};

    // Relate to Rule
    static Bitboard millTableBB[SQUARE_EXT_NB][LD_NB];

    Square currentSquare[COLOR_NB] {SQ_NONE, SQ_NONE, SQ_NONE};
    Square lastMillFromSquare[COLOR_NB] {SQ_NONE, SQ_NONE, SQ_NONE};
    Square lastMillToSquare[COLOR_NB] {SQ_NONE, SQ_NONE, SQ_NONE};

    Bitboard formedMillsBB[COLOR_NB] {0};

    int gamesPlayedCount {0};

    static constexpr int RECORD_LEN_MAX = 64;
    char record[RECORD_LEN_MAX] {'\0'};

    Move move {MOVE_NONE};
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

template <PieceType Pt>
int Position::count(Color c) const
{
    if (Pt == ON_BOARD) {
        return pieceOnBoardCount[c];
    }

    if (Pt == IN_HAND) {
        return pieceInHandCount[c];
    }

    return 0;
}

inline Key Position::key() const noexcept
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

inline unsigned int Position::rule50_count() const
{
    return st.rule50;
}

inline bool Position::select_piece(File f, Rank r)
{
    return select_piece(make_square(f, r));
}

inline void Position::put_piece(Piece pc, Square s)
{
    board[s] = pc;
    byTypeBB[ALL_PIECES] |= byTypeBB[type_of(pc)] |= s;
    byColorBB[color_of(pc)] |= s;
}

inline bool Position::put_piece(File f, Rank r)
{
    const bool ret = put_piece(make_square(f, r), true);

    return ret;
}

inline bool Position::move_piece(File f1, Rank r1, File f2, Rank r2)
{
    return move_piece(make_square(f1, r1), make_square(f2, r2));
}

inline bool Position::remove_piece(File f, Rank r)
{
    const bool ret = remove_piece(make_square(f, r), true);

    return ret;
}

inline bool Position::move_piece(Square from, Square to)
{
    if (select_piece(from)) {
        if (put_piece(to)) {
            return true;
        }
    }

    return false;
}

/// Mill Game

inline Piece *Position::get_board() noexcept
{
    return board;
}

inline Square Position::current_square() const
{
    return currentSquare[sideToMove];
}

inline Square Position::last_mill_from_square() const
{
    return lastMillFromSquare[sideToMove];
}

inline Square Position::last_mill_to_square() const
{
    return lastMillToSquare[sideToMove];
}

inline Phase Position::get_phase() const
{
    return phase;
}

inline Action Position::get_action() const
{
    return action;
}

inline const char *Position::get_record() const
{
    return record;
}

inline int Position::piece_on_board_count(Color c) const
{
    return pieceOnBoardCount[c];
}

inline int Position::piece_in_hand_count(Color c) const
{
    return pieceInHandCount[c];
}

inline bool Position::is_board_empty() const
{
    return pieceOnBoardCount[WHITE] + pieceOnBoardCount[BLACK] == 0;
}

inline int Position::piece_to_remove_count(Color c) const
{
    return pieceToRemoveCount[c];
}

inline int Position::get_mobility_diff() const
{
    return mobilityDiff;
}

inline int Position::mills_pieces_count_difference() const
{
    return popcount(formedMillsBB[WHITE]) - popcount(formedMillsBB[BLACK]);
}

inline bool Position::shouldFocusOnBlockingPaths() const
{
    if (get_phase() == Phase::placing) {
        return gameOptions.getFocusOnBlockingPaths();
    } else if (get_phase() == Phase::moving) {
        return gameOptions.getFocusOnBlockingPaths() && rule.mayFly &&
               piece_on_board_count(~side_to_move()) ==
                   rule.piecesAtLeastCount + 1 &&
               // TODO: 9mm is 7 left, and 12mm is 10 left, right?
               piece_on_board_count(side_to_move()) >= rule.pieceCount - 2;
    }
    return false;
}

inline bool Position::shouldConsiderMobility() const
{
    // Note: Either consider mobility or focus on blocking paths
    return gameOptions.getConsiderMobility() ||
           gameOptions.getFocusOnBlockingPaths();
}

inline bool Position::is_three_endgame() const
{
    if (get_phase() == Phase::placing) {
        return false;
    }

    return pieceOnBoardCount[WHITE] == 3 || pieceOnBoardCount[BLACK] == 3;
}

#endif // #ifndef POSITION_H_INCLUDED
