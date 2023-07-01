// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <algorithm>
#include <iomanip>
#include <sstream>
#include <string> // std::string, std::stoi

#include "bitboard.h"
#include "mills.h"
#include "option.h"
#include "position.h"
#include "thread.h"

using std::string;

namespace Zobrist {
constexpr int KEY_MISC_BIT = 2;
Key psq[PIECE_TYPE_NB][SQUARE_EXT_NB];
Key side;
} // namespace Zobrist

namespace {
string PieceToChar(Piece p)
{
    if (p == NO_PIECE) {
        return "*";
    }

    if (p == BAN_PIECE) {
        return "X";
    }

    if (W_PIECE <= p && p <= W_PIECE_12) {
        return "O";
    }

    if (B_PIECE <= p && p <= B_PIECE_12) {
        return "@";
    }

    return "*";
}

Piece CharToPiece(char ch) noexcept
{
    if (ch == '*') {
        return NO_PIECE;
    }

    if (ch == 'O') {
        return W_PIECE;
    }

    if (ch == '@') {
        return B_PIECE;
    }

    if (ch == 'X') {
        return BAN_PIECE;
    }

    return NO_PIECE;
}

constexpr PieceType PieceTypes[] = {NO_PIECE_TYPE, WHITE_PIECE, BLACK_PIECE,
                                    BAN};
} // namespace

/// operator<<(Position) returns an ASCII representation of the position

std::ostream &operator<<(std::ostream &os, const Position &pos)
{
    /*
        X --- X --- X
        |\    |    /|
        | X - X - X |
        | |\  |  /| |
        | | X-X-X | |
        X-X-X   X-X-X
        | | X-X-X | |
        | |/  |  \| |
        | X - X - X |
        |/    |    \|
        X --- X --- X
    */

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

#define P(s) PieceToChar(pos.piece_on(Square(s)))

    if (rule.hasDiagonalLines) {
        os << "\n";
        os << P(31) << " --- " << P(24) << " --- " << P(25) << "\n";
        os << "|\\    |    /|\n";
        os << "| " << P(23) << " - " << P(16) << " - " << P(17) << " |\n";
        os << "| |\\  |  /| |\n";
        os << "| | " << P(15) << "-" << P(8) << "-" << P(9) << " | |\n";
        os << P(30) << "-" << P(22) << "-" << P(14) << "   " << P(10) << "-"
           << P(18) << "-" << P(26) << "\n";
        os << "| | " << P(13) << "-" << P(12) << "-" << P(11) << " | |\n";
        os << "| |/  |  \\| |\n";
        os << "| " << P(21) << " - " << P(20) << " - " << P(19) << " |\n";
        os << "|/    |    \\|\n";
        os << P(29) << " --- " << P(28) << " --- " << P(27) << "\n";
    } else {
        os << "\n";
        os << P(31) << " --- " << P(24) << " --- " << P(25) << "\n";
        os << "|     |     |\n";
        os << "| " << P(23) << " - " << P(16) << " - " << P(17) << " |\n";
        os << "| |   |   | |\n";
        os << "| | " << P(15) << "-" << P(8) << "-" << P(9) << " | |\n";
        os << P(30) << "-" << P(22) << "-" << P(14) << "   " << P(10) << "-"
           << P(18) << "-" << P(26) << "\n";
        os << "| | " << P(13) << "-" << P(12) << "-" << P(11) << " | |\n";
        os << "| |   |   | |\n";
        os << "| " << P(21) << " - " << P(20) << " - " << P(19) << " |\n";
        os << "|     |     |\n";
        os << P(29) << " --- " << P(28) << " --- " << P(27) << "\n";
    }

#undef P

    const auto fill = os.fill();
    const auto flags = os.flags();

    os << "\nFen: " << pos.fen() << "\nKey: " << std::hex << std::uppercase
       << std::setfill('0') << std::setw(16) << pos.key() << std::endl;

    os.flags(flags);
    os.fill(fill);

    return os;
}

#ifdef NNUE_GENERATE_TRAINING_DATA
// Training data
std::vector<std::string> nnueTrainingDataStringStream {};
Value nnueTrainingDataBestValue {VALUE_NONE};
std::string nnueTrainingDataBestMove;
std::string nnueTrainingDataGameResult = "#";
int nnueTrainingDataIndex = 0;

void Position::nnueGenerateTrainingFen()
{
    if (nnueTrainingDataBestMove == "") {
        return;
    }

    nnueTrainingDataIndex++;

    nnueTrainingDataStringStream.emplace_back(
        fen() + " " + std::to_string((int)nnueTrainingDataBestValue) + " " + nnueTrainingDataBestMove +
        " " + std::to_string(nnueTrainingDataIndex));
}

string Position::nnueGetOpponentGameResult()
{
    if (nnueTrainingDataGameResult == "1-0") {
        return "0-1";
    } else if (nnueTrainingDataGameResult == "0-1") {
        return "1-0";
    } else if (nnueTrainingDataGameResult == "1/2-1/2") {
        return nnueTrainingDataGameResult;
    } else {
        assert(0);
    }

    return "";
}

string Position::nnueGetCurSideGameResult(char lastSide, const string &fen)
{
    char side = fen[27];

    if (side == lastSide) {
        return nnueTrainingDataGameResult;
    } else {
        return nnueGetOpponentGameResult();
    }
}

void Position::nnueWriteTrainingData()
{
    if (nnueTrainingDataStringStream.size() == 0) {
        return;
    }

    string tail = nnueTrainingDataStringStream[nnueTrainingDataStringStream.size() - 1];
    char lastSide = tail[27];

    std::ofstream file;
    string filename = std::tmpnam(nullptr);
    filename = filename.substr(filename.find_last_of('\\') + 1);
    time_t t = time(NULL);
    unsigned long long time = (unsigned long long)t;
    filename = ".\\data\\training-data_" + filename + "_" +
               std::to_string(time) + ".txt";

    file.open(filename, std::ios::out);

    for each (string var in nnueTrainingDataStringStream) {
        file << var + " " + nnueGetCurSideGameResult(lastSide, var) + "\n";
    }

    file.close();

    nnueTrainingDataIndex = 0;
    nnueTrainingDataStringStream.clear();
    nnueTrainingDataBestValue = VALUE_NONE;
    nnueTrainingDataBestMove = "";
    nnueTrainingDataGameResult = "#";
}
#endif /* NNUE_GENERATE_TRAINING_DATA */

