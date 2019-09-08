#ifndef MOVEGEN_H
#define MOVEGEN_H

#include "config.h"
#include "millgame.h"
#include "search.h"

class MoveList
{
public:
    MoveList() = delete;

    MoveList &operator=(const MoveList &) = delete;

    using move_t = MillGameAi_ab::move_t;
    
    // 生成所有合法的着法并建立子节点
    static void generateLegalMoves(MillGameAi_ab &ai_ab, MillGame &chessTemp,
                                   MillGameAi_ab::Node *node, MillGameAi_ab::Node *rootNode,
                                   move_t bestMove);

    // 生成着法表
    static void createMoveTable(MillGame &chess);

    // 随机打乱着法搜索顺序
    static void shuffleMovePriorityTable(MillGame &chess);

    // 着法表 // TODO: Move to private
    inline static int moveTable[MillGame::N_POINTS][MillGame::N_MOVE_DIRECTIONS] = { {0} };

private:
    // 着法顺序表, 后续会被打乱
    inline static array<int, MillGame::N_RINGS *MillGame::N_SEATS> movePriorityTable {
        8, 9, 10, 11, 12, 13, 14, 15,
        16, 17, 18, 19, 20, 21, 22, 23,
        24, 25, 26, 27, 28, 29, 30, 31,
    };
};

#endif /* MOVEGEN_H */
