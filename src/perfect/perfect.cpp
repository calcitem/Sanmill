/*********************************************************************
    MiniMaxAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#if defined(MADWEASEL_MUEHLE_PERFECT_AI) || defined(MALOM_PERFECT_AI)

#include "misc.h"
#include "perfect.h"
#include "position.h"

#include <windows.h>

typedef int(__cdecl *GETBESTMOVE_FUNC)(int, int, int, int, int, bool);

#if 0

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

Move perfect_search()
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

#else

typedef int(__cdecl *GETBESTMOVE_FUNC)(int, int, int, int, int, bool);

HMODULE hModule = NULL;
GETBESTMOVE_FUNC GetBestMove = NULL;

int perfect_init()
{
    hModule = LoadLibrary("MalomAPI.dll");
    if (hModule == NULL) {
        return -1;
    }

    GetBestMove = (GETBESTMOVE_FUNC)GetProcAddress(hModule, "GetBestMoveNoException");
    if (GetBestMove == NULL) {
        return -1;
    }

    return 0;
}

int perfect_exit()
{
    if (hModule != NULL) {
        FreeLibrary(hModule);
        hModule = NULL;
        GetBestMove = NULL;
    }

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
                              SQ_29,  SQ_22,  SQ_23, SQ_16, SQ_17, SQ_18, SQ_19,
                              SQ_20, SQ_21, SQ_14, SQ_15, SQ_8, SQ_9, SQ_10,
                              SQ_11, SQ_12, SQ_13, SQ_0};

    return map[sq];
}

Move from_perfect_move(uint32_t from, uint32_t to)
{
    // TODO
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

void to_perfect_move(Move move, uint32_t &from, uint32_t &to)
{
    // TODO
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

Move perfect_search(Position *pos)
{
    // The white stones on the board, encoded as a bitboard:
    // Each of the first 24 bits corresponds to one place on the board.
    // For the mapping between bits, see Bitboard.png.
    // For example, the integer number 131 means that there is a vertical mill
    // on the left side of the board, because 131 = 1 + 2 + 128.
    int whiteBitboard = 0;

    // The black stones on the board.
    int blackBitboard = 0;

    // The number of stones the white player can still place on the board.
    int whiteStonesToPlace = 0;

    // The number of stones the black player can still place on the board.
    int blackStonesToPlace = 0;

    // 0 if white is to move, 1 if black is to move.
    int playerToMove = 0;

    // Always set this to false if you want to handle
    // mill-closing and stone-removal as a single move.
    // If you set it to true, it is assumed that a mill was just closed
    // and only the stone to be removed is returned.
    bool onlyStoneTaking = 0;

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
    int result = GetBestMove(whiteBitboard, blackBitboard, whiteStonesToPlace,
                             blackStonesToPlace, playerToMove, onlyStoneTaking);


    return MOVE_NONE;
}

#if 0
bool perfect_do_move(Move move)
{
    uint32_t from, to;

    to_perfect_move(move, from, to);

    return mill->doMove(from, to);
}
#endif

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

    #if 0
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
    #endif

    return false;
}

#endif

#endif // MADWEASEL_MUEHLE_PERFECT_AI || MALOM_PERFECT_AI
