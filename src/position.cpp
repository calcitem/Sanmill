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

string tips;

namespace Zobrist
{
#ifdef TRANSPOSITION_TABLE_CUTDOWN
const Key psq[PIECE_TYPE_NB][SQUARE_NB] = {
{
0x4E421A, 0x3962FF, 0x6DB6EE, 0x219AE1,
0x1F3DE2, 0xD9AACB, 0xD51733, 0xD3F9EA,
0xF5A7BB, 0xDC4109, 0xEE4319, 0x7CDA7A,
0xFD7B4D, 0x4138BE, 0xCCBB2D, 0xDA6097,
0x06D827, 0xCBC16C, 0x46F125, 0xE29F22,
0xCAAB94, 0x5B02DB, 0x877CD6, 0x35E438,
0x49FDAE, 0xE68314, 0xBE1664, 0x1F49D3,
0x50F5B1, 0x149AAF, 0xF509B9, 0x47AEB5,
0x18E993, 0x76BB4F, 0xFE1739, 0xF87B87,
0x0A8CD2, 0x630C6B, 0x88F5B4, 0x0A583E,
},
{
0xA0128E, 0x6F2251, 0x51E99D, 0x6D35BF,
0x66D6D9, 0x87D366, 0x75A57A, 0x534FC4,
0x1FE34B, 0xAD6FB0, 0xE5679D, 0xF88AFF,
0x0462DA, 0x4BDE96, 0xF28912, 0x10537E,
0x26D8EA, 0x37E6E7, 0x0871D9, 0xCD5F4F,
0xF4AFA1, 0x44A51B, 0x772656, 0x8B7965,
0xD8F17D, 0x80F3D7, 0x6B6206, 0x19B8BB,
0xFBC229, 0x0FCAB4, 0xFD7374, 0xA647B9,
0x296A8D, 0xA3D742, 0x624D6D, 0x459FD4,
0xCE8C26, 0x965448, 0x410171, 0x1EDD7A,
},
{
0x1FCF95, 0xA5634E, 0x21976A, 0x32902D,
0x55A27C, 0x49EC5F, 0x0176A1, 0xCAAAEF,
0x145886, 0xB4C808, 0x0153EE, 0x7D78DF,
0xE9C3C5, 0x66B7A6, 0x3CD930, 0xDBBA23,
0xF19841, 0x6BEFDF, 0xB979FE, 0xBA4D06,
0x96AECF, 0x33B96E, 0x76A99C, 0x1B8762,
0x747B20, 0x0DEC24, 0xA4E632, 0xBA2442,
0x59C91B, 0x41482D, 0xF2CD39, 0x30E9C1,
0x6B156D, 0xC7F191, 0x012D36, 0xC66B36,
0x631560, 0xA891FC, 0xF6C8AC, 0xD80B94,
},
{
0xF641E9, 0xF164BF, 0x2DBE4C, 0xE2A40C,
0x53FA06, 0x4F3117, 0x0ACA70, 0x2C72F5,
0xC81047, 0x4B76AE, 0xEB55C8, 0x0DB6EF,
0x7F57AB, 0x22D060, 0x390554, 0xDE9A43,
0x6583AF, 0x41D141, 0x9CBF92, 0x7E528F,
0x2BEFA1, 0x5C5FDC, 0x4DDAFA, 0x7C98A1,
0x65A13B, 0x2953BF, 0x8769A8, 0xE6DCA1,
0xD01A6E, 0xBCD935, 0x175659, 0xAD5A73,
0xB04E7D, 0x815F53, 0x12469A, 0xB2F25C,
0x564E4B, 0xD19437, 0xA4F63C, 0x7169E5,
},
};
#else
const Key psq[PIECE_TYPE_NB][SQUARE_NB] = {
{
0x618A9CF24E421A, 0xBA7A364A3962FF, 0xA4306AD06DB6EE, 0xBD592807219AE1,
0x83E4F70B1F3DE2, 0x5153D8FCD9AACB, 0x4A996847D51733, 0x2719CCC6D3F9EA,
0x7AE39BDEF5A7BB, 0xBCD7D5DEDC4109, 0x5B14285CEE4319, 0x9F721DD87CDA7A,
0x5D9ACD64FD7B4D, 0x620F60444138BE, 0x9725301DCCBB2D, 0x9275D47FDA6097,
0xF5EC163506D827, 0xDBF647FACBC16C, 0xB520224946F125, 0xB2889032E29F22,
0x964C65F0CAAB94, 0x461170C85B02DB, 0xA886E3A7877CD6, 0x26F1B8EF35E438,
0xF5B97EF849FDAE, 0xEE7C5D59E68314, 0x32648EFABE1664, 0x6189EDE91F49D3,
0x93CBB24B50F5B1, 0xF0F6C79D149AAF, 0x3A993B39F509B9, 0x1E5308DE47AEB5,
0x2600EE1A18E993, 0x390B489E76BB4F, 0x6F3B9027FE1739, 0x095BADF5F87B87,
0x8BEE19670A8CD2, 0x6CF81326630C6B, 0xADE52B7888F5B4, 0x8D3F6C790A583E,
},
{
0xCB53C13BA0128E, 0x3F72BC2E6F2251, 0xB42ED55551E99D, 0x4984708B6D35BF,
0x9543165266D6D9, 0xAAD0136987D366, 0x97D1867575A57A, 0xB207C471534FC4,
0xD2303A381FE34B, 0x93490C78AD6FB0, 0x87113B18E5679D, 0x54391F89F88AFF,
0xB6DEDA460462DA, 0x5185B8464BDE96, 0x51C69A99F28912, 0x46774A0A10537E,
0xE006203726D8EA, 0xA5474E6237E6E7, 0x39AC6AA70871D9, 0x3DEE0C9FCD5F4F,
0xF818EB3AF4AFA1, 0x8F3A441844A51B, 0x8A25D496772656, 0xCE06B0CA8B7965,
0x626F5F46D8F17D, 0x944977DB80F3D7, 0x7A227AA66B6206, 0x4DCC135019B8BB,
0x711EC2C8FBC229, 0xE7BB68800FCAB4, 0xD3955CDAFD7374, 0xE7534419A647B9,
0x9FDCA93E296A8D, 0xFDB2801DA3D742, 0xE3C38E0C624D6D, 0x4D69B7E2459FD4,
0x5A3A714CCE8C26, 0x05D969D4965448, 0x34FFB957410171, 0x9B1A08811EDD7A,
},
{
0xC6F613271FCF95, 0xCD947ECFA5634E, 0x8DB775C121976A, 0xD8E8477932902D,
0x1CAD3B5655A27C, 0x8AC13C7C49EC5F, 0xBA076D030176A1, 0xAC96DC58CAAAEF,
0xFEEFB931145886, 0x0E5CCD93B4C808, 0x9BDB4F0C0153EE, 0xAEB4F8927D78DF,
0x621E3A9EE9C3C5, 0xDE5AA56E66B7A6, 0x030E97EE3CD930, 0xE9A79619DBBA23,
0x77B25AEAF19841, 0xB8E4263C6BEFDF, 0xCE932447B979FE, 0xFFEE0A6DBA4D06,
0x241CFD8796AECF, 0xFE8A5B9C33B96E, 0xD47296D976A99C, 0x7AB3259A1B8762,
0x7977FD45747B20, 0x84C2C36A0DEC24, 0x12CF8CDEA4E632, 0xC02BE51BBA2442,
0xBD78281F59C91B, 0x5058264241482D, 0xA79BA355F2CD39, 0x3274B36F30E9C1,
0x751C8B5D6B156D, 0xB7C8814FC7F191, 0x11E74CCF012D36, 0xF58E3A35C66B36,
0xF92812B1631560, 0x6E98FEA1A891FC, 0x3A00752DF6C8AC, 0xDE4AC1B9D80B94,
},
{
0x1382738DF641E9, 0xF698FD60F164BF, 0xC1E4F6772DBE4C, 0x80AD23BCE2A40C,
0x22AD6ADB53FA06, 0xFB5D2D614F3117, 0x1DDDDF550ACA70, 0x962A4AD92C72F5,
0x46EB4A0AC81047, 0x140BB5664B76AE, 0xF5088729EB55C8, 0x148E44E10DB6EF,
0x1623D3EB7F57AB, 0x6E826D9722D060, 0x49C27320390554, 0x0C35E2C5DE9A43,
0x594468826583AF, 0xE190283B41D141, 0xEA3D0B0A9CBF92, 0x36BDEA707E528F,
0x4FE884872BEFA1, 0xE70A0AB95C5FDC, 0xA8EE1E864DDAFA, 0xDD58D6957C98A1,
0xFD678C8865A13B, 0xFF15F6332953BF, 0xDCE23A318769A8, 0xDF4C292EE6DCA1,
0xFD34EA18D01A6E, 0xFA1300F7BCD935, 0xAAC5CC68175659, 0xE0C64BA5AD5A73,
0x5ECF7987B04E7D, 0xAB38FFE6815F53, 0x94EA1A1812469A, 0x20EDFF94B2F25C,
0x0B2D4606564E4B, 0x83381E3CD19437, 0xD3DB04A0A4F63C, 0x789C60EF7169E5,
},
};
#endif // TRANSPOSITION_TABLE_CUTDOWN
}

