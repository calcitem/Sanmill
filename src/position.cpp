/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

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

#include <algorithm>
#include <cassert>
#include <cstddef> // For offsetof()
#include <cstring> // For std::memset, std::memcmp
#include <iomanip>
#include <sstream>

#include "bitboard.h"
#include "misc.h"
#include "movegen.h"
#include "position.h"
#include "thread.h"
#include "tt.h"
#include "uci.h"

#include "option.h"
#include "rule.h"

using std::string;

namespace Zobrist
{
const int KEY_MISC_BIT = 2;
Key psq[PIECE_TYPE_NB][SQUARE_NB];
Key side;
}

namespace
{
const string  PieceToChar(Piece p)
{
    if (p == NO_PIECE) {
        return "*";
    }

    if (p == BAN_STONE) {
        return "X";
    }

    if (B_STONE <= p && p <= B_STONE_12) {
        return "@";
    }

    if (W_STONE <= p && p <= W_STONE_12) {
        return "O";
    }

    return "*";
}

Piece CharToPiece(char ch)
{

    if (ch == '*') {
        return NO_PIECE;
    }

    if (ch == '@') {
        return B_STONE;
    }

    if (ch == 'O') {
        return W_STONE;
    }

    if (ch == 'X') {
        return BAN_STONE;
    }

    return NO_PIECE;
}

constexpr PieceType PieceTypes[] = { NO_PIECE_TYPE, BLACK_STONE, WHITE_STONE, BAN };
} // namespace


/// operator<<(Position) returns an ASCII representation of the position

std::ostream &operator<<(std::ostream &os, const Position &pos)
{
    /*
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

    /*
    X --- X --- X
    |\    |    /|
    | X - X - X |
    | |\  |  /| |
    | | X-X-X | |
    X-X-X   X-X-X
    | | X-X-X | |
    | |/     \| |
    | X - X - X |
    |/    |    \|
    X --- X --- X
*/

#define P(s) PieceToChar(pos.piece_on(Square(s)))

    os << "\n";
    os << P(31) << " --- " << P(24)<< " --- " << P(25) << "\n";
    os << "|\\    |    /|\n";
    os << "| " << P(23) << " - " << P(16) << " - " << P(17) << " |\n";
    os << "| |\\  |  /| |\n";
    os << "| | " << P(15) << "-" << P(8) << "-" << P(9) << " | |\n";
    os << P(30) << "-" << P(22) << "-" << P(14) << "   " << P(10) << "-" << P(18) << "-" << P(26) << "\n";
    os << "| | " << P(13) << "-" << P(12) << "-" << P(11) << " | |\n";
    os << "| |/     \\| |\n";
    os << "| " << P(21) << " - " << P(20) << " - " << P(19) << " |\n";
    os << "|/    |    \\|\n";
    os << P(29) << " --- " << P(28) << " --- " << P(27) << "\n";

#undef P

    os << "\nFen: " << pos.fen() << "\nKey: " << std::hex << std::uppercase
        << std::setfill('0') << std::setw(16) << pos.key();

    return os;
}


/// Position::init() initializes at startup the various arrays used to compute hash keys

void Position::init()
{
    PRNG rng(1070372);

    for (PieceType pt : PieceTypes)
        for (Square s = SQ_0; s < SQUARE_NB; ++s)
            Zobrist::psq[pt][s] = rng.rand<Key>() << Zobrist::KEY_MISC_BIT >> Zobrist::KEY_MISC_BIT;

    Zobrist::side = rng.rand<Key>() << Zobrist::KEY_MISC_BIT >> Zobrist::KEY_MISC_BIT;

    return;
}

Position::Position()
{
    construct_key();
    
    reset();

    score[BLACK] = score[WHITE] = score_draw = nPlayed = 0;
}


/// Position::set() initializes the position object with the given FEN string.
/// This function is not very robust - make sure that input FENs are correct,
/// this is assumed to be the responsibility of the GUI.

Position &Position::set(const string &fenStr, Thread *th)
{
    /*
       A FEN string defines a particular position using only the ASCII character set.

       A FEN string contains six fields separated by a space. The fields are:

       1) Piece placement. Each rank is described, starting
          with rank 1 and ending with rank 8. Within each rank, the contents of each
          square are described from file A through file C. Following the Standard
          Algebraic Notation (SAN), each piece is identified by a single letter taken
          from the standard English names. White pieces are designated using "O"
          whilst Black uses "@". Blank uses "*". Banned uses "X".
          noted using digits 1 through 8 (the number of blank squares), and "/"
          separates ranks.

       2) Active color. "w" means white moves next, "b" means black.

       3) Phrase.

       4) Act.

       5) Black on board/Black in hand/White on board/White in hand/need to remove

       6) Halfmove clock. This is the number of halfmoves since the last
          capture. This is used to determine if a draw can be claimed under the
          fifty-move rule.

       7) Fullmove number. The number of the full move. It starts at 1, and is
          incremented after Black's move.
    */

    unsigned char token;
    Square sq = SQ_A1;
    std::istringstream ss(fenStr);

    std::memset(this, 0, sizeof(Position));

    ss >> std::noskipws;

    // 1. Piece placement
    while ((ss >> token) && !isspace(token)) {
        if (token == '@' || token == 'O' || token == 'X') {
            put_piece(CharToPiece(token), sq);
            ++sq;
        }
        if (token == '*') {
            ++sq;
        }
    }

    // 2. Active color
    ss >> token;
    sideToMove = (token == 'b' ? BLACK : WHITE);

    // 3. Phrase
    ss >> token;
    ss >> token;

    switch (token) {
    case 'r':
        phase = Phase::ready;
        break;
    case 'p':
        phase = Phase::placing;
        break;
    case 'm':
        phase = Phase::moving;
        break;
    case 'o':
        phase = Phase::gameOver;
        break;
    default:
        phase = Phase::none;
    }

    // 4. Act
    ss >> token;
    ss >> token;

    switch (token) {
    case 'p':
        action = Act::place;
        break;
    case 's':
        action = Act::select;
        break;
    case 'r':
        action = Act::remove;
        break;
    default:
        action = Act::none;
    }
    
    // 5. Black on board / Black in hand / White on board / White in hand / need to remove
    ss >> std::skipws
        >> pieceCountOnBoard[BLACK] >> pieceCountInHand[BLACK]
        >> pieceCountOnBoard[WHITE] >> pieceCountInHand[WHITE]
        >> pieceCountNeedRemove;


    // 6-7. Halfmove clock and fullmove number
    ss >> std::skipws >> st.rule50 >> gamePly;

    // Convert from fullmove starting from 1 to gamePly starting from 0,
    // handle also common incorrect FEN with fullmove = 0.
    gamePly = std::max(2 * (gamePly - 1), 0) + (sideToMove == WHITE);

    thisThread = th;

    assert(pos_is_ok());

    return *this;
}


/// Position::fen() returns a FEN representation of the position.
/// This is mainly a debugging function.

