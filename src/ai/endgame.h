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
