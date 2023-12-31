// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