const string Position::fen() const
{
    std::ostringstream ss;

    // Piece placement data
    for (File f = FILE_A; f <= FILE_C; f = (File)(f + 1)) {
        for (Rank r = RANK_1; r <= RANK_8; r = (Rank)(r + 1)) {
            ss << PieceToChar(piece_on(make_square(f, r)));
        }

        if (f == FILE_C) {
            ss << " ";
        } else {
            ss << "/";
        }        
    }

    // Active color
    ss << (sideToMove == WHITE ? "w" : "b");

    ss << " ";

    // Phrase
    switch (phase) {
    case Phase::none:
        ss << "n";
        break;
    case Phase::ready:
        ss << "r";
        break;
    case Phase::placing:
        ss << "p";
        break;
    case Phase::moving:
        ss << "m";
        break;
    case Phase::gameOver:
        ss << "o";
        break;
    default:
        ss << "?";
        break;
    }

    ss << " ";

    // Act
    switch (action) {
    case Act::place:
        ss << "p";
        break;
    case Act::select:
        ss << "s";
        break;
    case Act::remove:
        ss << "r";
        break;
    default:
        ss << "?";
        break;
    }

    ss << " ";

    ss << pieceCountOnBoard[BLACK] << " " << pieceCountInHand[BLACK] << " "
        << pieceCountOnBoard[WHITE] << " " << pieceCountInHand[WHITE] << " "
        << pieceCountNeedRemove << " ";

    ss << st.rule50 << " " << 1 + (gamePly - (sideToMove == BLACK)) / 2;

    return ss.str();
}


/// Position::legal() tests whether a pseudo-legal move is legal

bool Position::legal(Move m) const
{
    assert(is_ok(m));

    Color us = sideToMove;
    Square from = from_sq(m);
    Square to = to_sq(m);

    if (from == to) {
        return false;   // TODO: Same with is_ok(m)
    }

    if (phase == Phase::moving && type_of(move) != MOVETYPE_REMOVE) {
        if (color_of(moved_piece(m)) != us) {
            return false;
        }
    }

    // TODO: Add more

    return true;
}


/// Position::pseudo_legal() takes a random move and tests whether the move is
/// pseudo legal. It is used to validate moves from TT that can be corrupted
/// due to SMP concurrent access or hash position key aliasing.

bool Position::pseudo_legal(const Move m) const
{
    // TODO
    return legal(m);
}


/// Position::do_move() makes a move, and saves all information necessary
/// to a StateInfo object. The move is assumed to be legal. Pseudo-legal
/// moves should be filtered out before this function is called.

void Position::do_move(Move m)
{
#if 0
    assert(is_ok(m));
    assert(&newSt != st);

    thisThread->nodes.fetch_add(1, std::memory_order_relaxed);

    // Copy some fields of the old state to our new StateInfo object except the
    // ones which are going to be recalculated from scratch anyway and then switch
    // our state pointer to point to the new (ready to be updated) state.
    std::memcpy(&newSt, st, offsetof(StateInfo, key));
    newSt.previous = st;
    st = &newSt;
#endif

    bool ret = false;

    MoveType mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        // Reset rule 50 counter
        st.rule50 = 0;
        ret = remove_piece(to_sq(m));
        break;
    case MOVETYPE_MOVE:
        ret = move_piece(from_sq(m), to_sq(m));
        break;
    case MOVETYPE_PLACE:
        ret = put_piece(to_sq(m));
        break;
    default:
        break;
    }

    if (!ret) {
        return;
    }

    // Increment ply counters. In particular, rule50 will be reset to zero later on
    // in case of a capture.
    ++gamePly;
    ++st.rule50;
    ++st.pliesFromNull;
    
    move = m;

#if 0
    // Calculate the repetition info. It is the ply distance from the previous
    // occurrence of the same position, negative in the 3-fold case, or zero
    // if the position was not repeated.
    st.repetition = 0;
    int end = std::min(st.rule50, st.pliesFromNull);
    if (end >= 4) {
        StateInfo *stp = st.previous->previous;
        for (int i = 4; i <= end; i += 2) {
            stp = stp->previous->previous;
            if (stp->key == st.key) {
                st.repetition = stp->repetition ? -i : i;
                break;
            }
        }
    }

    assert(pos_is_ok());
#endif
}


/// Position::undo_move() unmakes a move. When it returns, the position should
/// be restored to exactly the same state as before the move was made.

void Position::undo_move(Move m)
{
    assert(is_ok(m));

#if 0
    sideToMove = ~sideToMove;

    Color us = sideToMove;
    Square from = from_sq(m);
    Square to = to_sq(m);
    Piece pc = piece_on(to);

    assert(empty(from));

    {
        move_piece(to, from); // Put the piece back at the source square

        if (st.capturedPiece) {
            Square capsq = to;

            put_piece(st.capturedPiece, capsq); // Restore the captured piece
        }
    }
#endif

    bool ret = false;

    // TODO Start
    MoveType mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        ret = put_piece(to_sq((Move)-m));
        break;
    case MOVETYPE_MOVE:
        if (select_piece(to_sq(m))) {
            ret = put_piece(from_sq(m));
        }
        break;
    case MOVETYPE_PLACE:
        ret = remove_piece(static_cast<Square>(m));
        break;
    default:
        break;
    }

    if (!ret) {
        return;
    }

    // TODO: Adjust
    //int pieceCountInHand[COLOR_NB]{ 0 };
    //int pieceCountOnBoard[COLOR_NB]{ 0 };
    //int pieceCountNeedRemove{ 0 };

    // TODO End

    // Finally point our state pointer back to the previous state
    //st = st.previous;
    --gamePly;

    assert(pos_is_ok());
}

void Position::undo_move(Sanmill::Stack<Position> &ss)
{
    memcpy(this, ss.top(), sizeof(Position));
    ss.pop();
}


/// Position::key_after() computes the new hash key after the given move. Needed
/// for speculative prefetch. It doesn't recognize special moves like (need remove)

Key Position::key_after(Move m) const
{
    Key k = st.key;
    Square s = static_cast<Square>(to_sq(m));;
    MoveType mt = type_of(m);

    if (mt == MOVETYPE_REMOVE) {
        k ^= Zobrist::psq[~side_to_move()][s];

        if (rule.hasBannedLocations && phase == Phase::placing) {
            k ^= Zobrist::psq[BAN][s];
        }

        goto out;
    }

    k ^= Zobrist::psq[side_to_move()][s];

    if (mt == MOVETYPE_MOVE) {
        k ^= Zobrist::psq[side_to_move()][from_sq(m)];
    }

out:
    k ^= Zobrist::side;

    return k;
}

/// Position::flip() flips position with the white and black sides reversed. This
/// is only useful for debugging e.g. for finding evaluation symmetry bugs.

void Position::flip()
{
#if 0
    string f, token;
    std::stringstream ss(fen());

    for (Rank r = RANK_8; r >= RANK_1; --r) // Piece placement
    {
        std::getline(ss, token, r > RANK_1 ? '/' : ' ');
        f.insert(0, token + (f.empty() ? " " : "/"));
    }

    ss >> token; // Active color
    f += (token == "w" ? "B " : "W "); // Will be lowercased later

    ss >> token; // Castling availability
    f += token + " ";

    std::transform(f.begin(), f.end(), f.begin(),
                   [](char c) { return char(islower(c) ? toupper(c) : tolower(c)); });

    ss >> token; // En passant square
    f += (token == "-" ? token : token.replace(1, 1, token[1] == '3' ? "6" : "3"));

    std::getline(ss, token); // Half and full moves
    f += token;

    set(f, st, this_thread());

    assert(pos_is_ok());
#endif
}


/// Position::pos_is_ok() performs some consistency checks for the
/// position object and raises an asserts if something wrong is detected.
/// This is meant to be helpful when debugging.