/// Position::init() initializes at startup the various arrays used to compute
/// hash keys

void Position::init()
{
    PRNG rng(1070372);

    for (const PieceType pt : PieceTypes)
        for (Square s = SQ_BEGIN; s < SQ_END; ++s)
            Zobrist::psq[pt][s] = rng.rand<Key>() << Zobrist::KEY_MISC_BIT >>
                                  Zobrist::KEY_MISC_BIT;

    Zobrist::side = rng.rand<Key>() << Zobrist::KEY_MISC_BIT >>
                    Zobrist::KEY_MISC_BIT;
}

Position::Position()
{
    construct_key();

    reset();

    score[WHITE] = score[BLACK] = score_draw = gamesPlayedCount = 0;
}

/// Position::set() initializes the position object with the given FEN string.
/// This function is not very robust - make sure that input FENs are correct,
/// this is assumed to be the responsibility of the GUI.

Position &Position::set(const string &fenStr, Thread *th)
{
    /*
       A FEN string defines a particular position using only the ASCII character
       set.

       A FEN string contains six fields separated by a space. The fields are:

       1) Piece placement. Each rank is described, starting
          with rank 1 and ending with rank 8. Within each rank, the contents of
       each square are described from file A through file C. Following the
       Standard Algebraic Notation (SAN), each piece is identified by a single
       letter taken from the standard English names. White pieces are designated
       using "O" whilst Black uses "@". Blank uses "*". Banned uses "X". noted
       using digits 1 through 8 (the number of blank squares), and "/" separates
       ranks.

       2) Active color. "w" means white moves next, "b" means black.

       3) Phrase.

       4) Action.

       5) White on board/White in hand/Black on board/Black in hand/need to
       remove

       6) Halfmove clock. This is the number of halfmoves since the last
          capture. This is used to determine if a draw can be claimed under the
          N-move rule.

       7) Fullmove number. The number of the full move. It starts at 1, and is
          incremented after White's move.
    */

    unsigned char token = '\0';
    Square sq = SQ_A1;
    std::istringstream ss(fenStr);

    std::memset(this, 0, sizeof(Position));

    ss >> std::noskipws;

    // 1. Piece placement
    while ((ss >> token) && !isspace(token)) {
        if (token == 'O' || token == '@' || token == 'X') {
            put_piece(CharToPiece(token), sq);
            ++sq;
        }
        if (token == '*') {
            ++sq;
        }
    }

    // 2. Active color
    ss >> token;
    sideToMove = (token == 'w' ? WHITE : BLACK);
    them = ~sideToMove; // Note: Stockfish do not need to set them

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

    // 4. Action
    ss >> token;
    ss >> token;

    switch (token) {
    case 'p':
        action = Action::place;
        break;
    case 's':
        action = Action::select;
        break;
    case 'r':
        action = Action::remove;
        break;
    default:
        action = Action::none;
    }

    // 5. White on board / White in hand / Black on board / Black in hand /
    // White need to remove / Black need to remove
    ss >> std::skipws >> pieceOnBoardCount[WHITE] >> pieceInHandCount[WHITE] >>
        pieceOnBoardCount[BLACK] >> pieceInHandCount[BLACK] >>
        pieceToRemoveCount[WHITE] >> pieceToRemoveCount[BLACK];

    // 6-7. Halfmove clock and fullmove number
    ss >> std::skipws >> st.rule50 >> gamePly;

    // Convert from fullmove starting from 1 to gamePly starting from 0,
    // handle also common incorrect FEN with fullmove = 0.
    gamePly = std::max(2 * (gamePly - 1), 0) + (sideToMove == BLACK);

    // For Mill only
    check_if_game_is_over();
#if 0
    // It doesn't work
    if (pieceToRemoveCount[sideToMove] == 1) {
        action = Action::remove;
        isStalemateRemoving = true;
    }
#endif

    thisThread = th;

    return *this;
}

/// Position::fen() returns a FEN representation of the position.
/// This is mainly a debugging function.

string Position::fen() const
{
    std::ostringstream ss;

    // Piece placement data
    for (File f = FILE_A; f <= FILE_C; ++f) {
        for (Rank r = RANK_1; r <= RANK_8; ++r) {
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
    }

    ss << " ";

    // Action
    switch (action) {
    case Action::place:
        ss << "p";
        break;
    case Action::select:
        ss << "s";
        break;
    case Action::remove:
        ss << "r";
        break;
    case Action::none:
        ss << "?";
        break;
    }

    ss << " ";

    ss << pieceOnBoardCount[WHITE] << " " << pieceInHandCount[WHITE] << " "
       << pieceOnBoardCount[BLACK] << " " << pieceInHandCount[BLACK] << " "
       << pieceToRemoveCount[WHITE] << " " << pieceToRemoveCount[BLACK] << " ";

    ss << st.rule50 << " " << 1 + (gamePly - (sideToMove == BLACK)) / 2;

    return ss.str();
}

/// Position::legal() tests whether a pseudo-legal move is legal

bool Position::legal(Move m) const
{
    assert(is_ok(m));

    const Color us = sideToMove;
    const Square from = from_sq(m);
    const Square to = to_sq(m);

    if (from == to) {
        return false;
    }

    if (phase == Phase::moving && type_of(move) != MOVETYPE_REMOVE) {
        if (color_of(moved_piece(m)) != us) {
            return false;
        }
    }

    return true;
}

/// Position::do_move() makes a move, and saves all information necessary
/// to a StateInfo object. The move is assumed to be legal. Pseudo-legal
/// moves should be filtered out before this function is called.

void Position::do_move(Move m)
{
    bool ret = false;

    const MoveType mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        ret = remove_piece(to_sq(m));
        if (ret) {
            // Reset rule 50 counter
            st.rule50 = 0;
        }
        break;
    case MOVETYPE_MOVE:
        ret = move_piece(from_sq(m), to_sq(m));
        if (ret) {
            ++st.rule50;
        }
        break;
    case MOVETYPE_PLACE:
        ret = put_piece(to_sq(m));
        if (ret) {
            // Reset rule 50 counter
            st.rule50 = 0;
        }
        break;
    }

    if (!ret) {
        return;
    }

    // Increment ply counters. In particular
    ++gamePly;
    ++st.pliesFromNull;

    move = m;
}

