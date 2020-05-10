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

//#define MOBILE_APP_UI

//#define TRAINING_MODE

//#define TEST_MODE

//#define UCT_DEMO

#define ALPHABETA_AI
//#define PVS_AI
#define MTDF_AI
//#define MCTS_AI

//#define MCTS_PLD

#ifdef TEST_MODE
#define DONOT_PLAY_SOUND
#endif // TEST_MODE

//#define DEBUG_MODE
//#define DEBUG_MODE_A

#ifdef DEBUG_MODE_A
#define DONOT_PLAY_SOUND
#else
#define RANDOM_MOVE
#endif

#define DEFAULT_RULE_NUMBER 1

#define DEPTH_ADJUST (0)
//#define FIX_DEPTH   (24)

//#define NULL_MOVE

//#define FIRST_MOVE_STAR_PREFERRED

//#define TIME_STAT
//#define CYCLE_STAT

//#define EVALUATE_ENABLE

#ifdef EVALUATE_ENABLE
//#define EVALUATE_MATERIAL
//#define EVALUATE_SPACE
#define EVALUATE_MOBILITY
//#define EVALUATE_TEMPO
//#define EVALUATE_THREAT
//#define EVALUATE_SHAPE
//#define EVALUATE_MOTIF
#endif /* EVALUATE_ENABLE */

#define SORT_MOVE_WITH_HUMAN_KNOWLEDGES

//#define IDS_WINDOW

#define TRANSPOSITION_TABLE_ENABLE

#ifdef TRANSPOSITION_TABLE_ENABLE
#define CLEAR_TRANSPOSITION_TABLE
#define TRANSPOSITION_TABLE_FAKE_CLEAN
//#define TRANSPOSITION_TABLE_CUTDOWN
//#define TT_MOVE_ENABLE
//#define TRANSPOSITION_TABLE_DEBUG
#endif

//WIP
//#define HOSTORY_HEURISTIC

#ifdef HOSTORY_HEURISTIC
#define HOSTORY_HEURISTIC_ACTION_MOVE_ONLY
//#define HOSTORY_HEURISTIC_SCORE_HIGH_WHEN_DEEPER
#endif

#ifdef HOSTORY_HEURISTIC
//#define COMPARE_SCORE_ONLY
//#define COMPARE_RATING_PREFERRED
#define COMPARE_SCORE_PREFERRED
#else
#define COMPARE_RATING_ONLY
//#define COMPARE_RATING_1ST_VALUE_2ND
//#define COMPARE_VALUE_1ST_RATING_2ND
#endif // HOSTORY_HEURISTIC

#define PREFETCH_SUPPORT

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

// 摆棋阶段在叉下面显示被吃的子
//#define GAME_PLACING_SHOW_REMOVED_PIECES

// 启动时窗口最大化
//#define SHOW_MAXIMIZED_ON_LOAD

// 不使用哈希桶
#define DISABLE_HASHBUCKET
// 哈希表不加锁
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

#endif // CONFIG_H