bool Position::pos_is_ok() const
{
#if 0
    constexpr bool Fast = true; // Quick (default) or full check?

    if (Fast)
        return true;

    if ((pieces(WHITE) & pieces(BLACK))
        || (pieces(WHITE) | pieces(BLACK)) != pieces()
        || popcount(pieces(WHITE)) > 16
        || popcount(pieces(BLACK)) > 16)
        assert(0 && "pos_is_ok: Bitboards");

    for (PieceType p1 = BAN; p1 <= STONE; ++p1)
        for (PieceType p2 = BAN; p2 <= STONE; ++p2)
            if (p1 != p2 && (pieces(p1) & pieces(p2)))
                assert(0 && "pos_is_ok: Bitboards");

    StateInfo si = *st;
    set_state(&si);
    if (std::memcmp(&si, st, sizeof(StateInfo)))
        assert(0 && "pos_is_ok: State");

    for (Piece pc : Pieces) {
        if (pieceCount[pc] != popcount(pieces(color_of(pc), type_of(pc)))
            || pieceCount[pc] != std::count(board, board + SQUARE_NB, pc))
            assert(0 && "pos_is_ok: Pieces");

        for (int i = 0; i < pieceCount[pc]; ++i)
            if (board[pieceList[pc][i]] != pc || index[pieceList[pc][i]] != i)
                assert(0 && "pos_is_ok: Index");
    }
#endif
    return true;
}

///////////////////////////////////////////////////////////////////////////////

int Position::pieces_on_board_count()
{
    pieceCountOnBoard[BLACK] = pieceCountOnBoard[WHITE] = 0;

    for (int f = 1; f < FILE_NB + 2; f++) {
        for (int r = 0; r < RANK_NB; r++) {
            Square s = static_cast<Square>(f * RANK_NB + r);
            if (board[s] & B_STONE) {
                pieceCountOnBoard[BLACK]++;
            } else if (board[s] & W_STONE) {
                pieceCountOnBoard[WHITE]++;
            }
#if 0
            else if (board[s] & BAN_STONE) {
            }
#endif
        }
    }

    if (pieceCountOnBoard[BLACK] > rule.nTotalPiecesEachSide ||
        pieceCountOnBoard[WHITE] > rule.nTotalPiecesEachSide) {
        return -1;
    }

    return pieceCountOnBoard[BLACK] + pieceCountOnBoard[WHITE];
}

int Position::pieces_in_hand_count()
{
    pieceCountInHand[BLACK] = rule.nTotalPiecesEachSide - pieceCountOnBoard[BLACK];
    pieceCountInHand[WHITE] = rule.nTotalPiecesEachSide - pieceCountOnBoard[WHITE];

    return pieceCountInHand[BLACK] + pieceCountInHand[WHITE];
}

#ifdef THREEFOLD_REPETITION
extern int nRepetition;
#endif // THREEFOLD_REPETITION

bool Position::reset()
{
#ifdef THREEFOLD_REPETITION
    nRepetition = 0;
#endif // THREEFOLD_REPETITION

    gamePly = 0;
    st.rule50 = 0;

    phase = Phase::ready;
    set_side_to_move(BLACK);
    action = Act::place;

    winner = NOBODY;
    gameOverReason = GameOverReason::noReason;

    memset(board, 0, sizeof(board));
    st.key = 0;
    memset(byTypeBB, 0, sizeof(byTypeBB));
    memset(byColorBB, 0, sizeof(byColorBB));

    pieceCountOnBoard[BLACK] = pieceCountOnBoard[WHITE] = 0;
    pieceCountInHand[BLACK] = pieceCountInHand[WHITE] = rule.nTotalPiecesEachSide;
    pieceCountNeedRemove = 0;
    millListSize = 0;

    MoveList<LEGAL>::create();
    create_mill_table();
    currentSquare = SQ_0;

#ifdef ENDGAME_LEARNING
    if (gameOptions.getLearnEndgameEnabled() && nPlayed != 0 && nPlayed % 256 == 0) {
        AIAlgorithm::recordEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */

    int r;
    for (r = 0; r < N_RULES; r++) {
        if (strcmp(rule.name, RULES[r].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u",
                r + 1, rule.maxStepsLedToDraw, 0) > 0) {
        return true;
    }

    cmdline[0] = '\0';

    return false;
}

bool Position::start()
{
    gameOverReason = GameOverReason::noReason;

    switch (phase) {
    case Phase::placing:
    case Phase::moving:
        return false;
    case Phase::gameOver:
        reset();
        [[fallthrough]];
    case Phase::ready:
        phase = Phase::placing;
        return true;
    default:
        return false;
    }
}

bool Position::put_piece(Square s, bool updateCmdlist)
{
    Piece piece = NO_PIECE;
    int us = sideToMove;

    if (phase == Phase::gameOver ||
        action != Act::place ||
        !(SQ_BEGIN <= s && s < SQ_END) || board[s]) {
        return false;
    }

    if (phase == Phase::ready) {
        start();
    }

    if (phase == Phase::placing) {
        piece = (Piece)((0x01 | make_piece(sideToMove)) + rule.nTotalPiecesEachSide - pieceCountInHand[us]);
        pieceCountInHand[us]--;
        pieceCountOnBoard[us]++;

        Piece pc = board[s] = piece;
        byTypeBB[ALL_PIECES] |= byTypeBB[type_of(pc)] |= s;
        byColorBB[color_of(pc)] |= s;   // TODO: Put ban?

        update_key(s);

        if (updateCmdlist) {
            sprintf(cmdline, "(%1u,%1u)", file_of(s), rank_of(s));
        }

        currentSquare = s;

        int n = add_mills(currentSquare);

        if (n == 0) {
            assert(pieceCountInHand[BLACK] >= 0 && pieceCountInHand[WHITE] >= 0);     

            if (pieceCountInHand[BLACK] == 0 && pieceCountInHand[WHITE] == 0) {
                if (check_if_game_is_over()) {
                    return true;
                }

                phase = Phase::moving;
                action = Act::select;

                if (rule.hasBannedLocations) {
                    remove_ban_stones();
                }

                if (!rule.isDefenderMoveFirst) {
                    change_side_to_move();
                }

                if (check_if_game_is_over()) {
                    return true;
                }
            } else {
                change_side_to_move();
            }
        } else {
            pieceCountNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
            update_key_misc();
            action = Act::remove;
        } 

    } else if (phase == Phase::moving) {

        if (check_if_game_is_over()) {
            return true;
        }

        // if illegal
        if (pieceCountOnBoard[sideToMove] > rule.nPiecesAtLeast ||
            !rule.flyingAllowed) {
            if ((square_bb(s) & MoveList<LEGAL>::adjacentSquaresBB[currentSquare]) == 0) {
                return false;
            }
        }

        if (updateCmdlist) {
            sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)",
                    file_of(currentSquare), rank_of(currentSquare),
                    file_of(s), rank_of(s));
            st.rule50++;
        }

        Piece pc = board[currentSquare];

        board[s] = pc;
        update_key(s);
        revert_key(currentSquare);

        board[currentSquare] = NO_PIECE;

        CLEAR_BIT(byTypeBB[ALL_PIECES], currentSquare);
        CLEAR_BIT(byTypeBB[type_of(pc)], currentSquare);
        CLEAR_BIT(byColorBB[color_of(pc)], currentSquare);

        SET_BIT(byTypeBB[ALL_PIECES], s);
        SET_BIT(byTypeBB[type_of(pc)], s);
        SET_BIT(byColorBB[color_of(pc)], s);

        currentSquare = s;
        int n = add_mills(currentSquare);

        // midgame
        if (n == 0) {
            action = Act::select;
            change_side_to_move();

            if (check_if_game_is_over()) {
                return true;
            }
        } else {
            pieceCountNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
            update_key_misc();
            action = Act::remove;
        }
    } else {
        assert(0);
    }

    return true;
}