/// Position::undo_move() unmakes a move. When it returns, the position should
/// be restored to exactly the same state as before the move was made.

void Position::undo_move(Sanmill::Stack<Position> &ss)
{
    memcpy(this, ss.top(), sizeof(Position));
    ss.pop();
}

/// Position::key_after() computes the new hash key after the given move. Needed
/// for speculative prefetch. It doesn't recognize special moves like (need
/// remove)

Key Position::key_after(Move m) const
{
    Key k = st.key;
    const auto s = to_sq(m);
    const MoveType mt = type_of(m);

    if (mt == MOVETYPE_REMOVE) {
        k ^= Zobrist::psq[~side_to_move()][s];

        if (rule.hasBannedLocations && phase == Phase::placing) {
            k ^= Zobrist::psq[BAN][s];
        }
    } else {
        k ^= Zobrist::psq[side_to_move()][s];

        if (mt == MOVETYPE_MOVE) {
            k ^= Zobrist::psq[side_to_move()][from_sq(m)];
        }
    }

    k ^= Zobrist::side;

    return k;
}

int repetition;

// Position::has_repeated() tests whether there has been at least one repetition
// of positions since the last remove.

bool Position::has_repeated(Sanmill::Stack<Position> &ss) const
{
    for (int i = static_cast<int>(posKeyHistory.size()) - 2; i >= 0; i--) {
        if (key() == posKeyHistory[i]) {
            return true;
        }
    }

    const int size = ss.size();

    for (int i = size - 1; i >= 0; i--) {
        if (type_of(ss[i].move) == MOVETYPE_REMOVE) {
            break;
        }
        if (key() == ss[i].st.key) {
            return true;
        }
    }

    return false;
}

/// Position::has_game_cycle() tests if the position has a move which draws by
/// repetition.

bool Position::has_game_cycle() const
{
    for (const auto i : posKeyHistory) {
        if (key() == i) {
            repetition++;
            if (repetition == 3) {
                repetition = 0;
                return true;
            }
        }
    }

    return false;
}

/// Mill Game

bool Position::reset()
{
    repetition = 0;

    gamePly = 0;
    st.rule50 = 0;

    phase = Phase::ready;
    set_side_to_move(WHITE);
    action = Action::place;

    winner = NOBODY;
    gameOverReason = GameOverReason::none;

    memset(board, 0, sizeof(board));
    memset(byTypeBB, 0, sizeof(byTypeBB));
    memset(byColorBB, 0, sizeof(byColorBB));

    st.key = 0;

    pieceOnBoardCount[WHITE] = pieceOnBoardCount[BLACK] = 0;
    pieceInHandCount[WHITE] = pieceInHandCount[BLACK] = rule.pieceCount;
    pieceToRemoveCount[WHITE] = pieceToRemoveCount[BLACK] = 0;

    isNeedStalemateRemoval = false;
    isStalemateRemoving = false;

    mobilityDiff = 0;

    MoveList<LEGAL>::create();
    create_mill_table();
    currentSquare = SQ_0;

#ifdef ENDGAME_LEARNING
    if (gameOptions.isEndgameLearningEnabled() && gamesPlayedCount > 0 &&
        gamesPlayedCount % SAVE_ENDGAME_EVERY_N_GAMES == 0) {
        Thread::saveEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */

    int r;
    for (r = 0; r < N_RULES; r++) {
        if (strcmp(rule.name, RULES[r].name) == 0)
            break;
    }

    if (snprintf(record, RECORD_LEN_MAX, "r%1d s%03u t%02d", r + 1,
                 rule.nMoveRule, 0) > 0) {
        return true;
    }

    record[0] = '\0';

    return false;
}

bool Position::start()
{
    gameOverReason = GameOverReason::none;

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
    case Phase::none:
        return false;
    }

    return false;
}

