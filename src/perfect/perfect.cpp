#include "config.h"
#include "perfect.h"
#include "misc.h"
#include "position.h"

// Perfect AI
Mill* mill = nullptr;
PerfectAI* ai = nullptr;

int perfect_init(void)
{
    if (mill != nullptr || ai != nullptr) {
        return 0;
    }

    mill = new Mill();
    ai = new PerfectAI(databaseDirectory);
    ai->setDatabasePath(databaseDirectory);
    mill->beginNewGame(ai, ai, fieldStruct::playerOne);

    return 0;
}

int perfect_exit(void)
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

int perfect_reset(void)
{
    if (mill == nullptr || ai == nullptr) {
        perfect_init();
    } else {
        mill->resetGame();
    }

    return 0;
}

Square from_perfect_sq(unsigned int sq)
{
    Square map[] = {
        SQ_31, SQ_24, SQ_25, SQ_23, SQ_16, SQ_17, SQ_15, SQ_8,
        SQ_9, SQ_30, SQ_22, SQ_14, SQ_10, SQ_18, SQ_26, SQ_13,
        SQ_12, SQ_11, SQ_21, SQ_20, SQ_19, SQ_29, SQ_28, SQ_27,
        SQ_0
    };

    return map[sq];
}

Move from_perfect_move(unsigned int from, unsigned int to)
{
    Move ret = MOVE_NONE;

    if (to == 24)
        ret = (Move)-from_perfect_sq(from);
    else if (from == 24)
        ret = (Move)from_perfect_sq(to);
    else
        ret = (Move)(make_move(from_perfect_sq(from), from_perfect_sq(to)));

    if (ret == MOVE_NONE) {
        assert(false);
    }

    return ret;
}

unsigned to_perfect_sq(Square sq)
{
    int map[] = {
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        7,
        8,
        12,
        17,
        16,
        15,
        11,
        6, /* 8 - 15 */
        4,
        5,
        13,
        20,
        19,
        18,
        10,
        3, /* 16 - 23 */
        1,
        2,
        14,
        23,
        22,
        21,
        9,
        0, /* 24 - 31 */
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
        -1,
    };

    return map[sq];
}

void to_perfect_move(Move move, unsigned int& from, unsigned int& to)
{
    Square f = from_sq(move);
    Square t = to_sq(move);
    MoveType type = type_of(move);

    if (type == MOVETYPE_REMOVE) {
        from = to_perfect_sq(t);
        to = fieldStruct::size;
    } else if (type == MOVETYPE_PLACE) {
        from = fieldStruct::size;
        to = to_perfect_sq(t);
    } else {
        from = to_perfect_sq(f);
        to = to_perfect_sq(t);
    }
}

void to_perfect_postition(Position& pos)
{
}

Move perfect_search()
{
    bool ret = false;
    unsigned int from = 24, to = 24;
    //sync_cout << ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>" << sync_endl;
    //mill->printBoard();
    //sync_cout << "========================" << sync_endl;

    mill->getComputersChoice(&from, &to);

    ret = mill->doMove(from, to);
    assert(ret == true);

    mill->printBoard();
    //sync_cout << "<<<<<<<<<<<<<<<<<<<<<<<<<<<<" << sync_endl;

    sync_cout << "\nlast move was from " << (char)(mill->getLastMoveFrom() + 'a') << " to " << (char)(mill->getLastMoveTo() + 'a') << sync_endl;
    //sync_cout << "\nlast move was from " << (char)(from + 'a') << " to " << (char)(to + 'a') << sync_endl;

    //ret = mill->doMove(mill->getLastMoveFrom(), mill->getLastMoveTo());

    //return from_perfect_move(from, to);
    return from_perfect_move(mill->getLastMoveFrom(), mill->getLastMoveTo());

    //cout << "\nlast move was from " << (char)(mill->getLastMoveFrom() + 'a') << " to " << (char)(mill->getLastMoveTo() + 'a') << "\n\n";
    // return from_perfect_move(mill->getLastMoveFrom(), mill->getLastMoveTo());
}

bool perfect_do_move(Move move)
{
    bool ret;
    unsigned int from, to;

    to_perfect_move(move, from, to);

    ret = mill->doMove(from, to);
    return ret;
}

bool perfect_command(const char* cmd)
{
    unsigned int ruleNo = 0;
    unsigned t = 0;
    int step = 0;
    File file1 = FILE_A, file2 = FILE_A;
    Rank rank1 = RANK_1, rank2 = RANK_1;
    int args = 0;
    Move move = MOVE_NONE;

    if (sscanf(cmd, "r%1u s%3d t%2u", &ruleNo, &step, &t) == 3) {
        if (set_rule(ruleNo - 1) == false) {
            return false;
        }

        return perfect_reset();
    }

    args = sscanf(cmd, "(%1u,%1u)->(%1u,%1u)", (unsigned*)&file1, (unsigned*)&rank1, (unsigned*)&file2, (unsigned*)&rank2);

    if (args >= 4) {
        move = make_move(make_square(file1, rank1), make_square(file2, rank2));
        return perfect_do_move(move);
    }

    args = sscanf(cmd, "-(%1u,%1u)", (unsigned*)&file1, (unsigned*)&rank1);
    if (args >= 2) {
        move = (Move)-make_move(SQ_0, make_square(file1, rank1));
        return perfect_do_move(move);
    }

    args = sscanf(cmd, "(%1u,%1u)", (unsigned*)&file1, (unsigned*)&rank1);
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
            gameOverReason = GameOverReason::drawReasonThreefoldRepetition;
            //snprintf(record, RECORD_LEN_MAX, drawReasonThreefoldRepetitionStr);
            return true;
        }
    }

    return false;
#endif
}

// mill->getWinner() == 0
// mill->getCurrentPlayer() == fieldStruct::playerTwo
