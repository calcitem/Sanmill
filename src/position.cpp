// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// position.cpp

#include "search_engine.h"
#include "mills.h"
#include "position.h"
#include "thread.h"
#include "evaluate.h"
#include "uci.h"
#ifdef FLUTTER_UI
#include "base.h"
#endif

// Fallback LOGD definition if not available
#ifndef LOGD
#define LOGD(...) printf(__VA_ARGS__)
#endif

#include <algorithm>
#include <array>
#include <cctype>
#include <charconv>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <string>
#include <cstdio>

using std::string;
using std::vector;

extern vector<Key> posKeyHistory;

namespace Zobrist {
constexpr int KEY_MISC_BIT = 2;
Key psq[PIECE_TYPE_NB][SQUARE_EXT_NB];
Key side;
Key custodianTarget[COLOR_NB][SQUARE_EXT_NB];
Key custodianCount[COLOR_NB][5];
Key interventionTarget[COLOR_NB][SQUARE_EXT_NB];
Key interventionCount[COLOR_NB][9];
} // namespace Zobrist

namespace {

inline Key random_zobrist_key(PRNG &rng) noexcept
{
    const Key value = rng.rand<Key>();
    // Mask away the top KEY_MISC_BIT bits so update_key_misc() retains control
    // of the misc field stored in those slots.
    return (value << Zobrist::KEY_MISC_BIT) >> Zobrist::KEY_MISC_BIT;
}

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

constexpr int kMaxCustodianRemoval = 4;
constexpr int kMaxInterventionRemoval = 8;

constexpr std::array<std::array<Square, 3>, 12> kCustodianSquareEdgeLines = {{
    {{SQ_31, SQ_24, SQ_25}},
    {{SQ_23, SQ_16, SQ_17}},
    {{SQ_15, SQ_8, SQ_9}},
    {{SQ_13, SQ_12, SQ_11}},
    {{SQ_21, SQ_20, SQ_19}},
    {{SQ_29, SQ_28, SQ_27}},
    {{SQ_31, SQ_30, SQ_29}},
    {{SQ_23, SQ_22, SQ_21}},
    {{SQ_15, SQ_14, SQ_13}},
    {{SQ_9, SQ_10, SQ_11}},
    {{SQ_17, SQ_18, SQ_19}},
    {{SQ_25, SQ_26, SQ_27}},
}};

constexpr std::array<std::array<Square, 3>, 4> kCustodianCrossLines = {{
    {{SQ_30, SQ_22, SQ_14}},
    {{SQ_10, SQ_18, SQ_26}},
    {{SQ_24, SQ_16, SQ_8}},
    {{SQ_12, SQ_20, SQ_28}},
}};

constexpr std::array<std::array<Square, 3>, 4> kCustodianDiagonalLines = {{
    {{SQ_31, SQ_23, SQ_15}},
    {{SQ_9, SQ_17, SQ_25}},
    {{SQ_29, SQ_21, SQ_13}},
    {{SQ_11, SQ_19, SQ_27}},
}};
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

    const auto fillSquares = [&](Key *row) {
        Key *ptr = row + SQ_BEGIN;
        for (int idx = 0; idx < SQUARE_NB; ++idx) {
            ptr[idx] = random_zobrist_key(rng);
        }
    };

    const auto fillCounts = [&](Key *row, int maxCount) {
        for (int idx = 0; idx <= maxCount; ++idx) {
            row[idx] = random_zobrist_key(rng);
        }
    };

    for (const PieceType pt : PieceTypes) {
        fillSquares(Zobrist::psq[pt]);
    }

    for (int c = WHITE; c <= BLACK; ++c) {
        const Color color = static_cast<Color>(c);
        fillSquares(Zobrist::custodianTarget[color]);
        fillSquares(Zobrist::interventionTarget[color]);
        fillCounts(Zobrist::custodianCount[color], kMaxCustodianRemoval);
        fillCounts(Zobrist::interventionCount[color], kMaxInterventionRemoval);
    }

    Zobrist::side = random_zobrist_key(rng);
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

    // Note: Removal state will be properly initialized when
    // custodian/intervention data is parsed later in the FEN loading process

    // 6. Mills bitmask
    uint64_t mb = 0;
    ss >> std::skipws >> mb;
    setFormedMillsBB(mb);

    // 7-8. Halfmove clock and fullmove number
    ss >> std::skipws >> st.rule50 >> gamePly;

    // Convert from fullmove starting from 1 to gamePly starting from 0,
    // handle also common incorrect FEN with fullmove = 0.
    gamePly = std::max(2 * (gamePly - 1), 0) + (sideToMove == BLACK);

    std::array<Bitboard, COLOR_NB> custodianTargetsParsed {};
    custodianTargetsParsed.fill(0);
    std::array<int, COLOR_NB> custodianCountsParsed {};
    custodianCountsParsed.fill(0);
    std::array<bool, COLOR_NB> custodianHasColor {};
    custodianHasColor.fill(false);

    std::array<Bitboard, COLOR_NB> interventionTargetsParsed {};
    interventionTargetsParsed.fill(0);
    std::array<int, COLOR_NB> interventionCountsParsed {};
    interventionCountsParsed.fill(0);
    std::array<bool, COLOR_NB> interventionHasColor {};
    interventionHasColor.fill(false);

    std::array<Bitboard, COLOR_NB> millTargetsParsed {};
    millTargetsParsed.fill(0);
    std::array<int, COLOR_NB> millCountsParsed {};
    millCountsParsed.fill(0);
    std::array<bool, COLOR_NB> millHasColor {};
    millHasColor.fill(false);

