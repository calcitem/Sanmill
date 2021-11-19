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
    SYSTEM_INFO m_si = { 0 };

    GetSystemInfo(&m_si);

    // init default values
    executionPaused = false;
    executionCancelled = false;
    numThreads = m_si.dwNumberOfProcessors;
    hThread = new HANDLE[numThreads];
    threadId = new DWORD[numThreads];
    hBarrier = new HANDLE[numThreads];
    numThreadsPassedBarrier = 0;
    termineAllThreads = false;

    InitializeCriticalSection(&csBarrier);
    hEventBarrierPassedByEveryBody = CreateEvent(nullptr, true, false, nullptr);

    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
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

    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
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
    // cout << endl << "thread=" << threadNo << ", numThreadsPassedBarrier= " <<
    // numThreadsPassedBarrier << ": " << "while (numThreadsPassedBarrier>0)";
    if (numThreadsPassedBarrier > 0) {
        WaitForSingleObject(hEventBarrierPassedByEveryBody, INFINITE);
    }

    // a simple while (numThreadsPassedBarrier>0) {}; does not work, since the
    // variable 'numThreadsPassedBarrier' is not updated, due to compiler
    // optimizations

    // set signal that barrier is reached
    // cout << endl << "thread=" << threadNo << ", numThreadsPassedBarrier= " <<
    // numThreadsPassedBarrier << ": " << "SetEvent()";
    SetEvent(hBarrier[threadNo]);

    // enter the barrier one by one
    // cout << endl << "thread=" << threadNo << ", numThreadsPassedBarrier= " <<
    // numThreadsPassedBarrier << ": " << "EnterCriticalSection()";
    EnterCriticalSection(&csBarrier);

    // if the first one which entered, then wait until other threads
    if (numThreadsPassedBarrier == 0) {
        // cout << endl << "thread=" << threadNo << ", numThreadsPassedBarrier=
        // " << numThreadsPassedBarrier << ": " << "WaitForMultipleObjects()";
        WaitForMultipleObjects(numThreads, hBarrier, TRUE, INFINITE);
        ResetEvent(hEventBarrierPassedByEveryBody);
    }

    // count threads which passed the barrier
    // cout << endl << "thread=" << threadNo << ", numThreadsPassedBarrier= " <<
    // numThreadsPassedBarrier << ": " << "numThreadsPassedBarrier++";
    numThreadsPassedBarrier++;

    // the last one closes the door
    // cout << endl << "thread=" << threadNo << ", numThreadsPassedBarrier= " <<
    // numThreadsPassedBarrier << ": " << "if (numThreadsPassedBarrier ==
    // numThreads) numThreadsPassedBarrier = 0";
    if (numThreadsPassedBarrier == numThreads) {
        numThreadsPassedBarrier = 0;
        SetEvent(hEventBarrierPassedByEveryBody);
    }

    // cout << endl << "thread=" << threadNo << ", numThreadsPassedBarrier= " <<
    // numThreadsPassedBarrier << ": " << "LeaveCriticalSection()";
    LeaveCriticalSection(&csBarrier);
}

//-----------------------------------------------------------------------------
// getNumThreads()
//
//-----------------------------------------------------------------------------
unsigned int ThreadManager::getNumThreads() { return numThreads; }

