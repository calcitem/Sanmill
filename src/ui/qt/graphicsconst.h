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

