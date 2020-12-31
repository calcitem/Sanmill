/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

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

#ifndef ENDGAME_H_INCLUDED
#define ENDGAME_H_INCLUDED

#include "config.h"

#ifdef ENDGAME_LEARNING

#include <vector>

#include "types.h"
#include "hashmap.h"

using namespace std;
using namespace CTSL;

// TODO: uint8_t
enum endgame_t : uint32_t
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

extern HashMap<Key, Endgame> endgameHashMap;

#endif // ENDGAME_LEARNING

#endif // #ifndef ENDGAME_H_INCLUDED