    const auto trim = [](const std::string &input) -> std::string {
        size_t first = 0;
        size_t last = input.size();

        while (first < last &&
               std::isspace(static_cast<unsigned char>(input[first]))) {
            ++first;
        }

        while (last > first &&
               std::isspace(static_cast<unsigned char>(input[last - 1]))) {
            --last;
        }

        return input.substr(first, last - first);
    };

    const auto parseInt = [](const std::string &text, int &out) -> bool {
        if (text.empty()) {
            return false;
        }

        int sign = 1;
        size_t idx = 0;

        if (text[idx] == '-') {
            sign = -1;
            ++idx;
        }

        if (idx == text.size()) {
            return false;
        }

        int value = 0;

        for (; idx < text.size(); ++idx) {
            const unsigned char ch = static_cast<unsigned char>(text[idx]);

            if (ch < '0' || ch > '9') {
                return false;
            }

            value = value * 10 + (ch - '0');
        }

        out = sign * value;

        return true;
    };

    const auto parseCaptureField = [&](const std::string &field,
                                       std::array<Bitboard, COLOR_NB> &targets,
                                       std::array<int, COLOR_NB> &counts,
                                       std::array<bool, COLOR_NB> &hasColor) {
        std::stringstream segmentStream(field);
        std::string segment;

        while (std::getline(segmentStream, segment, '|')) {
            segment = trim(segment);

            if (segment.empty()) {
                continue;
            }

            if (segment.size() < 3 || segment[1] != '-') {
                continue;
            }

            const char colorChar = segment[0];
            const Color color = colorChar == 'w' ? WHITE :
                                colorChar == 'b' ? BLACK :
                                                   NOBODY;

            if (color != WHITE && color != BLACK) {
                continue;
            }

            const size_t secondDash = segment.find('-', 2);

            if (secondDash == std::string::npos) {
                continue;
            }

            const std::string countStr = trim(
                segment.substr(2, secondDash - 2));
            int parsedCount = 0;

            if (!parseInt(countStr, parsedCount)) {
                continue;
            }

            Bitboard targetsMask = 0;
            const std::string listStr = segment.substr(secondDash + 1);
            size_t pos = 0;

            while (pos < listStr.size()) {
                const size_t next = listStr.find('.', pos);
                const std::string squareToken = trim(
                    listStr.substr(pos, next - pos));

                if (!squareToken.empty()) {
                    int squareValue = 0;

                    if (parseInt(squareToken, squareValue) &&
                        squareValue >= SQ_BEGIN && squareValue < SQ_END) {
                        targetsMask |= square_bb(
                            static_cast<Square>(squareValue));
                    }
                }

                if (next == std::string::npos) {
                    break;
                }

                pos = next + 1;
            }

            const size_t idx = static_cast<size_t>(color);
            targets[idx] = targetsMask;
            counts[idx] = parsedCount;
            hasColor[idx] = true;
        }
    };

    std::string trailing;
    ss >> std::ws;
    std::getline(ss, trailing);

    if (!trailing.empty()) {
        std::stringstream extraStream(trailing);
        std::string extraToken;

        while (extraStream >> extraToken) {
            if (extraToken.size() < 2 || extraToken[1] != ':') {
                continue;
            }

            const std::string value = extraToken.substr(2);

            if (extraToken[0] == 'c') {
                parseCaptureField(value, custodianTargetsParsed,
                                  custodianCountsParsed, custodianHasColor);
            } else if (extraToken[0] == 'i') {
                parseCaptureField(value, interventionTargetsParsed,
                                  interventionCountsParsed,
                                  interventionHasColor);
            } else if (extraToken[0] == 'm') {
                parseCaptureField(value, millTargetsParsed, millCountsParsed,
                                  millHasColor);
            }
        }
    }

    for (int c = WHITE; c <= BLACK; ++c) {
        const auto color = static_cast<Color>(c);
        const size_t idx = static_cast<size_t>(color);

        if (custodianHasColor[idx]) {
            setCustodianCaptureState(color, custodianTargetsParsed[idx],
                                     custodianCountsParsed[idx]);
        } else {
            setCustodianCaptureState(color, 0, 0);
        }

        if (interventionHasColor[idx]) {
            setInterventionCaptureState(color, interventionTargetsParsed[idx],
                                        interventionCountsParsed[idx]);
        } else {
            setInterventionCaptureState(color, 0, 0);
        }

        // Initialize removal state based on actual capture data, not
        // assumptions
        if (action == Action::remove && pieceToRemoveCount[color] > 0) {
            const int custodianCount = custodianHasColor[idx] ?
                                           custodianCountsParsed[idx] :
                                           0;
            const int interventionCount = interventionHasColor[idx] ?
                                              interventionCountsParsed[idx] :
                                              0;

            int millRemovals = 0;
            if (millHasColor[idx]) {
                millRemovals = millCountsParsed[idx];
            } else {
                // Fallback for FEN strings without explicit mill counts
                const int totalCaptureRemovals = std::max(custodianCount, 0) +
                                                 std::max(interventionCount, 0);
                millRemovals = std::max(0, pieceToRemoveCount[color] -
                                               totalCaptureRemovals);
            }

            LOGD("FEN loading: Initializing removal state for color %d: "
                 "mill=%d, custodian=%d, intervention=%d (total "
                 "pieceToRemoveCount=%d)\n",
                 color, millRemovals, custodianCount, interventionCount,
                 pieceToRemoveCount[color]);

            initializeRemovalState(color, millRemovals, custodianCount,
                                   interventionCount);
        }
    }

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