#ifdef ONLY_USED_FOR_CONVERT
int main(void)
{
    for (int i = 0; i < 40; i++) {
        printf("{");
        for (int j = 0; j < 3; j++) {
            printf("0x%08X, ", (uint32_t)arr[i][j]);
        }
        printf("0x%08X},\n", (uint32_t)arr[i][3]);
    }

    return 0;
}
#endif


/// operator<<(Position) returns an ASCII representation of the position

#if 0
std::ostream &operator<<(std::ostream &os, const Position &pos)
{
    os << "\n +---+---+---+---+---+---+---+---+\n";

    for (Rank r = RANK_8; r >= RANK_1; --r) {
        for (File f = FILE_A; f <= FILE_C; ++f)
            os << " | " << PieceToChar[pos.piece_on(make_square(f, r))];

        os << " |\n +---+---+---+---+---+---+---+---+\n";
    }

    os << "\nFen: " << pos.fen() << "\nKey: " << std::hex << std::uppercase
        << std::setfill('0') << std::setw(16) << pos.key()
        << std::setfill(' ') << std::dec << "\nCheckers: ";

    if (int(Tablebases::MaxCardinality) >= popcount(pos.pieces())
        ) {
        StateInfo st;
        Position p;
        p.set(pos.fen(), &st, pos.this_thread());
        Tablebases::ProbeState s1, s2;
        Tablebases::WDLScore wdl = Tablebases::probe_wdl(p, &s1);
        int dtz = Tablebases::probe_dtz(p, &s2);
        os << "\nTablebases WDL: " << std::setw(4) << wdl << " (" << s1 << ")"
            << "\nTablebases DTZ: " << std::setw(4) << dtz << " (" << s2 << ")";
    }

    return os;
}
#endif

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

