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

#define CONST_MOVE_TABLE
#define CONST_MILL_TABLE

//#define DEAL_WITH_HORIZON_EFFECT

#define IDS_SUPPORT

//define DEEPER_IF_ONLY_ONE_LEGAL_MOVE

#define HASH_MAP_ENABLE

#ifdef HASH_MAP_ENABLE
#define CLEAR_HASH_MAP
#define HASH_MAP_CUTDOWN
//#define HASH_MAP_DEBUG
#endif

#define MEMORY_POOL

//#define RAPID_GAME

//#define BOOK_LEARNING

#define THREEFOLD_REPETITION

//#define DONOT_DELETE_TREE

#define SORT_CONSIDER_PRUNED

//#define MESSAGEBOX_ENABLE

#ifdef DEBUG_MODE
#define DONOT_PLAY_SOUND
#define DEBUG_AB_TREE
#endif

//#define DONOT_PLAY_SOUND

#ifdef DEBUG_MODE
#define GAME_PLACING_FIXED_DEPTH  3
#endif

#ifdef DEBUG_MODE
#define GAME_MOVING_FIXED_DEPTH  3
#else // DEBUG
#ifdef DEAL_WITH_HORIZON_EFFECT
#ifdef HASH_MAP_ENABLE
#define GAME_MOVING_FIXED_DEPTH 9
#else
#define GAME_MOVING_FIXED_DEPTH 9
#endif // HASH_MAP_ENABLE
#else // DEAL_WITH_HORIZON_EFFECT
#ifdef HASH_MAP_ENABLE
#define GAME_MOVING_FIXED_DEPTH  11
#else
#define GAME_MOVING_FIXED_DEPTH  10
#endif
#endif // DEAL_WITH_HORIZON_EFFECT
#endif // DEBUG

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

#ifdef WIN32
#define sscanf sscanf_s
#define sprintf sprintf_s
#endif

#endif // CONFIG_H
