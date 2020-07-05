/*
  Sanmill, a mill state playing engine derived from NineChess 1.5
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

#include <cmath>
#include <array>
#include <chrono>
#include <algorithm>

#include "search.h"
#include "evaluate.h"
#include "movegen.h"
#include "hashmap.h"
#include "tt.h"
#include "endgame.h"
#include "types.h"
#include "option.h"
#include "misc.h"
#include "movepick.h"

using namespace CTSL;

vector<Key> moveHistory;

AIAlgorithm::AIAlgorithm()
{
    position = new Position();
    pos = new Position();
    //movePicker = new MovePicker();
}

AIAlgorithm::~AIAlgorithm()
{
    //delete pos;
}

Depth AIAlgorithm::changeDepth(Depth origDepth)
{
    Depth d = origDepth;

#ifdef _DEBUG
    Depth reduce = 0;
#else
    Depth reduce = 0;
#endif

    const Depth placingDepthTable_12[] = {
         +1,  2,  +2,  4,     /* 0 ~ 3 */
         +4, 12, +12, 18,     /* 4 ~ 7 */
        +12, 16, +16, 16,     /* 8 ~ 11 */
        +16, 16, +16, 17,     /* 12 ~ 15 */
        +17, 16, +16, 15,     /* 16 ~ 19 */
        +15, 14, +14, 14,     /* 20 ~ 23 */
    };

    const Depth placingDepthTable_9[] = {
         +1, 7,  +7,  10,     /* 0 ~ 3 */
        +10, 12, +12, 12,     /* 4 ~ 7 */
        +12, 13, +13, 13,     /* 8 ~ 11 */
        +13, 13, +13, 13,     /* 12 ~ 15 */
        +13, 13,              /* 16 ~ 18 */
    };

    const Depth movingDepthTable[] = {
         1,  1,  1,  1,     /* 0 ~ 3 */
         1,  1, 11, 11,     /* 4 ~ 7 */
        11, 11, 11, 11,     /* 8 ~ 11 */
        11, 11, 11, 11,     /* 12 ~ 15 */
        11, 11, 11, 11,     /* 16 ~ 19 */
        12, 12, 13, 14,     /* 20 ~ 23 */
    };

#ifdef ENDGAME_LEARNING
    const Depth movingDiffDepthTable[] = {
        0, 0, 0,               /* 0 ~ 2 */
        0, 0, 0, 0, 0,       /* 3 ~ 7 */
        0, 0, 0, 0, 0          /* 8 ~ 12 */
    };
#else
    const Depth movingDiffDepthTable[] = {
        0, 0, 0,               /* 0 ~ 2 */
        11, 11, 10, 9, 8,       /* 3 ~ 7 */
        7, 6, 5, 4, 3          /* 8 ~ 12 */
    };
#endif /* ENDGAME_LEARNING */

    if (pos->phase & PHASE_PLACING) {
        if (rule.nTotalPiecesEachSide == 12) {
            d = placingDepthTable_12[rule.nTotalPiecesEachSide * 2 - pos->getPiecesInHandCount(BLACK) - pos->getPiecesInHandCount(WHITE)];
        } else {
            d = placingDepthTable_9[rule.nTotalPiecesEachSide * 2 - pos->getPiecesInHandCount(BLACK) - pos->getPiecesInHandCount(WHITE)];
        }
    }

    if (pos->phase & PHASE_MOVING) {
        int pb = pos->getPiecesOnBoardCount(BLACK);
        int pw = pos->getPiecesOnBoardCount(WHITE);

        int pieces = pb + pw;
        int diff = pb - pw;

        if (diff < 0) {
            diff = -diff;
        }

        d = movingDiffDepthTable[diff];

        if (d == 0) {
            d = movingDepthTable[pieces];
        }
    }

    if (unlikely(d > reduce)) {
        d -= reduce;
    }

    d += DEPTH_ADJUST;

    d = d >= 1 ? d : 1;

#if defined(FIX_DEPTH)
    d = FIX_DEPTH;
