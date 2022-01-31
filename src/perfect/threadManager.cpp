/*********************************************************************
    threadManager.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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
    SYSTEM_INFO m_si = {0};

    GetSystemInfo(&m_si);

    // init default values
    execPaused = false;
    execCancelled = false;
    threadCount = m_si.dwNumberOfProcessors;
    hThread = new HANDLE[threadCount];
    std::memset(hThread, 0, sizeof(HANDLE) * threadCount);
    threadId = new DWORD[threadCount];
    std::memset(threadId, 0, sizeof(DWORD) * threadCount);
    hBarrier = new HANDLE[threadCount];
    std::memset(hBarrier, 0, sizeof(HANDLE) * threadCount);
    threadPassedBarrierCount = 0;
    termineAllThreads = false;

    InitializeCriticalSection(&csBarrier);
    hEventBarrierPassedByEverybody = CreateEvent(nullptr, true, false, nullptr);

    for (uint32_t thd = 0; thd < threadCount; thd++) {
        hThread[thd] = nullptr;
        threadId[thd] = 0;
        hBarrier[thd] = CreateEvent(nullptr, false, false, nullptr);
    }
}

//-----------------------------------------------------------------------------
// ~ThreadManager()
// ThreadManager class destructor
//-----------------------------------------------------------------------------
ThreadManager::~ThreadManager()
{
    for (uint32_t thd = 0; thd < threadCount; thd++) {
        CloseHandle(hBarrier[thd]);
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
uint32_t ThreadManager::getThreadCount() const
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

    for (uint32_t thd = 0; thd < threadCount; thd++) {
        if (hThread[thd]) {
            LeaveCriticalSection(&csBarrier);
            return false;
        }
    }

    for (uint32_t thd = 0; thd < threadCount; thd++) {
        CloseHandle(hBarrier[thd]);
    }

    threadCount = newNumThreads;

    for (uint32_t thd = 0; thd < threadCount; thd++) {
        hBarrier[thd] = CreateEvent(nullptr, false, false, nullptr);
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
    for (uint32_t thd = 0; thd < threadCount; thd++) {
        // unsuspend all threads
        if (!execPaused) {
            SuspendThread(hThread[thd]);
            // suspend all threads
        } else {
            ResumeThread(hThread[thd]);
        }
    }

    execPaused = !execPaused;
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
bool ThreadManager::wasExecCancelled() const
{
    return execCancelled;
}

//-----------------------------------------------------------------------------
// getThreadId()
// Returns a number from 0 to 'threadCount'-1. Returns 0 if the function fails.
//-----------------------------------------------------------------------------
uint32_t ThreadManager::getThreadNumber() const
{
    // locals
    const DWORD curThreadId = GetCurrentThreadId();

    for (uint32_t thd = 0; thd < threadCount; thd++) {
        if (curThreadId == threadId[thd]) {
            return thd;
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
    uint32_t thd;
    const SIZE_T dwStackSize = 0;

    // params ok?
    if (pParam == nullptr)
        return TM_RETVAL_INVALID_PARAM;

    // globals
    termineAllThreads = false;

    // create threads
    for (thd = 0; thd < threadCount; thd++) {
        hThread[thd] = CreateThread(nullptr, dwStackSize, threadProc,
                                    static_cast<char *>(pParam) +
                                        thd * paramStructSize,
                                    CREATE_SUSPENDED, &threadId[thd]);

        if (hThread[thd] != nullptr) {
            SetThreadPriority(hThread[thd], THREAD_PRIORITY_BELOW_NORMAL);
        }

        if (hThread[thd] == nullptr) {
            for (thd; thd > 0; thd--) {
                CloseHandle(hThread[thd - 1]);
                hThread[thd - 1] = nullptr;
            }
            return TM_RETVAL_UNEXPECTED_ERROR;
        }
    }

    // start threads
    for (thd = 0; thd < threadCount; thd++) {
        if (!execPaused)
            ResumeThread(hThread[thd]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(threadCount, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (thd = 0; thd < threadCount; thd++) {
        CloseHandle(hThread[thd]);
        hThread[thd] = nullptr;
        threadId[thd] = 0;
    }

    // everything ok
    if (execCancelled) {
        return TM_RETVAL_EXEC_CANCELLED;
    }

    return TM_RETVAL_OK;
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
    uint32_t thd;

    // total number of iterations
    const int nIterations = (finalValue - initValue) / increment + 1;

    // number of iterations per chunk
    int chunkSize;

    // initial stack size of each thread. 0 means default size ~1MB
    const SIZE_T dwStackSize = 0;

    const auto forLoopParams = new ForLoop[threadCount];
    std::memset(forLoopParams, 0, sizeof(ForLoop) * threadCount);

    // globals
    termineAllThreads = false;

    // create threads
    for (thd = 0; thd < threadCount; thd++) {
        forLoopParams[thd].pParam = (pParam != nullptr ?
                                         static_cast<void *>(
                                             static_cast<char *>(pParam) +
                                             thd * paramStructSize) :
                                         nullptr);
        forLoopParams[thd].threadManager = this;
        forLoopParams[thd].threadProc = threadProc;
        forLoopParams[thd].increment = increment;
        forLoopParams[thd].schedType = schedType;

        switch (schedType) {
        case TM_SCHED_STATIC:
            chunkSize = nIterations / threadCount +
                        (thd < nIterations % threadCount ? 1 : 0);
            if (thd == 0) {
                forLoopParams[thd].initValue = initValue;
            } else {
                forLoopParams[thd].initValue =
                    forLoopParams[thd - 1].finalValue + 1;
            }
            forLoopParams[thd].finalValue = forLoopParams[thd].initValue +
                                            chunkSize - 1;
            break;
        case TM_SCHED_DYNAMIC:
            return TM_RETVAL_INVALID_PARAM;
        case TM_SCHED_GUIDED:
            return TM_RETVAL_INVALID_PARAM;
        case TM_SCHED_RUNTIME:
            return TM_RETVAL_INVALID_PARAM;
        }

        // create suspended thread
        hThread[thd] = CreateThread(nullptr, dwStackSize, threadForLoop,
                                    &forLoopParams[thd], CREATE_SUSPENDED,
                                    &threadId[thd]);

        if (hThread[thd] != nullptr) {
            SetThreadPriority(hThread[thd], THREAD_PRIORITY_BELOW_NORMAL);
        }

        if (hThread[thd] == nullptr) {
            for (thd; thd > 0; thd--) {
                CloseHandle(hThread[thd - 1]);
                hThread[thd - 1] = nullptr;
            }

            return TM_RETVAL_UNEXPECTED_ERROR;
        }

#if 0
        DWORD dwThreadAffinityMask = 1 << thd;
        SetThreadAffinityMask(hThread[thd], &dwThreadAffinityMask);
#endif
    }

    // start threads, but don't resume if in pause mode
    for (thd = 0; thd < threadCount; thd++) {
        if (!execPaused)
            ResumeThread(hThread[thd]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(threadCount, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (thd = 0; thd < threadCount; thd++) {
        CloseHandle(hThread[thd]);
        hThread[thd] = nullptr;
        threadId[thd] = 0;
    }
    delete[] forLoopParams;

    // everything ok
    if (execCancelled) {
        return TM_RETVAL_EXEC_CANCELLED;
    }

    return TM_RETVAL_OK;
}

//-----------------------------------------------------------------------------
// threadForLoop()
//
//-----------------------------------------------------------------------------
DWORD WINAPI ThreadManager::threadForLoop(LPVOID lpParam)
{
    // locals
    const auto forLoopParams = static_cast<ForLoop *>(lpParam);
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
    case TM_SCHED_GUIDED:
        return TM_RETVAL_INVALID_PARAM;
    case TM_SCHED_RUNTIME:
        return TM_RETVAL_INVALID_PARAM;
    }

    return TM_RETVAL_OK;
}

/*** To Do's
********************************************************************************
- Restriction to 'int' can lead to overflow if there are more states in a layer.
     ==> Maybe work with class templates
*********************************************************************************************/

#endif // MADWEASEL_MUEHLE_PERFECT_AI
