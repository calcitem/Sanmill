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

#ifndef CONFIG_H
#define CONFIG_H

#include "debug.h"

#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

//#undef QT_GUI_LIB

//#define UCI_AUTO_RE_GO
//#define UCI_AUTO_RESTART
//#define UCI_DO_BEST_MOVE
#define ANALYZE_POSITION

#ifdef FLUTTER_UI
#undef QT_GUI_LIB
#undef ANALYZE_POSITION
#endif

#ifdef UCI_AUTO_RESTART
#define UCI_AUTO_RE_GO
#endif

#define NET_FIGHT_SUPPORT

/// Qt simple GUI like a mobile app (WIP)
//#define QT_MOBILE_APP_UI

//#define QT_UI_TEST_MODE

//#define UCT_DEMO

//#define PVS_AI
#define MTDF_AI

#ifndef DISABLE_PERFECT_AI
#ifdef _MSC_VER
#ifndef __clang__
//#define PERFECT_AI_SUPPORT
#endif
#ifdef PERFECT_AI_SUPPORT
#define MUEHLE_NMM
#endif
#endif
#endif

//#define PERFECT_AI_TEST

//#define DEBUG_MODE

#define DEFAULT_RULE_NUMBER 2

#define DEPTH_ADJUST (0)

//#define NULL_MOVE

//#define TIME_STAT
//#define CYCLE_STAT

//#define SORT_MOVE_WITHOUT_HUMAN_KNOWLEDGES

#define TRANSPOSITION_TABLE_ENABLE

#ifdef TRANSPOSITION_TABLE_ENABLE
#define CLEAR_TRANSPOSITION_TABLE
#define TRANSPOSITION_TABLE_FAKE_CLEAN
//#define TRANSPOSITION_TABLE_FAKE_CLEAN_NOT_EXACT_ONLY
//#define TRANSPOSITION_TABLE_64BIT_KEY
//#define TT_MOVE_ENABLE
//#define TRANSPOSITION_TABLE_DEBUG
#endif

//#define DISABLE_PREFETCH

//#define BITBOARD_DEBUG
#ifndef USE_POPCNT
#define USE_POPCNT
#endif

#ifndef USE_POPCNT
#define DONOT_USE_POPCNT
#endif

// WIP, Debugging only
//#define OPENING_BOOK

//#define ENDGAME_LEARNING
//#define ENDGAME_LEARNING_FORCE

#define THREEFOLD_REPETITION
#define RULE_50

//#define MESSAGEBOX_ENABLE

#ifdef DEBUG_MODE
#define DONOT_PLAY_SOUND
#endif

//#define DONOT_PLAY_SOUND

#ifdef DEBUG_MODE
#define PLAYER_DRAW_SEAT_NUMBER
#endif

#ifndef QT_MOBILE_APP_UI
#define SAVE_GAMEBOOK_WHEN_ACTION_NEW_TRIGGERED
#endif

//#define DONOT_PLAY_WIN_SOUND

//#define GAME_PLACING_SHOW_REMOVED_PIECES

//#define SHOW_MAXIMIZED_ON_LOAD

#define DISABLE_HASHBUCKET

#define HASHMAP_NOLOCK

//#define ALIGNED_LARGE_PAGES

#ifdef WIN32
#pragma warning(disable: 4996)
#endif

#ifndef  __GNUC__
#define __builtin_expect(expr, n)    (expr)
#endif

#define likely(expr)    (__builtin_expect(!!(expr), 1))
#define unlikely(expr)  (__builtin_expect(!!(expr), 0))

#ifdef FLUTTER_UI
#include "base.h"
#endif // FLUTTER_UI

#endif // CONFIG_H
