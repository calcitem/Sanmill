// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// position.cpp

#include "search_engine.h"
#include "mills.h"
#include "position.h"
#include "thread.h"
#include "evaluate.h"
#include "uci.h"

#include <algorithm>
#include <cstring>
#include <iomanip>
#include <sstream>
#include <string>
#include <iostream>

using std::string;
using std::vector;

extern vector<Key> posKeyHistory;

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

    if (p == MARKED_PIECE) {
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
        return MARKED_PIECE;
    }

    return NO_PIECE;
}

constexpr PieceType PieceTypes[] = {NO_PIECE_TYPE, WHITE_PIECE, BLACK_PIECE,
                                    MARKED};
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
        | /       |      \ |\n"
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
        fen() + " " + std::to_string((int)nnueTrainingDataBestValue) + " " +
        nnueTrainingDataBestMove + " " + std::to_string(nnueTrainingDataIndex));
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

    string tail =
        nnueTrainingDataStringStream[nnueTrainingDataStringStream.size() - 1];
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

Position &Position::set(const string &fenStr)
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
       using "O" whilst Black uses "@". Blank uses "*". Marked uses "X". noted
       using digits 1 through 8 (the number of blank squares), and "/" separates
       ranks.

       2) Active color. "w" means white moves next, "b" means black.

       3) Phrase.

       4) Action.

       5) White on board/White in hand/Black on board/Black in hand/need to
       remove/Last mill square of white/Last mill square of black

       6) Mills bitmask.

       7) Halfmove clock. This is the number of halfmoves since the last
          capture. This is used to determine if a draw can be claimed under the
          N-move rule.

       8) Fullmove number. The number of the full move. It starts at 1, and is
          incremented after White's move.
    */

    unsigned char token = '\0';
    Square sq = SQ_A1;
    std::istringstream ss(fenStr);

    *this = Position();

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
    // White need to remove / Black need to remove / last mill square of white /
    // last mill square of black
    int tmpLastMillFromSquareWhite = 0;
    int tmpLastMillToSquareWhite = 0;
    int tmpLastMillFromSquareBlack = 0;
    int tmpLastMillToSquareBlack = 0;
    ss >> std::skipws >> pieceOnBoardCount[WHITE] >> pieceInHandCount[WHITE] >>
        pieceOnBoardCount[BLACK] >> pieceInHandCount[BLACK] >>
        pieceToRemoveCount[WHITE] >> pieceToRemoveCount[BLACK] >>
        tmpLastMillFromSquareWhite >> tmpLastMillToSquareWhite >>
        tmpLastMillFromSquareBlack >> tmpLastMillToSquareBlack;

    lastMillFromSquare[WHITE] = static_cast<Square>(tmpLastMillFromSquareWhite);
    lastMillToSquare[WHITE] = static_cast<Square>(tmpLastMillToSquareWhite);
    lastMillFromSquare[BLACK] = static_cast<Square>(tmpLastMillFromSquareBlack);
    lastMillToSquare[BLACK] = static_cast<Square>(tmpLastMillToSquareBlack);

    // 6. Mills bitmask
    uint64_t mb = 0;
    ss >> std::skipws >> mb;
    setFormedMillsBB(mb);

    // 7-8. Halfmove clock and fullmove number
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

    ss << lastMillFromSquare[WHITE] << " " << lastMillToSquare[WHITE] << " "
       << lastMillFromSquare[BLACK] << " " << lastMillToSquare[BLACK] << " ";

    uint64_t fm = (static_cast<uint64_t>(formedMillsBB[WHITE]) << 32) |
                  formedMillsBB[BLACK];
    ss << fm << " ";

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
    *this = *ss.top();
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

        if (rule.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase::markAndDelayRemovingPieces &&
            phase == Phase::placing) {
            k ^= Zobrist::psq[MARKED][s];
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
    ptrdiff_t count = std::count(posKeyHistory.begin(), posKeyHistory.end(),
                                 key());

    // TODO: Maintain consistent interface behavior
#ifdef QT_GUI_LIB
    return count >= 2;
#else
    return count >= 3;
#endif
}

/// Mill Game

bool Position::reset()
{
    gamePly = 0;
    st.rule50 = 0;

    set_side_to_move(WHITE);
    phase = Phase::ready;
    action = Action::place;

    winner = NOBODY;
    gameOverReason = GameOverReason::None;

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
    currentSquare[WHITE] = currentSquare[BLACK] = SQ_0;
    lastMillFromSquare[WHITE] = lastMillFromSquare[BLACK] = SQ_0;
    lastMillToSquare[WHITE] = lastMillToSquare[BLACK] = SQ_0;
    formedMillsBB[WHITE] = formedMillsBB[BLACK] = 0;

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

    record[0] = '\0';

    return true;
}

