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

#ifndef PLAYER_H
#define PLAYER_H

#include <string>

#include "config.h"
#include "types.h"

class Player
{
public:
    explicit Player();
    virtual ~Player();

    Color getColor() const
    {
        return color;
    }

    inline static char colorToCh(Color color)
    {
        return static_cast<char>('0' + color);
    }

    inline static std::string chToStr(char ch)
    {
        if (ch == '1') {
            return "1";
        } else {
            return "2";
        }
    }

    inline static Color getOpponent(Color c)
    {
        return c == BLACK ? WHITE : BLACK;
    }

private:
    Color color;
};

#endif // PLAYER_H
