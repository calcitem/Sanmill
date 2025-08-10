// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

// Ensure project global config is visible as required
#include "../../include/config.h"

#ifdef _WIN32
#  define PD_API __declspec(dllexport)
#else
#  define PD_API
#endif

extern "C" {

// 初始化标准九子棋 Perfect DB（std, 9 子）
// db_path: 包含 std_*.sec2 与 std.secval 的目录
// 返回 1 表示成功，0 表示失败
PD_API int pd_init_std(const char* db_path);

// 反初始化并释放资源
PD_API void pd_deinit();

// 使用 Perfect DB 评估一个局面
// 输入:
//  - whiteBits, blackBits: 24 位位板（第 i 位对应 perfect 索引 i）
//  - whiteStonesToPlace, blackStonesToPlace: 手中剩余待落子数
//  - playerToMove: 0=白走, 1=黑走
//  - onlyStoneTaking: 非 0 表示处于吃子子阶段
// 输出:
//  - outWdl: 1=胜, 0=和, -1=负
//  - outSteps: 到达结果的步数，未知为 -1
// 返回 1 表示成功（数据库有效），否则 0
PD_API int pd_evaluate(int whiteBits,
                       int blackBits,
                       int whiteStonesToPlace,
                       int blackStonesToPlace,
                       int playerToMove,
                       int onlyStoneTaking,
                       int* outWdl,
                       int* outSteps);

// 查询一个最佳着法，返回引擎风格的 token 字符串
// 输出格式: "a1"（落子）、"a1-a4"（走子）、"xg7"（吃子）
// 返回 1 表示成功，0 表示失败
PD_API int pd_best_move(int whiteBits,
                        int blackBits,
                        int whiteStonesToPlace,
                        int blackStonesToPlace,
                        int playerToMove,
                        int onlyStoneTaking,
                        char* outBuf,
                        int outBufLen);

}