bool Position::start()
{
    gameOverReason = GameOverReason::None;

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

    if (phase == Phase::gameOver || !(SQ_BEGIN <= s && s < SQ_END) ||
        board[s] & make_piece(~us) || board[s] == MARKED_PIECE) {
        return false;
    }

    if (!can_move_during_placing_phase() && board[s]) {
        return false;
    }

    if (rule.restrictRepeatedMillsFormation &&
        currentSquare[us] == lastMillToSquare[us] &&
        currentSquare[us] != SQ_NONE && s == lastMillFromSquare[us]) {
        if (potential_mills_count(s, us, currentSquare[us]) > 0 &&
            mills_count(currentSquare[us]) > 0) {
            return false;
        }
    }

    isNeedStalemateRemoval = false;

    if (phase == Phase::ready) {
        start();
    }

    if (phase == Phase::placing && action == Action::place) {
        if (can_move_during_placing_phase()) {
            if (board[s] == NO_PIECE) {
                if (currentSquare[us] != SQ_NONE) {
                    return handle_moving_phase_for_put_piece(s, updateRecord);
                }
            } else {
                // Select piece
                currentSquare[us] = currentSquare[us] == s ? SQ_NONE : s;
                return true;
            }
        }

        const auto piece = static_cast<Piece>((0x01 | make_piece(sideToMove)) +
                                              rule.pieceCount -
                                              pieceInHandCount[us]);
        if (pieceInHandCount[us] > 0) {
            pieceInHandCount[us]--;
        } else {
            // TODO: Deal with invalid position
            // assert(false);
            return false;
        }

        pieceOnBoardCount[us]++;

        const Piece pc = board[s] = piece;
        byTypeBB[ALL_PIECES] |= byTypeBB[type_of(pc)] |= s;
        byColorBB[color_of(pc)] |= s; // TODO: Put Marked?

        update_key(s);

        updateMobility(MOVETYPE_PLACE, s);

        currentSquare[sideToMove] = SQ_NONE;
        lastMillFromSquare[sideToMove] = lastMillToSquare[sideToMove] = SQ_NONE;

        if (updateRecord) {
            snprintf(record, RECORD_LEN_MAX, "%s", UCI::square(s).c_str());
        }

        const int n = mills_count(s);

        if (n == 0) {
            // If no Mill

            if (pieceToRemoveCount[WHITE] != 0 ||
                pieceToRemoveCount[BLACK] != 0) {
                assert(false);
                return false;
            }

            lastMillFromSquare[sideToMove] = SQ_NONE;
            lastMillToSquare[sideToMove] = SQ_NONE;

            if (rule.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase::removalBasedOnMillCounts) {
                if (pieceInHandCount[WHITE] == 0 &&
                    pieceInHandCount[BLACK] == 0) {
                    if (!handle_placing_phase_end()) {
                        change_side_to_move();
                    }

                    // Check if Stalemate and change side to move if needed
                    if (check_if_game_is_over()) {
                        return true;
                    }
                    return true;
                }
            }

            // Begin of set side to move

            // Board is full at the end of Placing phase
            if (rule.pieceCount == 12 &&
                (pieceOnBoardCount[WHITE] + pieceOnBoardCount[BLACK] >=
                 SQUARE_NB)) {
                // TODO: BoardFullAction: Support other actions
                switch (rule.boardFullAction) {
                case BoardFullAction::firstPlayerLose:
                    set_gameover(BLACK, GameOverReason::loseFullBoard);
                    return true;
                case BoardFullAction::firstAndSecondPlayerRemovePiece:
                    pieceToRemoveCount[WHITE] = pieceToRemoveCount[BLACK] = 1;
                    change_side_to_move();
                    break;
                case BoardFullAction::secondAndFirstPlayerRemovePiece:
                    pieceToRemoveCount[WHITE] = pieceToRemoveCount[BLACK] = 1;
                    keep_side_to_move();
                    break;
                case BoardFullAction::sideToMoveRemovePiece:
                    set_side_to_move(rule.isDefenderMoveFirst ? BLACK : WHITE);
                    pieceToRemoveCount[sideToMove] = 1;
                    keep_side_to_move();
                    break;
                case BoardFullAction::agreeToDraw:
                    set_gameover(DRAW, GameOverReason::drawFullBoard);
                    return true;
                }
            } else {
                // Board is not full at the end of Placing phase

                if (!handle_placing_phase_end()) {
                    change_side_to_move();
                }

                // Check if Stalemate and change side to move if needed
                if (check_if_game_is_over()) {
                    return true;
                }
            }
            // End of set side to move
        } else {
            // If forming Mill
            int rm = 0;

            if (rule.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase::removalBasedOnMillCounts) {
                rm = pieceToRemoveCount[sideToMove] = 0;
            } else {
                rm = pieceToRemoveCount[sideToMove] = rule.mayRemoveMultiple ?
                                                          n :
                                                          1;
                update_key_misc();
            }

            if (rule.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase::
                        removeOpponentsPieceFromHandThenYourTurn ||
                rule.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase::
                        removeOpponentsPieceFromHandThenOpponentsTurn) {
                for (int i = 0; i < rm; i++) {
                    if (pieceInHandCount[them] == 0) {
                        pieceToRemoveCount[sideToMove] = rm - i;
                        update_key_misc();
                        action = Action::remove;
                        return true;
                    } else {
                        pieceInHandCount[them]--;
                        pieceToRemoveCount[sideToMove]--;
                        update_key_misc();
                    }

                    assert(pieceInHandCount[WHITE] >= 0 &&
                           pieceInHandCount[BLACK] >= 0);
                }

                if (!handle_placing_phase_end()) {
                    if (rule.millFormationActionInPlacingPhase ==
                        MillFormationActionInPlacingPhase::
                            removeOpponentsPieceFromHandThenOpponentsTurn) {
                        change_side_to_move();
                    }
                }

                if (check_if_game_is_over()) {
                    return true;
                }
            } else {
                if (rule.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase::removalBasedOnMillCounts) {
                    if (pieceInHandCount[WHITE] == 0 &&
                        pieceInHandCount[BLACK] == 0) {
                        if (!handle_placing_phase_end()) {
                            change_side_to_move();
                        }

                        // Check if Stalemate and change side to move if needed
                        if (check_if_game_is_over()) {
                            return true;
                        }
                        return true;
                    } else {
                        change_side_to_move();
                    }
                } else {
                    action = Action::remove;
                }
                return true;
            }
        }

    } else if (phase == Phase::moving) {
        return handle_moving_phase_for_put_piece(s, updateRecord);
    } else {
        return false;
    }

    return true;
}