void Position::init()
{
    return;
}

Position::Position()
{
    construct_key();

    set_position(&RULES[DEFAULT_RULE_NUMBER]);

    score[BLACK] = score[WHITE] = score_draw = nPlayed = 0;

    //tips.reserve(1024);
    cmdlist.reserve(256);

#ifdef PREFETCH_SUPPORT
    prefetch_range(millTable, sizeof(millTable));
#endif
}

Position::~Position()
{
    cmdlist.clear();
}

/// Position::set() initializes the position object with the given FEN string.
/// This function is not very robust - make sure that input FENs are correct,
/// this is assumed to be the responsibility of the GUI.

Position &Position::set(const string &fenStr, StateInfo *si, Thread *th)
{
    // TODO
#if 0
    /*
       A FEN string defines a particular position using only the ASCII character set.

       A FEN string contains six fields separated by a space. The fields are:

       1) Piece placement (from white's perspective). Each rank is described, starting
          with rank 8 and ending with rank 1. Within each rank, the contents of each
          square are described from file A through file H. Following the Standard
          Algebraic Notation (SAN), each piece is identified by a single letter taken
          from the standard English names. White pieces are designated using upper-case
          letters ("PNBRQK") whilst Black uses lowercase ("pnbrqk"). Blank squares are
          noted using digits 1 through 8 (the number of blank squares), and "/"
          separates ranks.

       2) Active color. "w" means white moves next, "b" means black.

       4) En passant target square (in algebraic notation). If there's no en passant
          target square, this is "-". If a pawn has just made a 2-square move, this
          is the position "behind" the pawn. This is recorded only if there is a pawn
          in position to make an en passant capture, and if there really is a pawn
          that might have advanced two squares.

       5) Halfmove clock. This is the number of halfmoves since the last pawn advance
          or capture. This is used to determine if a draw can be claimed under the
          fifty-move rule.

       6) Fullmove number. The number of the full move. It starts at 1, and is
          incremented after Black's move.
    */

    unsigned char token;
    size_t idx;
    Square sq = SQ_A8;
    std::istringstream ss(fenStr);

    std::memset(this, 0, sizeof(Position));
    std::memset(si, 0, sizeof(StateInfo));
    std::fill_n(&pieceList[0][0], sizeof(pieceList) / sizeof(Square), SQ_NONE);
    st = si;

    ss >> std::noskipws;

    // 1. Piece placement
    while ((ss >> token) && !isspace(token)) {
        if (isdigit(token))
            sq += (token - '0') * EAST; // Advance the given number of files

        else if (token == '/')
            sq += 2 * SOUTH;

        else if ((idx = PieceToChar.find(token)) != string::npos) {
            put_piece(Piece(idx), sq);
            ++sq;
        }
    }

    // 2. Active color
    ss >> token;
    sideToMove = (token == 'w' ? WHITE : BLACK);
    ss >> token;

    // 5-6. Halfmove clock and fullmove number
    ss >> std::skipws >> st->rule50 >> gamePly;

    // Convert from fullmove starting from 1 to gamePly starting from 0,
    // handle also common incorrect FEN with fullmove = 0.
    gamePly = std::max(2 * (gamePly - 1), 0) + (sideToMove == BLACK);

    thisThread = th;
    set_state(st);

    assert(pos_is_ok());
#endif
    th = th;
    si = si;
    string str = fenStr;
    str = "";
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


/// Position::set() is an overload to initialize the position object with
/// the given endgame code string like "KBPKN". It is mainly a helper to
/// get the material key out of an endgame code.

Position &Position::set(const string &code, Color c, StateInfo *si)
{
    // TODO
#if 0
    assert(code[0] == 'K');

    string sides[] = { code.substr(code.find('K', 1)),      // Weak
                       code.substr(0, std::min(code.find('v'), code.find('K', 1))) }; // Strong

    assert(sides[0].length() > 0 && sides[0].length() < 8);
    assert(sides[1].length() > 0 && sides[1].length() < 8);

    std::transform(sides[c].begin(), sides[c].end(), sides[c].begin(), tolower);

    string fenStr = "8/" + sides[0] + char(8 - sides[0].length() + '0') + "/8/8/8/8/"
        + sides[1] + char(8 - sides[1].length() + '0') + "/8 w - - 0 10";

    return set(fenStr, si, nullptr);
#endif
    si = si;
    c = c;
    string ccc = code;
    ccc = "";
    return *this;
}

/// Position::fen() returns a FEN representation of the position. In case of
/// Chess960 the Shredder-FEN notation is used. This is mainly a debugging function.

const string Position::fen() const
{
    // TODO
#if 0
    int emptyCnt;
    std::ostringstream ss;

    for (Rank r = RANK_8; r >= RANK_1; --r) {
        for (File f = FILE_A; f <= FILE_C; ++f) {
            for (emptyCnt = 0; f <= FILE_C && empty(make_square(f, r)); ++f)
                ++emptyCnt;

            if (emptyCnt)
                ss << emptyCnt;

            if (f <= FILE_C)
                ss << PieceToChar[piece_on(make_square(f, r))];
        }

        if (r > RANK_1)
            ss << '/';
    }

    ss << (sideToMove == WHITE ? " w " : " b ");

    ss << (" - ")
        << st->rule50 << " " << 1 + (gamePly - (sideToMove == BLACK)) / 2;

    return ss.str();
#endif
    return "";
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

bool Position::set_position(const struct Rule *newRule)
{
    rule = *newRule;

    this->currentStep = 0;
    this->moveStep = 0;

    phase = PHASE_READY;
    set_side_to_move(BLACK);
    action = ACTION_PLACE;

    memset(board, 0, sizeof(board));
    st.key = 0;
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
    set_tips();
    cmdlist.clear();

    int r;
    for (r = 0; r < N_RULES; r++) {
        if (strcmp(rule.name, RULES[r].name) == 0)
            break;
    }

    if (sprintf(cmdline, "r%1u s%03u t%02u", r + 1, rule.maxStepsLedToDraw, rule.maxTimeLedToLose) > 0) {
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    cmdline[0] = '\0';
    return false;
}

bool Position::reset()
{
    if (phase == PHASE_READY &&
        elapsedSeconds[BLACK] == elapsedSeconds[WHITE] == 0) {
        return true;
    }

    currentStep = 0;
    moveStep = 0;

    phase = PHASE_READY;
    set_side_to_move(BLACK);
    action = ACTION_PLACE;

    winner = NOBODY;

    memset(board, 0, sizeof(board));
    st.key = 0;
    memset(byTypeBB, 0, sizeof(byTypeBB));

    pieceCountOnBoard[BLACK] = pieceCountOnBoard[WHITE] = 0;
    pieceCountInHand[BLACK] = pieceCountInHand[WHITE] = rule.nTotalPiecesEachSide;
    pieceCountNeedRemove = 0;
    millListSize = 0;
    currentSquare = SQ_0;
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;
    set_tips();
    cmdlist.clear();

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
                i + 1, rule.maxStepsLedToDraw, rule.maxTimeLedToLose) > 0) {
        cmdlist.emplace_back(string(cmdline));
        return true;
    }

    cmdline[0] = '\0';

    return false;
}

bool Position::start()
{
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
    File file;
    Rank rank;
    int i;
    int seconds = -1;

    Piece piece = NO_PIECE;
    int n = 0;

    int us = sideToMove;

    Bitboard fromTo;

    if (phase == PHASE_GAMEOVER)
        return false;

    if (phase == PHASE_READY)
        start();

    if (action != ACTION_PLACE)
        return false;

    if (!onBoard[s]|| board[s])
        return false;

    Position::square_to_polar(s, file, rank);

    if (phase == PHASE_PLACING) {
        piece = (Piece)((0x01 | (sideToMove << PLAYER_SHIFT)) + rule.nTotalPiecesEachSide - pieceCountInHand[us]);
        pieceCountInHand[us]--;
        pieceCountOnBoard[us]++;

        board[s]= piece;

        update_key(s);

        byTypeBB[ALL_PIECES] |= s;
        byTypeBB[us] |= s;

        move = static_cast<Move>(s);

        if (updateCmdlist) {
            seconds = update();
            sprintf(cmdline, "(%1u,%1u) %02u:%02u",
                    file, rank, seconds / 60, seconds % 60);
            cmdlist.emplace_back(string(cmdline));
            currentStep++;
        }

        currentSquare = s;

        n = add_mills(currentSquare);

        if (n == 0) {
            assert(pieceCountInHand[BLACK] >= 0 && pieceCountInHand[WHITE] >= 0);     

            if (pieceCountInHand[BLACK] == 0 && pieceCountInHand[WHITE] == 0) {
                if (check_gameover_condition(updateCmdlist)) {
                    goto out;
                }

                phase = PHASE_MOVING;
                action = ACTION_SELECT;
                clean_banned();

                if (rule.isDefenderMoveFirst) {
                    set_side_to_move(WHITE);
                } else {
                    set_side_to_move(BLACK);
                }

                if (check_gameover_condition(updateCmdlist)) {
                    goto out;
                }
            } else {
                change_side_to_move();
            }
        } else {
            pieceCountNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
            action = ACTION_REMOVE;
        }

        goto out;
    }

    if (check_gameover_condition(updateCmdlist)) {
        goto out;
    }

    // When hase == GAME_MOVING

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

    move = make_move(currentSquare, s);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u) %02u:%02u", currentSquare / RANK_NB, currentSquare % RANK_NB + 1,
                file, rank, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep++;
    }

    fromTo = square_bb(currentSquare) | square_bb(s);
    byTypeBB[ALL_PIECES] ^= fromTo;
    byTypeBB[us] ^= fromTo;

    board[s]= board[currentSquare];

    update_key(s);
    revert_key(currentSquare);

    board[currentSquare] = NO_PIECE;

    currentSquare = s;
    n = add_mills(currentSquare);

    // midgame
    if (n == 0) {
        action = ACTION_SELECT;
        change_side_to_move();

        if (check_gameover_condition(updateCmdlist)) {
            goto out;
        }
    } else {
        pieceCountNeedRemove = rule.allowRemoveMultiPiecesWhenCloseMultiMill ? n : 1;
        action = ACTION_REMOVE;
    }

