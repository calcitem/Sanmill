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

#ifndef LOCATION_H
#define LOCATION_H

#include "config.h"
#include "option.h"
#include "types.h"

 // 棋局，抽象为一个（5×8）的数组，上下两行留空
 /*
     0x00 代表无棋子
     0x0F 代表禁点
     0x11～0x1C 代表先手第 1～12 子
     0x21～0x2C 代表后手第 1～12 子
     判断棋子是先手的用 (locations[i] & 0x10)
     判断棋子是后手的用 (locations[i] & 0x20)
  */

class Location
{
public:
    Location();
    ~Location();

    Location & operator=(const Location &);

    inline static void setForbiden(location_t &location)
    {
        location = FLAG_FORBIDDEN;
    }

private:
    static const location_t FLAG_FORBIDDEN = 0x0F;
    static const location_t FLAG_PLAYER_BLACK = 0x10;
    static const location_t FLAG_PLAYER_WHITE = 0x20;
};

#endif /* LOCATION_H */

