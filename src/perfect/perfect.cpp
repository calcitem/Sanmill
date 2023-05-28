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

#include "config.h"

#include "misc.h"
#include "perfect.h"
#include "option.h"
#include "position.h"

#ifdef GABOR_MALOM_PERFECT_AI
#define USE_DEPRECATED_CLR_API_WITHOUT_WARNING
#include <mscoree.h>
#pragma comment(lib, "mscoree.lib")

static ICLRRuntimeHost *pHost = NULL;

static HMODULE hModule = NULL;

static Move malom_remove_move = MOVE_NONE;

static void check_hresult(HRESULT hr, const char *operation)
{
    if (hr != S_OK) {
        fprintf(stderr, "Unknown error during %s, code: 0x%x\n", operation, hr);
        exit(hr);
    }
}

static void start_dotnet()
{
    if (pHost != nullptr) {
        return;
    }

    HRESULT hr = CorBindToRuntimeEx(L"v4.0.30319", L"wks", 0,
                                    CLSID_CLRRuntimeHost, IID_ICLRRuntimeHost,
                                    (PVOID *)&pHost);
    check_hresult(hr, "CorBindToRuntimeEx");
    hr = pHost->Start();
    check_hresult(hr, "ICLRRuntimeHost::Start");
}

static void stop_dotnet()
{
    if (pHost == nullptr) {
        return;
    }

    HRESULT hr = pHost->Stop();
    check_hresult(hr, "ICLRRuntimeHost::Stop");
    pHost->Release();
    pHost = nullptr;
}

// TODO: Use gameOptions.getPerfectDatabase() as path
static int GetBestMove(int whiteBitboard, int blackBitboard,
                       int whiteStonesToPlace, int blackStonesToPlace,
                       int playerToMove, bool onlyStoneTaking)
{
    char buffer[MAX_PATH];
    GetModuleFileName(NULL, buffer, MAX_PATH);
    std::string::size_type pos = std::string(buffer).find_last_of("\\/");
    std::string strPath = std::string(buffer).substr(0, pos) + "\\MalomAPI.dll";
    //std::string strPath = gameOptions.getPerfectDatabase() + "\\MalomAPI.dll";
    std::wstring wstrPath(strPath.begin(), strPath.end());
    LPCWSTR malomApiDllPath = wstrPath.c_str();

    std::ostringstream ss;
    ss << whiteBitboard << " " << blackBitboard << " " << whiteStonesToPlace
       << " " << blackStonesToPlace << " " << playerToMove << " "
       << (onlyStoneTaking ? 1 : 0);
    std::string cppstr = ss.str();
    std::wstring cppwstr = std::wstring(cppstr.begin(), cppstr.end());
    LPCWSTR lpcwstr = cppwstr.c_str();
    DWORD dwRet = 0;
    HRESULT hr = pHost->ExecuteInDefaultAppDomain(
        malomApiDllPath, L"MalomAPI.MalomSolutionAccess", L"GetBestMoveStr",
        lpcwstr, &dwRet);
    check_hresult(hr, "ICLRRuntimeHost::ExecuteInDefaultAppDomain "
                      "GetBestMoveStr");
    if (dwRet == 0) {
        fprintf(stderr, ".Net exception, see printed above by "
                        "GetBestMoveStr\n");
        exit(-1);
    }
    return dwRet;
}

int perfect_init()
{
    malom_remove_move = MOVE_NONE;
    start_dotnet();

    return 0;
}

int perfect_exit()
{
    malom_remove_move = MOVE_NONE;
    stop_dotnet();

    return 0;
}

int perfect_reset()
{
    if (hModule == NULL) {
        perfect_init();
    }

    return 0;
}

Square from_perfect_sq(uint32_t sq)
{
    constexpr Square map[] = {SQ_30, SQ_31, SQ_24, SQ_25, SQ_26, SQ_27, SQ_28,
                              SQ_29, SQ_22, SQ_23, SQ_16, SQ_17, SQ_18, SQ_19,
                              SQ_20, SQ_21, SQ_14, SQ_15, SQ_8,  SQ_9,  SQ_10,
                              SQ_11, SQ_12, SQ_13, SQ_0};

    return map[sq];
}