out:
    if (updateCmdlist) {
        set_tips();
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

    File file;
    Rank rank;
    Position::square_to_polar(s, file, rank);

    int seconds = -1;

    int oppId = them;

    // if piece is not their
    if (!((them << PLAYER_SHIFT) & board[s]))
        return false;

    if (!rule.allowRemovePieceInMill &&
        in_how_many_mills(s, NOBODY) &&
        !is_all_in_mills(~sideToMove)) {
        return false;
    }

    if (rule.hasBannedLocations && phase == PHASE_PLACING) {
        revert_key(s);
        board[s]= BAN_STONE;
        update_key(s);

        byTypeBB[oppId] ^= s;
        byTypeBB[BAN] |= s;
    } else { // Remove
        revert_key(s);
        board[s]= NO_PIECE;

        byTypeBB[ALL_PIECES] ^= s;
        byTypeBB[them] ^= s;
    }

    pieceCountOnBoard[them]--;

    move = static_cast<Move>(-s);

    if (updateCmdlist) {
        seconds = update();
        sprintf(cmdline, "-(%1u,%1u)  %02u:%02u", file, rank, seconds / 60, seconds % 60);
        cmdlist.emplace_back(string(cmdline));
        currentStep++;
        moveStep = 0;
    }

    currentSquare = SQ_0;
    pieceCountNeedRemove--;

    // Remove piece completed

    if (check_gameover_condition(updateCmdlist)) {
        goto out;
    }

    if (pieceCountNeedRemove > 0) {
        return true;
    }

    if (phase == PHASE_PLACING) {
        if (pieceCountInHand[BLACK] == 0 && pieceCountInHand[WHITE] == 0) {

            phase = PHASE_MOVING;
            action = ACTION_SELECT;
            clean_banned();

            if (rule.isDefenderMoveFirst) {
                set_side_to_move(WHITE);
            } else {
                set_side_to_move(BLACK);
            }

            if (check_gameover_condition(updateCmdlist)) {
                goto out;
            }
        } else {
            action = ACTION_PLACE;
            change_side_to_move();

            if (check_gameover_condition(updateCmdlist)) {
                goto out;
            }
        }
    } else {
        action = ACTION_SELECT;
        change_side_to_move();

        if (check_gameover_condition(updateCmdlist)) {
            goto out;
        }
    }

out:
    if (updateCmdlist) {
        set_tips();
    }

    return true;
}