bool Position::handle_moving_phase_for_put_piece(Square s, bool updateRecord)
{
    if (board[s] != NO_PIECE) {
        return false;
    }

    if (check_if_game_is_over()) {
        return true;
    }

    // If illegal
    if (pieceOnBoardCount[sideToMove] > rule.flyPieceCount || !rule.mayFly ||
        pieceInHandCount[sideToMove] > 0) {
        if ((square_bb(s) &
             MoveList<LEGAL>::adjacentSquaresBB[currentSquare[sideToMove]]) ==
            0) {
            return false;
        }
    }

    if (updateRecord) {
        snprintf(record, RECORD_LEN_MAX, "%s-%s",
                 UCI::square(currentSquare[sideToMove]).c_str(),
                 UCI::square(s).c_str());
        st.rule50++;
    }

    const Piece pc = board[currentSquare[sideToMove]];

    CLEAR_BIT(byTypeBB[ALL_PIECES], currentSquare[sideToMove]);
    CLEAR_BIT(byTypeBB[type_of(pc)], currentSquare[sideToMove]);
    CLEAR_BIT(byColorBB[color_of(pc)], currentSquare[sideToMove]);

    updateMobility(MOVETYPE_REMOVE, currentSquare[sideToMove]);

    SET_BIT(byTypeBB[ALL_PIECES], s);
    SET_BIT(byTypeBB[type_of(pc)], s);
    SET_BIT(byColorBB[color_of(pc)], s);

    updateMobility(MOVETYPE_PLACE, s);

    board[s] = pc;
    update_key(s);
    revert_key(currentSquare[sideToMove]);

    board[currentSquare[sideToMove]] = NO_PIECE;

    const int n = mills_count(s);

    if (n == 0) {
        // If no mill during Moving phase
        currentSquare[sideToMove] = SQ_NONE;
        lastMillFromSquare[sideToMove] = lastMillToSquare[sideToMove] = SQ_NONE;
        change_side_to_move();

        if (check_if_game_is_over()) {
            return true;
        }
    } else {
        // If forming mill during Moving phase
        if (rule.restrictRepeatedMillsFormation) {
            int m = potential_mills_count(currentSquare[sideToMove],
                                          sideToMove);
            if (currentSquare[sideToMove] == lastMillToSquare[sideToMove] &&
                s == lastMillFromSquare[sideToMove] && m > 0) {
                return false;
            }

            if (m > 0) {
                lastMillFromSquare[sideToMove] = currentSquare[sideToMove];
                lastMillToSquare[sideToMove] = s;
            } else {
                lastMillFromSquare[sideToMove] = SQ_NONE;
                lastMillToSquare[sideToMove] = SQ_NONE;
            }
        }

        currentSquare[sideToMove] = SQ_NONE;

        pieceToRemoveCount[sideToMove] = rule.mayRemoveMultiple ? n : 1;
        update_key_misc();
        action = Action::remove;
    }

    return true;
}