    const auto appendCaptureField = [&](char label, const Bitboard *targets,
                                        const int *counts) {
        const bool hasData = counts[WHITE] > 0 || counts[BLACK] > 0 ||
                             targets[WHITE] != 0 || targets[BLACK] != 0;

        if (!hasData) {
            return;
        }

        ss << ' ' << label << ':';

        const auto appendColor = [&](Color color, char prefix) {
            const int idx = static_cast<int>(color);
            ss << prefix << '-' << counts[idx] << '-';

            bool first = true;
            const Bitboard colorTargets = targets[idx];

            for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
                if (!(colorTargets & square_bb(sq))) {
                    continue;
                }

                if (!first) {
                    ss << '.';
                }

                ss << static_cast<int>(sq);
                first = false;
            }
        };

        appendColor(WHITE, 'w');
        ss << '|';
        appendColor(BLACK, 'b');
    };

    appendCaptureField('c', custodianCaptureTargets, custodianRemovalCount);
    appendCaptureField('i', interventionCaptureTargets,
                       interventionRemovalCount);

    const std::array<Bitboard, COLOR_NB> emptyTargets {};
    appendCaptureField('m', emptyTargets.data(), pendingMillRemovals);

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

    if (phase == Phase::moving && type_of(m) != MOVETYPE_REMOVE) {
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

    for (int c = WHITE; c <= BLACK; ++c) {
        const Color color = static_cast<Color>(c);
        custodianCaptureTargets[color] = 0;
        custodianRemovalCount[color] = 0;
        interventionCaptureTargets[color] = 0;
        interventionRemovalCount[color] = 0;
        pendingMillRemovals[color] = 0;
        removalQuota[color] = 0;
        removalsPerformed[color] = 0;
        activeCaptureMode[color] = ActiveCaptureMode::none;
        interventionForcedPartner[color] = SQ_NONE;
        clearInterventionPairMap(color);
    }

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
    const bool custodianEnabled = rule.custodianCapture.enabled;
    const bool interventionEnabled = rule.interventionCapture.enabled;

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
        std::vector<Square> custodianCaptured;
        const bool hasCustodianCapture = custodianEnabled &&
                                         checkCustodianCapture(
                                             s, us, custodianCaptured);
        std::vector<Square> interventionCaptured;
        const bool hasInterventionCapture = interventionEnabled &&
                                            checkInterventionCapture(
                                                s, us, interventionCaptured);

        if (n == 0) {
            // If no Mill

            if (pieceToRemoveCount[WHITE] != 0 ||
                pieceToRemoveCount[BLACK] != 0) {
                assert(false);
                return false;
            }

            lastMillFromSquare[sideToMove] = SQ_NONE;
            lastMillToSquare[sideToMove] = SQ_NONE;

            int custodianRemoval = 0;
            if (hasCustodianCapture) {
                custodianRemoval = activateCustodianCapture(us,
                                                            custodianCaptured);
            } else if (custodianCaptureTargets[us] ||
                       custodianRemovalCount[us] != 0) {
                setCustodianCaptureState(us, 0, 0);
            }

            int interventionRemoval = 0;
            if (hasInterventionCapture) {
                interventionRemoval = activateInterventionCapture(
                    us, s, interventionCaptured);
            } else if (interventionCaptureTargets[us] ||
                       interventionRemovalCount[us] != 0) {
                setInterventionCaptureState(us, 0, 0);
            }

            const int totalCaptureRemoval = std::max(custodianRemoval, 0) +
                                            std::max(interventionRemoval, 0);

            initializeRemovalState(us, 0, custodianRemoval,
                                   interventionRemoval);
            // Don't return here - need to check placing phase end logic

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

            // If we have custodian capture to handle, return early
            if (totalCaptureRemoval > 0 && pieceToRemoveCount[sideToMove] > 0) {
                return true;
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

            LOGD("Mill formed in placing phase: n=%d, millFormationAction=%d\n",
                 n, static_cast<int>(rule.millFormationActionInPlacingPhase));

            if (rule.millFormationActionInPlacingPhase ==
                MillFormationActionInPlacingPhase::removalBasedOnMillCounts) {
                // Allow immediate special capture; mill removal count calculated at phase end
                int custodianRemoval = 0;
                if (hasCustodianCapture) {
                    custodianRemoval = activateCustodianCapture(us, custodianCaptured);
                }
                
                int interventionRemoval = 0;
                if (hasInterventionCapture) {
                    interventionRemoval = activateInterventionCapture(us, s, interventionCaptured);
                }
                
                if (custodianRemoval > 0 || interventionRemoval > 0) {
                    initializeRemovalState(us, /*mill=*/0, custodianRemoval, interventionRemoval);
                    return true;
                }
                
                // Otherwise follow original logic (involving hand piece counts etc.)
                initializeRemovalState(us, 0, 0, 0);
                setCustodianCaptureState(us, 0, 0);
                setInterventionCaptureState(us, 0, 0);
            } else if (rule.millFormationActionInPlacingPhase ==
                       MillFormationActionInPlacingPhase::
                           markAndDelayRemovingPieces) {
                // For markAndDelayRemovingPieces, try special captures first
                int custodianRemoval = 0;
                if (hasCustodianCapture) {
                    custodianRemoval = activateCustodianCapture(us, custodianCaptured);
                }
                
                int interventionRemoval = 0;
                if (hasInterventionCapture) {
                    interventionRemoval = activateInterventionCapture(us, s, interventionCaptured);
                }
                
                if (custodianRemoval > 0 || interventionRemoval > 0) {
                    initializeRemovalState(us, /*mill=*/0, custodianRemoval, interventionRemoval);
                    return true;  // Execute special capture; mill marking handled at phase end
                }
                
                // For markAndDelayRemovingPieces mode, mills allow immediate removal
                // but mill pieces are marked and processed at phase end
                rm = rule.mayRemoveMultiple ? n : 1;
                LOGD("Mill formed with markAndDelayRemovingPieces - allowing immediate removal of %d pieces\n", rm);
                
                // Store the mill removal count for phase end processing
                pendingMillRemovals[us] += rm;
            } else {
                rm = rule.mayRemoveMultiple ? n : 1;
                LOGD("Mill removal count rm=%d\n", rm);
            }

            if (rule.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase::
                        removeOpponentsPieceFromHandThenYourTurn ||
                rule.millFormationActionInPlacingPhase ==
                    MillFormationActionInPlacingPhase::
                        removeOpponentsPieceFromHandThenOpponentsTurn) {
                setCustodianCaptureState(us, 0, 0);
                setInterventionCaptureState(us, 0, 0);

                pieceToRemoveCount[sideToMove] = rm;

                for (int i = 0; i < rm; i++) {
                    if (pieceInHandCount[them] == 0) {
                        const int remainingRemovals = rm - i;
                        // Use initializeRemovalState to set the removal state
                        // consistently, ensuring that pendingMillRemovals,
                        // removalQuota, and action are consistent.
                        initializeRemovalState(us, remainingRemovals, 0, 0);
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
                    setCustodianCaptureState(us, 0, 0);
                    setInterventionCaptureState(us, 0, 0);

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
                    // For markAndDelayRemovingPieces, we still need to set up removal state
                    // so AI understands that mill formation leads to piece removal
                    if (rule.millFormationActionInPlacingPhase ==
                        MillFormationActionInPlacingPhase::markAndDelayRemovingPieces) {
                        // Set up normal removal state for mill formation
                        LOGD("Mill placing phase (markAndDelayRemovingPieces): calling "
                             "initializeRemovalState(us=%d, rm=%d)\n", us, rm);
                        initializeRemovalState(us, rm, 0, 0);
                    } else {
                        int custodianRemoval = 0;
                        if (hasCustodianCapture) {
                            custodianRemoval = activateCustodianCapture(
                                us, custodianCaptured);
                            if (custodianRemoval <= 0 &&
                                (custodianCaptureTargets[us] ||
                                 custodianRemovalCount[us] != 0)) {
                                setCustodianCaptureState(us, 0, 0);
                            }
                        } else if (custodianCaptureTargets[us] ||
                                   custodianRemovalCount[us] != 0) {
                            setCustodianCaptureState(us, 0, 0);
                        }

                        int interventionRemoval = 0;
                        if (hasInterventionCapture) {
                            interventionRemoval = activateInterventionCapture(
                                us, s, interventionCaptured);
                            if (interventionRemoval <= 0 &&
                                (interventionCaptureTargets[us] ||
                                 interventionRemovalCount[us] != 0)) {
                                setInterventionCaptureState(us, 0, 0);
                            }
                        } else if (interventionCaptureTargets[us] ||
                                   interventionRemovalCount[us] != 0) {
                            setInterventionCaptureState(us, 0, 0);
                        }

                        LOGD("Mill placing phase: calling "
                             "initializeRemovalState(us=%d, rm=%d, custodian=%d, "
                             "intervention=%d)\n",
                             us, rm, custodianRemoval, interventionRemoval);
                        initializeRemovalState(us, rm, custodianRemoval,
                                               interventionRemoval);
                    }
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

    const bool custodianEnabled = rule.custodianCapture.enabled;
    const bool interventionEnabled = rule.interventionCapture.enabled;

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
    std::vector<Square> custodianCaptured;
    const bool hasCustodianCapture = custodianEnabled &&
                                     checkCustodianCapture(s, sideToMove,
                                                           custodianCaptured);
    std::vector<Square> interventionCaptured;
    const bool hasInterventionCapture = interventionEnabled &&
                                        checkInterventionCapture(
                                            s, sideToMove,
                                            interventionCaptured);

    if (n == 0) {
        // If no mill during Moving phase
        currentSquare[sideToMove] = SQ_NONE;
        lastMillFromSquare[sideToMove] = lastMillToSquare[sideToMove] = SQ_NONE;

        int custodianRemoval = 0;
        if (hasCustodianCapture) {
            custodianRemoval = activateCustodianCapture(sideToMove,
                                                        custodianCaptured);
        } else if (custodianCaptureTargets[sideToMove] ||
                   custodianRemovalCount[sideToMove] != 0) {
            setCustodianCaptureState(sideToMove, 0, 0);
        }

        int interventionRemoval = 0;
        if (hasInterventionCapture) {
            interventionRemoval = activateInterventionCapture(
                sideToMove, s, interventionCaptured);
        } else if (interventionCaptureTargets[sideToMove] ||
                   interventionRemovalCount[sideToMove] != 0) {
            setInterventionCaptureState(sideToMove, 0, 0);
        }

        initializeRemovalState(sideToMove, 0, custodianRemoval,
                               interventionRemoval);

        if (removalQuota[sideToMove] > 0) {
            return true;
        }

        if (custodianCaptureTargets[sideToMove] ||
            custodianRemovalCount[sideToMove] != 0) {
            setCustodianCaptureState(sideToMove, 0, 0);
        }
        if (interventionCaptureTargets[sideToMove] ||
            interventionRemovalCount[sideToMove] != 0) {
            setInterventionCaptureState(sideToMove, 0, 0);
        }
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

        const int baseRemoval = rule.mayRemoveMultiple ? n : 1;

        int custodianRemoval = 0;
        if (hasCustodianCapture) {
            custodianRemoval = activateCustodianCapture(sideToMove,
                                                        custodianCaptured);
            if (custodianRemoval <= 0 &&
                (custodianCaptureTargets[sideToMove] ||
                 custodianRemovalCount[sideToMove] != 0)) {
                setCustodianCaptureState(sideToMove, 0, 0);
            }
        } else if (custodianCaptureTargets[sideToMove] ||
                   custodianRemovalCount[sideToMove] != 0) {
            setCustodianCaptureState(sideToMove, 0, 0);
        }

        int interventionRemoval = 0;
        if (hasInterventionCapture) {
            interventionRemoval = activateInterventionCapture(
                sideToMove, s, interventionCaptured);
            if (interventionRemoval <= 0 &&
                (interventionCaptureTargets[sideToMove] ||
                 interventionRemovalCount[sideToMove] != 0)) {
                setInterventionCaptureState(sideToMove, 0, 0);
            }
        } else if (interventionCaptureTargets[sideToMove] ||
                   interventionRemovalCount[sideToMove] != 0) {
            setInterventionCaptureState(sideToMove, 0, 0);
        }

        initializeRemovalState(sideToMove, baseRemoval, custodianRemoval,
                               interventionRemoval);
    }

    return true;
}

bool Position::remove_piece(Square s, bool updateRecord)
{
    if (phase == Phase::ready || phase == Phase::gameOver)
        return false;

    if (action != Action::remove)
        return false;

    const Bitboard mask = square_bb(s);
    Bitboard &custodianTargets = custodianCaptureTargets[sideToMove];
    int &custodianCount = custodianRemovalCount[sideToMove];
    Bitboard &interventionTargets = interventionCaptureTargets[sideToMove];
    int &interventionCount = interventionRemovalCount[sideToMove];

    ActiveCaptureMode &mode = activeCaptureMode[sideToMove];
    int &performed = removalsPerformed[sideToMove];
    int &quota = removalQuota[sideToMove];
    const int pendingMill = pendingMillRemovals[sideToMove];
    Square &forcedPartner = interventionForcedPartner[sideToMove];

    bool isCaptureTarget = false;

    const auto clearCustodianStateIfNeeded = [&]() {
        if (custodianTargets || custodianCount != 0) {
            setCustodianCaptureState(sideToMove, 0, 0);
        }
    };

    const auto clearInterventionStateIfNeeded = [&]() {
        if (interventionTargets || interventionCount != 0) {
            setInterventionCaptureState(sideToMove, 0, 0);
        }
    };

    if (pieceToRemoveCount[sideToMove] == 0) {
        return false;
    } else if (pieceToRemoveCount[sideToMove] > 0) {
        if (!(make_piece(~side_to_move()) & board[s])) {
            return false;
        }

        const bool isCustodianTarget = (custodianTargets & mask) != 0;
        const bool isInterventionTarget = (interventionTargets & mask) != 0;
        isCaptureTarget = isCustodianTarget || isInterventionTarget;

        if (mode == ActiveCaptureMode::none) {
            if (isInterventionTarget && interventionCount > 0) {
                mode = ActiveCaptureMode::intervention;
                quota = std::max(interventionCount, 2);
                pendingMillRemovals[sideToMove] = 0;
                clearCustodianStateIfNeeded();
                forcedPartner = SQ_NONE;
            } else if (isCustodianTarget && custodianCount > 0) {
                mode = ActiveCaptureMode::custodian;
                quota = custodianCount;                        // Only custodian quota
                pendingMillRemovals[sideToMove] = 0;          // Clear mill when choosing custodian
                clearInterventionStateIfNeeded();
                forcedPartner = SQ_NONE;
            } else {
                if (pendingMill > 0) {
                    mode = ActiveCaptureMode::mill;
                    quota = pendingMill;
                } else {
                    const int remaining = pieceToRemoveCount[sideToMove];
                    quota = std::max(quota, remaining);
                }
                clearCustodianStateIfNeeded();
                clearInterventionStateIfNeeded();
                forcedPartner = SQ_NONE;
            }

            removalQuota[sideToMove] = quota;
            performed = 0;
            pieceToRemoveCount[sideToMove] = std::max(0, quota - performed);
        } else {
            switch (mode) {
            case ActiveCaptureMode::custodian:
                if (custodianCount > 0) {
                    if (!isCustodianTarget) {
                        return false;
                    }
                } else {
                    // Custodian exhausted, no switching to other capture modes allowed
                    return false;
                }
                break;
            case ActiveCaptureMode::intervention:
                if (!isInterventionTarget) {
                    return false;
                }
                break;
            case ActiveCaptureMode::mill:
                if (isCaptureTarget) {
                    return false;
                }
                if (pendingMill <= performed) {
                    return false;
                }
                break;
            case ActiveCaptureMode::none:
                break;
            }
        }

        if (mode == ActiveCaptureMode::intervention) {
            if (performed == 0) {
                const Square partner = interventionPairMate[sideToMove][s];
                if (partner == SQ_NONE) {
                    return false;
                }
                forcedPartner = partner;
                setInterventionCaptureState(sideToMove, square_bb(partner), 1);
                quota = std::max(quota, 2);
                pieceToRemoveCount[sideToMove] = std::max(0, quota - performed);
            } else {
                if (forcedPartner != s) {
                    return false;
                }
                forcedPartner = SQ_NONE;
            }
        } else if (mode == ActiveCaptureMode::custodian && performed == 0) {
            quota = custodianCount;  // Only custodian quota, no mill mixing
            removalQuota[sideToMove] = quota;
            pieceToRemoveCount[sideToMove] = std::max(0, quota - performed);
        }

        if (isCustodianTarget && custodianCount > 0) {
            Bitboard newTargets = custodianTargets & ~mask;
            const int newCount = custodianCount - 1;

            if (newCount <= 0) {
                newTargets = 0;
            }

            setCustodianCaptureState(sideToMove, newTargets, newCount);
        }

        if (!(mode == ActiveCaptureMode::intervention && performed == 0) &&
            isInterventionTarget && interventionCount > 0) {
            Bitboard newTargets = interventionTargets & ~mask;
            const int newCount = interventionCount - 1;

            if (newCount <= 0) {
                newTargets = 0;
            }

            setInterventionCaptureState(sideToMove, newTargets, newCount);
        }
    } else {
        if (!(make_piece(side_to_move()) & board[s])) {
            return false;
        }

        clearCustodianStateIfNeeded();
        clearInterventionStateIfNeeded();
    }

    const bool specialCaptureActive = isCaptureTarget &&
                                      (mode == ActiveCaptureMode::custodian ||
                                       mode == ActiveCaptureMode::intervention);

    if (is_stalemate_removal()) {
        if (!specialCaptureActive && is_adjacent_to(s, sideToMove) == false) {
            return false;
        }
    } else if (!specialCaptureActive && !rule.mayRemoveFromMillsAlways &&
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
        performed++;
        pieceToRemoveCount[sideToMove] = std::max(0, quota - performed);
    } else {
        pieceToRemoveCount[sideToMove]++;
    }

    update_key_misc();

    // Need to remove rest pieces.
    if (pieceToRemoveCount[sideToMove] != 0) {
        return true;
    }

    clearCustodianStateIfNeeded();
    clearInterventionStateIfNeeded();
    removalQuota[sideToMove] = 0;
    pendingMillRemovals[sideToMove] = 0;
    performed = 0;
    mode = ActiveCaptureMode::none;
    forcedPartner = SQ_NONE;

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

    // Check game over conditions immediately after phase transition,
    // specifically stalemate This ensures stalemate conditions are properly
    // handled before the engine attempts to generate moves
    check_if_game_is_over();
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

void Position::setCustodianCaptureState(Color color, Bitboard targets,
                                        int count)
{
    if (color != WHITE && color != BLACK) {
        return;
    }

    const Bitboard previousTargets = custodianCaptureTargets[color];
    const int previousCount = custodianRemovalCount[color];

    const int clampedPrev = std::clamp(previousCount, 0, kMaxCustodianRemoval);
    const int clampedNew = std::clamp(count, 0, kMaxCustodianRemoval);

    if (clampedPrev != clampedNew) {
        st.key ^= Zobrist::custodianCount[color][clampedPrev];
        st.key ^= Zobrist::custodianCount[color][clampedNew];
    }

    if (previousTargets != targets) {
        for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
            const Bitboard mask = square_bb(sq);

            if (previousTargets & mask) {
                st.key ^= Zobrist::custodianTarget[color][sq];
            }

            if (targets & mask) {
                st.key ^= Zobrist::custodianTarget[color][sq];
            }
        }
    }

    custodianCaptureTargets[color] = targets;
    custodianRemovalCount[color] = count;
}

void Position::clearInterventionPairMap(Color color)
{
    if (color != WHITE && color != BLACK) {
        return;
    }

    for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
        interventionPairMate[color][sq] = SQ_NONE;
    }
}

void Position::initializeRemovalState(Color color, int millRemovals,
                                      int custodianRemovals,
                                      int interventionRemovals)
{
    if (color != WHITE && color != BLACK) {
        return;
    }

    pendingMillRemovals[color] = std::max(millRemovals, 0);
    removalsPerformed[color] = 0;
    removalQuota[color] = 0;
    activeCaptureMode[color] = ActiveCaptureMode::none;
    interventionForcedPartner[color] = SQ_NONE;

    const int totalAllowed = std::max({pendingMillRemovals[color],
                                       std::max(custodianRemovals, 0),
                                       std::max(interventionRemovals, 0)});

    removalQuota[color] = totalAllowed;

    if (totalAllowed > 0) {
        pieceToRemoveCount[color] = totalAllowed;
        update_key_misc();
        action = Action::remove;
        LOGD("initializeRemovalState: color=%d, totalAllowed=%d, "
             "action=remove, pendingMill=%d (mill=%d,cust=%d,inter=%d)\n",
             color, totalAllowed, pendingMillRemovals[color], millRemovals,
             custodianRemovals, interventionRemovals);
    } else {
        pieceToRemoveCount[color] = 0;
        LOGD("initializeRemovalState: color=%d, totalAllowed=0, no removal "
             "needed (mill=%d,cust=%d,inter=%d)\n",
             color, millRemovals, custodianRemovals, interventionRemovals);
    }
}

void Position::setInterventionCaptureState(Color color, Bitboard targets,
                                           int count)
{
    if (color != WHITE && color != BLACK) {
        return;
    }

    const Bitboard previousTargets = interventionCaptureTargets[color];
    const int previousCount = interventionRemovalCount[color];

    const int clampedPrev = std::clamp(previousCount, 0,
                                       kMaxInterventionRemoval);
    const int clampedNew = std::clamp(count, 0, kMaxInterventionRemoval);

    if (clampedPrev != clampedNew) {
        st.key ^= Zobrist::interventionCount[color][clampedPrev];
        st.key ^= Zobrist::interventionCount[color][clampedNew];
    }

    if (previousTargets != targets) {
        for (Square sq = SQ_BEGIN; sq < SQ_END; ++sq) {
            const Bitboard mask = square_bb(sq);

            if (previousTargets & mask) {
                st.key ^= Zobrist::interventionTarget[color][sq];
            }

            if (targets & mask) {
                st.key ^= Zobrist::interventionTarget[color][sq];
            }
        }
    }

    interventionCaptureTargets[color] = targets;
    interventionRemovalCount[color] = count;

    if (targets == 0 || count <= 0) {
        clearInterventionPairMap(color);
        interventionForcedPartner[color] = SQ_NONE;
    }
}

int Position::activateCustodianCapture(
    Color color, const std::vector<Square> &capturedPieces)
{
    if (capturedPieces.empty()) {
        setCustodianCaptureState(color, 0, 0);
        return 0;
    }

    Bitboard targets = 0;

    for (Square target : capturedPieces) {
        targets |= square_bb(target);
    }

    const int allowedRemovals = rule.mayRemoveMultiple ?
                                    static_cast<int>(capturedPieces.size()) :
                                    1;

    setCustodianCaptureState(color, targets, allowedRemovals);

    return allowedRemovals;
}

int Position::activateInterventionCapture(
    Color color, Square center, const std::vector<Square> &capturedPieces)
{
    if (capturedPieces.empty()) {
        clearInterventionPairMap(color);
        setInterventionCaptureState(color, 0, 0);
        return 0;
    }

    std::vector<std::array<Square, 2>> capturePairs;
    capturePairs.reserve(4);

    const auto processLine = [&](const std::array<Square, 3> &line) {
        if (center != line[1]) {
            return;
        }

        const Square first = line[0];
        const Square second = line[2];

        if (board[first] != NO_PIECE && color_of(board[first]) == ~color &&
            board[second] != NO_PIECE && color_of(board[second]) == ~color) {
            capturePairs.push_back({first, second});
        }
    };

    clearInterventionPairMap(color);
    interventionForcedPartner[color] = SQ_NONE;

    if (rule.interventionCapture.onSquareEdges) {
        for (const auto &line : kCustodianSquareEdgeLines) {
            processLine(line);
        }
    }

    if (rule.interventionCapture.onCrossLines) {
        for (const auto &line : kCustodianCrossLines) {
            processLine(line);
        }
    }

    if (rule.hasDiagonalLines && rule.interventionCapture.onDiagonalLines) {
        for (const auto &line : kCustodianDiagonalLines) {
            processLine(line);
        }
    }

    if (capturePairs.empty()) {
        setInterventionCaptureState(color, 0, 0);
        return 0;
    }

    Bitboard targets = 0;

    for (const auto &pair : capturePairs) {
        targets |= square_bb(pair[0]);
        targets |= square_bb(pair[1]);
        interventionPairMate[color][pair[0]] = pair[1];
        interventionPairMate[color][pair[1]] = pair[0];
    }

    // Only one line of intervention capture can be selected per move.
    const int allowedRemovals = 2;

    setInterventionCaptureState(color, targets, allowedRemovals);

    return allowedRemovals;
}

bool Position::checkCustodianCapture(Square sq, Color us,
                                     std::vector<Square> &capturedPieces) const
{
    capturedPieces.clear();

    if (!rule.custodianCapture.enabled) {
        return false;
    }

    if ((phase == Phase::placing && !rule.custodianCapture.inPlacingPhase) ||
        (phase == Phase::moving && !rule.custodianCapture.inMovingPhase) ||
        (phase != Phase::placing && phase != Phase::moving)) {
        return false;
    }

    // Check piece count condition: only in moving phase and based on remaining
    // pieces
    if (rule.custodianCapture.onlyAvailableWhenOwnPiecesLeq3) {
        // This condition only applies in moving phase
        if (phase == Phase::moving) {
            const int usPieces = pieceOnBoardCount[us];
            const int themPieces = pieceOnBoardCount[~us];

            // If both sides have <= 3 pieces, both can use custodian capture
            // If only one side has <= 3 pieces, only that side can use it
            // If neither side has <= 3 pieces, neither can use it
            if (usPieces > 3 && themPieces > 3) {
                // Neither side qualifies
                return false;
            } else if (usPieces > 3 && themPieces <= 3) {
                // Only opponent qualifies, current player cannot use
                return false;
            }
            // If us <= 3, we can use it (regardless of opponent's count)
        }
        // In placing phase, piece count condition doesn't apply
    }

    const auto processLine = [&](const std::array<Square, 3> &line,
                                 Bitboard &accumulated) {
        if (sq == line[0]) {
            Square middle = line[1];
            Square far_sq = line[2];

            if (board[middle] != NO_PIECE && color_of(board[middle]) == ~us &&
                board[far_sq] != NO_PIECE && color_of(board[far_sq]) == us) {
                accumulated |= square_bb(middle);
            }
        } else if (sq == line[2]) {
            Square middle = line[1];
            Square far_sq = line[0];

            if (board[middle] != NO_PIECE && color_of(board[middle]) == ~us &&
                board[far_sq] != NO_PIECE && color_of(board[far_sq]) == us) {
                accumulated |= square_bb(middle);
            }
        }
    };

    Bitboard captured = 0;

    if (rule.custodianCapture.onSquareEdges) {
        for (const auto &line : kCustodianSquareEdgeLines) {
            processLine(line, captured);
        }
    }

    if (rule.custodianCapture.onCrossLines) {
        for (const auto &line : kCustodianCrossLines) {
            processLine(line, captured);
        }
    }

    if (rule.hasDiagonalLines && rule.custodianCapture.onDiagonalLines) {
        for (const auto &line : kCustodianDiagonalLines) {
            processLine(line, captured);
        }
    }

    if (!captured) {
        return false;
    }

    Bitboard validTargets = 0;

    for (Square target = SQ_BEGIN; target < SQ_END; ++target) {
        const Bitboard mask = square_bb(target);

        if (!(captured & mask)) {
            continue;
        }

        if (board[target] == NO_PIECE || color_of(board[target]) != ~us) {
            continue;
        }

        if (!rule.mayRemoveFromMillsAlways &&
            const_cast<Position *>(this)->potential_mills_count(target,
                                                                NOBODY) &&
            !const_cast<Position *>(this)->is_all_in_mills(~us)) {
            continue;
        }

        validTargets |= mask;
    }

    if (!validTargets) {
        return false;
    }

    for (Square target = SQ_BEGIN; target < SQ_END; ++target) {
        if (validTargets & square_bb(target)) {
            capturedPieces.push_back(target);
        }
    }

    return !capturedPieces.empty();
}

bool Position::checkInterventionCapture(
    Square sq, Color us, std::vector<Square> &capturedPieces) const
{
    capturedPieces.clear();

    if (!rule.interventionCapture.enabled) {
        return false;
    }

    if ((phase == Phase::placing && !rule.interventionCapture.inPlacingPhase) ||
        (phase == Phase::moving && !rule.interventionCapture.inMovingPhase) ||
        (phase != Phase::placing && phase != Phase::moving)) {
        return false;
    }

    if (rule.interventionCapture.onlyAvailableWhenOwnPiecesLeq3) {
        if (phase == Phase::moving) {
            const int usPieces = pieceOnBoardCount[us];
            const int themPieces = pieceOnBoardCount[~us];

            if (usPieces > 3 && themPieces > 3) {
                return false;
            } else if (usPieces > 3 && themPieces <= 3) {
                return false;
            }
        }
    }

    const auto processLine = [&](const std::array<Square, 3> &line,
                                 Bitboard &accumulated) {
        if (sq != line[1]) {
            return;
        }

        const Square first = line[0];
        const Square second = line[2];

        if (board[first] != NO_PIECE && color_of(board[first]) == ~us &&
            board[second] != NO_PIECE && color_of(board[second]) == ~us) {
            accumulated |= square_bb(first);
            accumulated |= square_bb(second);
        }
    };

    Bitboard captured = 0;

    if (rule.interventionCapture.onSquareEdges) {
        for (const auto &line : kCustodianSquareEdgeLines) {
            processLine(line, captured);
        }
    }

    if (rule.interventionCapture.onCrossLines) {
        for (const auto &line : kCustodianCrossLines) {
            processLine(line, captured);
        }
    }

    if (rule.hasDiagonalLines && rule.interventionCapture.onDiagonalLines) {
        for (const auto &line : kCustodianDiagonalLines) {
            processLine(line, captured);
        }
    }

    if (!captured) {
        return false;
    }

    Bitboard validTargets = 0;

    for (Square target = SQ_BEGIN; target < SQ_END; ++target) {
        const Bitboard mask = square_bb(target);

        if (!(captured & mask)) {
            continue;
        }

        if (board[target] == NO_PIECE || color_of(board[target]) != ~us) {
            continue;
        }

        if (!rule.mayRemoveFromMillsAlways &&
            const_cast<Position *>(this)->potential_mills_count(target,
                                                                NOBODY) &&
            !const_cast<Position *>(this)->is_all_in_mills(~us)) {
            continue;
        }

        validTargets |= mask;
    }

    if (!validTargets) {
        return false;
    }

    for (Square target = SQ_BEGIN; target < SQ_END; ++target) {
        if (validTargets & square_bb(target)) {
            capturedPieces.push_back(target);
        }
    }

    return !capturedPieces.empty();
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
    assert(s >= SQ_BEGIN && s < SQ_END);
    for (MoveDirection d = MD_BEGIN; d < MD_NB; ++d) {
        const Square moveSquare = MoveList<LEGAL>::adjacentSquares[s][d];

        if (!moveSquare) {
            continue;
        }

        assert(moveSquare >= SQ_BEGIN && moveSquare < SQ_END);

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
            int rankIndex = rank - '1'; // Convert to 0-based index (0-7)

            if (rotationDegrees == 2) {
                // Rotate up by 2 positions
                rankIndex = (rankIndex + 2) % 8;
            } else if (rotationDegrees == 6) {
                // Rotate down by 2 positions
                rankIndex = (rankIndex + 6) % 8;
            } else if (rotationDegrees == 4) {
                // Rotate by 4 positions (opposite)
                rankIndex = (rankIndex + 4) % 8;
            }

            return static_cast<char>('1' + rankIndex); // Convert back to
                                                       // character
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