bool Position::remove_piece(Square s, bool updateCmdlist)
{
    if (phase == Phase::ready || phase == Phase::gameOver)
        return false;

    if (action != Act::remove)
        return false;

    if (pieceCountNeedRemove <= 0)
        return false;

    // if piece is not their
    if (!(make_piece(~side_to_move()) & board[s]))
        return false;

    if (!rule.allowRemovePieceInMill &&
        in_how_many_mills(s, NOBODY) &&
        !is_all_in_mills(~sideToMove)) {
        return false;
    }

    revert_key(s);

    if (rule.hasBannedLocations && phase == Phase::placing) {
        // Remove and put ban
        Piece pc = board[s];

        CLEAR_BIT(byTypeBB[type_of(pc)], s);    // TODO
        CLEAR_BIT(byColorBB[color_of(pc)], s);

        pc = board[s] = BAN_STONE;
        update_key(s);

        SET_BIT(byTypeBB[type_of(pc)], s);
    } else {
        // Remove only
        Piece pc = board[s];

        CLEAR_BIT(byTypeBB[ALL_PIECES], s);
        CLEAR_BIT(byTypeBB[type_of(pc)], s);
        CLEAR_BIT(byColorBB[color_of(pc)], s);

        pc = board[s] = NO_PIECE;
    }

    if (updateCmdlist) {
        sprintf(cmdline, "-(%1u,%1u)", file_of(s), rank_of(s));
        st.rule50 = 0;     // TODO: Need to move out?
    }

    pieceCountOnBoard[them]--;

    if (pieceCountOnBoard[them] + pieceCountInHand[them] < rule.nPiecesAtLeast) {
        set_gameover(sideToMove, GameOverReason::loseReasonlessThanThree);
        return true;
    }

    currentSquare = SQ_0;

    pieceCountNeedRemove--;
    update_key_misc();

    if (pieceCountNeedRemove > 0) {
        return true;
    }

    if (phase == Phase::placing) {
        if (pieceCountInHand[BLACK] == 0 && pieceCountInHand[WHITE] == 0) {
            phase = Phase::moving;
            action = Act::select;

            if (rule.hasBannedLocations) {
                remove_ban_stones();
            }

            if (rule.isDefenderMoveFirst) {
                goto check;
            }
        } else {
            action = Act::place;
        }
    } else {
        action = Act::select;
    }

    change_side_to_move();

check:
    check_if_game_is_over();    

    return true;
}

bool Position::select_piece(Square s)
{
    if (phase != Phase::moving)
        return false;

    if (action != Act::select && action != Act::place)
        return false;

    if (board[s] & make_piece(sideToMove)) {
        currentSquare = s;
        action = Act::place;

        return true;
    }

    return false;
}

bool Position::resign(Color loser)
{
    if (phase == Phase::ready ||
        phase == Phase::gameOver ||
        phase == Phase::none) {
        return false;
    }

    set_gameover(~loser, GameOverReason::loseReasonResign);

    //sprintf(cmdline, "Player%d give up!", loser);
    update_score();

    return true;
}

bool Position::command(const char *cmd)
{
    unsigned int ruleNo;
    unsigned t;
    int step;
    File file1, file2;
    Rank rank1, rank2;
    int args = 0;

    if (sscanf(cmd, "r%1u s%3d t%2u", &ruleNo, &step, &t) == 3) {
        if (set_rule(ruleNo - 1) == false) {
            return false;
        }

        return reset();
    }

    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u)", (unsigned*)&file1, (unsigned*)&rank1, (unsigned*)&file2, (unsigned*)&rank2);

    if (args >= 4) {
        return move_piece(file1, rank1, file2, rank2);
    }

    args = sscanf(cmd, "-(%1u,%1u)", (unsigned *)&file1, (unsigned *)&rank1);
    if (args >= 2) {
        return remove_piece(file1, rank1);
    }

    args = sscanf(cmd, "(%1u,%1u)", (unsigned *)&file1, (unsigned *)&rank1);
    if (args >= 2) {
        return put_piece(file1, rank1);
    }

    args = sscanf(cmd, "Player%1u give up!", &t);

    if (args == 1) {
        return resign((Color)t);
    }

#ifdef THREEFOLD_REPETITION
    if (!strcmp(cmd, "Threefold Repetition. Draw!")) {
        return true;
    }

    if (!strcmp(cmd, "draw")) {
        phase = Phase::gameOver;
        winner = DRAW;
        score_draw++;
        gameOverReason = GameOverReason::drawReasonThreefoldRepetition;
        //sprintf(cmdline, "Threefold Repetition. Draw!");
        return true;
    }
#endif /* THREEFOLD_REPETITION */

    return false;
}

Color Position::get_winner() const
{
    return winner;
}

inline void Position::set_gameover(Color w, GameOverReason reason)
{
    phase = Phase::gameOver;
    gameOverReason = reason;
    winner = w;
}

void Position::update_score()
{
    if (phase == Phase::gameOver) {
        if (winner == DRAW) {
            score_draw++;
            return;
        }

        score[winner]++;
    }
}

bool Position::check_if_game_is_over()
{
    if (phase == Phase::ready || phase == Phase::gameOver) {
        return true;
    }

    if (rule.maxStepsLedToDraw > 0 &&
        st.rule50 > rule.maxStepsLedToDraw) {
        winner = DRAW;
        phase = Phase::gameOver;
        gameOverReason = GameOverReason::drawReasonRule50;
        return true;
    }

    if (pieceCountOnBoard[BLACK] + pieceCountOnBoard[WHITE] >= EFFECTIVE_SQUARE_NB) {
        if (rule.isBlackLoseButNotDrawWhenBoardFull) {
            set_gameover(WHITE, GameOverReason::loseReasonBoardIsFull);
        } else {
            set_gameover(DRAW, GameOverReason::drawReasonBoardIsFull);
        }

        return true;
    }

    if (phase == Phase::moving && action == Act::select && is_all_surrounded()) {
        if (rule.isLoseButNotChangeSideWhenNoWay) {
            set_gameover(~sideToMove, GameOverReason::loseReasonNoWay);
            return true;
        } else {
            change_side_to_move();  // TODO: Need?
            return false;
        }
    }

    return false;
}

int Position::get_mobility_diff(bool includeFobidden)
{
    // TODO: Deal with rule is no ban location
    int mobilityBlack = 0;
    int mobilityWhite = 0;
    int diff = 0;
    int n = 0;

    for (Square i = SQ_BEGIN; i < SQ_END; ++i) {
        n = surrounded_empty_squares_count(i, includeFobidden);

        if (board[i] & B_STONE) {
            mobilityBlack += n;
        } else if (board[i] & W_STONE) {
            mobilityWhite += n;
        }
    }

    diff = mobilityBlack - mobilityWhite;

    return diff;
}

void Position::remove_ban_stones()
{
    assert(rule.hasBannedLocations);

    Square s = SQ_0;

    for (int f = 1; f <= FILE_NB; f++) {
        for (int r = 0; r < RANK_NB; r++) {
            s = static_cast<Square>(f * RANK_NB + r);

            if (board[s] == BAN_STONE) {                
                Piece pc = board[s];
                byTypeBB[ALL_PIECES] ^= s;
                byTypeBB[type_of(pc)] ^= s;
                board[s] = NO_PIECE;
                revert_key(s);
            }
        }
    }
}

inline void Position::set_side_to_move(Color c)
{
    sideToMove = c;
    //us = c;
    them = ~sideToMove;
}

inline void Position::change_side_to_move()
{
    set_side_to_move(~sideToMove);
    st.key ^= Zobrist::side;
}

inline Key Position::update_key(Square s)
{
    // PieceType is board[s]

    // 0b00 - no piece, 0b01 = 1 black, 0b10 = 2 white, 0b11 = 3 ban
    int pieceType = color_on(s);
    // TODO: this is std, but current code can work
    //Location loc = board[s];
    //int pieceType = loc == 0x0f? 3 : loc >> 4;

    st.key ^= Zobrist::psq[pieceType][s];

    return st.key;
}