bool Position::select_piece(Square s)
{
    if (phase != PHASE_MOVING)
        return false;

    if (action != ACTION_SELECT && action != ACTION_PLACE)
        return false;

    if (board[s]& (sideToMove << PLAYER_SHIFT)) {
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

    Color loserColor = loser;
    char loserCh = color_to_char(loserColor);
    string loserStr = char_to_string(loserCh);

    winner = ~loser;
    tips = "玩家" + loserStr + "投子认负";
    sprintf(cmdline, "Player%d give up!", loserColor);
    score[winner]++;

    cmdlist.emplace_back(string(cmdline));

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
    int mm = 0, ss = 0;

    if (sscanf(cmd, "r%1u s%3hd t%2u", &ruleIndex, &step, &t) == 3) {
        if (ruleIndex <= 0 || ruleIndex > N_RULES) {
            return false;
        }

        return set_position(&RULES[ruleIndex - 1]);
    }

    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &file1, &rank1, &file2, &rank2, &mm, &ss);

    if (args >= 4) {
        if (args == 7) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }

        if (select_piece(file1, rank1)) {
            return put_piece(file2, rank2);
        }

        return false;
    }

    args = sscanf(cmd, "-(%1u,%1u) %2u:%2u", &file1, &rank1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
        return remove_piece(file1, rank1);
    }

    args = sscanf(cmd, "(%1u,%1u) %2u:%2u", &file1, &rank1, &mm, &ss);
    if (args >= 2) {
        if (args == 5) {
            if (mm >= 0 && ss >= 0)
                tm = mm * 60 + ss;
        }
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
        tips = "三次重复局面判和。";
        sprintf(cmdline, "Threefold Repetition. Draw!");
        cmdlist.emplace_back(string(cmdline));
        return true;
    }