bool Position::remove_piece(Square s, bool updateRecord)
{
    if (phase == Phase::ready || phase == Phase::gameOver)
        return false;

    if (action != Action::remove)
        return false;

    if (pieceToRemoveCount[sideToMove] == 0) {
        return false;
    } else if (pieceToRemoveCount[sideToMove] > 0) {
        if (!(make_piece(~side_to_move()) & board[s])) {
            return false;
        }
    } else {
        if (!(make_piece(side_to_move()) & board[s])) {
            return false;
        }
    }

    if (is_stalemate_removal()) {
        if (is_adjacent_to(s, sideToMove) == false) {
            return false;
        }
    } else if (!rule.mayRemoveFromMillsAlways &&
               potential_mills_count(s, NOBODY) &&
               !is_all_in_mills(~sideToMove)) {
        return false;
    }

    revert_key(s);

    Piece pc = board[s];

    CLEAR_BIT(
        byTypeBB[type_of(pc)],
        s); // TODO(calcitem):
            // MillFormationActionInPlacingPhase::markAndDelayRemovingPieces
            // and placing need?
    CLEAR_BIT(byColorBB[color_of(pc)], s);

    updateMobility(MOVETYPE_REMOVE, s);

    if (rule.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase::markAndDelayRemovingPieces &&
        phase == Phase::placing) {
        // Remove and put marked
        pc = board[s] = MARKED_PIECE;
        update_key(s);
        SET_BIT(byTypeBB[type_of(pc)], s);
    } else {
        // Remove only
        CLEAR_BIT(byTypeBB[ALL_PIECES], s);
        board[s] = NO_PIECE;
    }

    if (updateRecord) {
        snprintf(record, RECORD_LEN_MAX, "x%s", UCI::square(s).c_str());
        st.rule50 = 0; // TODO(calcitem): Need to move out?
    }

    pieceOnBoardCount[them]--;

    if (pieceOnBoardCount[them] + pieceInHandCount[them] <
        rule.piecesAtLeastCount) {
        set_gameover(sideToMove, GameOverReason::loseFewerThanThree);
        return true;
    }

    currentSquare[sideToMove] = SQ_0;

    if (pieceToRemoveCount[sideToMove] > 0) {
        pieceToRemoveCount[sideToMove]--;
    } else {
        pieceToRemoveCount[sideToMove]++;
    }

    update_key_misc();

    // Need to remove rest pieces.
    if (pieceToRemoveCount[sideToMove] != 0) {
        return true;
    }

    if (handle_placing_phase_end() == false) {
        if (isStalemateRemoving) {
            isStalemateRemoving = false;
            keep_side_to_move();
        } else {
            change_side_to_move();
        }
    }

    if (pieceToRemoveCount[sideToMove] != 0) {
        return true;
    }

    if (pieceInHandCount[sideToMove] == 0) {
        if (check_if_game_is_over()) {
            return true;
        }
    }

    return true;
}

bool Position::select_piece(Square s)
{
    // Allow selecting pieces during placing phase if allowed
    if (phase != Phase::moving &&
        !(phase == Phase::placing && can_move_during_placing_phase()))
        return false;

    if (action != Action::select && action != Action::place)
        return false;

    if (board[s] & make_piece(sideToMove)) {
        currentSquare[sideToMove] = s;
        action = Action::place;

        return true;
    }

    return false;
}

bool Position::handle_placing_phase_end()
{
    if (phase != Phase::placing || pieceInHandCount[WHITE] > 0 ||
        pieceInHandCount[BLACK] > 0 ||
        ((pieceToRemoveCount[WHITE] < 0 ? -pieceToRemoveCount[WHITE] :
                                          pieceToRemoveCount[WHITE]) > 0) ||
        ((pieceToRemoveCount[BLACK] < 0 ? -pieceToRemoveCount[BLACK] :
                                          pieceToRemoveCount[BLACK]) > 0)) {
        return false;
    }

    const bool invariant =
        rule.millFormationActionInPlacingPhase ==
            MillFormationActionInPlacingPhase ::
                removeOpponentsPieceFromHandThenOpponentsTurn ||
        (rule.millFormationActionInPlacingPhase ==
             MillFormationActionInPlacingPhase ::
                 removeOpponentsPieceFromHandThenYourTurn &&
         rule.mayRemoveMultiple == true) ||
        rule.mayMoveInPlacingPhase == true;

    if (rule.millFormationActionInPlacingPhase ==
        MillFormationActionInPlacingPhase::markAndDelayRemovingPieces) {
        remove_marked_pieces();
    } else if (rule.millFormationActionInPlacingPhase ==
               MillFormationActionInPlacingPhase::removalBasedOnMillCounts) {
        calculate_removal_based_on_mill_counts();
    } else if (invariant) {
        if (rule.isDefenderMoveFirst == true) {
            set_side_to_move(BLACK);
            return true;
        } else {
            // Ignore
            return false;
        }
    }

    set_side_to_move(rule.isDefenderMoveFirst == true ? BLACK : WHITE);

    return true;
}

inline bool Position::can_move_during_placing_phase() const
{
    return rule.mayMoveInPlacingPhase;
}

