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

#ifndef ENDGAME_H
#define ENDGAME_H

#include "config.h"

#ifdef ENDGAME_LEARNING

#include <vector>

#include "types.h"
#include "hashmap.h"

using namespace std;
using namespace CTSL;

enum endgame_t : uint8_t
{
    ENDGAME_NONE,
    ENDGAME_PLAYER_BLACK_WIN,
    ENDGAME_PLAYER_WHITE_WIN,
    ENDGAME_DRAW,
};

//#pragma pack (push, 1)  
struct Endgame
{
    endgame_t type;
};
//#pragma pack(pop)  

extern HashMap<hash_t, Endgame> endgameHashMap;

#endif // ENDGAME_LEARNING

#endif // ENDGAME_H
