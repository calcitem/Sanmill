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
    unsigned int curThreadNo;
    SYSTEM_INFO m_si = {0};

    GetSystemInfo(&m_si);

    // init default values
    executionPaused = false;
    executionCancelled = false;
    threadCount = m_si.dwNumberOfProcessors;
    hThread = new HANDLE[threadCount];
    threadId = new DWORD[threadCount];
    hBarrier = new HANDLE[threadCount];
    threadPassedBarrierCount = 0;
    termineAllThreads = false;

    InitializeCriticalSection(&csBarrier);
    hEventBarrierPassedByEveryBody = CreateEvent(nullptr, true, false, nullptr);

    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        hThread[curThreadNo] = nullptr;
        threadId[curThreadNo] = 0;
        hBarrier[curThreadNo] = CreateEvent(nullptr, false, false, nullptr);
    }
}

//-----------------------------------------------------------------------------
// ~ThreadManager()
// ThreadManager class destructor
//-----------------------------------------------------------------------------
ThreadManager::~ThreadManager()
{
    // locals
    unsigned int curThreadNo;

    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        CloseHandle(hBarrier[curThreadNo]);
    }

    DeleteCriticalSection(&csBarrier);
    CloseHandle(hEventBarrierPassedByEveryBody);

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
void ThreadManager::waitForOtherThreads(unsigned int threadNo)
{
    // wait if other threads are still waiting at the barrier

#if 0
    cout << endl
         << "thread=" << threadNo
         << ", threadPassedBarrierCount= " << threadPassedBarrierCount << ": "
         << "while (threadPassedBarrierCount>0)";
#endif

    if (threadPassedBarrierCount > 0) {
        WaitForSingleObject(hEventBarrierPassedByEveryBody, INFINITE);
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
        ResetEvent(hEventBarrierPassedByEveryBody);
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
        SetEvent(hEventBarrierPassedByEveryBody);
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
unsigned int ThreadManager::getThreadCount()
{
    return threadCount;
}

//-----------------------------------------------------------------------------
// setNumThreads()
//
//-----------------------------------------------------------------------------
bool ThreadManager::setNumThreads(unsigned int newNumThreads)
{
    // cancel if any thread running
    EnterCriticalSection(&csBarrier);

    for (unsigned int curThreadNo = 0; curThreadNo < threadCount;
         curThreadNo++) {
        if (hThread[curThreadNo]) {
            LeaveCriticalSection(&csBarrier);
            return false;
        }
    }

    for (unsigned int curThreadNo = 0; curThreadNo < threadCount;
         curThreadNo++) {
        CloseHandle(hBarrier[curThreadNo]);
    }

    threadCount = newNumThreads;

    for (unsigned int curThreadNo = 0; curThreadNo < threadCount;
         curThreadNo++) {
        hBarrier[curThreadNo] = CreateEvent(nullptr, false, false, nullptr);
    }

    LeaveCriticalSection(&csBarrier);

    return true;
}

//-----------------------------------------------------------------------------
// pauseExecution()
//
//-----------------------------------------------------------------------------
void ThreadManager::pauseExecution()
{
    for (unsigned int curThread = 0; curThread < threadCount; curThread++) {
        // unsuspend all threads
        if (!executionPaused) {
            SuspendThread(hThread[curThread]);
            // suspend all threads
        } else {
            ResumeThread(hThread[curThread]);
        }
    }

    executionPaused = (!executionPaused);
}

//-----------------------------------------------------------------------------
// cancelExecution()
// Stops executeParallelLoop() before the next iteration.
//     When executeInParallel() was called, user has to handle cancellation by
//     himself.
//-----------------------------------------------------------------------------
void ThreadManager::cancelExecution()
{
    termineAllThreads = true;
    executionCancelled = true;

    if (executionPaused) {
        pauseExecution();
    }
}

//-----------------------------------------------------------------------------
// unCancelExecution()
//
//-----------------------------------------------------------------------------
void ThreadManager::unCancelExecution()
{
    executionCancelled = false;
}

//-----------------------------------------------------------------------------
// wasExecutionCancelled()
//
//-----------------------------------------------------------------------------
bool ThreadManager::wasExecutionCancelled()
{
    return executionCancelled;
}

//-----------------------------------------------------------------------------
// getThreadId()
// Returns a number from 0 to 'threadCount'-1. Returns 0 if the function fails.
//-----------------------------------------------------------------------------
unsigned int ThreadManager::getThreadNumber()
{
    // locals
    DWORD curThreadId = GetCurrentThreadId();
    unsigned int curThreadNo;

    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        if (curThreadId == threadId[curThreadNo]) {
            return curThreadNo;
        }
    }

    return 0;
}

//-----------------------------------------------------------------------------
// executeInParallel()
// lpParameter is an array of size threadCount.
//-----------------------------------------------------------------------------
unsigned int
ThreadManager::executeInParallel(DWORD threadProc(void *pParameter),
                                 void *pParameter,
                                 unsigned int parameterStructSize)
{
    // locals
    unsigned int curThreadNo;
    SIZE_T dwStackSize = 0;

    // parameters ok?
    if (pParameter == nullptr)
        return TM_RETURN_VALUE_INVALID_PARAM;

    // globals
    termineAllThreads = false;

    // create threads
    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        hThread[curThreadNo] = CreateThread(
            nullptr, dwStackSize, (LPTHREAD_START_ROUTINE)threadProc,
            (void *)(((char *)pParameter) + curThreadNo * parameterStructSize),
            CREATE_SUSPENDED, &threadId[curThreadNo]);

        if (hThread[curThreadNo] != nullptr) {
            SetThreadPriority(hThread[curThreadNo],
                              THREAD_PRIORITY_BELOW_NORMAL);
        }

        if (hThread[curThreadNo] == nullptr) {
            for (curThreadNo; curThreadNo > 0; curThreadNo--) {
                CloseHandle(hThread[curThreadNo - 1]);
                hThread[curThreadNo - 1] = nullptr;
            }
            return TM_RETURN_VALUE_UNEXPECTED_ERROR;
        }
    }

    // start threads
    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        if (!executionPaused)
            ResumeThread(hThread[curThreadNo]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(threadCount, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        CloseHandle(hThread[curThreadNo]);
        hThread[curThreadNo] = nullptr;
        threadId[curThreadNo] = 0;
    }

    // everything ok
    if (executionCancelled) {
        return TM_RETURN_VALUE_EXECUTION_CANCELLED;
    } else {
        return TM_RETURN_VALUE_OK;
    }
}

//-----------------------------------------------------------------------------
// executeInParallel()
//
// lpParameter - an array of size threadCount
// finalValue  - this value is part of the iteration, meaning that index ranges
// from initialValue to finalValue including both border values
//-----------------------------------------------------------------------------
unsigned int ThreadManager::executeParallelLoop(
    DWORD threadProc(void *pParameter, unsigned index), void *pParameter,
    unsigned int parameterStructSize, unsigned int schedType, int initialValue,
    int finalValue, int inkrement)
{
    // parameters ok?
    if (executionCancelled == true)
        return TM_RETURN_VALUE_EXECUTION_CANCELLED;

    if (pParameter == nullptr)
        return TM_RETURN_VALUE_INVALID_PARAM;

    if (schedType >= TM_SCHED_NUM_TYPES)
        return TM_RETURN_VALUE_INVALID_PARAM;

    if (inkrement == 0)
        return TM_RETURN_VALUE_INVALID_PARAM;

    if (abs(finalValue - initialValue) == abs(inkrement))
        return TM_RETURN_VALUE_INVALID_PARAM;

    // locals

    // the threads are enumerated from 0 to threadCount-1
    unsigned int curThreadNo;

    // total number of iterations
    int nIterations = (finalValue - initialValue) / inkrement + 1;

    // number of iterations per chunk
    int chunkSize = 0;

    // initital stack size of each thread. 0 means default size ~1MB
    SIZE_T dwStackSize = 0;

    ForLoop *forLoopParameters = new ForLoop[threadCount];

    // globals
    termineAllThreads = false;

    // create threads
    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        forLoopParameters[curThreadNo].pParameter =
            (pParameter != nullptr ?
                 (void *)(((char *)pParameter) +
                          curThreadNo * parameterStructSize) :
                 nullptr);
        forLoopParameters[curThreadNo].threadManager = this;
        forLoopParameters[curThreadNo].threadProc = threadProc;
        forLoopParameters[curThreadNo].inkrement = inkrement;
        forLoopParameters[curThreadNo].schedType = schedType;

        switch (schedType) {
        case TM_SCHED_STATIC:
            chunkSize = nIterations / threadCount +
                        (curThreadNo < nIterations % threadCount ? 1 : 0);
            if (curThreadNo == 0) {
                forLoopParameters[curThreadNo].initialValue = initialValue;
            } else {
                forLoopParameters[curThreadNo].initialValue =
                    forLoopParameters[curThreadNo - 1].finalValue + 1;
            }
            forLoopParameters[curThreadNo].finalValue =
                forLoopParameters[curThreadNo].initialValue + chunkSize - 1;
            break;
        case TM_SCHED_DYNAMIC:
            return TM_RETURN_VALUE_INVALID_PARAM;
            break;
        case TM_SCHED_GUIDED:
            return TM_RETURN_VALUE_INVALID_PARAM;
            break;
        case TM_SCHED_RUNTIME:
            return TM_RETURN_VALUE_INVALID_PARAM;
            break;
        }

        // create suspended thread
        hThread[curThreadNo] = CreateThread(
            nullptr, dwStackSize, threadForLoop,
            (LPVOID)(&forLoopParameters[curThreadNo]), CREATE_SUSPENDED,
            &threadId[curThreadNo]);

        if (hThread[curThreadNo] != nullptr) {
            SetThreadPriority(hThread[curThreadNo],
                              THREAD_PRIORITY_BELOW_NORMAL);
        }

        if (hThread[curThreadNo] == nullptr) {
            for (curThreadNo; curThreadNo > 0; curThreadNo--) {
                CloseHandle(hThread[curThreadNo - 1]);
                hThread[curThreadNo - 1] = nullptr;
            }

            return TM_RETURN_VALUE_UNEXPECTED_ERROR;
        }

#if 0
        DWORD dwThreadAffinityMask = 1 << curThreadNo;
        SetThreadAffinityMask(hThread[curThreadNo], &dwThreadAffinityMask);
#endif
    }

    // start threads, but don't resume if in pause mode
    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        if (!executionPaused)
            ResumeThread(hThread[curThreadNo]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(threadCount, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (curThreadNo = 0; curThreadNo < threadCount; curThreadNo++) {
        CloseHandle(hThread[curThreadNo]);
        hThread[curThreadNo] = nullptr;
        threadId[curThreadNo] = 0;
    }
    delete[] forLoopParameters;

    // everything ok
    if (executionCancelled) {
        return TM_RETURN_VALUE_EXECUTION_CANCELLED;
    } else {
        return TM_RETURN_VALUE_OK;
    }
}

//-----------------------------------------------------------------------------
// threadForLoop()
//
//-----------------------------------------------------------------------------
DWORD WINAPI ThreadManager::threadForLoop(LPVOID lpParameter)
{
    // locals
    ForLoop *forLoopParameters = (ForLoop *)lpParameter;
    int index;

    switch (forLoopParameters->schedType) {
    case TM_SCHED_STATIC:
        for (index = forLoopParameters->initialValue;
             (forLoopParameters->inkrement < 0) ?
                 index >= forLoopParameters->finalValue :
                 index <= forLoopParameters->finalValue;
             index += forLoopParameters->inkrement) {
            switch (forLoopParameters->threadProc(forLoopParameters->pParameter,
                                                  index)) {
            case TM_RETURN_VALUE_OK:
                break;
            case TM_RETURN_VALUE_TERMINATE_ALL_THREADS:
                forLoopParameters->threadManager->termineAllThreads = true;
                break;
            default:
                break;
            }
            if (forLoopParameters->threadManager->termineAllThreads)
                break;
        }
        break;
    case TM_SCHED_DYNAMIC:
        return TM_RETURN_VALUE_INVALID_PARAM;
        break;
    case TM_SCHED_GUIDED:
        return TM_RETURN_VALUE_INVALID_PARAM;
        break;
    case TM_SCHED_RUNTIME:
        return TM_RETURN_VALUE_INVALID_PARAM;
        break;
    }

    return TM_RETURN_VALUE_OK;
}

/*** To Do's
********************************************************************************
- Restriction to 'int' can lead to overflow if there are more states in a layer.
     ==> Maybe work with class templates
*********************************************************************************************/

#endif // MADWEASEL_MUEHLE_PERFECT_AI
