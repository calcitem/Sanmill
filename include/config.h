/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: Calcitem <calcitem@outlook.com>
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

#ifndef CONFIG_H
#define CONFIG_H

#include "debug.h"

#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

//#define MOBILE_APP_UI

//#define DEBUG_MODE
//#define DEBUG_MODE_A

#ifdef DEBUG_MODE_A
#define EMIT_COMMAND_DELAY (0)
#define DONOT_PLAY_SOUND
#else
#define RANDOM_MOVE
#define EMIT_COMMAND_DELAY (0)
#endif

//#define MIN_MAX_ONLY

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

//#define MILL_FIRST

//#define DEAL_WITH_HORIZON_EFFECT

#define IDS_SUPPORT

//define DEEPER_IF_ONLY_ONE_LEGAL_MOVE

#define TRANSPOSITION_TABLE_ENABLE

#ifdef TRANSPOSITION_TABLE_ENABLE
#define CLEAR_TRANSPOSITION_TABLE
#define TRANSPOSITION_TABLE_FAKE_CLEAN
#define TRANSPOSITION_TABLE_CUTDOWN
//#define TRANSPOSITION_TABLE_DEBUG
#endif

// TODO: Fix disable Memory Tool build failed
#define MEMORY_POOL

//#define USE_STD_STACK

//#define RAPID_GAME

#define ENDGAME_LEARNING

#define THREEFOLD_REPETITION

//#define DONOT_DELETE_TREE

#define SORT_CONSIDER_PRUNED

//#define MESSAGEBOX_ENABLE

#ifdef DEBUG_MODE
#define DONOT_PLAY_SOUND
#define DEBUG_AB_TREE
#endif

//#define DONOT_PLAY_SOUND

#ifndef DEBUG_MODE
#define GAME_PLACING_DYNAMIC_DEPTH
#endif

#ifdef DEBUG_MODE
#define PLAYER_DRAW_SEAT_NUMBER
#endif

#ifndef MOBILE_APP_UI
#define SAVE_GAMEBOOK_WHEN_ACTION_NEW_TRIGGERED
#endif

// #define DONOT_PLAY_WIN_SOUND

// 摆棋阶段在叉下面显示被吃的子
//#define GAME_PLACING_SHOW_CAPTURED_PIECES

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

#endif // CONFIG_H
