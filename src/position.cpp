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

namespace Zobrist
{
Key psq[PIECE_TYPE_NB][SQUARE_NB];
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

// Marcel van Kervinck's cuckoo algorithm for fast detection of "upcoming repetition"
// situations. Description of the algorithm in the following paper:
// https://marcelk.net/2013-04-06/paper/upcoming-rep-v2.pdf

// First and second hash functions for indexing the cuckoo tables
inline int H1(Key h)
{
    return h & 0x1fff;
}
inline int H2(Key h)
{
    return (h >> 16) & 0x1fff;
}

// Cuckoo tables with Zobrist hashes of valid reversible moves, and the moves themselves
Key cuckoo[8192];
Move cuckooMove[8192];

/// Position::init() initializes at startup the various arrays used to compute
/// hash keys.

void Position::init()
{
    PRNG rng(1070372);

    for (PieceType pt : PieceTypes)
        for (Square s = SQ_0; s < SQUARE_NB; ++s)
            Zobrist::psq[pt][s] = rng.rand<Key>();

    // Prepare the cuckoo tables
    std::memset(cuckoo, 0, sizeof(cuckoo));
    std::memset(cuckooMove, 0, sizeof(cuckooMove));

    return;
}

Position::Position()
{
    // TODO
    st = &tmpSt;

    construct_key();

    set_position(&RULES[DEFAULT_RULE_NUMBER]);

    score[BLACK] = score[WHITE] = score_draw = nPlayed = 0;

    //tips.reserve(1024);

#ifdef PREFETCH_SUPPORT
    prefetch_range(millTable, sizeof(millTable));
#endif
}

Position::~Position()
{

}

/// Position::set() initializes the position object with the given FEN string.
/// This function is not very robust - make sure that input FENs are correct,
/// this is assumed to be the responsibility of the GUI.

Position &Position::set(const string &fenStr, StateInfo *si, Thread *th)
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

       4) Halfmove clock. This is the number of halfmoves since the last
          capture. This is used to determine if a draw can be claimed under the
          fifty-move rule.

       5) Fullmove number. The number of the full move. It starts at 1, and is
          incremented after Black's move.
    */

    unsigned char token;
    size_t idx;
    Square sq = SQ_A1;
    std::istringstream ss(fenStr);

    std::memset(this, 0, sizeof(Position));
    std::memset(si, 0, sizeof(StateInfo));
    st = si;

    ss >> std::noskipws;

    // 1. Piece placement
    while ((ss >> token) && !isspace(token)) {
        if (token == '@' || token == 'O' || token == 'X') {
            // put_piece(Piece(idx), sq);   // TODO
        }

        ++sq;
    }

    // 2. Active color
    ss >> token;
    sideToMove = (token == 'b' ? BLACK : WHITE);    

    // 3. Phrase
    ss >> token;

    switch (token) {
    case 'r':
        phase = PHASE_READY;
        break;
    case 'p':
        phase = PHASE_PLACING;
        break;
    case 'm':
        phase = PHASE_MOVING;
        break;
    case 'o':
        phase = PHASE_GAMEOVER;
        break;
    default:
        phase = PHASE_NONE;
    }

    // 4-5. Halfmove clock and fullmove number
    ss >> std::skipws >> st->rule50 >> gamePly;

    // Convert from fullmove starting from 1 to gamePly starting from 0,
    // handle also common incorrect FEN with fullmove = 0.
    gamePly = std::max(2 * (gamePly - 1), 0) + (sideToMove == WHITE);

    thisThread = th;
    set_state(st);

    assert(pos_is_ok());

    return *this;
}

/// Position::set_state() computes the hash keys of the position, and other
/// data that once computed is updated incrementally as moves are made.
/// The function is only used when a new position is set up, and to verify
/// the correctness of the StateInfo data when running in debug mode.

void Position::set_state(StateInfo *si) const
{
    // TODO
#if 0
    si->key = 0;

    for (Bitboard b = pieces(); b; ) {
        Square s = pop_lsb(&b);
        Piece pc = piece_on(s);
        si->key ^= Zobrist::psq[pc][s];
    }

    if (sideToMove == BLACK)
        si->key ^= Zobrist::side;
#endif
    si = si;
}