#endif

    loggerDebug("Depth: %d\n", d);

    return d;
}

void AIAlgorithm::setPosition(Position *p)
{
    if (strcmp(rule.name, rule.name) != 0) {
#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::clear();
#endif // TRANSPOSITION_TABLE_ENABLE

#ifdef ENDGAME_LEARNING
        // TODO: 规则改变时清空残局库
        //clearEndgameHashMap();
        //endgameList.clear();
#endif // ENDGAME_LEARNING

        moveHistory.clear();
    }

    //position = p;
    pos = p;
    position = pos;

    requiredQuit = false;
}

#ifdef ALPHABETA_AI
int AIAlgorithm::search(Depth depth)
{
    Value value = VALUE_ZERO;

    Depth d = changeDepth(depth);

    time_t time0 = time(nullptr);
    srand(static_cast<unsigned int>(time0));

#ifdef TIME_STAT
    auto timeStart = chrono::steady_clock::now();
    chrono::steady_clock::time_point timeEnd;
#endif
#ifdef CYCLE_STAT
    auto cycleStart = stopwatch::rdtscp_clock::now();
    chrono::steady_clock::time_point cycleEnd;
#endif

#ifdef THREEFOLD_REPETITION
    static int nRepetition = 0;

    if (position->getPhase() == PHASE_MOVING) {
        Key key = position->getPosKey();
        
        if (std::find(moveHistory.begin(), moveHistory.end(), key) != moveHistory.end()) {
            nRepetition++;
            if (nRepetition == 3) {
                nRepetition = 0;
                return 3;
            }
        } else {
            moveHistory.push_back(key);
        }
    }

    if (position->getPhase() == PHASE_PLACING) {
        moveHistory.clear();
    }
#endif // THREEFOLD_REPETITION

    MoveList::shuffle();   

    Value alpha = -VALUE_INFINITE;
    Value beta = VALUE_INFINITE;

    if (gameOptions.getIDSEnabled()) {
        loggerDebug("IDS: ");

        Depth depthBegin = 2;
        Value lastValue = VALUE_ZERO;

        loggerDebug("\n==============================\n");
        loggerDebug("==============================\n");
        loggerDebug("==============================\n");

        for (Depth i = depthBegin; i < d; i += 1) {
#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
            TranspositionTable::clear();
#endif
#endif

#ifdef MTDF_AI
            value = MTDF(value, i);
#else
            value = search(i, alpha, beta);
#endif

            loggerDebug("%d(%d) ", value, value - lastValue);

            lastValue = value;
        }

#ifdef TIME_STAT
        timeEnd = chrono::steady_clock::now();
        loggerDebug("\nIDS Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef CLEAR_TRANSPOSITION_TABLE
    TranspositionTable::clear();
#endif
#endif

    if (gameOptions.getIDSEnabled()) {
        alpha = -VALUE_INFINITE;
        beta = VALUE_INFINITE;
    }

    originDepth = d;

#ifdef MTDF_AI
    value = MTDF(value, d);
#else
    value = search(d, alpha, beta);
#endif

#ifdef TIME_STAT
    timeEnd = chrono::steady_clock::now();
    loggerDebug("Total Time: %llus\n", chrono::duration_cast<chrono::seconds>(timeEnd - timeStart).count());
#endif

    lastvalue = bestvalue;
    bestvalue = value;

    return 0;
}

Value AIAlgorithm::MTDF(Value firstguess, Depth depth)
{
    Value g = firstguess;
    Value lowerbound = -VALUE_INFINITE;
    Value upperbound = VALUE_INFINITE;
    Value beta;

    while (lowerbound < upperbound) {
        if (g == lowerbound) {
            beta = g + VALUE_MTDF_WINDOW;
        } else {
            beta = g;
        }

        g = search(depth, beta - VALUE_MTDF_WINDOW, beta);

        if (g < beta) {
            upperbound = g;    // fail low
        } else {
            lowerbound = g;    // fail high
        }
    }

    return g;
}

Value AIAlgorithm::search(Depth depth, Value alpha, Value beta)
{
    Value value;
    Value bestValue = -VALUE_INFINITE;

    Depth epsilon;

#ifdef TT_MOVE_ENABLE
    Move ttMove = MOVE_NONE;
#endif // TT_MOVE_ENABLE

#if defined (TRANSPOSITION_TABLE_ENABLE) || defined(ENDGAME_LEARNING)
    Key posKey = pos->getPosKey();
#endif

#ifdef ENDGAME_LEARNING
    // 检索残局库
    Endgame endgame;

    if (gameOptions.getLearnEndgameEnabled() &&
        findEndgameHash(posKey, endgame)) {
        switch (endgame.type) {
        case ENDGAME_PLAYER_BLACK_WIN:
            bestValue = VALUE_MATE;
            bestValue += depth;
            break;
        case ENDGAME_PLAYER_WHITE_WIN:
            bestValue = -VALUE_MATE;
            bestValue -= depth;
            break;
        default:
            break;
        }

        return bestValue;
    }
#endif /* ENDGAME_LEARNING */

#ifdef TRANSPOSITION_TABLE_ENABLE
    Bound type = BOUND_NONE;

    Value probeVal = TranspositionTable::probe(posKey, depth, alpha, beta, type
#ifdef TT_MOVE_ENABLE
                                     , ttMove
#endif // TT_MOVE_ENABLE                                     
    );

    if (probeVal != VALUE_UNKNOWN) {
#ifdef TRANSPOSITION_TABLE_DEBUG
        ttHitCount++;
#endif

        bestValue = probeVal;

#if 0
        // TODO: 有必要针对深度微调 value?
        if (position->turn == BLACK)
            bestValue += tte.depth - depth;
        else
            bestValue -= tte.depth - depth;
#endif

#ifdef TT_MOVE_ENABLE
//         if (ttMove != MOVE_NONE) {
//             bestMove = ttMove;
//         }
#endif // TT_MOVE_ENABLE

        return bestValue;
    }
#ifdef TRANSPOSITION_TABLE_DEBUG
    else {
        ttMissCount++;
    }
#endif

    //hashMapMutex.unlock();
#endif /* TRANSPOSITION_TABLE_ENABLE */

#if 0
    if (position->phase == PHASE_PLACING && depth == 1 && pos->nPiecesNeedRemove > 0) {
        depth--;
    }
#endif

    if (unlikely(position->phase == PHASE_GAMEOVER) ||   // TODO: Deal with hash
        depth <= 0 ||
        unlikely(requiredQuit)) {
        bestValue = Eval::evaluate(position);

        // For win quickly
        if (bestValue > 0) {
            bestValue += depth;
        } else {
            bestValue -= depth;
        }

#ifdef NULL_MOVE
        if (depth % 2 == 1)
        {
            // TODO: WIP       
            st->generateNullMove(moves);
            st->generateChildren(moves, this, node);
            doNullMove();
            int moveCount = st->generateMoves(moves);
            if (moveCount)
            {
                st->generateChildren(moves, this, node->children[0]);
                value = -search(depth - 1 - 2, -beta, -beta + 1, node->children[0]);
                undoNullMove();

                if (value >= beta) {
                    bestValue = beta;
                    return beta;
                }
            }

        }
#endif

#ifdef TRANSPOSITION_TABLE_ENABLE
        TranspositionTable::save(bestValue,
                       depth,
                       BOUND_EXACT,
                       posKey
#ifdef TT_MOVE_ENABLE
                       , MOVE_NONE
#endif // TT_MOVE_ENABLE
                      );
#endif

        return bestValue;
    }

    ExtMove extMoves[MAX_MOVES];
    memset(extMoves, 0, sizeof(extMoves));
    ExtMove *end = generateMoves(pos, extMoves);
    MovePicker mp(pos, extMoves);
    mp.score();

    partial_insertion_sort(extMoves, end, -100);
    ExtMove *cur = extMoves;

    int nchild = end - cur;

    if (nchild == 1 && depth == originDepth) {
        bestMove = extMoves[0].move;
        bestValue = VALUE_UNIQUE;
        return bestValue;
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef PREFETCH_SUPPORT
    for (int i = 0; i < nchild; i++) {
        TranspositionTable::prefetch(pos->getNextPrimaryKey(extMoves[i].move));
    }

#ifdef PREFETCH_DEBUG
    if (posKey << 8 >> 8 == 0x0)
    {
        int pause = 1;
    }
#endif // PREFETCH_DEBUG
#endif // PREFETCH_SUPPORT
#endif // TRANSPOSITION_TABLE_ENABLE

    for (int i = 0; i < nchild; i++) {
        stashPosition();
        Color before = pos->sideToMove;
        Move move = extMoves[i].move;
        doMove(move);
        Color after = pos->sideToMove;

        if (gameOptions.getDepthExtension() == true && nchild == 1) {
            epsilon = 1;
        } else {
            epsilon = 0;
        }

#ifdef PVS_AI
        if (i == 0) {
            if (after != before) {
                value = -search(depth - 1 + epsilon, -beta, -alpha);
            } else {
                value = search(depth - 1 + epsilon, alpha, beta);
    }
        } else {
            if (after != before) {
                value = -search(depth - 1 + epsilon, -alpha - VALUE_PVS_WINDOW, -alpha);

                if (value > alpha && value < beta) {
                    value = -search(depth - 1 + epsilon, -beta, -alpha);
                    //assert(value >= alpha && value <= beta);
                }
            } else {
                value = search(depth - 1 + epsilon, alpha, alpha + VALUE_PVS_WINDOW);

                if (value > alpha && value < beta) {
                    value = search(depth - 1 + epsilon, alpha, beta);
                    //assert(value >= alpha && value <= beta);
                }
            }
        }
#else
        if (after != before) {
            value = -search(depth - 1 + epsilon, -beta, -alpha);
        } else {
            value = search(depth - 1 + epsilon, alpha, beta);
        }
#endif // PVS_AI

        undoMove();

        assert(value > -VALUE_INFINITE && value < VALUE_INFINITE);

        if (value >= bestValue) {
            bestValue = value;

            if (value > alpha) {
                if (depth == originDepth) {
                    bestMove = move;
                }

                break;
            }
        }
    }

#ifdef TRANSPOSITION_TABLE_ENABLE
    TranspositionTable::save(bestValue,
                   depth,
                   bestValue >= beta ? BOUND_LOWER :
                   BOUND_UPPER,
                   posKey
#ifdef TT_MOVE_ENABLE
                   , bestMove
#endif // TT_MOVE_ENABLE
                  );
#endif /* TRANSPOSITION_TABLE_ENABLE */

#ifdef HOSTORY_HEURISTIC
    movePicker->setHistoryScore(bestMove, depth);
#endif

    assert(bestValue > -VALUE_INFINITE && bestValue < VALUE_INFINITE);

    return bestValue;
}
#endif // ALPHABETA_AI

void AIAlgorithm::stashPosition()
{
    positionStack.push(*(pos));
}

void AIAlgorithm::doMove(Move move)
{
    pos->doMove(move);
}

void AIAlgorithm::undoMove()
{
    memcpy(pos, positionStack.top(), sizeof(Position));
    //tmppos = positionStack.top();
    positionStack.pop();
}

void AIAlgorithm::doNullMove()
{
    pos->doNullMove();
}

void AIAlgorithm::undoNullMove()
{
    pos->undoNullMove();
}

#ifdef ALPHABETA_AI
const char* AIAlgorithm::nextMove()
{
    return moveToCommand(bestMove);

#if 0
    char charSelect = '*';

    Board::printBoard();

    int moveIndex = 0;
    bool foundBest = false;

    int cs = root->childrenSize;
    for (int i = 0; i < cs; i++) {
        if (root->children[i]->move != bestMove) {
            charSelect = ' ';
        } else {
            charSelect = '*';
            foundBest = true;
        }

        loggerDebug("[%.2d] %d\t%s\t%d\t%d\t%u %c\n", moveIndex,
                    root->children[i]->move,
                    moveToCommand(root->children[i]->move),
                    root->children[i]->value,
                    root->children[i]->rating,
#ifdef HOSTORY_HEURISTIC
                    root->children[i]->score,
#else
                    0,
#endif
                    charSelect);

        moveIndex++;
    }

    Color side = position->sideToMove;

#ifdef ENDGAME_LEARNING
    // Check if very weak
    if (gameOptions.getLearnEndgameEnabled()) {
        if (bestValue <= -VALUE_KNOWN_WIN) {
            Endgame endgame;
            endgame.type = state->position->playerSideToMove == PLAYER_BLACK ?
                ENDGAME_PLAYER_WHITE_WIN : ENDGAME_PLAYER_BLACK_WIN;
            key_t endgameHash = position->getPosKey(); // TODO: Do not generate hash repeately
            recordEndgameHash(endgameHash, endgame);
        }
    }
#endif /* ENDGAME_LEARNING */

    if (gameOptions.getGiveUpIfMostLose() == true) {
        if (root->value <= -VALUE_MATE) {
            sprintf(cmdline, "Player%d give up!", position->sideToMove);
            return cmdline;
        }
    }

    nodeCount = 0;

#ifdef TRANSPOSITION_TABLE_ENABLE
#ifdef TRANSPOSITION_TABLE_DEBUG
    size_t hashProbeCount = ttHitCount + ttMissCount;
    if (hashProbeCount)
    {
        loggerDebug("[posKey] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                    hashProbeCount, ttHitCount, ttMissCount, ttHitCount * 100 / hashProbeCount);
    }
#endif // TRANSPOSITION_TABLE_DEBUG
#endif // TRANSPOSITION_TABLE_ENABLE

    if (foundBest == false) {
        loggerDebug("Warning: Best Move NOT Found\n");
    }

    return moveToCommand(bestMove);
#endif
}
#endif // ALPHABETA_AI

const char *AIAlgorithm::moveToCommand(Move move)
{
    File file2;
    Rank rank2;
    Board::squareToPolar(to_sq(move), file2, rank2);

    if (move < 0) {
        sprintf(cmdline, "-(%1u,%1u)", file2, rank2);
    } else if (move & 0x7f00) {
        File file1;
        Rank rank1;
        Board::squareToPolar(from_sq(move), file1, rank1);
        sprintf(cmdline, "(%1u,%1u)->(%1u,%1u)", file1, rank1, file2, rank2);
    } else {
        sprintf(cmdline, "(%1u,%1u)", file2, rank2);
    }

    return cmdline;
}

#ifdef ENDGAME_LEARNING
bool AIAlgorithm::findEndgameHash(key_t posKey, Endgame &endgame)
{
    return endgameHashMap.find(posKey, endgame);
}

int AIAlgorithm::recordEndgameHash(key_t posKey, const Endgame &endgame)
{
    //hashMapMutex.lock();
    key_t hashValue = endgameHashMap.insert(posKey, endgame);
    unsigned addr = hashValue * (sizeof(posKey) + sizeof(endgame));
    //hashMapMutex.unlock();

    loggerDebug("[endgame] Record 0x%08I32x (%d) to Endgame Hash map, TTEntry: 0x%08I32x, Address: 0x%08I32x\n", posKey, endgame.type, hashValue, addr);

    return 0;
}

void AIAlgorithm::clearEndgameHashMap()
{
    //hashMapMutex.lock();
    endgameHashMap.clear();
    //hashMapMutex.unlock();
}

void AIAlgorithm::recordEndgameHashMapToFile()
{
    const QString filename = "endgame.txt";
    endgameHashMap.dump(filename);

    loggerDebug("[endgame] Dump hash map to file\n");
}

void AIAlgorithm::loadEndgameFileToHashMap()
{
    const QString filename = "endgame.txt";
    endgameHashMap.load(filename);
}
#endif // ENDGAME_LEARNING