//-----------------------------------------------------------------------------
// setNumThreads()
//
//-----------------------------------------------------------------------------
bool ThreadManager::setNumThreads(unsigned int newNumThreads)
{
    // cancel if any thread running
    EnterCriticalSection(&csBarrier);

    for (unsigned int curThreadNo = 0; curThreadNo < numThreads;
         curThreadNo++) {
        if (hThread[curThreadNo]) {
            LeaveCriticalSection(&csBarrier);
            return false;
        }
    }

    for (unsigned int curThreadNo = 0; curThreadNo < numThreads;
         curThreadNo++) {
        CloseHandle(hBarrier[curThreadNo]);
    }

    numThreads = newNumThreads;

    for (unsigned int curThreadNo = 0; curThreadNo < numThreads;
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
    for (unsigned int curThread = 0; curThread < numThreads; curThread++) {
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
void ThreadManager::unCancelExecution() { executionCancelled = false; }

//-----------------------------------------------------------------------------
// wasExecutionCancelled()
//
//-----------------------------------------------------------------------------
bool ThreadManager::wasExecutionCancelled() { return executionCancelled; }

//-----------------------------------------------------------------------------
// getThreadId()
// Returns a number from 0 to 'numThreads'-1. Returns 0 if the function fails.
//-----------------------------------------------------------------------------
unsigned int ThreadManager::getThreadNumber()
{
    // locals
    DWORD curThreadId = GetCurrentThreadId();
    unsigned int curThreadNo;

    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
        if (curThreadId == threadId[curThreadNo]) {
            return curThreadNo;
        }
    }

    return 0;
}

//-----------------------------------------------------------------------------
// executeInParallel()
// lpParameter is an array of size numThreads.
//-----------------------------------------------------------------------------
unsigned int ThreadManager::executeInParallel(
    DWORD threadProc(void* pParameter), void* pParameter,
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
    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
        hThread[curThreadNo] = CreateThread(nullptr, dwStackSize,
            (LPTHREAD_START_ROUTINE)threadProc,
            (void*)(((char*)pParameter) + curThreadNo * parameterStructSize),
            CREATE_SUSPENDED, &threadId[curThreadNo]);

        if (hThread[curThreadNo] != nullptr) {
            SetThreadPriority(
                hThread[curThreadNo], THREAD_PRIORITY_BELOW_NORMAL);
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
    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
        if (!executionPaused)
            ResumeThread(hThread[curThreadNo]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(numThreads, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
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
// lpParameter - an array of size numThreads
// finalValue  - this value is part of the iteration, meaning that index ranges
// from initialValue to finalValue including both border values
//-----------------------------------------------------------------------------
unsigned int ThreadManager::executeParallelLoop(
    DWORD threadProc(void* pParameter, unsigned index), void* pParameter,
    unsigned int parameterStructSize, unsigned int scheduleType,
    int initialValue, int finalValue, int inkrement)
{
    // parameters ok?
    if (executionCancelled == true)
        return TM_RETURN_VALUE_EXECUTION_CANCELLED;

    if (pParameter == nullptr)
        return TM_RETURN_VALUE_INVALID_PARAM;

    if (scheduleType >= TM_SCHEDULE_NUM_TYPES)
        return TM_RETURN_VALUE_INVALID_PARAM;

    if (inkrement == 0)
        return TM_RETURN_VALUE_INVALID_PARAM;

    if (abs(finalValue - initialValue) == abs(inkrement))
        return TM_RETURN_VALUE_INVALID_PARAM;

    // locals
    unsigned int
        curThreadNo; // the threads are enumerated from 0 to numThreads-1
    int numIterations = (finalValue - initialValue) / inkrement
        + 1; // total number of iterations
    int chunkSize = 0; // number of iterations per chunk
    SIZE_T dwStackSize
        = 0; // initital stack size of each thread. 0 means default size ~1MB
    ForLoop* forLoopParameters = new ForLoop[numThreads]; //

    // globals
    termineAllThreads = false;

    // create threads
    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
        forLoopParameters[curThreadNo].pParameter
            = (pParameter != nullptr ? (void*)(((char*)pParameter)
                   + curThreadNo * parameterStructSize)
                                     : nullptr);
        forLoopParameters[curThreadNo].threadManager = this;
        forLoopParameters[curThreadNo].threadProc = threadProc;
        forLoopParameters[curThreadNo].inkrement = inkrement;
        forLoopParameters[curThreadNo].scheduleType = scheduleType;

        switch (scheduleType) {
        case TM_SCHEDULE_STATIC:
            chunkSize = numIterations / numThreads
                + (curThreadNo < numIterations % numThreads ? 1 : 0);
            if (curThreadNo == 0) {
                forLoopParameters[curThreadNo].initialValue = initialValue;
            } else {
                forLoopParameters[curThreadNo].initialValue
                    = forLoopParameters[curThreadNo - 1].finalValue + 1;
            }
            forLoopParameters[curThreadNo].finalValue
                = forLoopParameters[curThreadNo].initialValue + chunkSize - 1;
            break;
        case TM_SCHEDULE_DYNAMIC:
            return TM_RETURN_VALUE_INVALID_PARAM;
            break;
        case TM_SCHEDULE_GUIDED:
            return TM_RETURN_VALUE_INVALID_PARAM;
            break;
        case TM_SCHEDULE_RUNTIME:
            return TM_RETURN_VALUE_INVALID_PARAM;
            break;
        }

        // create suspended thread
        hThread[curThreadNo] = CreateThread(nullptr, dwStackSize, threadForLoop,
            (LPVOID)(&forLoopParameters[curThreadNo]), CREATE_SUSPENDED,
            &threadId[curThreadNo]);

        if (hThread[curThreadNo] != nullptr) {
            SetThreadPriority(
                hThread[curThreadNo], THREAD_PRIORITY_BELOW_NORMAL);
        }

        if (hThread[curThreadNo] == nullptr) {
            for (curThreadNo; curThreadNo > 0; curThreadNo--) {
                CloseHandle(hThread[curThreadNo - 1]);
                hThread[curThreadNo - 1] = nullptr;
            }

            return TM_RETURN_VALUE_UNEXPECTED_ERROR;
        }

        // DWORD dwThreadAffinityMask = 1 << curThreadNo;
        // SetThreadAffinityMask(hThread[curThreadNo], &dwThreadAffinityMask);
    }

    // start threads, but don't resume if in pause mode
    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
        if (!executionPaused)
            ResumeThread(hThread[curThreadNo]);
    }

    // wait for every thread to end
    WaitForMultipleObjects(numThreads, hThread, TRUE, INFINITE);

    // Close all thread handles upon completion.
    for (curThreadNo = 0; curThreadNo < numThreads; curThreadNo++) {
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
    ForLoop* forLoopParameters = (ForLoop*)lpParameter;
    int index;

    switch (forLoopParameters->scheduleType) {
    case TM_SCHEDULE_STATIC:
        for (index = forLoopParameters->initialValue;
             (forLoopParameters->inkrement < 0)
                 ? index >= forLoopParameters->finalValue
                 : index <= forLoopParameters->finalValue;
             index += forLoopParameters->inkrement) {
            switch (forLoopParameters->threadProc(
                forLoopParameters->pParameter, index)) {
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
    case TM_SCHEDULE_DYNAMIC:
        return TM_RETURN_VALUE_INVALID_PARAM;
        break;
    case TM_SCHEDULE_GUIDED:
        return TM_RETURN_VALUE_INVALID_PARAM;
        break;
    case TM_SCHEDULE_RUNTIME:
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
