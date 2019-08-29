/*****************************************************************************
 * Copyright (C) 2018-2019 NineChess authors
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

// 定义绘图相关常量的头文件
#ifndef GRAPHICSCONST
#define GRAPHICSCONST

#include "config.h"

#ifdef MOBILE_APP_UI
const short BOARD_SIZE = 500;     // 棋盘大小
#else
const short BOARD_SIZE = 600;     // 棋盘大小
#endif /* MOBILE_APP_UI */

const short BOARD_MINISIZE = 150; // 最小宽高，即1/4大小
const short PIECE_SIZE = 56;      // 棋子大小
const short LINE_INTERVAL = 72;   // 线间距
const short LINE_WEIGHT = 3;      // 线宽

#endif // GRAPHICSCONST