bool Position::put_piece(Square s, bool updateRecord)
{
    const Color us = sideToMove;

    if (phase == Phase::gameOver || action != Action::place ||
        !(SQ_BEGIN <= s && s < SQ_END) || board[s]) {
        return false;
    }

    isNeedStalemateRemoval = false;

    if (phase == Phase::ready) {
        start();
    }

    if (phase == Phase::placing) {
        const auto piece = static_cast<Piece>((0x01 | make_piece(sideToMove)) +
                                              rule.pieceCount -
                                              pieceInHandCount[us]);
        pieceInHandCount[us]--;
        pieceOnBoardCount[us]++;

        const Piece pc = board[s] = piece;
        byTypeBB[ALL_PIECES] |= byTypeBB[type_of(pc)] |= s;
        byColorBB[color_of(pc)] |= s; // TODO(calcitem): Put ban?

        update_key(s);

        updateMobility(MOVETYPE_PLACE, s);

        if (updateRecord) {
            snprintf(record, RECORD_LEN_MAX, "(%1d,%1d)", file_of(s),
                     rank_of(s));
        }

        currentSquare = s;

#ifdef MADWEASEL_MUEHLE_RULE
        if (pieceInHandCount[WHITE] == 0 && pieceInHandCount[BLACK] == 0 &&
            is_all_surrounded(~sideToMove, SQ_0, s)) {
            set_gameover(sideToMove, GameOverReason::loseNoWay);
            // change_side_to_move();
            return true;
        }
#endif

        const int n = mills_count(currentSquare);

        if (n == 0
#ifdef MADWEASEL_MUEHLE_RULE
            || is_all_in_mills(them)
#endif
        ) {
            if (pieceInHandCount[WHITE] < 0 || pieceInHandCount[BLACK] < 0) {
                return false;
            }

            if (pieceInHandCount[WHITE] == 0 && pieceInHandCount[BLACK] == 0) {
                if (check_if_game_is_over()) {
                    return true;
                }

                if (pieceToRemoveCount[sideToMove] > 0) {
                    action = Action::remove;
                    update_key_misc();
                } else {
                    phase = Phase::moving;
                    action = Action::select;

                    if (rule.hasBannedLocations) {
                        remove_ban_pieces();
                    }

                    if (!rule.isDefenderMoveFirst) {
                        change_side_to_move();
                    }

                    if (check_if_game_is_over()) {
                        return true;
                    }
                }
            } else {
                change_side_to_move();
            }
        } else {
            pieceToRemoveCount[sideToMove] = rule.mayRemoveMultiple ? n : 1;
            update_key_misc();

            if (rule.mayOnlyRemoveUnplacedPieceInPlacingPhase) {
                pieceInHandCount[them] -= 1; // Or pieceToRemoveCount?;

                if (pieceInHandCount[them] < 0) {
                    pieceInHandCount[them] = 0;
                }

                if (pieceInHandCount[WHITE] < 0 ||
                    pieceInHandCount[BLACK] < 0) {
                    return false;
                }

                if (pieceInHandCount[WHITE] == 0 &&
                    pieceInHandCount[BLACK] == 0) {
                    if (check_if_game_is_over()) {
                        return true;
                    }

                    phase = Phase::moving;
                    action = Action::select;

                    if (rule.isDefenderMoveFirst) {
                        change_side_to_move();
                    }

                    if (check_if_game_is_over()) {
                        return true;
                    }
                }
            } else {
                action = Action::remove;
            }
        }

    } else if (phase == Phase::moving) {
#ifdef MADWEASEL_MUEHLE_RULE
        if (is_all_surrounded(~sideToMove, currentSquare, s)) {
            set_gameover(sideToMove, GameOverReason::loseNoWay);
        }
#else
        if (check_if_game_is_over()) {
            return true;
        }
#endif // MADWEASEL_MUEHLE_RULE

        // If illegal
        if (pieceOnBoardCount[sideToMove] > rule.flyPieceCount ||
            !rule.mayFly) {
            if ((square_bb(s) &
                 MoveList<LEGAL>::adjacentSquaresBB[currentSquare]) == 0) {
                return false;
            }
        }

        if (updateRecord) {
            snprintf(record, RECORD_LEN_MAX, "(%1d,%1d)->(%1d,%1d)",
                     file_of(currentSquare), rank_of(currentSquare), file_of(s),
                     rank_of(s));
            st.rule50++;
        }

        const Piece pc = board[currentSquare];

        CLEAR_BIT(byTypeBB[ALL_PIECES], currentSquare);
        CLEAR_BIT(byTypeBB[type_of(pc)], currentSquare);
        CLEAR_BIT(byColorBB[color_of(pc)], currentSquare);

        updateMobility(MOVETYPE_REMOVE, currentSquare);

        SET_BIT(byTypeBB[ALL_PIECES], s);
        SET_BIT(byTypeBB[type_of(pc)], s);
        SET_BIT(byColorBB[color_of(pc)], s);

        updateMobility(MOVETYPE_PLACE, s);

        board[s] = pc;
        update_key(s);
        revert_key(currentSquare);

        board[currentSquare] = NO_PIECE;

        currentSquare = s;

        const int n = mills_count(currentSquare);

        if (n == 0
#ifdef MADWEASEL_MUEHLE_RULE
            || is_all_in_mills(them)
#endif
        ) {
            action = Action::select;
            change_side_to_move();

            if (check_if_game_is_over()) {
                return true;
            }

            if (pieceToRemoveCount[sideToMove] == 1) {
                update_key_misc();
                action = Action::remove;
                isNeedStalemateRemoval = true;
            }
        } else {
            pieceToRemoveCount[sideToMove] = rule.mayRemoveMultiple ? n : 1;
            update_key_misc();
            action = Action::remove;
        }
    } else {
        return false;
    }

    return true;
}

bool Position::remove_piece(Square s, bool updateRecord)
{
    if (phase == Phase::ready || phase == Phase::gameOver)
        return false;

    if (action != Action::remove)
        return false;

    if (pieceToRemoveCount[sideToMove] <= 0)
        return false;

    // if piece is not their
    if (!(make_piece(~side_to_move()) & board[s]))
        return false;

    if (is_stalemate_removal()) {
        if (is_adjacent_to(s, sideToMove) == false) {
            return false;
        }
    } else if (!rule.mayRemoveFromMillsAlways &&
               potential_mills_count(s, NOBODY)
#ifndef MADWEASEL_MUEHLE_RULE
               && !is_all_in_mills(~sideToMove)
#endif
    ) {
        return false;
    }

    revert_key(s);

    Piece pc = board[s];

    CLEAR_BIT(byTypeBB[type_of(pc)],
              s); // TODO(calcitem): rule.hasBannedLocations and placing need?
    CLEAR_BIT(byColorBB[color_of(pc)], s);

    updateMobility(MOVETYPE_REMOVE, s);

    if (rule.hasBannedLocations && phase == Phase::placing) {
        // Remove and put ban
        pc = board[s] = BAN_PIECE;
        update_key(s);
        SET_BIT(byTypeBB[type_of(pc)], s);
    } else {
        // Remove only
        CLEAR_BIT(byTypeBB[ALL_PIECES], s);
        board[s] = NO_PIECE;
    }

    if (updateRecord) {
        snprintf(record, RECORD_LEN_MAX, "-(%1d,%1d)", file_of(s), rank_of(s));
        st.rule50 = 0; // TODO(calcitem): Need to move out?
    }

    pieceOnBoardCount[them]--;

    if (pieceOnBoardCount[them] + pieceInHandCount[them] <
        rule.piecesAtLeastCount) {
        set_gameover(sideToMove, GameOverReason::loseLessThanThree);
        return true;
    }

    currentSquare = SQ_0;

    pieceToRemoveCount[sideToMove]--;
    update_key_misc();

    if (pieceToRemoveCount[sideToMove] > 0) {
        return true;
    }

    if (isStalemateRemoving) {
        isStalemateRemoving = false;
    } else {
        change_side_to_move();
    }

    if (pieceToRemoveCount[sideToMove] > 0) {
        return true;
    }

    if (phase == Phase::placing) {
        if (pieceInHandCount[WHITE] == 0 && pieceInHandCount[BLACK] == 0) {
            phase = Phase::moving;
            action = Action::select;

            if (rule.hasBannedLocations) {
                remove_ban_pieces();
            }

            if (rule.isDefenderMoveFirst) {
                set_side_to_move(BLACK);
                goto check;
            } else {
                set_side_to_move(WHITE);
            }
        } else {
            action = Action::place;
        }
    } else {
        action = Action::select;
    }

check:
    if (check_if_game_is_over()) {
        return true;
    }

    return true;
}