inline Key Position::revert_key(Square s)
{
    return update_key(s);
}

Key Position::update_key_misc()
{
    st.key = st.key << Zobrist::KEY_MISC_BIT >> Zobrist::KEY_MISC_BIT;

    st.key |= static_cast<Key>(pieceCountNeedRemove) << (CHAR_BIT * sizeof(Key) - Zobrist::KEY_MISC_BIT);

    return st.key;
}

///////////////////////////////////////////////////////////////////////////////

#include "movegen.h"
#include "misc.h"

Bitboard Position::millTableBB[SQUARE_NB][LD_NB] = {{0}};

#if 0
Position &Position::operator= (const Position &other)
{
    if (this == &other)
        return *this;

    memcpy(this->board, other.board, sizeof(this->board));
    memcpy(this->byTypeBB, other.byTypeBB, sizeof(this->byTypeBB));
    memcpy(this->byColorBB, other.byColorBB, sizeof(this->byColorBB));

    memcpy(&millList, &other.millList, sizeof(millList));
    millListSize = other.millListSize;

    return *this;
}
#endif

void Position::create_mill_table()
{
    const Bitboard millTableBB9[SQUARE_NB][LD_NB] = {
        /* 0 */ {0, 0, 0},
        /* 1 */ {0, 0, 0},
        /* 2 */ {0, 0, 0},
        /* 3 */ {0, 0, 0},
        /* 4 */ {0, 0, 0},
        /* 5 */ {0, 0, 0},
        /* 6 */ {0, 0, 0},
        /* 7 */ {0, 0, 0},

        /*  8 */ {square_bb(SQ_16) | square_bb(SQ_24), square_bb(SQ_9) | square_bb(SQ_15), ~0U},
        /*  9 */ {~0U, square_bb(SQ_15) | square_bb(SQ_8), square_bb(SQ_10) | square_bb(SQ_11)},
        /* 10 */ {square_bb(SQ_18) | square_bb(SQ_26), square_bb(SQ_11) | square_bb(SQ_9), ~0U},
        /* 11 */ {~0U, square_bb(SQ_9) | square_bb(SQ_10), square_bb(SQ_12) | square_bb(SQ_13)},
        /* 12 */ {square_bb(SQ_20) | square_bb(SQ_28), square_bb(SQ_13) | square_bb(SQ_11), ~0U},
        /* 13 */ {~0U, square_bb(SQ_11) | square_bb(SQ_12), square_bb(SQ_14) | square_bb(SQ_15)},
        /* 14 */ {square_bb(SQ_22) | square_bb(SQ_30), square_bb(SQ_15) | square_bb(SQ_13), ~0U},
        /* 15 */ {~0U, square_bb(SQ_13) | square_bb(SQ_14), square_bb(SQ_8) | square_bb(SQ_9)},

        /* 16 */ {square_bb(SQ_8) | square_bb(SQ_24), square_bb(SQ_17) | square_bb(SQ_23), ~0U},
        /* 17 */ {~0U, square_bb(SQ_23) | square_bb(SQ_16), square_bb(SQ_18) | square_bb(SQ_19)},
        /* 18 */ {square_bb(SQ_10) | square_bb(SQ_26), square_bb(SQ_19) | square_bb(SQ_17), ~0U},
        /* 19 */ {~0U, square_bb(SQ_17) | square_bb(SQ_18), square_bb(SQ_20) | square_bb(SQ_21)},
        /* 20 */ {square_bb(SQ_12) | square_bb(SQ_28), square_bb(SQ_21) | square_bb(SQ_19), ~0U},
        /* 21 */ {~0U, square_bb(SQ_19) | square_bb(SQ_20), square_bb(SQ_22) | square_bb(SQ_23)},
        /* 22 */ {square_bb(SQ_14) | square_bb(SQ_30), square_bb(SQ_23) | square_bb(SQ_21), ~0U},
        /* 23 */ {~0U, square_bb(SQ_21) | square_bb(SQ_22), square_bb(SQ_16) | square_bb(SQ_17)},

        /* 24 */ {square_bb(SQ_8) | square_bb(SQ_16), square_bb(SQ_25) | square_bb(SQ_31), ~0U},
        /* 25 */ {~0U, square_bb(SQ_31) | square_bb(SQ_24), square_bb(SQ_26) | square_bb(SQ_27)},
        /* 26 */ {square_bb(SQ_10) | square_bb(SQ_18), square_bb(SQ_27) | square_bb(SQ_25), ~0U},
        /* 27 */ {~0U, square_bb(SQ_25) | square_bb(SQ_26), square_bb(SQ_28) | square_bb(SQ_29)},
        /* 28 */ {square_bb(SQ_12) | square_bb(SQ_20), square_bb(SQ_29) | square_bb(SQ_27), ~0U},
        /* 29 */ {~0U, square_bb(SQ_27) | square_bb(SQ_28), square_bb(SQ_30) | square_bb(SQ_31)},
        /* 30 */ {square_bb(SQ_14) | square_bb(SQ_22), square_bb(SQ_31) | square_bb(SQ_29), ~0U},
        /* 31 */ {~0U, square_bb(SQ_29) | square_bb(SQ_30), square_bb(SQ_24) | square_bb(SQ_25)},

        /* 32 */ {0, 0, 0},
        /* 33 */ {0, 0, 0},
        /* 34 */ {0, 0, 0},
        /* 35 */ {0, 0, 0},
        /* 36 */ {0, 0, 0},
        /* 37 */ {0, 0, 0},
        /* 38 */ {0, 0, 0},
        /* 39 */ {0, 0, 0},
    };

    const Bitboard millTableBB12[SQUARE_NB][LD_NB] = {
        /* 0 */ {0, 0, 0},
        /* 1 */ {0, 0, 0},
        /* 2 */ {0, 0, 0},
        /* 3 */ {0, 0, 0},
        /* 4 */ {0, 0, 0},
        /* 5 */ {0, 0, 0},
        /* 6 */ {0, 0, 0},
        /* 7 */ {0, 0, 0},

        /* 8 */  {square_bb(SQ_16) | square_bb(SQ_24), square_bb(SQ_9) | square_bb(SQ_15), ~0U},
        /* 9 */  {square_bb(SQ_17) | square_bb(SQ_25), square_bb(SQ_15) | square_bb(SQ_8),  square_bb(SQ_10) | square_bb(SQ_11)},
        /* 10 */ {square_bb(SQ_18) | square_bb(SQ_26), square_bb(SQ_11) | square_bb(SQ_9), ~0U},
        /* 11 */ {square_bb(SQ_19) | square_bb(SQ_27), square_bb(SQ_9) | square_bb(SQ_10), square_bb(SQ_12) | square_bb(SQ_13)},
        /* 12 */ {square_bb(SQ_20) | square_bb(SQ_28), square_bb(SQ_13) | square_bb(SQ_11), ~0U},
        /* 13 */ {square_bb(SQ_21) | square_bb(SQ_29), square_bb(SQ_11) | square_bb(SQ_12), square_bb(SQ_14) | square_bb(SQ_15)},
        /* 14 */ {square_bb(SQ_22) | square_bb(SQ_30), square_bb(SQ_15) | square_bb(SQ_13), ~0U},
        /* 15 */ {square_bb(SQ_23) | square_bb(SQ_31), square_bb(SQ_13) | square_bb(SQ_14),  square_bb(SQ_8) | square_bb(SQ_9)},

        /* 16 */ {square_bb(SQ_8) | square_bb(SQ_24), square_bb(SQ_17) | square_bb(SQ_23), ~0U},
        /* 17 */ {square_bb(SQ_9) | square_bb(SQ_25), square_bb(SQ_23) | square_bb(SQ_16), square_bb(SQ_18) | square_bb(SQ_19)},
        /* 18 */ {square_bb(SQ_10) | square_bb(SQ_26), square_bb(SQ_19) | square_bb(SQ_17), ~0U},
        /* 19 */ {square_bb(SQ_11) | square_bb(SQ_27), square_bb(SQ_17) | square_bb(SQ_18), square_bb(SQ_20) | square_bb(SQ_21)},
        /* 20 */ {square_bb(SQ_12) | square_bb(SQ_28), square_bb(SQ_21) | square_bb(SQ_19), ~0U},
        /* 21 */ {square_bb(SQ_13) | square_bb(SQ_29), square_bb(SQ_19) | square_bb(SQ_20), square_bb(SQ_22) | square_bb(SQ_23)},
        /* 22 */ {square_bb(SQ_14) | square_bb(SQ_30), square_bb(SQ_23) | square_bb(SQ_21), ~0U},
        /* 23 */ {square_bb(SQ_15) | square_bb(SQ_31), square_bb(SQ_21) | square_bb(SQ_22), square_bb(SQ_16) | square_bb(SQ_17)},

        /* 24 */ {square_bb(SQ_8) | square_bb(SQ_16), square_bb(SQ_25) | square_bb(SQ_31), ~0U},
        /* 25 */ {square_bb(SQ_9) | square_bb(SQ_17), square_bb(SQ_31) | square_bb(SQ_24), square_bb(SQ_26) | square_bb(SQ_27)},
        /* 26 */ {square_bb(SQ_10) | square_bb(SQ_18), square_bb(SQ_27) | square_bb(SQ_25), ~0U},
        /* 27 */ {square_bb(SQ_11) | square_bb(SQ_19), square_bb(SQ_25) | square_bb(SQ_26), square_bb(SQ_28) | square_bb(SQ_29)},
        /* 28 */ {square_bb(SQ_12) | square_bb(SQ_20), square_bb(SQ_29) | square_bb(SQ_27), ~0U},
        /* 29 */ {square_bb(SQ_13) | square_bb(SQ_21), square_bb(SQ_27) | square_bb(SQ_28), square_bb(SQ_30) | square_bb(SQ_31)},
        /* 30 */ {square_bb(SQ_14) | square_bb(SQ_22), square_bb(SQ_31) | square_bb(SQ_29), ~0U},
        /* 31 */ {square_bb(SQ_15) | square_bb(SQ_23), square_bb(SQ_29) | square_bb(SQ_30), square_bb(SQ_24) | square_bb(SQ_25)},

        /* 32 */ {0, 0, 0},
        /* 33 */ {0, 0, 0},
        /* 34 */ {0, 0, 0},
        /* 35 */ {0, 0, 0},
        /* 36 */ {0, 0, 0},
        /* 37 */ {0, 0, 0},
        /* 38 */ {0, 0, 0},
        /* 39 */ {0, 0, 0},
    };

    // TODO: change to ptr?
    if (rule.hasObliqueLines) {
        memcpy(millTableBB, millTableBB12, sizeof(millTableBB));
    } else {
        memcpy(millTableBB, millTableBB9, sizeof(millTableBB));
    }
}

