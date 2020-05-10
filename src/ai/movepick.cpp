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

#include "movepick.h"
#include "option.h"
#include "types.h"
#include "config.h"

// partial_insertion_sort() sorts moves in descending order up to and including
// a given limit. The order of moves smaller than the limit is left unspecified.
void partial_insertion_sort(ExtMove *begin, ExtMove *end, int limit)
{
    for (ExtMove *sortedEnd = begin, *p = begin + 1; p < end; ++p)
        if (p->value >= limit) {
            ExtMove tmp = *p, *q;
            *p = *++sortedEnd;
            for (q = sortedEnd; q != begin && *(q - 1) < tmp; --q)
                *q = *(q - 1);
            *q = tmp;
        }
}

MovePicker::MovePicker(Position *pos, ExtMove *extMove)
{
    position = pos;
    cur = extMove;

#ifdef HOSTORY_HEURISTIC
    clearHistoryScore();
#endif
}

void MovePicker::score()
{
    while (cur++->move != MOVE_NONE) {
        move_t m = cur->move;

        square_t sq = to_sq(m);
        square_t sqsrc = from_sq(m);

#if 0
        if (m > 0) {
            if (m & 0x1f00) {
                // 走子
                sqsrc = static_cast<square_t>(m >> 8);
            }

            // 摆子或走子
            sq = static_cast<square_t>(m & 0x00ff);
        } else {
            // 吃子
            sq = static_cast<square_t>((-m) & 0x00ff);
        }
#endif

        // 若为走子之前的统计故走棋阶段可能会从 @-0-@ 走成 0-@-@, 并未成三，所以需要传值 sqsrc 进行判断
        int nMills = position->board.inHowManyMills(sq, position->sideToMove, sqsrc);
        int nopponentMills = 0;

    #ifdef SORT_MOVE_WITH_HUMAN_KNOWLEDGES
        // TODO: rule.allowRemoveMultiPieces 以及 适配打三棋之外的其他规则
        if (m > 0) {
            // 在任何阶段, 都检测落子点是否能使得本方成三
            if (nMills > 0) {
    #ifdef ALPHABETA_AI
                cur->rating += static_cast<rating_t>(RATING_ONE_MILL * nMills);
    #endif
            } else if (position->getPhase() == PHASE_PLACING) {
                // 在摆棋阶段, 检测落子点是否能阻止对方成三
                nopponentMills = position->board.inHowManyMills(sq, position->opponent);
    #ifdef ALPHABETA_AI
                cur->rating += static_cast<rating_t>(RATING_BLOCK_ONE_MILL * nopponentMills);
    #endif
            }
    #if 1
            else if (position->getPhase() == PHASE_MOVING) {
                // 在走棋阶段, 检测落子点是否能阻止对方成三
                nopponentMills = position->board.inHowManyMills(sq, position->opponent);

                if (nopponentMills) {
                    int nPlayerPiece = 0;
                    int nOpponentPiece = 0;
                    int nForbidden = 0;
                    int nEmpty = 0;

                    position->board.getSurroundedPieceCount(sq, position->sideId,
                                                            nPlayerPiece, nOpponentPiece, nForbidden, nEmpty);

    #ifdef ALPHABETA_AI
                    if (sq % 2 == 0 && nOpponentPiece == 3) {
                        cur->rating += static_cast<rating_t>(RATING_BLOCK_ONE_MILL * nopponentMills);
                    } else if (sq % 2 == 1 && nOpponentPiece == 2 && rule.nTotalPiecesEachSide == 12) {
                        cur->rating += static_cast<rating_t>(RATING_BLOCK_ONE_MILL * nopponentMills);
                    }
    #endif
                }
            }
    #endif

            //newNode->rating += static_cast<rating_t>(nForbidden);  // 摆子阶段尽量往禁点旁边落子

            // 对于12子棋, 白方第2着走星点的重要性和成三一样重要 (TODO)
    #ifdef ALPHABETA_AI
            if (rule.nTotalPiecesEachSide == 12 &&
                position->getPiecesOnBoardCount(2) < 2 &&    // patch: 仅当白方第2着时
                Board::isStar(static_cast<square_t>(m))) {
                cur->rating += RATING_STAR_SQUARE;
            }
    #endif
        } else if (m < 0) {
            int nPlayerPiece = 0;
            int nOpponentPiece = 0;
            int nForbidden = 0;
            int nEmpty = 0;

            position->board.getSurroundedPieceCount(sq, position->sideId,
                                                    nPlayerPiece, nOpponentPiece, nForbidden, nEmpty);

    #ifdef ALPHABETA_AI
            if (nMills > 0) {
                // 吃子点处于我方的三连中
                //newNode->rating += static_cast<rating_t>(RATING_CAPTURE_ONE_MILL * nMills);

                if (nOpponentPiece == 0) {
                    // 吃子点旁边没有对方棋子则优先考虑     
                    cur->rating += static_cast<rating_t>(1);
                    if (nPlayerPiece > 0) {
                        // 且吃子点旁边有我方棋子则更优先考虑
                        cur->rating += static_cast<rating_t>(nPlayerPiece);
                    }
                }
            }

            // 吃子点处于对方的三连中
            nopponentMills = position->board.inHowManyMills(sq, position->opponent);
            if (nopponentMills) {
                if (nOpponentPiece >= 2) {
                    // 旁边对方的子较多, 则倾向不吃
                    cur->rating -= static_cast<rating_t>(nOpponentPiece);

                    if (nPlayerPiece == 0) {
                        // 如果旁边无我方棋子, 则更倾向不吃
                        cur->rating -= static_cast<rating_t>(1);
                    }
                }
            }

            // 优先吃活动力强的棋子
            cur->rating += static_cast<rating_t>(nEmpty);
    #endif
        }
    #endif // SORT_MOVE_WITH_HUMAN_KNOWLEDGES
        }
}

#ifdef HOSTORY_HEURISTIC
score_t MovePicker::getHistoryScore(move_t move)
{
    score_t ret = 0;

    if (move < 0) {
#ifndef HOSTORY_HEURISTIC_ACTION_MOVE_ONLY
        ret = placeHistory[-move];
#endif
    } else if (move & 0x7f00) {
        ret = moveHistory[move];
    } else {
#ifndef HOSTORY_HEURISTIC_ACTION_MOVE_ONLY
        ret = placeHistory[move];
#endif
    }

    return ret;
}

void MovePicker::setHistoryScore(move_t move, depth_t depth)
{
    if (move == MOVE_NONE) {
        return;
    }

#ifdef HOSTORY_HEURISTIC_SCORE_HIGH_WHEN_DEEPER
    score_t score = 1 << (32 - depth);
#else
    score_t score = 1 << depth;
#endif

    if (move < 0) {
#ifndef HOSTORY_HEURISTIC_ACTION_MOVE_ONLY
        placeHistory[-move] += score;
#endif
    } else if (move & 0x7f00) {
        moveHistory[move] += score;
    } else {
#ifndef HOSTORY_HEURISTIC_ACTION_MOVE_ONLY
        moveHistory[move] += score;
#endif
    }
}

void MovePicker::clearHistoryScore()
{
#ifndef HOSTORY_HEURISTIC_ACTION_MOVE_ONLY
    memset(placeHistory, 0, sizeof(placeHistory));
    memset(captureHistory, 0, sizeof(captureHistory));
#endif
    memset(moveHistory, 0, sizeof(moveHistory));
}
#endif // HOSTORY_HEURISTIC