bool Position::select_piece(Square s)
{
    if (phase != Phase::moving)
        return false;

    if (action != Action::select && action != Action::place)
        return false;

    if (board[s] & make_piece(sideToMove)) {
        currentSquare = s;
        action = Action::place;

        return true;
    }

    return false;
}

bool Position::resign(Color loser)
{
    if (phase == Phase::ready || phase == Phase::gameOver ||
        phase == Phase::none) {
        return false;
    }

    set_gameover(~loser, GameOverReason::loseResign);

    snprintf(record, RECORD_LEN_MAX, loseReasonResignStr, loser);

    return true;
}

bool Position::command(const char *cmd)
{
    char moveStr[64] = {0};
    unsigned int ruleNo = 0;
    unsigned t = 0;
    int step = 0;
    File file1 = FILE_A, file2 = FILE_A;
    Rank rank1 = RANK_1, rank2 = RANK_1;

    sscanf(cmd, "info score %d bestmove %s", &bestvalue, moveStr, 32);

    if (sscanf(moveStr, "r%1u s%3d t%2u", &ruleNo, &step, &t) == 3) {
        if (set_rule(ruleNo - 1) == false) {
            return false;
        }

        return reset();
    }

    int args = sscanf(moveStr, "(%1u,%1u)->(%1u,%1u)",
                      reinterpret_cast<unsigned *>(&file1),
                      reinterpret_cast<unsigned *>(&rank1),
                      reinterpret_cast<unsigned *>(&file2),
                      reinterpret_cast<unsigned *>(&rank2));

    if (args >= 4) {
        return move_piece(file1, rank1, file2, rank2);
    }

    args = sscanf(moveStr, "-(%1u,%1u)", reinterpret_cast<unsigned *>(&file1),
                  reinterpret_cast<unsigned *>(&rank1));
    if (args >= 2) {
        return remove_piece(file1, rank1);
    }

    args = sscanf(moveStr, "(%1u,%1u)", reinterpret_cast<unsigned *>(&file1),
                  reinterpret_cast<unsigned *>(&rank1));
    if (args >= 2) {
        return put_piece(file1, rank1);
    }

    args = sscanf(moveStr, "Player%1u give up!", &t);

    if (args == 1) {
        return resign(static_cast<Color>(t));
    }

    if (rule.threefoldRepetitionRule) {
        if (!strcmp(moveStr, drawReasonThreefoldRepetitionStr)) {
            return true;
        }

        if (!strcmp(moveStr, "draw")) {
            set_gameover(DRAW, GameOverReason::drawThreefoldRepetition);
            // snprintf(record, RECORD_LEN_MAX,
            // drawReasonThreefoldRepetitionStr);
            return true;
        }
    }

    return false;
}

Color Position::get_winner() const noexcept
{
    return winner;
}

void Position::set_gameover(Color w, GameOverReason reason)
{
    phase = Phase::gameOver;
    gameOverReason = reason;
    winner = w;

    update_score();
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
#ifdef RULE_50
    if (rule.nMoveRule > 0 && posKeyHistory.size() >= rule.nMoveRule) {
        set_gameover(DRAW, GameOverReason::drawRule50);
        return true;
    }

    if (rule.endgameNMoveRule < rule.nMoveRule && is_three_endgame() &&
        posKeyHistory.size() >= rule.endgameNMoveRule) {
        set_gameover(DRAW, GameOverReason::drawEndgameRule50);
        return true;
    }
#endif // RULE_50

    if (rule.pieceCount == 12 &&
        (pieceOnBoardCount[WHITE] + pieceOnBoardCount[BLACK] >= SQUARE_NB)) {
        // TODO: BoardFullAction: Support other actions
        switch (rule.boardFullAction) {
        case BoardFullAction::firstPlayerLose:
            set_gameover(BLACK, GameOverReason::loseBoardIsFull);
            return true;
        case BoardFullAction::firstAndSecondPlayerRemovePiece:
            pieceToRemoveCount[WHITE] = pieceToRemoveCount[BLACK] = 1;
            // Pursue performance at the expense of maintainability
            change_side_to_move();
            return false;
        case BoardFullAction::secondAndFirstPlayerRemovePiece:
            pieceToRemoveCount[WHITE] = pieceToRemoveCount[BLACK] = 1;
            return false;
        case BoardFullAction::sideToMoveRemovePiece:
            if (rule.isDefenderMoveFirst) {
                set_side_to_move(BLACK);
            } else {
                set_side_to_move(WHITE);
            }
            pieceToRemoveCount[sideToMove] = 1;
            return false;
        case BoardFullAction::agreeToDraw:
            set_gameover(DRAW, GameOverReason::drawBoardIsFull);
            return true;
        };
    }

    if (phase == Phase::moving && action == Action::select &&
        is_all_surrounded(sideToMove)) {
        switch (rule.stalemateAction) {
        case StalemateAction::endWithStalemateLoss:
            set_gameover(~sideToMove, GameOverReason::loseNoWay);
            return true;
        case StalemateAction::changeSideToMove:
            change_side_to_move(); // TODO(calcitem): Need?
            return false;
        case StalemateAction::removeOpponentsPieceAndMakeNextMove:
            pieceToRemoveCount[sideToMove] = 1;
            isStalemateRemoving = true;
            action = Action::remove;
            return false;
        case StalemateAction::removeOpponentsPieceAndChangeSideToMove:
            pieceToRemoveCount[sideToMove] = 1;
            action = Action::remove;
            return false;
        case StalemateAction::endWithStalemateDraw:
            set_gameover(DRAW, GameOverReason::drawNoWay);
            return true;
        }
    }

    return false;
}