Color Position::color_on(Square s) const
{
    return color_of(board[s]);
}

bool Position::bitboard_is_ok()
{
#ifdef BITBOARD_DEBUG
    Bitboard blackBB = byColorBB[BLACK];
    Bitboard whiteBB = byColorBB[WHITE];

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {

        if (board[s] == NO_PIECE)
        {
            if (blackBB & (1 << s)) {
                return false;
            }

            if (whiteBB & (1 << s)) {
                return false;
            }
        }

        if (color_of(board[s]) == BLACK)
        {
            if ((blackBB & (1 << s)) == 0) {
                return false;
            }

            if (whiteBB & (1 << s)) {
                return false;
            }
        }

        if (color_of(board[s]) == WHITE) {
            if ((whiteBB & (1 << s)) == 0) {
                return false;
            }

            if (blackBB & (1 << s)) {
                return false;
            }
        }
    }
#endif

    return true;
}

int Position::in_how_many_mills(Square s, Color c, Square squareSelected)
{
    int n = 0;
    Piece locbak = NO_PIECE;

    assert(SQ_0 <= squareSelected && squareSelected < SQUARE_NB);

    if (c == NOBODY) {
        c = color_on(s);
    }

    if (squareSelected != SQ_0) {
        locbak = board[squareSelected];
        board[squareSelected] = NO_PIECE;

        CLEAR_BIT(byTypeBB[ALL_PIECES], squareSelected);
        CLEAR_BIT(byTypeBB[type_of(locbak)], squareSelected);
        CLEAR_BIT(byColorBB[color_of(locbak)], squareSelected);
    }

    Bitboard bc = byColorBB[c];
    Bitboard *mt = millTableBB[s];

    for (int l = 0; l < LD_NB; l++) {
        if ((bc & mt[l]) == mt[l]) {
            n++;
        }
    }

    if (squareSelected != SQ_0) {
        board[squareSelected] = locbak;

        SET_BIT(byTypeBB[ALL_PIECES], squareSelected);
        SET_BIT(byTypeBB[type_of(locbak)], squareSelected);
        SET_BIT(byColorBB[color_of(locbak)], squareSelected);
    }

    return n;
}

int Position::add_mills(Square s)
{
    int n = 0;

    Bitboard bc = byColorBB[color_on(s)];
    Bitboard *mt = millTableBB[s];

    for (auto i = 0; i < LD_NB; ++i) {
        if (((bc & mt[i]) == mt[i])) {
            n++;
        }        
    }

    return n;
}

bool Position::is_all_in_mills(Color c)
{
    for (Square i = SQ_BEGIN; i < SQ_END; ++i) {
        if (board[i] & ((uint8_t)make_piece(c))) {
            if (!in_how_many_mills(i, NOBODY)) {
                return false;
            }
        }
    }

    return true;
}

// Stat include ban
int Position::surrounded_empty_squares_count(Square s, bool includeFobidden)
{
    //assert(rule.hasBannedLocations == includeFobidden);

    int n = 0;

    if (pieceCountOnBoard[sideToMove] > rule.nPiecesAtLeast ||
        !rule.flyingAllowed) {
        Square moveSquare;
        for (MoveDirection d = MD_BEGIN; d < MD_NB; ++d) {
            moveSquare = static_cast<Square>(MoveList<LEGAL>::adjacentSquares[s][d]);
            if (moveSquare) {
                if (board[moveSquare] == 0x00 ||
                    (includeFobidden && board[moveSquare] == BAN_STONE)) {
                    n++;
                }
            }
        }
    }

    return n;
}

void Position::surrounded_pieces_count(Square s, int &nOurPieces, int &nTheirPieces, int &nBanned, int &nEmpty)
{
    Square moveSquare;

    for (MoveDirection d = MD_BEGIN; d < MD_NB; ++d) {
        moveSquare = static_cast<Square>(MoveList<LEGAL>::adjacentSquares[s][d]);

        if (!moveSquare) {
            continue;
        }

        enum Piece pieceType = static_cast<Piece>(board[moveSquare]);

        switch (pieceType) {
        case NO_PIECE:
            nEmpty++;
            break;
        case BAN_STONE:
            nBanned++;
            break;
        default:
            if (color_of(pieceType) == sideToMove) {
                nOurPieces++;
            } else {
                nTheirPieces++;
            }
            break;
        }
    }
}