bool Position::resign(Color loser)
{
    if (phase == Phase::ready || phase == Phase::gameOver ||
        phase == Phase::none) {
        return false;
    }

    set_gameover(~loser, GameOverReason::loseResign);

    snprintf(record, RECORD_LEN_MAX, LOSE_REASON_PLAYER_RESIGNS, loser);

    return true;
}

bool Position::command(const char *cmd)
{
    char moveStr[64] = {0};
    unsigned char t = 0;

    if (strlen(cmd) == 0) { /* "" */
        return reset();
    }

#ifdef _MSC_VER
    sscanf_s(cmd, "info score %d bestmove %63s", &bestvalue, moveStr,
             (unsigned)_countof(moveStr));
#else
    sscanf(cmd, "info score %d bestmove %63s", &bestvalue, moveStr);
#endif

    if (strlen(moveStr) == 0 && strlen(cmd) > 0) {
#ifdef _MSC_VER
        strncpy_s(moveStr, sizeof(moveStr), cmd, _TRUNCATE);
#else
        strncpy(moveStr, cmd, sizeof(moveStr) - 1);
        moveStr[sizeof(moveStr) - 1] = '\0';
#endif
    }

    Move m = UCI::to_move(this, moveStr);
    if (m != MOVE_NONE) {
        switch (type_of(m)) {
        case MOVETYPE_MOVE: {
            const Square from = from_sq(m);
            const Square to = to_sq(m);
            return move_piece(file_of(from), rank_of(from), file_of(to),
                              rank_of(to));
        }
        case MOVETYPE_REMOVE: {
            const Square to = to_sq(m);
            return remove_piece(file_of(to), rank_of(to));
        }
        case MOVETYPE_PLACE: {
            const Square to = to_sq(m);
            return put_piece(file_of(to), rank_of(to));
        }
        default:
            break;
        }
    }

    int args = sscanf(moveStr, "Player %hhu resigns!", &t);
    if (args == 1) {
        return resign(static_cast<Color>(t));
    }

    if (rule.threefoldRepetitionRule) {
        if (!strcmp(moveStr, DRAW_REASON_THREEFOLD_REPETITION)) {
            return true;
        }

        if (!strcmp(moveStr, "draw")) {
            set_gameover(DRAW, GameOverReason::drawThreefoldRepetition);
            // snprintf(record, RECORD_LEN_MAX,
            // DRAW_REASON_THREEFOLD_REPETITION);
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
        set_gameover(DRAW, GameOverReason::drawFiftyMove);
        return true;
    }

    if (rule.endgameNMoveRule < rule.nMoveRule && is_three_endgame() &&
        posKeyHistory.size() >= rule.endgameNMoveRule) {
        set_gameover(DRAW, GameOverReason::drawEndgameFiftyMove);
        return true;
    }
#endif // RULE_50

    // Stalemate.
    if (phase == Phase::moving && action == Action::select &&
        is_all_surrounded(sideToMove)) {
        switch (rule.stalemateAction) {
        case StalemateAction::endWithStalemateLoss:
            set_gameover(~sideToMove, GameOverReason::loseNoLegalMoves);
            return true;
        case StalemateAction::changeSideToMove:
            change_side_to_move(); // TODO(calcitem): Need?
            break;
        case StalemateAction::removeOpponentsPieceAndMakeNextMove:
            pieceToRemoveCount[sideToMove] = 1;
            isStalemateRemoving = true;
            break;
        case StalemateAction::removeOpponentsPieceAndChangeSideToMove:
            pieceToRemoveCount[sideToMove] = 1;
            break;
        case StalemateAction::endWithStalemateDraw:
            set_gameover(DRAW, GameOverReason::drawStalemateCondition);
            return true;
        }
    }

    if (pieceToRemoveCount[sideToMove] > 0 ||
        pieceToRemoveCount[sideToMove] < 0) {
        action = Action::remove;
    }

    return false;
}

int Position::calculate_mobility_diff()
{
    // TODO(calcitem): Deal with rule is no marked pieces
    int mobilityWhite = 0;
    int mobilityBlack = 0;

    for (Square s = SQ_BEGIN; s < SQ_END; ++s) {
        if (board[s] == NO_PIECE || board[s] == MARKED_PIECE) {
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

void Position::remove_marked_pieces()
{
    assert(rule.millFormationActionInPlacingPhase ==
           MillFormationActionInPlacingPhase::markAndDelayRemovingPieces);

    for (int f = 1; f <= FILE_NB; f++) {
        for (int r = 0; r < RANK_NB; r++) {
            const auto s = static_cast<Square>(f * RANK_NB + r);

            if (board[s] == MARKED_PIECE) {
                const Piece pc = board[s];
                byTypeBB[ALL_PIECES] ^= s;
                byTypeBB[type_of(pc)] ^= s;
                board[s] = NO_PIECE;
                revert_key(s);
            }
        }
    }
}

inline void Position::calculate_removal_based_on_mill_counts()
{
    int whiteMills = total_mills_count(WHITE);
    int blackMills = total_mills_count(BLACK);

    int whiteRemove = 1;
    int blackRemove = 1;

    if (whiteMills == 0 && blackMills == 0) {
        whiteRemove = -1;
        blackRemove = -1;
    } else if (whiteMills > 0 && blackMills == 0) {
        whiteRemove = 2;
        blackRemove = 1;
    } else if (blackMills > 0 && whiteMills == 0) {
        whiteRemove = 1;
        blackRemove = 2;
    } else {
        if (whiteMills == blackMills) {
            whiteRemove = whiteMills;
            blackRemove = blackMills;
        } else {
            if (whiteMills > blackMills) {
                blackRemove = blackMills;
                whiteRemove = blackRemove + 1;
            } else if (whiteMills < blackMills) {
                whiteRemove = whiteMills;
                blackRemove = whiteRemove + 1;
            } else {
                assert(false);
            }
        }
    }

    pieceToRemoveCount[WHITE] = whiteRemove;
    pieceToRemoveCount[BLACK] = blackRemove;

    // TODO: Bits count is not enough
    update_key_misc();
}

inline void Position::set_side_to_move(Color c)
{
    if (sideToMove != c) {
        sideToMove = c;
        // us = c;
        st.key ^= Zobrist::side;
    }

    them = ~sideToMove;

    // TODO: Move changing phase/action to other function
    if (pieceInHandCount[sideToMove] == 0) {
        phase = Phase::moving;
        action = Action::select;
    } else {
        phase = Phase::placing;
        action = Action::place;
    }

    if (pieceToRemoveCount[sideToMove] > 0 ||
        pieceToRemoveCount[sideToMove] < 0) {
        action = Action::remove;
    }
}

inline void Position::keep_side_to_move()
{
    set_side_to_move(sideToMove);
}

inline void Position::change_side_to_move()
{
    set_side_to_move(~sideToMove);
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
    // TODO: If pieceToRemoveCount[sideToMove]! <= 3,
    //  the top 2 bits can store its value correctly;
    //  if it is greater than 3, since only 2 bits are left,
    //  the storage will be truncated or directly get 0,
    //  and the original value cannot be completely retained.
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
    Color color = c;

    assert(SQ_0 <= from && from < SQ_END);

    if (c == NOBODY) {
        color = color_on(to);
    }

    if (from >= SQ_BEGIN && from < SQ_END) {
        locbak = board[from];
        board[from] = NO_PIECE;

        CLEAR_BIT(byTypeBB[ALL_PIECES], from);
        CLEAR_BIT(byTypeBB[type_of(locbak)], from);
        CLEAR_BIT(byColorBB[color_of(locbak)], from);
    }

    const Bitboard bc = byColorBB[color];
    const Bitboard *mt = millTableBB[to];

    if (unlikely(rule.oneTimeUseMill)) {
        Bitboard potentialMill = 0;

        for (auto i = 0; i < LD_NB; ++i) {
            potentialMill = mt[i];

            if ((bc & potentialMill) == potentialMill) {
                if (c == NOBODY) {
                    n++;
                } else {
                    Bitboard line = square_bb(to) | potentialMill;
                    if ((line & formedMillsBB[sideToMove]) != line) {
                        n++;
                    }
                }
            }
        }
    } else {
        if ((bc & mt[LD_HORIZONTAL]) == mt[LD_HORIZONTAL]) {
            n++;
        }

        if ((bc & mt[LD_VERTICAL]) == mt[LD_VERTICAL]) {
            n++;
        }

        if ((bc & mt[LD_SLASH]) == mt[LD_SLASH]) {
            n++;
        }
    }

    if (from >= SQ_BEGIN && from < SQ_END) {
        board[from] = locbak;

        SET_BIT(byTypeBB[ALL_PIECES], from);
        SET_BIT(byTypeBB[type_of(locbak)], from);
        SET_BIT(byColorBB[color_of(locbak)], from);
    }

    return n;
}

int Position::mills_count(Square s)
{
    int n = 0;
    Color side = color_on(s);

    const Bitboard bc = byColorBB[side];
    const Bitboard *mt = millTableBB[s];

    if (unlikely(rule.oneTimeUseMill)) {
        for (auto i = 0; i < LD_NB; ++i) {
            Bitboard potentialMill = mt[i];
            if ((bc & potentialMill) == potentialMill) {
                auto line = square_bb(s) | potentialMill;
                if ((line & formedMillsBB[side]) != line) {
                    formedMillsBB[side] |= line;
                    n++;
                }
            }
        }
    } else {
        for (auto i = 0; i < LD_NB; ++i) {
            if ((bc & mt[i]) == mt[i]) {
                n++;
            }
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
                                       int &theirPieceCount, int &markedCount,
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
        case MARKED_PIECE:
            markedCount++;
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

bool Position::is_all_surrounded(Color c) const
{
    // Full
    if (pieceOnBoardCount[WHITE] + pieceOnBoardCount[BLACK] >= SQUARE_NB)
        return true;

    // Can fly
    if (pieceOnBoardCount[c] <= rule.flyPieceCount && rule.mayFly) {
        return false;
    }

    Bitboard bb = byTypeBB[ALL_PIECES];

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
    if (!shouldConsiderMobility()) {
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

    for (int i = 0; i < 16; i++) {
        if (color_on(static_cast<Square>(horizontalAndVerticalLines[i][0])) ==
                c &&
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

void Position::setFormedMillsBB(uint64_t millsBitmask)
{
    Bitboard whiteMills = (millsBitmask >> 32) & 0xFFFFFFFF;
    Bitboard blackMills = millsBitmask & 0xFFFFFFFF;

    formedMillsBB[WHITE] = whiteMills;
    formedMillsBB[BLACK] = blackMills;
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

void Position::flipBoardHorizontally(vector<string> &gameMoveList,
                                     bool cmdChange /*= true*/)
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

    if (currentSquare[sideToMove] != 0) {
        f = currentSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = currentSquare[sideToMove] % static_cast<Square>(RANK_NB);
        r = (RANK_NB - r) % RANK_NB;
        currentSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    if (lastMillFromSquare[sideToMove] != 0) {
        f = lastMillFromSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = lastMillFromSquare[sideToMove] % static_cast<Square>(RANK_NB);
        r = (RANK_NB - r) % RANK_NB;
        lastMillFromSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    if (lastMillToSquare[sideToMove] != 0) {
        f = lastMillToSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = lastMillToSquare[sideToMove] % static_cast<Square>(RANK_NB);
        r = (RANK_NB - r) % RANK_NB;
        lastMillToSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    // Transform move records in standard notation for horizontal flip operation
    if (cmdChange) {
        // Helper function to transform rank (row) coordinates for horizontal
        // flip
        auto transformRank = [](char rank) -> char {
            // Horizontal flip: rank coordinates are flipped vertically
            switch (rank) {
            case '1':
                return '7';
            case '2':
                return '6';
            case '3':
                return '5';
            case '4':
                return '4';
            case '5':
                return '3';
            case '6':
                return '2';
            case '7':
                return '1';
            default:
                return rank;
            }
        };

        // Transform move notation string
        auto transformMoveString = [&](std::string &moveStr) {
            if (moveStr.length() >= 2) {
                if (moveStr[0] == 'x' && moveStr.length() >= 3) {
                    // Remove move: "xa1" -> "xa7"
                    moveStr[2] = transformRank(moveStr[2]);
                } else if (moveStr.length() == 5 && moveStr[2] == '-') {
                    // Move: "a1-a4" -> "a7-a4"
                    moveStr[1] = transformRank(moveStr[1]);
                    moveStr[4] = transformRank(moveStr[4]);
                } else if (moveStr.length() == 2) {
                    // Place move: "a1" -> "a7"
                    moveStr[1] = transformRank(moveStr[1]);
                }
            }
        };

        // Transform current record
        if (strlen(record) > 0) {
            std::string recordStr(record);
            transformMoveString(recordStr);
#ifdef _MSC_VER
            strncpy_s(record, sizeof(record), recordStr.c_str(), _TRUNCATE);
#else
            strncpy(record, recordStr.c_str(), sizeof(record) - 1);
            record[sizeof(record) - 1] = '\0';
#endif
        }

        // Transform all moves in game move list
        for (auto &iter : gameMoveList) {
            transformMoveString(iter);
        }
    }

    // as we now use standard notation exclusively
    (void)cmdChange;
    (void)gameMoveList;
}

void Position::turn(vector<string> &gameMoveList, bool cmdChange /*= true*/)
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

    if (currentSquare[sideToMove] != 0) {
        f = currentSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = currentSquare[sideToMove] % static_cast<Square>(RANK_NB);

        if (f == 1)
            f = FILE_NB;
        else if (f == FILE_NB)
            f = 1;

        currentSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    if (lastMillFromSquare[sideToMove] != 0) {
        f = lastMillFromSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = lastMillFromSquare[sideToMove] % static_cast<Square>(RANK_NB);

        if (f == 1)
            f = FILE_NB;
        else if (f == FILE_NB)
            f = 1;

        lastMillFromSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    if (lastMillToSquare[sideToMove] != 0) {
        f = lastMillToSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = lastMillToSquare[sideToMove] % static_cast<Square>(RANK_NB);
        r = (RANK_NB - r) % RANK_NB;
        lastMillToSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    // Transform move records in standard notation for turn operation
    if (cmdChange) {
        // Helper function to transform a single square in standard notation
        auto transformSquare = [](char file) -> char {
            switch (file) {
            case 'a':
                return 'g'; // file 1 <-> file 7
            case 'b':
                return 'f'; // file 2 <-> file 6
            case 'c':
                return 'e'; // file 3 <-> file 5
            case 'd':
                return 'd'; // file 4 stays same
            case 'e':
                return 'c'; // file 5 <-> file 3
            case 'f':
                return 'b'; // file 6 <-> file 2
            case 'g':
                return 'a'; // file 7 <-> file 1
            default:
                return file;
            }
        };

        // Transform move notation string
        auto transformMoveString = [&](std::string &moveStr) {
            if (moveStr.length() >= 2) {
                if (moveStr[0] == 'x' && moveStr.length() >= 3) {
                    // Remove move: "xa1" -> "xg1"
                    moveStr[1] = transformSquare(moveStr[1]);
                } else if (moveStr.length() == 5 && moveStr[2] == '-') {
                    // Move: "a1-a4" -> "g1-g4"
                    moveStr[0] = transformSquare(moveStr[0]);
                    moveStr[3] = transformSquare(moveStr[3]);
                } else if (moveStr.length() == 2) {
                    // Place move: "a1" -> "g1"
                    moveStr[0] = transformSquare(moveStr[0]);
                }
            }
        };

        // Transform current record
        if (strlen(record) > 0) {
            std::string recordStr(record);
            transformMoveString(recordStr);
#ifdef _MSC_VER
            strncpy_s(record, sizeof(record), recordStr.c_str(), _TRUNCATE);
#else
            strncpy(record, recordStr.c_str(), sizeof(record) - 1);
            record[sizeof(record) - 1] = '\0';
#endif
        }

        // Transform all moves in game move list
        for (auto &iter : gameMoveList) {
            transformMoveString(iter);
        }
    }

    // as we now use standard notation exclusively
    (void)cmdChange;
    (void)gameMoveList;
}

void Position::rotate(vector<string> &gameMoveList, int degrees,
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

    if (currentSquare[sideToMove] != 0) {
        f = currentSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = currentSquare[sideToMove] % static_cast<Square>(RANK_NB);
        r = (r + RANK_NB - degrees) % RANK_NB;
        currentSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    if (lastMillFromSquare[sideToMove] != 0) {
        f = lastMillFromSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = lastMillFromSquare[sideToMove] % static_cast<Square>(RANK_NB);
        r = (r + RANK_NB - degrees) % RANK_NB;
        lastMillFromSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    if (lastMillToSquare[sideToMove] != 0) {
        f = lastMillToSquare[sideToMove] / static_cast<Square>(RANK_NB);
        r = lastMillToSquare[sideToMove] % static_cast<Square>(RANK_NB);
        r = (r + RANK_NB - degrees) % RANK_NB;
        lastMillToSquare[sideToMove] = static_cast<Square>(f * RANK_NB + r);
    }

    // Transform move records in standard notation for rotation operation
    if (cmdChange) {
        // Helper function to transform rank coordinates for rotation
        auto transformRankForRotation = [&](char rank,
                                            int rotationDegrees) -> char {
            int r = rank - '1'; // Convert to 0-based index (0-7)

            if (rotationDegrees == 2) {
                // Rotate up by 2 positions
                r = (r + 2) % 8;
            } else if (rotationDegrees == 6) {
                // Rotate down by 2 positions
                r = (r + 6) % 8;
            } else if (rotationDegrees == 4) {
                // Rotate by 4 positions (opposite)
                r = (r + 4) % 8;
            }

            return static_cast<char>('1' + r); // Convert back to character
        };

        // Transform move notation string
        auto transformMoveString = [&](std::string &moveStr) {
            if (moveStr.length() >= 2) {
                if (moveStr[0] == 'x' && moveStr.length() >= 3) {
                    // Remove move: transform rank
                    moveStr[2] = transformRankForRotation(moveStr[2], degrees);
                } else if (moveStr.length() == 5 && moveStr[2] == '-') {
                    // Move: transform both ranks
                    moveStr[1] = transformRankForRotation(moveStr[1], degrees);
                    moveStr[4] = transformRankForRotation(moveStr[4], degrees);
                } else if (moveStr.length() == 2) {
                    // Place move: transform rank
                    moveStr[1] = transformRankForRotation(moveStr[1], degrees);
                }
            }
        };

        // Transform current record
        if (strlen(record) > 0) {
            std::string recordStr(record);
            transformMoveString(recordStr);
#ifdef _MSC_VER
            strncpy_s(record, sizeof(record), recordStr.c_str(), _TRUNCATE);
#else
            strncpy(record, recordStr.c_str(), sizeof(record) - 1);
            record[sizeof(record) - 1] = '\0';
#endif
        }

        // Transform all moves in game move list
        for (auto &iter : gameMoveList) {
            transformMoveString(iter);
        }
    }

    // as we now use standard notation exclusively
    (void)cmdChange;
    (void)gameMoveList;
}
