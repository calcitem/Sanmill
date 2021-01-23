#include "perfect.h"


// Perfect AI
Mill *mill = nullptr;
PerfectAI *ai = nullptr;

int perfect_init(void)
{
#ifdef _DEBUG
    char databaseDirectory[] = "D:\\database";
#elif _RELEASE_X64
    char databaseDirectory[] = "";
#endif

    if (mill != nullptr) {
        return 0;
    }

    mill = new Mill();
    ai = new PerfectAI(databaseDirectory);
    ai->setDatabasePath(databaseDirectory);
    mill->beginNewGame(ai, ai, fieldStruct::playerOne);

    return 0;
}

Square perfect_sq_to_sq(unsigned int sq)
{
    Square map[] = {
        SQ_31, SQ_24, SQ_25, SQ_23, SQ_16, SQ_17, SQ_15, SQ_8,
        SQ_9, SQ_30, SQ_22, SQ_14, SQ_10, SQ_18, SQ_26, SQ_13,
        SQ_12, SQ_11, SQ_21, SQ_20, SQ_19, SQ_29, SQ_28, SQ_27,
        SQ_0 };

    return map[sq];
}

Move perfect_move_to_move(unsigned int from, unsigned int to)
{
    if (mill->mustStoneBeRemoved())
        return (Move)-perfect_sq_to_sq(to);
    else if (mill->inSettingPhase())
        return (Move)perfect_sq_to_sq(to);
    else
        return (Move)(make_move(perfect_sq_to_sq(from), perfect_sq_to_sq(to)));
}

unsigned sq_to_perfect_sq(Square sq)
{
    int map[] = {
        -1, -1, -1, -1, -1, -1, -1, -1,
        7, 8, 12, 17, 16, 15, 11, 6,    /* 8 - 15 */
        4, 5, 13, 20, 19, 18, 10, 3,    /* 16 - 23 */
        1, 2, 14, 23, 22, 21, 9, 0,     /* 24 - 31 */
        -1, -1, -1, -1, -1, -1, -1, -1,
    };

    return map[sq];
}

void move_to_perfect_move(Move move, unsigned int &from, unsigned int &to)
{
    Square f = from_sq(move);
    Square t = to_sq(move);

    if (mill->mustStoneBeRemoved()) {
        from = fieldStruct::size;
        to = sq_to_perfect_sq(t);
    } else if (mill->inSettingPhase()) {
        from = fieldStruct::size;
        to = sq_to_perfect_sq(t);
    } else {
        from = sq_to_perfect_sq(f);
        to = sq_to_perfect_sq(t);
    }
}

Move perfect_search()
{
    unsigned int from, to;
    mill->getComputersChoice(&from, &to);

    cout << "\nlast move was from " << (char)(mill->getLastMoveFrom() + 'a') << " to " << (char)(mill->getLastMoveTo() + 'a') << "\n\n";

    mill->printBoard();

   return perfect_move_to_move(mill->getLastMoveFrom(), mill->getLastMoveTo());
}

bool perfect_do_move(Move move)
{
    bool ret;
    unsigned int from, to;

    move_to_perfect_move(move, from, to);

    ret = mill->doMove(from, to);
    return ret;
}

// mill->getWinner() == 0
// mill->getCurrentPlayer() == fieldStruct::playerTwo