#if 0
unsigned to_perfect_sq(Square sq)
{
    constexpr int map[] = {
        -1, -1, -1, -1, -1, -1, -1, -1,
        18,  19,  20, 21, 22, 23, 16, 17, /* 8 - 15 */
        10,  11,  12, 13, 14, 15, 8, 9, /* 16 - 23 */
        2,  3,  4, 5, 6, 7, 0,  1, /* 24 - 31 */
        -1, -1, -1, -1, -1, -1, -1, -1,
    };

    return map[sq];
}
#endif

int countBits(int n)
{
    int count = 0;
    while (n) {
        n &= (n - 1);
        count++;
    }
    return count;
}

std::vector<Move> convertBitboardMove(int whiteBitboard, int blackBitboard,
                                      int playerToMove, int moveBitboard)
{
    std::vector<Move> moves;
    int usBitboard = playerToMove == 0 ? whiteBitboard : blackBitboard;
    int themBitboard = playerToMove == 1 ? whiteBitboard : blackBitboard;
    int count = countBits(moveBitboard);

    int from = -1;
    int to = -1;
    int removed = -1;

    for (int i = 0; i < 24; ++i) {
        int mask = 1 << i;
        bool usHasPiece = usBitboard & mask;
        bool themHasPiece = themBitboard & mask;
        bool noPiece = !usHasPiece && !themHasPiece;
        bool hasPiece = !noPiece;
        bool changed = moveBitboard & mask;

        if (changed) {
            if (count == 1) {
                if (noPiece) {
                    // The stone is placed here
                    moves.push_back(Move(from_perfect_sq(i)));
                    return moves;
                } else if (hasPiece) {
                    if (themHasPiece) {
                        // Only remove their piece
                        moves.push_back(Move(-from_perfect_sq(i)));
                        return moves;
                    } else if (usHasPiece) {
                        // Only remove our piece, not move
                        assert(false);
                    }
                }
            } else if (count == 2 || count == 3) {
                if (hasPiece) {
                    if (usHasPiece) {
                        from = i;
                    } else if (themHasPiece) {
                        // Remove their piece
                        removed = i;
                    }
                } else if (noPiece) {
                    to = i;
                }
            } else {
                assert(false);
            }
        }
    }

    if (count == 2) {
        if (from != -1 && to != -1 && removed == -1) {
            // Move
            moves.push_back(
                make_move(from_perfect_sq(from), from_perfect_sq(to)));
        } else if (from == -1 && to != -1 && removed != -1) {
            // Place and remove piece
            moves.push_back(Move(from_perfect_sq(to)));
            moves.push_back(Move(-from_perfect_sq(removed)));
        }
    } else if (count == 3) {
        moves.push_back(make_move(from_perfect_sq(from), from_perfect_sq(to)));
        moves.push_back(Move(-from_perfect_sq(removed)));
    } else {
        assert(false);
    }

    assert(moves.size() <= count);

    return moves;
}