bool Position::is_all_surrounded() const
{
    // Full
    if (pieceCountOnBoard[BLACK] + pieceCountOnBoard[WHITE] >= EFFECTIVE_SQUARE_NB)
        return true;

    // Can fly
    if (pieceCountOnBoard[sideToMove] <= rule.nPiecesAtLeast &&
        rule.flyingAllowed) {
        return false;
    }

    for (Square s = SQ_BEGIN; s < SQ_END; s = (Square)(s + 1)) {
        if ((sideToMove & color_on(s)) &&
            (byTypeBB[ALL_PIECES] & MoveList<LEGAL>::adjacentSquaresBB[s]) != MoveList<LEGAL>::adjacentSquaresBB[s]) {
            return false;
        }
    }

    return true;
}

bool Position::is_star_square(Square s)
{
    if (rule.hasObliqueLines == true) {
        return (s == 17 ||
                s == 19 ||
                s == 21 ||
                s == 23);
    }

    return (s == 16 ||
            s == 18 ||
            s == 20 ||
            s == 22);
}

void Position::print_board()
{
    if (rule.nTotalPiecesEachSide == 12) {
        printf("\n"
                    "31 ----- 24 ----- 25\n"
                    "| \\       |      / |\n"
                    "|  23 -- 16 -- 17  |\n"
                    "|  | \\    |   / |  |\n"
                    "|  |  15-08-09  |  |\n"
                    "30-22-14    10-18-26\n"
                    "|  |  13-12-11  |  |\n"
                    "|  | /    |   \\ |  |\n"
                    "|  21 -- 20 -- 19  |\n"
                    "| /       |      \\ |\n"
                    "29 ----- 28 ----- 27\n"
                    "\n");
    } else {
        printf("\n"
                    "31 ----- 24 ----- 25\n"
                    "|         |        |\n"
                    "|  23 -- 16 -- 17  |\n"
                    "|  |      |     |  |\n"
                    "|  |  15-08-09  |  |\n"
                    "30-22-14    10-18-26\n"
                    "|  |  13-12-11  |  |\n"
                    "|  |      |     |  |\n"
                    "|  21 -- 20 -- 19  |\n"
                    "|         |        |\n"
                    "29 ----- 28 ----- 27\n"
                    "\n");
    }
}

void Position::reset_bb()
{
    memset(byTypeBB, 0, sizeof(byTypeBB));
    memset(byColorBB, 0, sizeof(byColorBB));

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        Piece pc = board[s];
        byTypeBB[ALL_PIECES] |= byTypeBB[type_of(pc)] |= s;
        byColorBB[color_of(pc)] |= s;
    }
}

