// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// endgame.h

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

// Declare the endgame hash map
extern HashMap<Key, Endgame> endgameHashMap;

// Function declarations for endgame operations
bool probeEndgameHash(Key key, Endgame &endgame);
int saveEndgameHash(Key key, const Endgame &endgame);
void clearEndgameHashMap();
void saveEndgameHashMapToFile();
void loadEndgameFileToHashMap();

#endif // ENDGAME_LEARNING

#endif // ENDGAME_H_INCLUDED