Move perfect_search(Position *pos)
{
    if (malom_remove_move != MOVE_NONE) {
        Move ret = malom_remove_move;
        malom_remove_move = MOVE_NONE;
        return ret;
    }

    // The white stones on the board, encoded as a bitboard:
    // Each of the first 24 bits corresponds to one place on the board.
    // For the mapping between bits, see Bitboard.png.
    // For example, the integer number 131 means that there is a vertical mill
    // on the left side of the board, because 131 = 1 + 2 + 128.
    int whiteBitboard = 0;

    // The black stones on the board.
    int blackBitboard = 0;

    for (int i = 0; i < 24; i++) {
        auto c = color_of(pos->board[from_perfect_sq(i)]);
        if (c == WHITE) {
            whiteBitboard |= 1 << i;
        } else if (c == BLACK) {
            blackBitboard |= 1 << i;
        }
    }

    // The number of stones the white player can still place on the board.
    int whiteStonesToPlace = pos->piece_in_hand_count(WHITE);

    // The number of stones the black player can still place on the board.
    int blackStonesToPlace = pos->piece_in_hand_count(BLACK);

    // 0 if white is to move, 1 if black is to move.
    int playerToMove = pos->side_to_move() == WHITE ? 0 : 1;

    // Always set this to false if you want to handle
    // mill-closing and stone-removal as a single move.
    // If you set it to true, it is assumed that a mill was just closed
    // and only the stone to be removed is returned.
    bool onlyStoneTaking = (pos->piece_to_remove_count(pos->side_to_move()) >
                            0);

    // Return value:
    // The move is returned as a bitboard,
    // which has a bit set for each change on the board:
    // - If the place corresponding to a set bit is empty,
    //   then a stone of the player to move appears there.
    // - If the place corresponding to a set bit currently has a stone,
    //   then that stone disappears. (If it's a stone of the opponent,
    //   then this move involves a stone-removal.
    //   If it's a stone of the player to move,
    //   then this is a sliding or jumping move,
    //   and that stone is being slided or jumped to a different place.)
    // If this increases the number of stones the player to move has,
    // then that player will have one less stone to place after the move.
    int moveBitboard = GetBestMove(whiteBitboard, blackBitboard,
                                   whiteStonesToPlace, blackStonesToPlace,
                                   playerToMove, onlyStoneTaking);

    std::vector<Move> moves = convertBitboardMove(whiteBitboard, blackBitboard,
                                                  playerToMove, moveBitboard);

    if (moves.size() == 2) {
        malom_remove_move = moves.at(1);
    }

    return Move(moves.at(0));
}

#endif // GABOR_MALOM_PERFECT_AI

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

// Perfect AI
Mill *mill = nullptr;
PerfectAI *ai = nullptr;

int perfect_init()
{
    if (mill != nullptr || ai != nullptr) {
        return 0;
    }

    mill = new Mill();
    ai = new PerfectAI(PERFECT_AI_DATABASE_DIR);
    ai->setDatabasePath(PERFECT_AI_DATABASE_DIR);
    mill->beginNewGame(ai, ai, fieldStruct::playerOne);

    return 0;
}

int perfect_exit()
{
    if (mill != nullptr) {
        delete mill;
        mill = nullptr;
    }

    if (ai != nullptr) {
        delete ai;
        ai = nullptr;
    }

    return 0;
}

int perfect_reset()
{
    if (mill == nullptr || ai == nullptr) {
        perfect_init();
    } else {
        mill->resetGame();
    }

    return 0;
}

Square from_perfect_sq(uint32_t sq)
{
    constexpr Square map[] = {SQ_31, SQ_24, SQ_25, SQ_23, SQ_16, SQ_17, SQ_15,
                              SQ_8,  SQ_9,  SQ_30, SQ_22, SQ_14, SQ_10, SQ_18,
                              SQ_26, SQ_13, SQ_12, SQ_11, SQ_21, SQ_20, SQ_19,
                              SQ_29, SQ_28, SQ_27, SQ_0};

    return map[sq];
}

Move from_perfect_move(uint32_t from, uint32_t to)
{
    Move ret;

    if (to == 24)
        ret = static_cast<Move>(-from_perfect_sq(from));
    else if (from == 24)
        ret = static_cast<Move>(from_perfect_sq(to));
    else
        ret = make_move(from_perfect_sq(from), from_perfect_sq(to));

    if (ret == MOVE_NONE) {
        assert(false);
    }

    return ret;
}

unsigned to_perfect_sq(Square sq)
{
    constexpr int map[] = {
        -1, -1, -1, -1, -1, -1, -1, -1,
        7,  8,  12, 17, 16, 15, 11, 6, /* 8 - 15 */
        4,  5,  13, 20, 19, 18, 10, 3, /* 16 - 23 */
        1,  2,  14, 23, 22, 21, 9,  0, /* 24 - 31 */
        -1, -1, -1, -1, -1, -1, -1, -1,
    };

    return map[sq];
}

