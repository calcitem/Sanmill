// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#ifndef ENDGAME_H_INCLUDED
#define ENDGAME_H_INCLUDED

#include "config.h"

#ifdef ENDGAME_LEARNING

#include "hashmap.h"
#include "types.h"

using CTSL::HashMap;

static const int SAVE_ENDGAME_EVERY_N_GAMES = 256;

enum class EndGameType : uint32_t {
    none,
    whiteWin,
    blackWin,
    draw,
};

struct Endgame
{
    EndGameType type;
};

extern HashMap<Key, Endgame> endgameHashMap;

#endif // ENDGAME_LEARNING

#endif // #ifndef ENDGAME_H_INCLUDED