int Position::calculate_mobility_diff()
{
    // TODO(calcitem): Deal with rule is no ban location
    int mobilityWhite = 0;
    int mobilityBlack = 0;

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        if (board[s] == NO_PIECE || board[s] == BAN_PIECE) {
            for (MoveDirection d = MD_BEGIN; d < MD_NB; ++d) {
                const Square moveSquare = MoveList<LEGAL>::adjacentSquares[s][d];
                if (moveSquare) {
                    if (board[moveSquare] & W_PIECE) {
                        mobilityWhite++;
                    }
                    if (board[moveSquare] & B_PIECE) {
                        mobilityBlack++;
                    }
                }
            }
        }
    }

    return mobilityWhite - mobilityBlack;
}

void Position::remove_ban_pieces()
{
    assert(rule.hasBannedLocations);

    for (int f = 1; f <= FILE_NB; f++) {
        for (int r = 0; r < RANK_NB; r++) {
            const auto s = static_cast<Square>(f * RANK_NB + r);

            if (board[s] == BAN_PIECE) {
                const Piece pc = board[s];
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
    // us = c;
    them = ~sideToMove;
}

inline void Position::change_side_to_move()
{
    set_side_to_move(~sideToMove);
    st.key ^= Zobrist::side;
}

inline Key Position::update_key(Square s)
{
    const int pieceType = color_on(s);

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

    // TODO: pieceToRemoveCount[sideToMove] or
    // abs(pieceToRemoveCount[sideToMove] - pieceToRemoveCount[~sideToMove])?
    st.key |= static_cast<Key>(pieceToRemoveCount[sideToMove])
              << (CHAR_BIT * sizeof(Key) - Zobrist::KEY_MISC_BIT);

    return st.key;
}

///////////////////////////////////////////////////////////////////////////////

#include "misc.h"
#include "movegen.h"

Bitboard Position::millTableBB[SQUARE_EXT_NB][LD_NB] = {{0}};

void Position::create_mill_table()
{
    Mills::mill_table_init();
}

Color Position::color_on(Square s) const
{
    return color_of(board[s]);
}

bool Position::bitboard_is_ok()
{
#ifdef BITBOARD_DEBUG
    Bitboard whiteBB = byColorBB[WHITE];
    Bitboard blackBB = byColorBB[BLACK];

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        if (empty(s)) {
            if (whiteBB & (1 << s)) {
                return false;
            }

            if (blackBB & (1 << s)) {
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

        if (color_of(board[s]) == BLACK) {
            if ((blackBB & (1 << s)) == 0) {
                return false;
            }

            if (whiteBB & (1 << s)) {
                return false;
            }
        }
    }
#endif

    return true;
}

int Position::potential_mills_count(Square to, Color c, Square from)
{
    int n = 0;
    Piece locbak = NO_PIECE;

    assert(SQ_0 <= from && from < SQUARE_EXT_NB);

    if (c == NOBODY) {
        c = color_on(to);
    }

    if (from >= SQ_BEGIN && from < SQ_END) {
        locbak = board[from];
        board[from] = NO_PIECE;

        CLEAR_BIT(byTypeBB[ALL_PIECES], from);
        CLEAR_BIT(byTypeBB[type_of(locbak)], from);
        CLEAR_BIT(byColorBB[color_of(locbak)], from);
    }

    const Bitboard bc = byColorBB[c];
    const Bitboard *mt = millTableBB[to];

    if ((bc & mt[LD_HORIZONTAL]) == mt[LD_HORIZONTAL]) {
        n++;
    }

    if ((bc & mt[LD_VERTICAL]) == mt[LD_VERTICAL]) {
        n++;
    }

    if ((bc & mt[LD_SLASH]) == mt[LD_SLASH]) {
        n++;
    }

    if (from >= SQ_BEGIN && from < SQ_END) {
        board[from] = locbak;

        SET_BIT(byTypeBB[ALL_PIECES], from);
        SET_BIT(byTypeBB[type_of(locbak)], from);
        SET_BIT(byColorBB[color_of(locbak)], from);
    }

    return n;
}

int Position::mills_count(Square s) const
{
    int n = 0;

    const Bitboard bc = byColorBB[color_on(s)];
    const Bitboard *mt = millTableBB[s];

    for (auto i = 0; i < LD_NB; ++i) {
        if ((bc & mt[i]) == mt[i]) {
            n++;
        }
    }

    return n;
}

bool Position::is_all_in_mills(Color c)
{
    for (Square i = SQ_BEGIN; i < SQ_END; ++i) {
        if (board[i] & static_cast<uint8_t>(make_piece(c))) {
            if (!potential_mills_count(i, NOBODY)) {
                return false;
            }
        }
    }

    return true;
}

void Position::surrounded_pieces_count(Square s, int &ourPieceCount,
                                       int &theirPieceCount, int &bannedCount,
                                       int &emptyCount) const
{
    for (MoveDirection d = MD_BEGIN; d < MD_NB; ++d) {
        const Square moveSquare = MoveList<LEGAL>::adjacentSquares[s][d];

        if (!moveSquare) {
            continue;
        }

        switch (const auto pieceType = board[moveSquare]) {
        case NO_PIECE:
            emptyCount++;
            break;
        case BAN_PIECE:
            bannedCount++;
            break;
        default:
            if (color_of(pieceType) == sideToMove) {
                ourPieceCount++;
            } else {
                theirPieceCount++;
            }
            break;
        }
    }
}

bool Position::is_all_surrounded(Color c
#ifdef MADWEASEL_MUEHLE_RULE
                                 ,
                                 Square from, Square to
#endif // MADWEASEL_MUEHLE_RULE
) const
{
    // Full
    if (pieceOnBoardCount[WHITE] + pieceOnBoardCount[BLACK] >= SQUARE_NB)
        return true;

    // Can fly
    if (pieceOnBoardCount[c] <= rule.flyPieceCount && rule.mayFly) {
        return false;
    }

    Bitboard bb = byTypeBB[ALL_PIECES];

#ifdef MADWEASEL_MUEHLE_RULE
    CLEAR_BIT(bb, from);
    SET_BIT(bb, to);
#endif // MADWEASEL_MUEHLE_RULE

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        if ((c & color_on(s)) && (bb & MoveList<LEGAL>::adjacentSquaresBB[s]) !=
                                     MoveList<LEGAL>::adjacentSquaresBB[s]) {
            return false;
        }
    }

    return true;
}

bool Position::is_star_square(Square s)
{
    if (rule.hasDiagonalLines == true) {
        return s == 17 || s == 19 || s == 21 || s == 23;
    }

    return s == 16 || s == 18 || s == 20 || s == 22;
}

void Position::print_board()
{
    if (rule.hasDiagonalLines) {
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
        const Piece pc = board[s];
        byTypeBB[ALL_PIECES] |= byTypeBB[type_of(pc)] |= s;
        byColorBB[color_of(pc)] |= s;
    }
}

void Position::updateMobility(MoveType mt, Square s)
{
    if (!gameOptions.getConsiderMobility()) {
        return;
    }

    const Bitboard adjacentWhiteBB = byColorBB[WHITE] &
                                     MoveList<LEGAL>::adjacentSquaresBB[s];
    const Bitboard adjacentBlackBB = byColorBB[BLACK] &
                                     MoveList<LEGAL>::adjacentSquaresBB[s];
    const Bitboard adjacentNoColorBB = (~(byColorBB[BLACK] |
                                          byColorBB[WHITE])) &
                                       MoveList<LEGAL>::adjacentSquaresBB[s];
    const int adjacentWhiteBBCount = popcount(adjacentWhiteBB);
    const int adjacentBlackBBCount = popcount(adjacentBlackBB);
    const int adjacentNoColorBBCount = popcount(adjacentNoColorBB);

    if (mt == MOVETYPE_PLACE) {
        mobilityDiff -= adjacentWhiteBBCount;
        mobilityDiff += adjacentBlackBBCount;

        if (side_to_move() == WHITE) {
            mobilityDiff += adjacentNoColorBBCount;
        } else {
            mobilityDiff -= adjacentNoColorBBCount;
        }
    } else if (mt == MOVETYPE_REMOVE) {
        mobilityDiff += adjacentWhiteBBCount;
        mobilityDiff -= adjacentBlackBBCount;

        if (color_of(board[s]) == WHITE) {
            mobilityDiff -= adjacentNoColorBBCount;
        } else {
            mobilityDiff += adjacentNoColorBBCount;
        }
    } else {
        assert(0);
    }
}

int Position::total_mills_count(Color c)
{
    assert(c == WHITE || c == BLACK);

    // TODO: Move to mills.cpp
    static const int horizontalAndVerticalLines[16][3] = {
        // Horizontal lines
        {31, 24, 25},
        {23, 16, 17},
        {15, 8, 9},
        {30, 22, 14},
        {10, 18, 26},
        {13, 12, 11},
        {21, 20, 19},
        {29, 28, 27},
        // Vertical lines
        {31, 30, 29},
        {23, 22, 21},
        {15, 14, 13},
        {24, 16, 8},
        {12, 20, 28},
        {9, 10, 11},
        {17, 18, 19},
        {25, 26, 27},
    };

    static const int diagonalLines[4][3] = {
        {31, 23, 15},
        {9, 17, 25},
        {29, 21, 13},
        {11, 19, 27},
    };

    int n = 0;

        for (int i  = 0; i < 16; i++) {
        if (color_on(static_cast<Square>(horizontalAndVerticalLines[i][0])) == c &&
            color_on(static_cast<Square>(horizontalAndVerticalLines[i][1])) ==
                c &&
            color_on(static_cast<Square>(horizontalAndVerticalLines[i][2])) ==
                c) {
            n++;
        }
    }

    if (rule.hasDiagonalLines == true) {
        for (int i = 0; i < 4; i++) {
            if (color_on(static_cast<Square>(diagonalLines[i][0])) == c &&
                color_on(static_cast<Square>(diagonalLines[i][1])) == c &&
                color_on(static_cast<Square>(diagonalLines[i][2])) == c) {
                n++;
            }
        }
    }

    return n;
}

bool Position::is_board_full_removal_at_placing_phase_end()
{
    if (rule.pieceCount == 12 &&
        rule.boardFullAction != BoardFullAction::firstPlayerLose &&
        rule.boardFullAction != BoardFullAction::agreeToDraw &&
        phase == Phase::placing && pieceInHandCount[WHITE] == 0 &&
        pieceInHandCount[BLACK] == 0 &&
        // TODO: Performance
        total_mills_count(BLACK) == 0) {
        return true;
    }

    return false;
}

bool Position::is_adjacent_to(Square s, Color c)
{
    for (int d = MD_BEGIN; d < MD_NB; d++) {
        const Square moveSquare = MoveList<LEGAL>::adjacentSquares[s][d];
        if (moveSquare != SQ_0 && color_on(moveSquare) == c) {
            return true;
        }
    }
    return false;
}

bool Position::is_stalemate_removal()
{
    if (is_board_full_removal_at_placing_phase_end()) {
        return true;
    }

    if (!(rule.stalemateAction ==
              StalemateAction::removeOpponentsPieceAndChangeSideToMove ||
          rule.stalemateAction ==
              StalemateAction::removeOpponentsPieceAndMakeNextMove)) {
        return false;
    }

    if (isStalemateRemoving == true) {
        return true;
    }

    // TODO: StalemateAction: It is best to inform the engine of this state by
    // the front end to improve performance.
    if (is_all_surrounded(sideToMove)) {
        return true;
    }

    return false;
}

void Position::mirror(vector<string> &moveHistory, bool cmdChange /*= true*/)
{
    int f, r;

    for (f = 1; f <= FILE_NB; f++) {
        for (r = 1; r < RANK_NB / 2; r++) {
            const Piece ch = board[f * RANK_NB + r];
            board[f * RANK_NB + r] = board[(f + 1) * RANK_NB - r];
            board[(f + 1) * RANK_NB - r] = ch;
        }
    }

    reset_bb();

    if (move < 0) {
        f = (-move) / RANK_NB;
        r = (-move) % RANK_NB;
        r = (RANK_NB - r) % RANK_NB;
        move = static_cast<Move>(-(f * RANK_NB + r));
    } else {
        uint64_t llp[3] = {0};

        llp[0] = static_cast<uint64_t>(from_sq(move));
        llp[1] = to_sq(move);

        for (int i = 0; i < 2; i++) {
            f = static_cast<int>(llp[i]) / RANK_NB;
            r = static_cast<int>(llp[i]) % RANK_NB;
            r = (RANK_NB - r) % RANK_NB;
            llp[i] = static_cast<uint64_t>(f) * RANK_NB + r;
        }

        move = static_cast<Move>((llp[0] << 8) | llp[1]);
    }

    if (currentSquare != 0) {
        f = currentSquare / static_cast<Square>(RANK_NB);
        r = currentSquare % static_cast<Square>(RANK_NB);
        r = (RANK_NB - r) % RANK_NB;
        currentSquare = static_cast<Square>(f * RANK_NB + r);
    }

    if (cmdChange) {
        unsigned r1, s1, r2, s2;

        int args = sscanf(record, "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2, &s2);
        if (args >= 4) {
            s1 = (RANK_NB - s1 + 1) % RANK_NB;
            s2 = (RANK_NB - s2 + 1) % RANK_NB;
            record[3] = '1' + static_cast<char>(s1);
            record[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(record, "-(%1u,%1u)", &r1, &s1);
            if (args >= 2) {
                s1 = (RANK_NB - s1 + 1) % RANK_NB;
                record[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(record, "(%1u,%1u)", &r1, &s1);
                if (args >= 2) {
                    s1 = (RANK_NB - s1 + 1) % RANK_NB;
                    record[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : moveHistory) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2,
                          &s2);
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

void Position::turn(vector<string> &moveHistory, bool cmdChange /*= true*/)
{
    int f, r;

    for (r = 0; r < RANK_NB; r++) {
        const Piece ch = board[RANK_NB + r];
        board[RANK_NB + r] = board[SQUARE_NB + r];
        board[SQUARE_NB + r] = ch;
    }

    reset_bb();

    uint64_t llp[3] = {0};

    if (move < 0) {
        f = (-move) / RANK_NB;
        r = (-move) % RANK_NB;

        if (f == 1)
            f = FILE_NB;
        else if (f == FILE_NB)
            f = 1;

        move = static_cast<Move>(-(f * RANK_NB + r));
    } else {
        llp[0] = static_cast<uint64_t>(from_sq(move));
        llp[1] = to_sq(move);

        for (int i = 0; i < 2; i++) {
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
        f = currentSquare / static_cast<Square>(RANK_NB);
        r = currentSquare % static_cast<Square>(RANK_NB);

        if (f == 1)
            f = FILE_NB;
        else if (f == FILE_NB)
            f = 1;

        currentSquare = static_cast<Square>(f * RANK_NB + r);
    }

    if (cmdChange) {
        unsigned r1, s1, r2, s2;

        int args = sscanf(record, "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2, &s2);

        if (args >= 4) {
            if (r1 == 1)
                r1 = FILE_NB;
            else if (r1 == FILE_NB)
                r1 = 1;

            if (r2 == 1)
                r2 = FILE_NB;
            else if (r2 == FILE_NB)
                r2 = 1;

            record[1] = '0' + static_cast<char>(r1);
            record[8] = '0' + static_cast<char>(r2);
        } else {
            args = sscanf(record, "-(%1u,%1u)", &r1, &s1);
            if (args >= 2) {
                if (r1 == 1)
                    r1 = FILE_NB;
                else if (r1 == FILE_NB)
                    r1 = 1;
                record[2] = '0' + static_cast<char>(r1);
            } else {
                args = sscanf(record, "(%1u,%1u)", &r1, &s1);
                if (args >= 2) {
                    if (r1 == 1)
                        r1 = FILE_NB;
                    else if (r1 == FILE_NB)
                        r1 = 1;
                    record[1] = '0' + static_cast<char>(r1);
                }
            }
        }

        for (auto &iter : moveHistory) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2,
                          &s2);

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

void Position::rotate(vector<string> &moveHistory, int degrees,
                      bool cmdChange /*= true*/)
{
    degrees = degrees % 360;

    if (degrees < 0)
        degrees += 360;

    if (degrees == 0 || degrees % 90)
        return;

    degrees /= 45;

    Piece ch1, ch2;
    int f, r;

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

    if (move < 0) {
        f = (-move) / RANK_NB;
        r = (-move) % RANK_NB;
        r = (r + RANK_NB - degrees) % RANK_NB;
        move = static_cast<Move>(-(f * RANK_NB + r));
    } else {
        uint64_t llp[3] = {0};

        llp[0] = static_cast<uint64_t>(from_sq(move));
        llp[1] = to_sq(move);
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
        f = currentSquare / static_cast<Square>(RANK_NB);
        r = currentSquare % static_cast<Square>(RANK_NB);
        r = (r + RANK_NB - degrees) % RANK_NB;
        currentSquare = static_cast<Square>(f * RANK_NB + r);
    }

    if (cmdChange) {
        unsigned r1, s1, r2, s2;

        int args = sscanf(record, "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2, &s2);

        if (args >= 4) {
            s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
            s2 = (s2 - 1 + RANK_NB - degrees) % RANK_NB;
            record[3] = '1' + static_cast<char>(s1);
            record[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(record, "-(%1u,%1u)", &r1, &s1);

            if (args >= 2) {
                s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                record[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(record, "(%1u,%1u)", &r1, &s1);

                if (args >= 2) {
                    s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                    record[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : moveHistory) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u)", &r1, &s1, &r2,
                          &s2);

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