void to_perfect_move(Move move, uint32_t &from, uint32_t &to)
{
    const Square f = from_sq(move);
    const Square t = to_sq(move);
    const MoveType type = type_of(move);

    if (type == MOVETYPE_REMOVE) {
        from = to_perfect_sq(t);
        to = SQUARE_NB;
    } else if (type == MOVETYPE_PLACE) {
        from = SQUARE_NB;
        to = to_perfect_sq(t);
    } else {
        from = to_perfect_sq(f);
        to = to_perfect_sq(t);
    }
}

Move perfect_search(Position *pos)
{
    uint32_t from = 24, to = 24;
    // sync_cout << ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>" << sync_endl;
    // mill->printBoard();
    // sync_cout << "========================" << sync_endl;

    mill->getComputersChoice(&from, &to);

    mill->doMove(from, to);

    mill->printBoard();
    // sync_cout << "<<<<<<<<<<<<<<<<<<<<<<<<<<<<" << sync_endl;

    sync_cout << "\nlast move was from "
              << static_cast<char>(mill->getLastMoveFrom() + 'a') << " to "
              << static_cast<char>(mill->getLastMoveTo() + 'a') << sync_endl;
    // sync_cout << "\nlast move was from " << (char)(from + 'a') << " to " <<
    // (char)(to + 'a') << sync_endl;

    // ret = mill->doMove(mill->getLastMoveFrom(), mill->getLastMoveTo());

    // return from_perfect_move(from, to);
    return from_perfect_move(mill->getLastMoveFrom(), mill->getLastMoveTo());

    // cout << "\nlast move was from " << (char)(mill->getLastMoveFrom() + 'a')
    // << " to " << (char)(mill->getLastMoveTo() + 'a') << "\n\n";
    // return from_perfect_move(mill->getLastMoveFrom(), mill->getLastMoveTo());
}

bool perfect_do_move(Move move)
{
    uint32_t from, to;

    to_perfect_move(move, from, to);

    return mill->doMove(from, to);
}

bool perfect_command(const char *cmd)
{
    uint32_t ruleNo = 0;
    unsigned t = 0;
    int step = 0;
    File file1 = FILE_A, file2 = FILE_A;
    Rank rank1 = RANK_1, rank2 = RANK_1;
    Move move;

    if (sscanf(cmd, "r%1u s%3d t%2u", &ruleNo, &step, &t) == 3) {
        if (set_rule(ruleNo - 1) == false) {
            return false;
        }

        return perfect_reset();
    }

    int args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u)",
                      reinterpret_cast<unsigned *>(&file1),
                      reinterpret_cast<unsigned *>(&rank1),
                      reinterpret_cast<unsigned *>(&file2),
                      reinterpret_cast<unsigned *>(&rank2));

    if (args >= 4) {
        move = make_move(make_square(file1, rank1), make_square(file2, rank2));
        return perfect_do_move(move);
    }

    args = sscanf(cmd, "-(%1u,%1u)", reinterpret_cast<unsigned *>(&file1),
                  reinterpret_cast<unsigned *>(&rank1));
    if (args >= 2) {
        move = static_cast<Move>(-make_move(SQ_0, make_square(file1, rank1)));
        return perfect_do_move(move);
    }

    args = sscanf(cmd, "(%1u,%1u)", reinterpret_cast<unsigned *>(&file1),
                  reinterpret_cast<unsigned *>(&rank1));
    if (args >= 2) {
        move = make_move(SQ_0, make_square(file1, rank1));
        return perfect_do_move(move);
    }

    return false;

#if 0
    args = sscanf(cmd, "Player%1u give up!", &t);

    //     if (args == 1) {
    //         return resign((Color)t);
    //     }

    if (rule.threefoldRepetitionRule) {
        if (!strcmp(cmd, drawReasonThreefoldRepetitionStr)) {
            return true;
        }

        if (!strcmp(cmd, "draw")) {
            phase = Phase::gameOver;
            winner = DRAW;
            score_draw++;
            gameOverReason = GameOverReason::drawThreefoldRepetition;
            //snprintf(record, RECORD_LEN_MAX, drawReasonThreefoldRepetitionStr);
            return true;
        }
    }

    return false;
#endif
}

// mill->getWinner() == 0
// mill->getCurPlayer() == fieldStruct::playerTwo

#endif // MADWEASEL_MUEHLE_PERFECT_AI
