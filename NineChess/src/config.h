#ifndef CONFIG_H
#define CONFIG_H

#define DEBUG

#ifndef DEBUG
#define PLAY_SOUND
#endif

#ifdef DEBUG
#define AB_RANDOM_SORT_CHILDREN
#define DEBUG_AB_TREE
#define SAVE_CHESSBOOK_WHEN_ACTION_NEW_TRIGGERED
#endif

#ifndef DEBUG
#define GAME_PLACING_DYNAMIC_DEPTH
#endif

#ifdef DEBUG
#define GAME_PLACING_FIXED_DEPTH  3
#endif

#ifdef DEBUG
#define GAME_MOVING_FIXED_DEPTH  3
#else
#define GAME_MOVING_FIXED_DEPTH  10
#endif

#ifdef DEBUG
#define DRAW_SEAT_NUMBER
#endif

// 摆棋阶段在叉下面显示被吃的子
#define GAME_PLACING_SHOW_CAPTURED_PIECES

// 启动时窗口最大化
//#define SHOW_MAXIMIZED_ON_LOAD

#endif // CONFIG_H