/// Position::fen() returns a FEN representation of the position. In case of
/// Chess960 the Shredder-FEN notation is used. This is mainly a debugging function.

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
    case PHASE_NONE:
        ss << "n";
        break;
    case PHASE_READY:
        ss << "r";
        break;
    case PHASE_PLACING:
        ss << "p";
        break;
    case PHASE_MOVING:
        ss << "m";
        break;
    case PHASE_GAMEOVER:
        ss << "o";
        break;
    default:
        ss << "?";
        break;
    }

    ss << " ";

    ss << st->rule50 << " " << 1 + (gamePly - (sideToMove == BLACK)) / 2;

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

    if (phase == PHASE_MOVING && type_of(move) != MOVETYPE_REMOVE) {
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

void Position::do_move(Move m, StateInfo &newSt)
{
    bool ret = false;

    ++st->rule50;

    MoveType mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        // Reset rule 50 counter
        st->rule50 = 0;
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
    
    move = m;
}

/// Position::undo_move() unmakes a move. When it returns, the position should
/// be restored to exactly the same state as before the move was made.

void Position::undo_move(Move m)
{
#if 0
    MoveType mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        return put_piece(to_sq(-m));
    case MOVETYPE_MOVE:
        if (select_piece(to_sq(m))) {
            return put_piece(from_sq(m));
        }
        break;
    case MOVETYPE_PLACE:
        return remove_piece(static_cast<Square>(m));
    default:
        break;
    }

    // Finally point our state pointer back to the previous state
    st = st->previous;
    --gamePly;

    //assert(pos_is_ok()); // TODO
#endif

    // TODO: Adjust
    //int pieceCountInHand[COLOR_NB]{ 0 };
    //int pieceCountOnBoard[COLOR_NB]{ 0 };
    //int pieceCountNeedRemove{ 0 };
    m = m;
}

void Position::undo_move(Stack<Position> &ss)
{
    memcpy(this, ss.top(), sizeof(Position));
    ss.pop();
}

