/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include "rule.h"
#include "types.h"

 // 当前使用的规则
struct Rule currentRule;

// 对静态常量数组的定义要放在类外，不要放在头文件
// 预定义的4套规则
const struct Rule RULES[N_RULES] = {
    {
        "成三棋",   // 成三棋
        // 规则说明
        "1. 双方各9颗子，开局依次摆子；\n"
        "2. 凡出现三子相连，就提掉对手一子；\n"
        "3. 不能提对手的“三连”子，除非无子可提；\n"
        "4. 同时出现两个“三连”只能提一子；\n"
        "5. 摆完后依次走子，每次只能往相邻位置走一步；\n"
        "6. 把对手棋子提到少于3颗时胜利；\n"
        "7. 走棋阶段不能行动（被“闷”）算负。",
        9,          // 双方各9子
        3,          // 赛点子数为3
        false,      // 没有斜线
        false,      // 没有禁点，摆棋阶段被提子的点可以再摆子
        false,      // 先摆棋者先行棋
        true,       // 可以重复成三
        false,      // 多个“三连”只能提一子
        false,      // 不能提对手的“三连”子，除非无子可提；
        true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
        true,       // 走棋阶段不能行动（被“闷”）算负
        false,      // 剩三子时不可以飞棋
        0,          // 不计步数
        0           // 不计时
    },
    {
        "打三棋(12连棋)",           // 打三棋
        // 规则说明
        "1. 双方各12颗子，棋盘有斜线；\n"
        "2. 摆棋阶段被提子的位置不能再摆子，直到走棋阶段；\n"
        "3. 摆棋阶段，摆满棋盘算先手负；\n"
        "4. 走棋阶段，后摆棋的一方先走；\n"
        "5. 同时出现两个“三连”只能提一子；\n"
        "6. 其它规则与成三棋基本相同。",
        12,          // 双方各12子
        3,          // 赛点子数为3
        true,       // 有斜线
        true,       // 有禁点，摆棋阶段被提子的点不能再摆子
        true,       // 后摆棋者先行棋
        true,       // 可以重复成三
        false,      // 多个“三连”只能提一子
        true,       // 可以提对手的“三连”子
        true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
        true,       // 走棋阶段不能行动（被“闷”）算负
        false,      // 剩三子时不可以飞棋
        50,          // 不计步数
        0           // 不计时
    },
    {
        "九连棋",   // 九连棋
        // 规则说明
        "1. 规则与成三棋基本相同，只是它的棋子有序号，\n"
        "2. 相同序号、位置的“三连”不能重复提子；\n"
        "3. 走棋阶段不能行动（被“闷”），则由对手继续走棋；\n"
        "4. 一步出现几个“三连”就可以提几个子。",
        9,          // 双方各9子
        3,          // 赛点子数为3
        false,      // 没有斜线
        false,      // 没有禁点，摆棋阶段被提子的点可以再摆子
        false,      // 先摆棋者先行棋
        false,      // 不可以重复成三
        true,       // 出现几个“三连”就可以提几个子
        false,      // 不能提对手的“三连”子，除非无子可提；
        true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
        false,      // 走棋阶段不能行动（被“闷”），则由对手继续走棋
        false,      // 剩三子时不可以飞棋
        0,          // 不计步数
        0           // 不计时
    },
    {
        "莫里斯九子棋",      // 莫里斯九子棋
        // 规则说明
        "规则与成三棋基本相同，只是在走子阶段，当一方仅剩3子时，他可以飞子到任意空位。",
        9,          // 双方各9子
        3,          // 赛点子数为3
        false,      // 没有斜线
        false,      // 没有禁点，摆棋阶段被提子的点可以再摆子
        false,      // 先摆棋者先行棋
        true,       // 可以重复成三
        false,      // 多个“三连”只能提一子
        false,      // 不能提对手的“三连”子，除非无子可提；
        true,       // 摆棋满子（闷棋，只有12子棋才出现）算先手负
        true,       // 走棋阶段不能行动（被“闷”）算负
        true,       // 剩三子时可以飞棋
        0,          // 不计步数
        0           // 不计时
    }
};