#endif /* THREEFOLD_REPETITION */

    return false;
}

bool Position::do_move(Move m)
{
    MoveType mt = type_of(m);

    switch (mt) {
    case MOVETYPE_REMOVE:
        return remove_piece(static_cast<Square>(-m));
    case MOVETYPE_MOVE:
        return move_piece(from_sq(m), to_sq(m));
    case MOVETYPE_PLACE:
        return put_piece(to_sq(m));
    default:
        break;
    }

    return false;
}

/// Position::undo_move() unmakes a move. When it returns, the position should
/// be restored to exactly the same state as before the move was made.

bool Position::undo_move(Move m)
{
    bool ret = false;

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

    return ret;
}

void Position::undo_move(Stack<Position> &ss)
{
    memcpy(this, ss.top(), sizeof(Position));
    ss.pop();
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

    if (rule.maxTimeLedToLose > 0) {
        check_gameover_condition();
    }

    return ret;
}

bool Position::check_gameover_condition(int8_t updateCmdlist)
{
    if (phase & PHASE_NOTPLAYING) {
        return true;
    }

    if (rule.maxTimeLedToLose > 0) {
        phase = PHASE_GAMEOVER;

        if (updateCmdlist) {
            for (int i = 1; i <= 2; i++) {
                if (elapsedSeconds[i] > rule.maxTimeLedToLose * 60) {
                    elapsedSeconds[i] = rule.maxTimeLedToLose * 60;
                    winner = ~Color(i);
                    tips = "玩家" + char_to_string(color_to_char(Color(i))) + "超时判负。";
                    sprintf(cmdline, "Time over. Player%d win!", ~Color(i));
                }
            }

            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    if (rule.maxStepsLedToDraw > 0 &&
        moveStep > rule.maxStepsLedToDraw) {
        winner = DRAW;
        phase = PHASE_GAMEOVER;
        if (updateCmdlist) {
            sprintf(cmdline, "Steps over. In draw!");
            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    for (int i = 1; i <= 2; i++)
    {
        if (pieceCountOnBoard[i] + pieceCountInHand[i] < rule.nPiecesAtLeast) {
            winner = ~Color(i);
            phase = PHASE_GAMEOVER;

            if (updateCmdlist) {
                sprintf(cmdline, "Player%d win!", winner);
                cmdlist.emplace_back(string(cmdline));
            }

            return true;
        }
    }

#ifdef MCTS_AI
#if 0
    int diff = pieceCountOnBoard[BLACK] - pieceCountOnBoard[WHITE];
    if (diff > 4) {
        winner = BLACK;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player1 win!");
        cmdlist.emplace_back(string(cmdline));

        return true;
    }

    if (diff < -4) {
        winner = WHITE;
        phase = PHASE_GAMEOVER;
        sprintf(cmdline, "Player2 win!");
        cmdlist.emplace_back(string(cmdline));

        return true;
    }
#endif
#endif

    if (pieceCountOnBoard[BLACK] + pieceCountOnBoard[WHITE] >= RANK_NB * FILE_NB) {
        phase = PHASE_GAMEOVER;

        if (rule.isBlackLosebutNotDrawWhenBoardFull) {
            winner = WHITE;
            if (updateCmdlist) {
                sprintf(cmdline, "Player2 win!");
            }
        } else {
            winner = DRAW; 
            if (updateCmdlist) {
                sprintf(cmdline, "Full. In draw!");
            }
        }

        if (updateCmdlist) {
            cmdlist.emplace_back(string(cmdline));
        }

        return true;
    }

    if (phase == PHASE_MOVING && action == ACTION_SELECT && is_all_surrounded()) {
        // TODO: move to next branch
        phase = PHASE_GAMEOVER;

        if (rule.isLoseButNotChangeTurnWhenNoWay) {
            if (updateCmdlist) {
                tips = "玩家" + char_to_string(color_to_char(sideToMove)) + "无子可走被闷";
                winner = ~sideToMove;
                sprintf(cmdline, "Player%d no way to go. Player%d win!", sideToMove, winner);
                cmdlist.emplace_back(string(cmdline));  // TODO: memleak
            }

            return true;
        }

        change_side_to_move();

        return false;
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

void Position::clean_banned()
{
    if (!rule.hasBannedLocations) {
        return;
    }

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

void Position::set_side_to_move(Color c)
{
    sideToMove = c;
    them = ~sideToMove;
}

void Position::change_side_to_move()
{
    set_side_to_move(~sideToMove);
}

bool Position::do_null_move()
{
    change_side_to_move();
    return true;
}

bool Position::undo_null_move()
{
    change_side_to_move();
    return true;
}

void Position::set_tips()
{
    string winnerStr, t;
    string turnStr = char_to_string(color_to_char(sideToMove));

    switch (phase) {
    case PHASE_READY:
        tips = "轮到玩家1落子，剩余" + std::to_string(pieceCountInHand[BLACK]) + "子" +
            "  比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);
        break;

    case PHASE_PLACING:
        if (action == ACTION_PLACE) {
            tips = "轮到玩家" + turnStr + "落子，剩余" + std::to_string(pieceCountInHand[sideToMove]) + "子";
        } else if (action == ACTION_REMOVE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(pieceCountNeedRemove) + "子";
        }
        break;

    case PHASE_MOVING:
        if (action == ACTION_PLACE || action == ACTION_SELECT) {
            tips = "轮到玩家" + turnStr + "选子移动";
        } else if (action == ACTION_REMOVE) {
            tips = "成三！轮到玩家" + turnStr + "去子，需去" + std::to_string(pieceCountNeedRemove) + "子";
        }
        break;

    case PHASE_GAMEOVER:  
        if (winner == DRAW) {
            score_draw++;
            tips = "双方平局！比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);
            break;
        }

        winnerStr = char_to_string(color_to_char(winner));

        score[winner]++;

        t = "玩家" + winnerStr + "获胜！比分 " + to_string(score[BLACK]) + ":" + to_string(score[WHITE]) + ", 和棋 " + to_string(score_draw);

        if (tips.find("无子可走") != string::npos) {
            tips += t;
        } else {
            tips = t;
        }

        break;

    default:
        break;
    }
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
    //int pieceType = loc == 0x0f? 3 : loc >> PLAYER_SHIFT;

    st.key ^= Zobrist::psq[pieceType][s];

    return st.key;
}

inline Key Position::revert_key(Square s)
{
    return update_key(s);
}

Key Position::update_key_misc()
{
    const int KEY_MISC_BIT = 8;

    st.key = st.key << KEY_MISC_BIT >> KEY_MISC_BIT;
    Key hi = 0;

    if (sideToMove == WHITE) {
        hi |= 1U;
    }

    if (action == ACTION_REMOVE) {
        hi |= 1U << 1;
    }

    hi |= static_cast<Key>(pieceCountNeedRemove) << 2;
    hi |= static_cast<Key>(pieceCountInHand[BLACK]) << 4;     // TODO: may use phase is also OK?

    st.key = st.key | (hi << (CHAR_BIT * sizeof(Key) - KEY_MISC_BIT));

    return st.key;
}

Key Position::next_primary_key(Move m)
{
    Key npKey = st.key /* << 8 >> 8 */;
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

void Position::square_to_polar(const Square s, File &file, Rank &rank)
{
    //r = s / RANK_NB;
    //s = s % RANK_NB + 1;
    file = File(s >> 3);
    rank = Rank((s & 0x07) + 1);
}

Square Position::polar_to_square(File file, Rank rank)
{
    assert(!(file < 1 || file > FILE_NB || rank < 1 || rank > RANK_NB));

    return static_cast<Square>(file * RANK_NB + rank - 1);
}

Color Position::color_on(Square s)
{
    return Color((board[s] & 0x30) >> PLAYER_SHIFT);
}

int Position::in_how_many_mills(Square s, Color c, Square squareSelected)
{
    int n = 0;
    Piece locbak = NO_PIECE;

    if (c == NOBODY) {
        c = Color(color_on(s) >> PLAYER_SHIFT);
    }

    if (squareSelected != SQ_0) {
        locbak = board[squareSelected];
        board[squareSelected] = NO_PIECE;
    }

    for (int l = 0; l < LD_NB; l++) {
        if ((c << PLAYER_SHIFT) &
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
        if (!((m << PLAYER_SHIFT) & board[idx[1]] & board[idx[2]])) {
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
        if (board[i] & ((uint8_t)(c << PLAYER_SHIFT))) {
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
            if (sideToMove == pieceType >> PLAYER_SHIFT) {
                nOurPieces++;
            } else {
                nTheirPieces++;
            }
            break;
        }
    }
}

bool Position::is_all_surrounded()
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

void Position::mirror(bool cmdChange /*= true*/)
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
        int mm = 0, ss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);
        if (args >= 4) {
            s1 = (RANK_NB - s1 + 1) % RANK_NB;
            s2 = (RANK_NB - s2 + 1) % RANK_NB;
            cmdline[3] = '1' + static_cast<char>(s1);
            cmdline[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
            if (args >= 2) {
                s1 = (RANK_NB - s1 + 1) % RANK_NB;
                cmdline[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                if (args >= 2) {
                    s1 = (RANK_NB - s1 + 1) % RANK_NB;
                    cmdline[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);
            if (args >= 4) {
                s1 = (RANK_NB - s1 + 1) % RANK_NB;
                s2 = (RANK_NB - s2 + 1) % RANK_NB;
                iter[3] = '1' + static_cast<char>(s1);
                iter[10] = '1' + static_cast<char>(s2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                if (args >= 2) {
                    s1 = (RANK_NB - s1 + 1) % RANK_NB;
                    iter[4] = '1' + static_cast<char>(s1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                    if (args >= 2) {
                        s1 = (RANK_NB - s1 + 1) % RANK_NB;
                        iter[3] = '1' + static_cast<char>(s1);
                    }
                }
            }
        }
    }
}

void Position::turn(bool cmdChange /*= true*/)
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
        int mm = 0, ss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u",
                      &r1, &s1, &r2, &s2, &mm, &ss);

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
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
            if (args >= 2) {
                if (r1 == 1)
                    r1 = FILE_NB;
                else if (r1 == FILE_NB)
                    r1 = 1;
                cmdline[2] = '0' + static_cast<char>(r1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
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
                          "(%1u,%1u)->(%1u,%1u) %2u:%2u",
                          &r1, &s1, &r2, &s2, &mm, &ss);

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
                args = sscanf(iter.c_str(), "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
                if (args >= 2) {
                    if (r1 == 1)
                        r1 = FILE_NB;
                    else if (r1 == FILE_NB)
                        r1 = 1;

                    iter[2] = '0' + static_cast<char>(r1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
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

void Position::rotate(int degrees, bool cmdChange /*= true*/)
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
        int mm = 0, ss = 0;

        args = sscanf(cmdline, "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);
        if (args >= 4) {
            s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
            s2 = (s2 - 1 + RANK_NB - degrees) % RANK_NB;
            cmdline[3] = '1' + static_cast<char>(s1);
            cmdline[10] = '1' + static_cast<char>(s2);
        } else {
            args = sscanf(cmdline, "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);

            if (args >= 2) {
                s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                cmdline[4] = '1' + static_cast<char>(s1);
            } else {
                args = sscanf(cmdline, "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);

                if (args >= 2) {
                    s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                    cmdline[3] = '1' + static_cast<char>(s1);
                }
            }
        }

        for (auto &iter : cmdlist) {
            args = sscanf(iter.c_str(), "(%1u,%1u)->(%1u,%1u) %2u:%2u", &r1, &s1, &r2, &s2, &mm, &ss);

            if (args >= 4) {
                s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                s2 = (s2 - 1 + RANK_NB - degrees) % RANK_NB;
                iter[3] = '1' + static_cast<char>(s1);
                iter[10] = '1' + static_cast<char>(s2);
            } else {
                args = sscanf(iter.c_str(), "-(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);

                if (args >= 2) {
                    s1 = (s1 - 1 + RANK_NB - degrees) % RANK_NB;
                    iter[4] = '1' + static_cast<char>(s1);
                } else {
                    args = sscanf(iter.c_str(), "(%1u,%1u) %2u:%2u", &r1, &s1, &mm, &ss);
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
