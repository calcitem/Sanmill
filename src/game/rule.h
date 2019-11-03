/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019 Calcitem <calcitem@outlook.com>

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

#ifndef RULE_H
#define RULE_H

#include "types.h"

struct Rule
{
    // 规则名称
    const char *name;

    // 规则介绍
    const char *description;

    // 任一方子数，各9子或各12子
    int nTotalPiecesEachSide;

    // 赛点子数，少于则判负
    int nPiecesAtLeast;

    // 是否有斜线
    bool hasObliqueLines;

    // 是否有禁点（摆棋阶段被提子的点不能再摆子）
    bool hasForbiddenLocations;

    // 是否后摆棋者先行棋
    bool isDefenderMoveFirst;

    // 相同顺序和位置的重复“三连”是否可反复提子
    bool allowRemovePiecesRepeatedly;

    // 多个“三连”能否多提子
    bool allowRemoveMultiPieces;

    // 能否提“三连”的子
    bool allowRemoveMill;

    // 摆棋满子（闷棋，只有12子棋才出现），是否算先手负，false为和棋
    bool isStartingPlayerLoseWhenBoardFull;

    // 走棋阶段不能行动（被“闷”）是否算负，false则轮空（由对手走棋）
    bool isLoseWhenNoWay;

    // 剩三子时是否可以飞棋
    bool allowFlyWhenRemainThreePieces;

    // 最大步数，超出判和
    step_t maxStepsLedToDraw;

    // 包干最长时间（秒），超出判负，为0则不计时
    int maxTimeLedToLose;
};

// 预定义的规则数目
#define N_RULES 5

// 预定义的规则
extern const struct Rule RULES[N_RULES];

// 当前规则
extern struct Rule rule;

#endif /* RULE_H */

