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

#ifndef LOCATION_H
#define LOCATION_H

#include "config.h"
#include "option.h"
#include "types.h"
#include "rule.h"

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
        assert(rule.hasForbiddenLocations == true);
        location = PIECE_FORBIDDEN;
    }

private:
};

#endif /* LOCATION_H */

