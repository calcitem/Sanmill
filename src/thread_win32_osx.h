// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// thread_win32_osx.h

#ifndef THREAD_WIN32_OSX_H_INCLUDED
#define THREAD_WIN32_OSX_H_INCLUDED

#include <thread>
#include <utility>

/// On OSX threads other than the main thread are created with a reduced stack
/// size of 512KB by default, this is too low for deep searches, which require
/// somewhat more than 1MB stack, so adjust it to TH_STACK_SIZE.
/// The implementation calls pthread_create() with the stack size parameter
/// equal to the linux 8MB default, on platforms that support it.

#if defined(__APPLE__) || defined(__MINGW32__) || defined(__MINGW64__) || \
    defined(USE_PTHREADS)

#include <pthread.h>

static const size_t TH_STACK_SIZE = 8 * 1024 * 1024;

template <class T, class P = std::pair<T *, void (T::*)()>>
void *start_routine(void *ptr)
{
    P *p = reinterpret_cast<P *>(ptr);
    (p->first->*(p->second))(); // Call member function pointer
    delete p;
    return NULL;
}

class NativeThread
{
    pthread_t thread;

public:
    template <class T, class P = std::pair<T *, void (T::*)()>>
    explicit NativeThread(void (T::*fun)(), T *obj)
    {
        pthread_attr_t attr_storage, *attr = &attr_storage;
        pthread_attr_init(attr);
        pthread_attr_setstacksize(attr, TH_STACK_SIZE);
        pthread_create(&thread, attr, start_routine<T>, new P(obj, fun));
    }
    void join() { pthread_join(thread, NULL); }
};

#else // Default case: use STL classes

using NativeThread = std::thread;

#endif

#endif // #ifndef THREAD_WIN32_OSX_H_INCLUDED
