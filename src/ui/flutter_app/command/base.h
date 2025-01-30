// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// base.h

#ifndef BASE2_H
#define BASE2_H

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>
#endif // _WIN32

#include <string.h>

#ifdef __ANDROID__
#include <android/log.h>
#endif // __ANDROID__

#ifdef _WIN32
inline void Idle(void)
{
    Sleep(1);
}
#else
inline void Idle(void)
{
    usleep(1000);
}
#endif // _WIN32

#define LOG_logTag "MillEngine"

#ifdef __ANDROID__
#define LOGD(...) \
    __android_log_print(ANDROID_LOG_DEBUG, LOG_logTag, __VA_ARGS__)
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_logTag, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_logTag, __VA_ARGS__)
#define LOGE(...) \
    __android_log_print(ANDROID_LOG_ERROR, LOG_logTag, __VA_ARGS__)
#define LOGF(...) \
    __android_log_print(ANDROID_LOG_FATAL, LOG_logTag, __VA_ARGS__)
#else
#define LOGD(...) printf(__VA_ARGS__)
#define LOGI(...) printf(__VA_ARGS__)
#define LOGW(...) printf(__VA_ARGS__)
#define LOGE(...) printf(__VA_ARGS__)
#define LOGF(...) printf(__VA_ARGS__)
#endif // _WIN32

#endif // BASE2_H
