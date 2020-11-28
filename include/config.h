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

#ifndef CONFIG_H
#define CONFIG_H

#include "debug.h"

#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

//#undef QT_GUI_LIB

//#define DISABLE_RANDOM_MOVE
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

//#define MOBILE_APP_UI

//#define TRAINING_MODE

//#define TEST_MODE

//#define UCT_DEMO

//#define PVS_AI
#define MTDF_AI

#ifdef TEST_MODE
#define DONOT_PLAY_SOUND
#endif // TEST_MODE

//#define DEBUG_MODE

#define DEFAULT_RULE_NUMBER 1

#define DEPTH_ADJUST (0)
//#define FIX_DEPTH   (24)

//#define NULL_MOVE

//#define FIRST_MOVE_STAR_PREFERRED

//#define TIME_STAT
//#define CYCLE_STAT

//#define SORT_MOVE_WITHOUT_HUMAN_KNOWLEDGES

#define TRANSPOSITION_TABLE_ENABLE

#ifdef TRANSPOSITION_TABLE_ENABLE
#define CLEAR_TRANSPOSITION_TABLE
#define TRANSPOSITION_TABLE_FAKE_CLEAN
//#define TRANSPOSITION_TABLE_FAKE_CLEAN_NOT_EXACT_ONLY
//#define TRANSPOSITION_TABLE_CUTDOWN
//#define TT_MOVE_ENABLE
//#define TRANSPOSITION_TABLE_DEBUG
#endif

//#define DISABLE_PREFETCH

// WIP, Debugging only
//#define OPENING_BOOK

//#define ENDGAME_LEARNING
//#define ENDGAME_LEARNING_FORCE
//#define ENDGAME_LEARNING_DEBUG

#define THREEFOLD_REPETITION

//#define MESSAGEBOX_ENABLE

#ifdef DEBUG_MODE
#define DONOT_PLAY_SOUND
#endif

//#define DONOT_PLAY_SOUND

#ifdef DEBUG_MODE
#define PLAYER_DRAW_SEAT_NUMBER
#endif

#ifndef MOBILE_APP_UI
#define SAVE_GAMEBOOK_WHEN_ACTION_NEW_TRIGGERED
#endif

//#define DONOT_PLAY_WIN_SOUND

//#define GAME_PLACING_SHOW_REMOVED_PIECES

//#define SHOW_MAXIMIZED_ON_LOAD

#define DISABLE_HASHBUCKET

#define HASHMAP_NOLOCK

#ifdef WIN32
#define sscanf sscanf_s
#define sprintf sprintf_s
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
