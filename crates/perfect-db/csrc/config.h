// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2019-2026 The Sanmill developers (see AUTHORS file)

// config.h

#ifndef INCLUDE_CONFIG_H_
#define INCLUDE_CONFIG_H_

#include "debug.h"

#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

/// In UCI, do move when the opponent has done moving, usually for the test.
// #define UCI_AUTO_RE_GO

/// In UCI, restart the game when the game is over, usually for the test.
// #define UCI_AUTO_RESTART

/// In UCI, AI will do the best move when the best move is searched.
// #define UCI_DO_BEST_MOVE

/// Print position analysis information.
#define ANALYZE_POSITION

/// FLUTTER_UI is defined by CMakeList.txt of flutter_app.
#ifdef FLUTTER_UI
#undef ANALYZE_POSITION
#endif

#ifdef UCI_AUTO_RESTART
#define UCI_AUTO_RE_GO
#endif

// Play via network.
// #define NET_FIGHT_SUPPORT

// #define UCT_DEMO

#ifndef DISABLE_PERFECT_AI
#define GABOR_MALOM_PERFECT_AI
#endif

// #define NNUE_GENERATE_TRAINING_DATA

#ifdef _DEBUG
#define DEBUG_MODE
#endif

constexpr auto DEFAULT_RULE_NUMBER = 0;

constexpr auto DEPTH_ADJUST = 0;

#ifdef DEBUG
#ifndef FLUTTER_UI
#define TIME_STAT
#endif
// #define CYCLE_STAT
#endif

// #define SORT_MOVE_WITHOUT_HUMAN_KNOWLEDGE

#define TRANSPOSITION_TABLE_ENABLE

#ifdef TRANSPOSITION_TABLE_ENABLE
#define CLEAR_TRANSPOSITION_TABLE
#define TRANSPOSITION_TABLE_FAKE_CLEAN
// #define TRANSPOSITION_TABLE_FAKE_CLEAN_NOT_EXACT_ONLY
// #define TRANSPOSITION_TABLE_64BIT_KEY
// #define TT_MOVE_ENABLE
// #define TRANSPOSITION_TABLE_DEBUG
#endif

// #define DISABLE_PREFETCH

// #define BITBOARD_DEBUG
#ifndef USE_POPCNT
#define USE_POPCNT
#endif

#ifndef USE_POPCNT
#define DO_NOT_USE_POPCNT
#endif

/// Opening book (WIP)
// #define OPENING_BOOK

/// Endgame learning (WIP)
// #define ENDGAME_LEARNING
// #define ENDGAME_LEARNING_FORCE

/// The game is drawn if there has been no removal
/// in a specific number of moves.
#define RULE_50

// #define MESSAGE_BOX_ENABLE

#ifdef DEBUG_MODE
// #define DO_NOT_PLAY_SOUND
#endif

#ifdef DEBUG_MODE
#define DRAW_POLAR_COORDINATES
#endif

#define SAVE_GAME_BOOK_WHEN_ACTION_NEW_TRIGGERED

// #define DO_NOT_PLAY_WIN_SOUND

// #define GAME_PLACING_SHOW_REMOVED_PIECES

// #define SHOW_MAXIMIZED_ON_LOAD

#define DISABLE_HASHBUCKET

#define HASHMAP_NOLOCK

// #define ALIGNED_LARGE_PAGES

#ifndef __GNUC__
#define __builtin_expect(expr, n) (expr)
#endif

#define likely(expr) (__builtin_expect(!!(expr), 1))
#define unlikely(expr) (__builtin_expect(!!(expr), 0))

#ifdef _MSC_VER
#define sscanf sscanf_s
#endif

#ifdef FLUTTER_UI
#include "base.h"
#endif

// #define ENABLE_BENCHMARK

#endif // INCLUDE_CONFIG_H_