void Position::mirror(vector <string> &cmdlist, bool cmdChange /*= true*/)
{
    Piece ch;
    int f, r;
    int i;

    for (f = 1; f <= FILE_NB; f++) {
        for (r = 1; r < RANK_NB / 2; r++) {
            ch = board[f * RANK_NB + r];
            board[f * RANK_NB + r] = board[(f + 1) * RANK_NB - r];
            board[(f + 1) * RANK_NB - r] = ch;
        }
    }

    reset_bb();

    uint64_t llp[3] = { 0 };

    if (move < 0) {
        f = (-move) / RANK_NB;
        r = (-move) % RANK_NB;
        r = (RANK_NB - r) % RANK_NB;
        move = static_cast<Move>(-(f * RANK_NB + r));
    } else {
        llp[0] = static_cast<uint64_t>(from_sq((Move)move));
        llp[1] = to_sq((Move)move);

        for (i = 0; i < 2; i++) {
            f = static_cast<int>(llp[i]) / RANK_NB;
            r = static_cast<int>(llp[i]) % RANK_NB;
            r = (RANK_NB - r) % RANK_NB;
            llp[i] = (static_cast<uint64_t>(f) * RANK_NB + r);
        }

        move = static_cast<Move>(((llp[0] << 8) | llp[1]));
    }

    if (currentSquare != 0) {
        f = currentSquare / RANK_NB;
        r = currentSquare % RANK_NB;
        r = (RANK_NB - r) % RANK_NB;
        currentSquare = static_cast<Square>(f * RANK_NB + r);
    }


    for (auto &mill : millList) {
        llp[0] = (mill & 0x000000ff00000000) >> 32;
        llp[1] = (mill & 0x0000000000ff0000) >> 16;
        llp[2] = (mill & 0x00000000000000ff);

        for (i = 0; i < 3; i++) {
            f = static_cast<int>(llp[i]) / RANK_NB;
            r = static_cast<int>(llp[i]) % RANK_NB;
            r = (RANK_NB - r) % RANK_NB;
            llp[i] = static_cast<uint64_t>(f * RANK_NB + r);
        }

        mill &= 0xffffff00ff00ff00;
        mill |= (llp[0] << 32) | (llp[1] << 16) | llp[2];
    }

    if (cmdChange) {
        unsigned r1, s1, r2, s2;
        int args = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2, &s2);
        if (args >= 4) {
            s1 = (RANK_NB - s1 + 1) % RANK_NB;
            s2 = (RANK_NB - s2 + 1) % RANK_NB;
            cmdline[3] = '1' + static_cast<char>(s1);
            cmdline[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u)", &r1, &s1);
            if (args >= 2) {
                s1 = (RANK_NB - s1 + 1) % RANK_NB;
                cmdline[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u)", &r1, &s1);
                if (args >= 2) {
                    s1 = (RANK_NB - s1 + 1) % RANK_NB;
                    cmdline[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2, &s2);
            if (args >= 4) {
                s1 = (RANK_NB - s1 + 1) % RANK_NB;
                s2 = (RANK_NB - s2 + 1) % RANK_NB;
                iter[3] = '1' + static_cast<char>(s1);
                iter[10] = '1' + static_cast<char>(s2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u)", &r1, &s1);
                if (args >= 2) {
                    s1 = (RANK_NB - s1 + 1) % RANK_NB;
                    iter[4] = '1' + static_cast<char>(s1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u)", &r1, &s1);
                    if (args >= 2) {
                        s1 = (RANK_NB - s1 + 1) % RANK_NB;
                        iter[3] = '1' + static_cast<char>(s1);
                    }
                }
            }
        }
    }
}

void Position::turn(vector <string> &cmdlist, bool cmdChange /*= true*/)
{
    Piece ch;
    int f, r;
    int i;

    for (r = 0; r < RANK_NB; r++) {
        ch = board[RANK_NB + r];
        board[RANK_NB + r] = board[EFFECTIVE_SQUARE_NB + r];
        board[EFFECTIVE_SQUARE_NB + r] = ch;
    }

    reset_bb();

    uint64_t llp[3] = { 0 };

    if (move < 0) {
        f = (-move) / RANK_NB;
        r = (-move) % RANK_NB;

        if (f == 1)
            f = FILE_NB;
        else if (f == FILE_NB)
            f = 1;

        move = static_cast<Move>(-(f * RANK_NB + r));
    } else {
        llp[0] = static_cast<uint64_t>(from_sq((Move)move));
        llp[1] = to_sq((Move)move);

        for (i = 0; i < 2; i++) {
            f = static_cast<int>(llp[i]) / RANK_NB;
            r = static_cast<int>(llp[i]) % RANK_NB;

            if (f == 1)
                f = FILE_NB;
            else if (f == FILE_NB)
                f = 1;

            llp[i] = static_cast<uint64_t>(f * RANK_NB + r);
        }

        move = static_cast<Move>(((llp[0] << 8) | llp[1]));
    }

    if (currentSquare != 0) {
        f = currentSquare / RANK_NB;
        r = currentSquare % RANK_NB;

        if (f == 1)
            f = FILE_NB;
        else if (f == FILE_NB)
            f = 1;

        currentSquare = static_cast<Square>(f * RANK_NB + r);
    }

    for (auto &mill : millList) {
        llp[0] = (mill & 0x000000ff00000000) >> 32;
        llp[1] = (mill & 0x0000000000ff0000) >> 16;
        llp[2] = (mill & 0x00000000000000ff);

        for (i = 0; i < 3; i++) {
            f = static_cast<int>(llp[i]) / RANK_NB;
            r = static_cast<int>(llp[i]) % RANK_NB;

            if (f == 1)
                f = FILE_NB;
            else if (f == FILE_NB)
                f = 1;

            llp[i] = static_cast<uint64_t>(f * RANK_NB + r);
        }

        mill &= 0xffffff00ff00ff00;
        mill |= (llp[0] << 32) | (llp[1] << 16) | llp[2];
    }

    // 命令行解析
    if (cmdChange) {
        unsigned r1, s1, r2, s2;
        int args = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u)",
                      &r1, &s1, &r2, &s2);

        if (args >= 4) {
            if (r1 == 1)
                r1 = FILE_NB;
            else if (r1 == FILE_NB)
                r1 = 1;

            if (r2 == 1)
                r2 = FILE_NB;
            else if (r2 == FILE_NB)
                r2 = 1;

            cmdline[1] = '0' + static_cast<char>(r1);
            cmdline[8] = '0' + static_cast<char>(r2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u)", &r1, &s1);
            if (args >= 2) {
                if (r1 == 1)
                    r1 = FILE_NB;
                else if (r1 == FILE_NB)
                    r1 = 1;
                cmdline[2] = '0' + static_cast<char>(r1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u)", &r1, &s1);
                if (args >= 2) {
                    if (r1 == 1)
                        r1 = FILE_NB;
                    else if (r1 == FILE_NB)
                        r1 = 1;
                    cmdline[1] = '0' + static_cast<char>(r1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(),
                          "(%1u,%1u)->(%1u,%1u)",
                          &r1, &s1, &r2, &s2);

            if (args >= 4) {
                if (r1 == 1)
                    r1 = FILE_NB;
                else if (r1 == FILE_NB)
                    r1 = 1;

                if (r2 == 1)
                    r2 = FILE_NB;
                else if (r2 == FILE_NB)
                    r2 = 1;

                iter[1] = '0' + static_cast<char>(r1);
                iter[8] = '0' + static_cast<char>(r2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u)", &r1, &s1);
                if (args >= 2) {
                    if (r1 == 1)
                        r1 = FILE_NB;
                    else if (r1 == FILE_NB)
                        r1 = 1;

                    iter[2] = '0' + static_cast<char>(r1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u)", &r1, &s1);
                    if (args >= 2) {
                        if (r1 == 1)
                            r1 = FILE_NB;
                        else if (r1 == FILE_NB)
                            r1 = 1;

                        iter[1] = '0' + static_cast<char>(r1);
                    }
                }
            }
        }
    }
}

void Position::rotate(vector <string> &cmdlist, int degrees, bool cmdChange /*= true*/)
{
    degrees = degrees % 360;

    if (degrees < 0)
        degrees += 360;

    if (degrees == 0 || degrees % 90)
        return;

    degrees /= 45;

    Piece ch1, ch2;
    int f, r;
    int i;

    if (degrees == 2) {
        for (f = 1; f <= FILE_NB; f++) {
            ch1 = board[f * RANK_NB];
            ch2 = board[f * RANK_NB + 1];

            for (r = 0; r < RANK_NB - 2; r++) {
                board[f * RANK_NB + r] = board[f * RANK_NB + r + 2];
            }

            board[f * RANK_NB + 6] = ch1;
            board[f * RANK_NB + 7] = ch2;
        }
    } else if (degrees == 6) {
        for (f = 1; f <= FILE_NB; f++) {
            ch1 = board[f * RANK_NB + 7];
            ch2 = board[f * RANK_NB + 6];

            for (r = RANK_NB - 1; r >= 2; r--) {
                board[f * RANK_NB + r] = board[f * RANK_NB + r - 2];
            }

            board[f * RANK_NB + 1] = ch1;
            board[f * RANK_NB] = ch2;
        }
    } else if (degrees == 4) {
        for (f = 1; f <= FILE_NB; f++) {
            for (r = 0; r < RANK_NB / 2; r++) {
                ch1 = board[f * RANK_NB + r];
                board[f * RANK_NB + r] = board[f * RANK_NB + r + 4];
                board[f * RANK_NB + r + 4] = ch1;
            }
        }
    } else {
        return;
    }

    reset_bb();

    uint64_t llp[3] = { 0 };

    if (move < 0) {
        f = (-move) / RANK_NB;
        r = (-move) % RANK_NB;
        r = (r + RANK_NB - degrees) % RANK_NB;
        move = static_cast<Move>(-(f * RANK_NB + r));
    } else {
        llp[0] = static_cast<uint64_t>(from_sq((Move)move));
        llp[1] = to_sq((Move)move);
        f = static_cast<int>(llp[0]) / RANK_NB;
        r = static_cast<int>(llp[0]) % RANK_NB;
        r = (r + RANK_NB - degrees) % RANK_NB;
        llp[0] = static_cast<uint64_t>(f * RANK_NB + r);
        f = static_cast<int>(llp[1]) / RANK_NB;
        r = static_cast<int>(llp[1]) % RANK_NB;
        r = (r + RANK_NB - degrees) % RANK_NB;
        llp[1] = static_cast<uint64_t>(f * RANK_NB + r);
        move = static_cast<Move>(((llp[0] << 8) | llp[1]));
    }

    if (currentSquare != 0) {
        f = currentSquare / RANK_NB;
        r = currentSquare % RANK_NB;
        r = (r + RANK_NB - degrees) % RANK_NB;
        currentSquare = static_cast<Square>(f * RANK_NB + r);
    }

    for (auto &mill : millList) {
        llp[0] = (mill & 0x000000ff00000000) >> 32;
        llp[1] = (mill & 0x0000000000ff0000) >> 16;
        llp[2] = (mill & 0x00000000000000ff);

        for (i = 0; i < 3; i++) {
            f = static_cast<int>(llp[i]) / RANK_NB;
            r = static_cast<int>(llp[i]) % RANK_NB;
            r = (r + RANK_NB - degrees) % RANK_NB;
            llp[i] = static_cast<uint64_t>(f * RANK_NB + r);
        }

        mill &= 0xffffff00ff00ff00;
        mill |= (llp[0] << 32) | (llp[1] << 16) | llp[2];
    }

    if (cmdChange) {
        unsigned r1, s1, r2, s2;
        int args = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2, &s2);
        if (args >= 4) {
            s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
            s2 = (s2 - 1 + RANK_NB - degrees) % RANK_NB;
            cmdline[3] = '1' + static_cast<char>(s1);
            cmdline[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u)", &r1, &s1);

            if (args >= 2) {
                s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                cmdline[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u)", &r1, &s1);

                if (args >= 2) {
                    s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                    cmdline[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2, &s2);

            if (args >= 4) {
                s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                s2 = (s2 - 1 + RANK_NB - degrees) % RANK_NB;
                iter[3] = '1' + static_cast<char>(s1);
                iter[10] = '1' + static_cast<char>(s2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u)", &r1, &s1);

                if (args >= 2) {
                    s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                    iter[4] = '1' + static_cast<char>(s1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u)", &r1, &s1);
                    if (args >= 2) {
                        s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                        iter[3] = '1' + static_cast<char>(s1);
                    }
                }
            }
        }
    }
}
