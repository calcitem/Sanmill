/*********************************************************************
    threadManager.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "threadManager.h"

//-----------------------------------------------------------------------------
// ThreadManager()
// ThreadManager class constructor
//-----------------------------------------------------------------------------
ThreadManager::ThreadManager()
{
    // locals
    uint32_t th;
    SYSTEM_INFO m_si = {0};

    GetSystemInfo(&m_si);

    // init default values
    execPaused = false;
    execCancelled = false;
    threadCount = m_si.dwNumberOfProcessors;
    hThread = new HANDLE[threadCount];
    threadId = new DWORD[threadCount];
    hBarrier = new HANDLE[threadCount];
    threadPassedBarrierCount = 0;
    termineAllThreads = false;

    InitializeCriticalSection(&csBarrier);
    hEventBarrierPassedByEverybody = CreateEvent(nullptr, true, false, nullptr);

    for (th = 0; th < threadCount; th++) {
        hThread[th] = nullptr;
        threadId[th] = 0;
        hBarrier[th] = CreateEvent(nullptr, false, false, nullptr);
    }
}

//-----------------------------------------------------------------------------
// ~ThreadManager()
// ThreadManager class destructor
//-----------------------------------------------------------------------------
ThreadManager::~ThreadManager()
{
    // locals
    uint32_t th;

    for (th = 0; th < threadCount; th++) {
        CloseHandle(hBarrier[th]);
    }

    DeleteCriticalSection(&csBarrier);
    CloseHandle(hEventBarrierPassedByEverybody);

    if (hBarrier != nullptr)
        delete[] hBarrier;
    hBarrier = nullptr;

    if (hThread != nullptr)
        delete[] hThread;
    hThread = nullptr;

    if (threadId != nullptr)
        delete[] threadId;
    threadId = nullptr;
}

//-----------------------------------------------------------------------------
// waitForOtherThreads()
//
//-----------------------------------------------------------------------------
void ThreadManager::waitForOtherThreads(uint32_t threadNo)
{
    // wait if other threads are still waiting at the barrier

#if 0
    cout << endl
         << "thread=" << threadNo
         << ", threadPassedBarrierCount= " << threadPassedBarrierCount << ": "
         << "while (threadPassedBarrierCount>0)";
#endif

    if (threadPassedBarrierCount > 0) {
        WaitForSingleObject(hEventBarrierPassedByEverybody, INFINITE);
    }

    // a simple while (threadPassedBarrierCount>0) {}; does not work, since the
    // variable 'threadPassedBarrierCount' is not updated, due to compiler
    // optimizations

    // set signal that barrier is reached

#if 0
    cout << endl
         << "thread=" << threadNo
         << ", threadPassedBarrierCount= " << threadPassedBarrierCount << ": "
         << "SetEvent()";
#endif

    SetEvent(hBarrier[threadNo]);

    // enter the barrier one by one

#if 0
    cout << endl
         << "thread=" << threadNo
         << ", threadPassedBarrierCount= " << threadPassedBarrierCount << ": "
         << "EnterCriticalSection()";
#endif

    EnterCriticalSection(&csBarrier);

    // if the first one which entered, then wait until other threads
    if (threadPassedBarrierCount == 0) {
#if 0
        cout << endl
             << "thread=" << threadNo
             << ", threadPassedBarrierCount=
                " << threadPassedBarrierCount << "
            : " << " WaitForMultipleObjects() ";
#endif
        WaitForMultipleObjects(threadCount, hBarrier, TRUE, INFINITE);
        ResetEvent(hEventBarrierPassedByEverybody);
    }

// count threads which passed the barrier
#if 0
    cout << endl
         << "thread=" << threadNo
         << ", threadPassedBarrierCount= " << threadPassedBarrierCount << ": "
         << "threadPassedBarrierCount++";
#endif

    threadPassedBarrierCount++;

    // the last one closes the door
#if 0
    cout << endl
         << "thread=" << threadNo
         << ", threadPassedBarrierCount= " << threadPassedBarrierCount << ": "
         << "if (threadPassedBarrierCount == threadCount) "
            "threadPassedBarrierCount = 0";
#endif

    if (threadPassedBarrierCount == threadCount) {
        threadPassedBarrierCount = 0;
        SetEvent(hEventBarrierPassedByEverybody);
    }

#if 0
    cout << endl
         << "thread=" << threadNo
         << ", threadPassedBarrierCount= " << threadPassedBarrierCount << ": "
         << "LeaveCriticalSection()";
#endif

    LeaveCriticalSection(&csBarrier);
}

//-----------------------------------------------------------------------------
// getThreadCount()
//
//-----------------------------------------------------------------------------
uint32_t ThreadManager::getThreadCount()
{
    return threadCount;
}

//-----------------------------------------------------------------------------
// setThreadCount()
//
//-----------------------------------------------------------------------------
bool ThreadManager::setThreadCount(uint32_t newNumThreads)
{
    // cancel if any thread running
    EnterCriticalSection(&csBarrier);

    for (uint32_t th = 0; th < threadCount; th++) {
        if (hThread[th]) {
            LeaveCriticalSection(&csBarrier);
            return false;
        }
    }

    for (uint32_t th = 0; th < threadCount; th++) {
        CloseHandle(hBarrier[th]);
    }

    threadCount = newNumThreads;

    for (uint32_t th = 0; th < threadCount; th++) {
        hBarrier[th] = CreateEvent(nullptr, false, false, nullptr);
    }

    LeaveCriticalSection(&csBarrier);

    return true;
}

//-----------------------------------------------------------------------------
// pauseExec()
//
//-----------------------------------------------------------------------------
void ThreadManager::pauseExec()
{
    for (uint32_t th = 0; th < threadCount; th++) {
        // unsuspend all threads
        if (!execPaused) {
            SuspendThread(hThread[th]);
            // suspend all threads
        } else {
            ResumeThread(hThread[th]);
        }
    }

    execPaused = (!execPaused);
}

//-----------------------------------------------------------------------------
// cancelExec()
// Stops execParallelLoop() before the next iteration.
//     When execInParallel() was called, user has to handle cancellation by
//     himself.
//-----------------------------------------------------------------------------
void ThreadManager::cancelExec()
{
    termineAllThreads = true;
    execCancelled = true;

    if (execPaused) {
        pauseExec();
    }
}

//-----------------------------------------------------------------------------
// uncancelExec()
//
//-----------------------------------------------------------------------------
void ThreadManager::uncancelExec()
{
    execCancelled = false;
}

//-----------------------------------------------------------------------------
// wasExecCancelled()
//
//-----------------------------------------------------------------------------
bool ThreadManager::wasExecCancelled()
{
    return execCancelled;
}

//-----------------------------------------------------------------------------
// getThreadId()
// Returns a number from 0 to 'threadCount'-1. Returns 0 if the function fails.
//-----------------------------------------------------------------------------
uint32_t ThreadManager::getThreadNumber()
{
    // locals
    DWORD curThreadId = GetCurrentThreadId();
    uint32_t th;

    for (th = 0; th < threadCount; th++) {
        if (curThreadId == threadId[th]) {
            return th;
        }
    }

    return 0;
}

//-----------------------------------------------------------------------------
// execInParallel()
// lpParam is an array of size threadCount.
//-----------------------------------------------------------------------------
uint32_t ThreadManager::execInParallel(DWORD threadProc(void *pParam),
                                       void *pParam, uint32_t paramStructSize)
{
    // locals
    uint32_t th;
    SIZE_T dwStackSize = 0;

    // params ok?
    if (pParam == nullptr)
        return TM_RETVAL_INVALID_PARAM;

    // globals
    termineAllThreads = false;

    // create threads
    for (th = 0; th < threadCount; th++) {
        hThread[th] = CreateThread(
            nullptr, dwStackSize, (LPTHREAD_START_ROUTINE)threadProc,
            (void *)(((char *)pParam) + th * paramStructSize), CREATE_SUSPENDED,
            &threadId[th]);

        if (hThread[th] != nullptr) {
            SetThreadPriority(hThread[th], THREAD_PRIORITY_BELOW_NORMAL);
        }

        if (hThread[th] == nullptr) {
            for (th; th > 0; th--) {
                CloseHandle(hThread[th - 1]);
                hThread[th - 1] = nullptr;
            }
            return TM_RETVAL_UNEXPECTED_ERROR;
        }
    }

    // start threads
    for (th = 0; th < threadCount; th++) {
        if (!execPaused)
            ResumeThread(hThread[th]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(threadCount, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (th = 0; th < threadCount; th++) {
        CloseHandle(hThread[th]);
        hThread[th] = nullptr;
        threadId[th] = 0;
    }

    // everything ok
    if (execCancelled) {
        return TM_RETVAL_EXEC_CANCELLED;
    } else {
        return TM_RETVAL_OK;
    }
}

//-----------------------------------------------------------------------------
// execInParallel()
//
// lpParam - an array of size threadCount
// finalValue  - this value is part of the iteration, meaning that index ranges
// from initValue to finalValue including both border values
//-----------------------------------------------------------------------------
uint32_t ThreadManager::execParallelLoop(DWORD threadProc(void *pParam,
                                                          unsigned index),
                                         void *pParam, uint32_t paramStructSize,
                                         uint32_t schedType, int initValue,
                                         int finalValue, int increment)
{
    // params ok?
    if (execCancelled == true)
        return TM_RETVAL_EXEC_CANCELLED;

    if (pParam == nullptr)
        return TM_RETVAL_INVALID_PARAM;

    if (schedType >= TM_SCHED_TYPE_COUNT)
        return TM_RETVAL_INVALID_PARAM;

    if (increment == 0)
        return TM_RETVAL_INVALID_PARAM;

    if (abs(finalValue - initValue) == abs(increment))
        return TM_RETVAL_INVALID_PARAM;

    // locals

    // the threads are enumerated from 0 to threadCount-1
    uint32_t th;

    // total number of iterations
    int nIterations = (finalValue - initValue) / increment + 1;

    // number of iterations per chunk
    int chunkSize = 0;

    // initital stack size of each thread. 0 means default size ~1MB
    SIZE_T dwStackSize = 0;

    ForLoop *forLoopParams = new ForLoop[threadCount];

    // globals
    termineAllThreads = false;

    // create threads
    for (th = 0; th < threadCount; th++) {
        forLoopParams[th].pParam = (pParam != nullptr ?
                                        (void *)(((char *)pParam) +
                                                 th * paramStructSize) :
                                        nullptr);
        forLoopParams[th].threadManager = this;
        forLoopParams[th].threadProc = threadProc;
        forLoopParams[th].increment = increment;
        forLoopParams[th].schedType = schedType;

        switch (schedType) {
        case TM_SCHED_STATIC:
            chunkSize = nIterations / threadCount +
                        (th < nIterations % threadCount ? 1 : 0);
            if (th == 0) {
                forLoopParams[th].initValue = initValue;
            } else {
                forLoopParams[th].initValue = forLoopParams[th - 1].finalValue +
                                              1;
            }
            forLoopParams[th].finalValue = forLoopParams[th].initValue +
                                           chunkSize - 1;
            break;
        case TM_SCHED_DYNAMIC:
            return TM_RETVAL_INVALID_PARAM;
            break;
        case TM_SCHED_GUIDED:
            return TM_RETVAL_INVALID_PARAM;
            break;
        case TM_SCHED_RUNTIME:
            return TM_RETVAL_INVALID_PARAM;
            break;
        }

        // create suspended thread
        hThread[th] = CreateThread(nullptr, dwStackSize, threadForLoop,
                                   (LPVOID)(&forLoopParams[th]),
                                   CREATE_SUSPENDED, &threadId[th]);

        if (hThread[th] != nullptr) {
            SetThreadPriority(hThread[th], THREAD_PRIORITY_BELOW_NORMAL);
        }

        if (hThread[th] == nullptr) {
            for (th; th > 0; th--) {
                CloseHandle(hThread[th - 1]);
                hThread[th - 1] = nullptr;
            }

            return TM_RETVAL_UNEXPECTED_ERROR;
        }

#if 0
        DWORD dwThreadAffinityMask = 1 << th;
        SetThreadAffinityMask(hThread[th], &dwThreadAffinityMask);
#endif
    }

    // start threads, but don't resume if in pause mode
    for (th = 0; th < threadCount; th++) {
        if (!execPaused)
            ResumeThread(hThread[th]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(threadCount, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (th = 0; th < threadCount; th++) {
        CloseHandle(hThread[th]);
        hThread[th] = nullptr;
        threadId[th] = 0;
    }
    delete[] forLoopParams;

    // everything ok
    if (execCancelled) {
        return TM_RETVAL_EXEC_CANCELLED;
    } else {
        return TM_RETVAL_OK;
    }
}

//-----------------------------------------------------------------------------
// threadForLoop()
//
//-----------------------------------------------------------------------------
DWORD WINAPI ThreadManager::threadForLoop(LPVOID lpParam)
{
    // locals
    ForLoop *forLoopParams = (ForLoop *)lpParam;
    int i;

    switch (forLoopParams->schedType) {
    case TM_SCHED_STATIC:
        for (i = forLoopParams->initValue;
             (forLoopParams->increment < 0) ? i >= forLoopParams->finalValue :
                                              i <= forLoopParams->finalValue;
             i += forLoopParams->increment) {
            switch (forLoopParams->threadProc(forLoopParams->pParam, i)) {
            case TM_RETVAL_OK:
                break;
            case TM_RETVAL_TERMINATE_ALL_THREADS:
                forLoopParams->threadManager->termineAllThreads = true;
                break;
            default:
                break;
            }
            if (forLoopParams->threadManager->termineAllThreads)
                break;
        }
        break;
    case TM_SCHED_DYNAMIC:
        return TM_RETVAL_INVALID_PARAM;
        break;
    case TM_SCHED_GUIDED:
        return TM_RETVAL_INVALID_PARAM;
        break;
    case TM_SCHED_RUNTIME:
        return TM_RETVAL_INVALID_PARAM;
        break;
    }

    return TM_RETVAL_OK;
}

/*** To Do's
********************************************************************************
- Restriction to 'int' can lead to overflow if there are more states in a layer.
     ==> Maybe work with class templates
*********************************************************************************************/

#endif // MADWEASEL_MUEHLE_PERFECT_AI