int Position::pieces_on_board_count()
{
    pieceCountOnBoard[BLACK] = pieceCountOnBoard[WHITE] = 0;

    for (int f = 1; f < FILE_NB + 2; f++) {
        for (int r = 0; r < RANK_NB; r++) {
            Square s = static_cast<Square>(f * RANK_NB + r);
            if (board[s] & B_STONE) {
                pieceCountOnBoard[BLACK]++;
            } else if (board[s]& W_STONE) {
                pieceCountOnBoard[WHITE]++;
            }
#if 0
            else if (board[s]& BAN_STONE) {
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

int Position::set_position(const struct Rule *newRule)
{
    rule = *newRule;

    gamePly = 0;
    st->rule50 = 0;

    phase = PHASE_READY;
    set_side_to_move(BLACK);
    action = ACTION_PLACE;

    memset(board, 0, sizeof(board));
    st->key = 0;
    memset(byTypeBB, 0, sizeof(byTypeBB));

    if (pieces_on_board_count() == -1) {
        return false;
    }

    pieces_in_hand_count();
    pieceCountNeedRemove = 0;
    millListSize = 0;
    winner = NOBODY;
    MoveList::create();
    create_mill_table();
    currentSquare = SQ_0;
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;

    int r;
    for (r = 0; r < N_RULES; r++) {
        if (strcmp(rule.name, RULES[r].name) == 0)
            return r;
    }

    return -1;
}

bool Position::reset()
{
    if (phase == PHASE_READY &&
        elapsedSeconds[BLACK] == elapsedSeconds[WHITE] == 0) {
        return true;
    }

    gamePly = 0;
    st->rule50 = 0;

    phase = PHASE_READY;
    set_side_to_move(BLACK);
    action = ACTION_PLACE;

    winner = NOBODY;
    gameoverReason = NO_REASON;

    memset(board, 0, sizeof(board));
    st->key = 0;
    memset(byTypeBB, 0, sizeof(byTypeBB));

    pieceCountOnBoard[BLACK] = pieceCountOnBoard[WHITE] = 0;
    pieceCountInHand[BLACK] = pieceCountInHand[WHITE] = rule.nTotalPiecesEachSide;
    pieceCountNeedRemove = 0;
    millListSize = 0;
    currentSquare = SQ_0;
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;

#ifdef ENDGAME_LEARNING
    if (gameOptions.getLearnEndgameEnabled() && nPlayed != 0 && nPlayed % 256 == 0) {
        AIAlgorithm::recordEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */

    int i;

    for (i = 0; i < N_RULES; i++) {
        if (strcmp(rule.name, RULES[i].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u",
                i + 1, rule.maxStepsLedToDraw, 0) > 0) {
        return true;
    }

    cmdline[0] = '\0';

    return false;
}

bool Position::start()
{
    gameoverReason = NO_REASON;

    switch (phase) {
    case PHASE_PLACING:
    case PHASE_MOVING:
        return false;
    case PHASE_GAMEOVER:
        reset();
        [[fallthrough]];
    case PHASE_READY:
        startTime = time(nullptr);
        phase = PHASE_PLACING;
        return true;
    default:
        return false;
    }
}

bool Position::put_piece(Square s, bool updateCmdlist)
{
    int i;

    Piece piece = NO_PIECE;
    int n = 0;

    int us = sideToMove;

    Bitboard fromTo;

    if (phase == PHASE_GAMEOVER ||
        action != ACTION_PLACE ||
        !onBoard[s] || board[s]) {
        return false;
    }

    if (phase == PHASE_READY) {
        start();
    }        

    if (phase == PHASE_PLACING) {
        piece = (Piece)((0x01 | make_piece(sideToMove)) + rule.nTotalPiecesEachSide - pieceCountInHand[us]);
        pieceCountInHand[us]--;
        pieceCountOnBoard[us]++;

        board[s]= piece;

        update_key(s);

        byTypeBB[ALL_PIECES] |= s;
        byTypeBB[us] |= s;

        if (updateCmdlist) {
            sprintf(cmdline, "(%1u,%1u)", file_of(s), rank_of(s));
            gamePly++;
        }

        currentSquare = s;

        n = add_mills(currentSquare);

        if (n == 0) {
            assert(pieceCountInHand[BLACK] >= 0 && pieceCountInHand[WHITE] >= 0);     

            if (pieceCountInHand[BLACK] == 0 && pieceCountInHand[WHITE] == 0) {
                if (check_gameover_condition()) {
                    return true;
                }

                phase = PHASE_MOVING;
                action = ACTION_SELECT;

                if (rule.hasBannedLocations) {
                    remove_ban_stones();
                }

                if (!rule.isDefenderMoveFirst) {
                    change_side_to_move();
                }

                if (check_gameover_condition()) {
                    return true;
                }
            } else {
                change_side_to_move();
            }
        } else {
            pieceCountNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
            action = ACTION_REMOVE;
        } 

    } else if (phase == PHASE_MOVING) {

        if (check_gameover_condition()) {
            return true;
        }

        // if illegal
        if (pieceCountOnBoard[sideToMove] > rule.nPiecesAtLeast ||
            !rule.allowFlyWhenRemainThreePieces) {
            for (i = 0; i < 4; i++) {
                if (s == MoveList::moveTable[currentSquare][i])
                    break;
            }

            // not in moveTable
            if (i == 4) {
                return false;
            }
        }

        if (updateCmdlist) {
            sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)",
                    file_of(currentSquare), rank_of(currentSquare),
                    file_of(s), rank_of(s));
            gamePly++;
            st->rule50++;
        }

        fromTo = square_bb(currentSquare) | square_bb(s);
        byTypeBB[ALL_PIECES] ^= fromTo;
        byTypeBB[us] ^= fromTo;

        board[s] = board[currentSquare];

        update_key(s);
        revert_key(currentSquare);

        board[currentSquare] = NO_PIECE;

        currentSquare = s;
        n = add_mills(currentSquare);

        // midgame
        if (n == 0) {
            action = ACTION_SELECT;
            change_side_to_move();

            if (check_gameover_condition()) {
                return true;
            }
        } else {
            pieceCountNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
            action = ACTION_REMOVE;
        }
    }

    return true;
}

bool Position::remove_piece(Square s, bool updateCmdlist)
{
    if (phase & PHASE_NOTPLAYING)
        return false;

    if (action != ACTION_REMOVE)
        return false;

    if (pieceCountNeedRemove <= 0)
        return false;

    // if piece is not their
    if (!(make_piece(them) & board[s]))
        return false;

    if (!rule.allowRemovePieceInMill &&
        in_how_many_mills(s, NOBODY) &&
        !is_all_in_mills(~sideToMove)) {
        return false;
    }

    revert_key(s);

    if (rule.hasBannedLocations && phase == PHASE_PLACING) {
        board[s]= BAN_STONE;
        update_key(s);
        byTypeBB[them] ^= s;
        byTypeBB[BAN] |= s;
    } else { // Remove
        board[s]= NO_PIECE;
        byTypeBB[ALL_PIECES] ^= s;
        byTypeBB[them] ^= s;
    }

    if (updateCmdlist) {
        sprintf(cmdline, "-(%1u,%1u)", file_of(s), rank_of(s));
        gamePly++;
        st->rule50 = 0;     // TODO: Need to move out?
    }

    pieceCountOnBoard[them]--;

    if (pieceCountOnBoard[them] + pieceCountInHand[them] < rule.nPiecesAtLeast) {
        winner = sideToMove;
        phase = PHASE_GAMEOVER;
        gameoverReason = LOSE_REASON_LESS_THAN_THREE;
        return true;
    }

    currentSquare = SQ_0;

    pieceCountNeedRemove--;

    if (pieceCountNeedRemove > 0) {
        return true;
    }

    if (phase == PHASE_PLACING) {
        if (pieceCountInHand[BLACK] == 0 && pieceCountInHand[WHITE] == 0) {
            phase = PHASE_MOVING;
            action = ACTION_SELECT;

            if (rule.hasBannedLocations) {
                remove_ban_stones();
            }

            if (rule.isDefenderMoveFirst) {
                goto check;
            }
        } else {
            action = ACTION_PLACE;
        }
    } else {
        action = ACTION_SELECT;
    }

    change_side_to_move();

check:
    check_gameover_condition();    

    return true;
}

bool Position::select_piece(Square s)
{
    if (phase != PHASE_MOVING)
        return false;

    if (action != ACTION_SELECT && action != ACTION_PLACE)
        return false;

    if (board[s] & make_piece(sideToMove)) {
        currentSquare = s;
        action = ACTION_PLACE;

        return true;
    }

    return false;
}

bool Position::giveup(Color loser)
{
    if (phase & PHASE_NOTPLAYING ||
        phase == PHASE_NONE) {
        return false;
    }

    phase = PHASE_GAMEOVER;

    winner = ~loser;
    gameoverReason = LOSE_REASON_GIVE_UP;
    //sprintf(cmdline, "Player%d give up!", loser);
    update_score();

    return true;
}

bool Position::command(const char *cmd)
{
    int ruleIndex;
    unsigned t;
    Step step;
    File file1, file2;
    Rank rank1, rank2;
    int args = 0;

    if (sscanf(cmd, "r%1u s%3hd t%2u", &ruleIndex, &step, &t) == 3) {
        if (ruleIndex <= 0 || ruleIndex > N_RULES) {
            return false;
        }

        return set_position(&RULES[ruleIndex - 1]) >= 0 ? true : false;
    }

    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u)", &file1, &rank1, &file2, &rank2);

    if (args >= 4) {
        return move_piece(file1, rank1, file2, rank2);
    }

    args = sscanf(cmd, "-(%1u,%1u)", &file1, &rank1);
    if (args >= 2) {
        return remove_piece(file1, rank1);
    }

    args = sscanf(cmd, "(%1u,%1u)", &file1, &rank1);
    if (args >= 2) {
        return put_piece(file1, rank1);
    }

    args = sscanf(cmd, "Player%1u give up!", &t);

    if (args == 1) {
        return giveup((Color)t);
    }

#ifdef THREEFOLD_REPETITION
    if (!strcmp(cmd, "Threefold Repetition. Draw!")) {
        return true;
    }

    if (!strcmp(cmd, "draw")) {
        phase = PHASE_GAMEOVER;
        winner = DRAW;
        score_draw++;
        gameoverReason = DRAW_REASON_THREEFOLD_REPETITION;        
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

int Position::update()
{
    int ret = -1;
    int timePoint = -1;
    time_t *ourSeconds = &elapsedSeconds[sideToMove];
    time_t theirSeconds = elapsedSeconds[them];

    if (!(phase & PHASE_PLAYING)) {
        return -1;
    }

    currentTime = time(NULL);

    if (timePoint >= *ourSeconds) {
        *ourSeconds = ret = timePoint;
        startTime = currentTime - (elapsedSeconds[BLACK] + elapsedSeconds[WHITE]);
    } else {
        *ourSeconds = ret = currentTime - startTime - theirSeconds;
    }

    return ret;
}

void Position::update_score()
{
    if (phase == PHASE_GAMEOVER) {    
        if (winner == DRAW) {
            score_draw++;
            return;
        }

        score[winner]++;
    }
}

bool Position::check_gameover_condition()
{
    if (phase & PHASE_NOTPLAYING) {
        return true;
    }

    if (rule.maxStepsLedToDraw > 0 &&
        st->rule50 > rule.maxStepsLedToDraw) {
        winner = DRAW;
        phase = PHASE_GAMEOVER;        
        gameoverReason = DRAW_REASON_RULE_50;
        return true;
    }

#ifdef MCTS_AI
#if 0
    int diff = pieceCountOnBoard[BLACK] - pieceCountOnBoard[WHITE];
    if (diff > 4) {
        winner = BLACK;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player1 win!");

        return true;
    }

    if (diff < -4) {
        winner = WHITE;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player2 win!");

        return true;
    }
#endif
#endif

    if (pieceCountOnBoard[BLACK] + pieceCountOnBoard[WHITE] >= RANK_NB * FILE_NB) {
        phase = PHASE_GAMEOVER;

        if (rule.isBlackLosebutNotDrawWhenBoardFull) {
            winner = WHITE;
            gameoverReason = LOSE_REASON_BOARD_IS_FULL;
        } else {
            winner = DRAW;
            gameoverReason = DRAW_REASON_BOARD_IS_FULL;
        }

        return true;
    }

    if (phase == PHASE_MOVING && action == ACTION_SELECT && is_all_surrounded()) {
        // TODO: move to next branch
        phase = PHASE_GAMEOVER;

        if (rule.isLoseButNotChangeSideWhenNoWay) {
            gameoverReason = LOSE_REASON_NO_WAY;
            winner = ~sideToMove;
            return true;
        } else {
            change_side_to_move();
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

    for (Square i = SQ_BEGIN; i < SQ_END; i = static_cast<Square>(i + 1)) {
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

            if (board[s]== BAN_STONE) {
                revert_key(s);
                board[s]= NO_PIECE;
                byTypeBB[ALL_PIECES] ^= s;   // Need to remove?
            }
        }
    }
}

inline void Position::set_side_to_move(Color c)
{
    sideToMove = c;
    them = ~sideToMove;
}

inline void Position::change_side_to_move()
{
    set_side_to_move(~sideToMove);
}

void Position::do_null_move()
{
    change_side_to_move();
}

void Position::undo_null_move()
{
    change_side_to_move();
}

time_t Position::get_elapsed_time(int us)
{
    return elapsedSeconds[us];
}

inline Key Position::update_key(Square s)
{
    // PieceType is board[s]

    // 0b00 - no piece，0b01 = 1 black，0b10 = 2 white，0b11 = 3 ban
    int pieceType = color_on(s);
    // TODO: this is std, but current code can work
    //Location loc = board[s];
    //int pieceType = loc == 0x0f? 3 : loc >> 4;

    st->key ^= Zobrist::psq[pieceType][s];

    return st->key;
}

inline Key Position::revert_key(Square s)
{
    return update_key(s);
}

Key Position::update_key_misc()
{
    const int KEY_MISC_BIT = 8;

    st->key = st->key << KEY_MISC_BIT >> KEY_MISC_BIT;
    Key hi = 0;

    if (sideToMove == WHITE) {
        hi |= 1U;
    }

    if (action == ACTION_REMOVE) {
        hi |= 1U << 1;
    }

    hi |= static_cast<Key>(pieceCountNeedRemove) << 2;
    hi |= static_cast<Key>(pieceCountInHand[BLACK]) << 4;     // TODO: may use phase is also OK?

    st->key = st->key | (hi << (CHAR_BIT * sizeof(Key) - KEY_MISC_BIT));

    return st->key;
}

Key Position::next_primary_key(Move m)
{
    Key npKey = st->key /* << 8 >> 8 */;
    Square s = static_cast<Square>(to_sq(m));;
    MoveType mt = type_of(m);

    if (mt == MOVETYPE_REMOVE) {
        int pieceType = ~sideToMove;
        npKey ^= Zobrist::psq[pieceType][s];

        if (rule.hasBannedLocations && phase == PHASE_PLACING) {
            npKey ^= Zobrist::psq[BAN][s];
        }

        return npKey;
    }

    int pieceType = sideToMove;
    npKey ^= Zobrist::psq[pieceType][s];

    if (mt == MOVETYPE_MOVE) {
        npKey ^= Zobrist::psq[pieceType][from_sq(m)];
    }

    return npKey;
}

///////////////////////////////////////////////////////////////////////////////

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


#include "movegen.h"
#include "misc.h"

const int Position::onBoard[SQUARE_NB] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

int Position::millTable[SQUARE_NB][LD_NB][FILE_NB - 1] = { {{0}} };

#if 0
Position &Position::operator= (const Position &other)
{
    if (this == &other)
        return *this;

    memcpy(this->board, other.board, sizeof(this->board));
    memcpy(this->byTypeBB, other.byTypeBB, sizeof(this->byTypeBB));

    memcpy(&millList, &other.millList, sizeof(millList));
    millListSize = other.millListSize;

    return *this;
}
#endif

void Position::create_mill_table()
{
    const int millTable_noObliqueLine[SQUARE_NB][LD_NB][2] = {
        /* 0 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 1 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 2 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 3 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 4 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 5 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 6 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 7 */ {{0, 0}, {0, 0}, {0, 0}},

        /* 8 */ {{16, 24}, {9, 15}, {0, 0}},
        /* 9 */ {{0, 0}, {15, 8}, {10, 11}},
        /* 10 */ {{18, 26}, {11, 9}, {0, 0}},
        /* 11 */ {{0, 0}, {9, 10}, {12, 13}},
        /* 12 */ {{20, 28}, {13, 11}, {0, 0}},
        /* 13 */ {{0, 0}, {11, 12}, {14, 15}},
        /* 14 */ {{22, 30}, {15, 13}, {0, 0}},
        /* 15 */ {{0, 0}, {13, 14}, {8, 9}},

        /* 16 */ {{8, 24}, {17, 23}, {0, 0}},
        /* 17 */ {{0, 0}, {23, 16}, {18, 19}},
        /* 18 */ {{10, 26}, {19, 17}, {0, 0}},
        /* 19 */ {{0, 0}, {17, 18}, {20, 21}},
        /* 20 */ {{12, 28}, {21, 19}, {0, 0}},
        /* 21 */ {{0, 0}, {19, 20}, {22, 23}},
        /* 22 */ {{14, 30}, {23, 21}, {0, 0}},
        /* 23 */ {{0, 0}, {21, 22}, {16, 17}},

        /* 24 */ {{8, 16}, {25, 31}, {0, 0}},
        /* 25 */ {{0, 0}, {31, 24}, {26, 27}},
        /* 26 */ {{10, 18}, {27, 25}, {0, 0}},
        /* 27 */ {{0, 0}, {25, 26}, {28, 29}},
        /* 28 */ {{12, 20}, {29, 27}, {0, 0}},
        /* 29 */ {{0, 0}, {27, 28}, {30, 31}},
        /* 30 */ {{14, 22}, {31, 29}, {0, 0}},
        /* 31 */ {{0, 0}, {29, 30}, {24, 25}},

        /* 32 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 33 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 34 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 35 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 36 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 37 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 38 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 39 */ {{0, 0}, {0, 0}, {0, 0}}
    };

    const int millTable_hasObliqueLines[SQUARE_NB][LD_NB][2] = {
        /*  0 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  1 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  2 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  3 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  4 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  5 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  6 */ {{0, 0}, {0, 0}, {0, 0}},
        /*  7 */ {{0, 0}, {0, 0}, {0, 0}},

        /*  8 */ {{16, 24}, {9, 15}, {0, 0}},
        /*  9 */ {{17, 25}, {15, 8}, {10, 11}},
        /* 10 */ {{18, 26}, {11, 9}, {0, 0}},
        /* 11 */ {{19, 27}, {9, 10}, {12, 13}},
        /* 12 */ {{20, 28}, {13, 11}, {0, 0}},
        /* 13 */ {{21, 29}, {11, 12}, {14, 15}},
        /* 14 */ {{22, 30}, {15, 13}, {0, 0}},
        /* 15 */ {{23, 31}, {13, 14}, {8, 9}},

        /* 16 */ {{8, 24}, {17, 23}, {0, 0}},
        /* 17 */ {{9, 25}, {23, 16}, {18, 19}},
        /* 18 */ {{10, 26}, {19, 17}, {0, 0}},
        /* 19 */ {{11, 27}, {17, 18}, {20, 21}},
        /* 20 */ {{12, 28}, {21, 19}, {0, 0}},
        /* 21 */ {{13, 29}, {19, 20}, {22, 23}},
        /* 22 */ {{14, 30}, {23, 21}, {0, 0}},
        /* 23 */ {{15, 31}, {21, 22}, {16, 17}},

        /* 24 */ {{8, 16}, {25, 31}, {0, 0}},
        /* 25 */ {{9, 17}, {31, 24}, {26, 27}},
        /* 26 */ {{10, 18}, {27, 25}, {0, 0}},
        /* 27 */ {{11, 19}, {25, 26}, {28, 29}},
        /* 28 */ {{12, 20}, {29, 27}, {0, 0}},
        /* 29 */ {{13, 21}, {27, 28}, {30, 31}},
        /* 30 */ {{14, 22}, {31, 29}, {0, 0}},
        /* 31 */ {{15, 23}, {29, 30}, {24, 25}},

        /* 32 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 33 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 34 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 35 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 36 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 37 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 38 */ {{0, 0}, {0, 0}, {0, 0}},
        /* 39 */ {{0, 0}, {0, 0}, {0, 0}}
    };

    if (rule.hasObliqueLines) {
        memcpy(millTable, millTable_hasObliqueLines, sizeof(millTable));
    } else {
        memcpy(millTable, millTable_noObliqueLine, sizeof(millTable));
    }

#ifdef DEBUG_MODE
    for (int i = 0; i < SQUARE_NB; i++) {
        loggerDebug("/* %d */ {", i);
        for (int j = 0; j < MD_NB; j++) {
            loggerDebug("{");
            for (int k = 0; k < 2; k++) {
                if (k == 0) {
                    loggerDebug("%d, ", millTable[i][j][k]);
                } else {
                    loggerDebug("%d", millTable[i][j][k]);
                }

            }
            if (j == 2)
                loggerDebug("}");
            else
                loggerDebug("}, ");
        }
        loggerDebug("},\n");
    }

    loggerDebug("======== millTable End =========\n");
#endif /* DEBUG_MODE */
}

Color Position::color_on(Square s) const
{
    return color_of(board[s]);
}

int Position::in_how_many_mills(Square s, Color c, Square squareSelected)
{
    int n = 0;
    Piece locbak = NO_PIECE;

    if (c == NOBODY) {
        c = color_on(s);
    }

    if (squareSelected != SQ_0) {
        locbak = board[squareSelected];
        board[squareSelected] = NO_PIECE;
    }

    for (int l = 0; l < LD_NB; l++) {
        if (make_piece(c) &
            board[millTable[s][l][0]] &
            board[millTable[s][l][1]]) {
            n++;
        }
    }

    if (squareSelected != SQ_0) {
        board[squareSelected] = locbak;
    }

    return n;
}

int Position::add_mills(Square s)
{
    uint64_t mill = 0;
    int n = 0;
    int idx[3], min, temp;
    Color m = color_on(s);

    for (int i = 0; i < 3; i++) {
        idx[0] = s;
        idx[1] = millTable[s][i][0];
        idx[2] = millTable[s][i][1];

        // no mill
        if (!(make_piece(m) & board[idx[1]] & board[idx[2]])) {
            continue;
        }

        // close mill

        // sort
        for (int j = 0; j < 2; j++) {
            min = j;

            for (int k = j + 1; k < 3; k++) {
                if (idx[min] > idx[k])
                    min = k;
            }

            if (min == j) {
                continue;
            }

            temp = idx[min];
            idx[min] = idx[j];
            idx[j] = temp;
        }

        mill = (static_cast<uint64_t>(board[idx[0]]) << 40)
            + (static_cast<uint64_t>(idx[0]) << 32)
            + (static_cast<uint64_t>(board[idx[1]]) << 24)
            + (static_cast<uint64_t>(idx[1]) << 16)
            + (static_cast<uint64_t>(board[idx[2]]) << 8)
            + static_cast<uint64_t>(idx[2]);

        if (rule.allowRemovePiecesRepeatedlyWhenCloseSameMill) {
            n++;
            continue;
        }

        int im = 0;
        for (im = 0; im < millListSize; im++) {
            if (mill == millList[im]) {
                break;
            }
        }

        if (im == millListSize) {
            n++;
            millList[i] = mill;
            millListSize++;
        }
    }

    return n;
}

bool Position::is_all_in_mills(Color c)
{
    for (Square i = SQ_BEGIN; i < SQ_END; i = static_cast<Square>(i + 1)) {
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

    int count = 0;

    if (pieceCountOnBoard[sideToMove] > rule.nPiecesAtLeast ||
        !rule.allowFlyWhenRemainThreePieces) {
        Square moveSquare;
        for (MoveDirection d = MD_BEGIN; d < MD_NB; d = (MoveDirection)(d + 1)) {
            moveSquare = static_cast<Square>(MoveList::moveTable[s][d]);
            if (moveSquare) {
                if (board[moveSquare] == 0x00 ||
                    (includeFobidden && board[moveSquare] == BAN_STONE)) {
                    count++;
                }
            }
        }
    }

    return count;
}

void Position::surrounded_pieces_count(Square s, int &nOurPieces, int &nTheirPieces, int &nBanned, int &nEmpty)
{
    Square moveSquare;

    for (MoveDirection d = MD_BEGIN; d < MD_NB; d = (MoveDirection)(d + 1)) {
        moveSquare = static_cast<Square>(MoveList::moveTable[s][d]);

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
    if (pieceCountOnBoard[BLACK] + pieceCountOnBoard[WHITE] >= RANK_NB * FILE_NB)
        return true;

    // Can fly
    if (pieceCountOnBoard[sideToMove] <= rule.nPiecesAtLeast &&
        rule.allowFlyWhenRemainThreePieces) {
        return false;
    }

    Square moveSquare;

    for (Square s = SQ_BEGIN; s < SQ_END; s = (Square)(s + 1)) {
        if (!(sideToMove & color_on(s))) {
            continue;
        }

        for (MoveDirection d = MD_BEGIN; d < MD_NB; d = (MoveDirection)(d + 1)) {
            moveSquare = static_cast<Square>(MoveList::moveTable[s][d]);
            if (moveSquare && !board[moveSquare]) {
                return false;
            }
        }
    }

    return true;
}

bool Position::is_star_square(Square s)
{
    if (rule.nTotalPiecesEachSide == 12) {
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

    if (rule.allowRemovePiecesRepeatedlyWhenCloseSameMill) {
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
    }

    if (cmdChange) {
        int r1, s1, r2, s2;
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
        board[RANK_NB + r] = board[RANK_NB * FILE_NB + r];
        board[RANK_NB * FILE_NB + r] = ch;
    }

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

    if (rule.allowRemovePiecesRepeatedlyWhenCloseSameMill) {
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
    }

    // 命令行解析
    if (cmdChange) {
        int r1, s1, r2, s2;
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

    if (rule.allowRemovePiecesRepeatedlyWhenCloseSameMill) {
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
    }

    if (cmdChange) {
        int r1, s1, r2, s2;
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

void Position::flip()
{
    // TODO
    return;
}

void Position::print_board()
{
    if (rule.nTotalPiecesEachSide == 12) {
        loggerDebug("\n"
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
        loggerDebug("\n"
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

/// Position::pos_is_ok() performs some consistency checks for the
/// position object and raises an asserts if something wrong is detected.
/// This is meant to be helpful when debugging.

bool Position::pos_is_ok() const
{
    // TODO
    return true;
}
