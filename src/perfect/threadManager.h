/*********************************************************************\
    threadManager.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef THREADMANAGER_H_INCLUDED
#define THREADMANAGER_H_INCLUDED

// standard library & win32 api
#include <cstdio>
#include <iostream>
#include <windows.h>

using std::iostream; // use standard library namespace

enum ThreadManagerSched {
    TM_SCHED_USER_DEFINED = 0,
    TM_SCHED_STATIC = 1,
    TM_SCHED_DYNAMIC = 2,
    TM_SCHED_GUIDED = 3,
    TM_SCHED_RUNTIME = 4,
    TM_SCHED_TYPE_COUNT = 5
};

enum ThreadManagerReturnValue {
    TM_RETVAL_OK = 0,
    TM_RETVAL_TERMINATE_ALL_THREADS = 1,
    TM_RETVAL_EXEC_CANCELLED = 2,
    TM_RETVAL_INVALID_PARAM = 3,
    TM_RETVAL_UNEXPECTED_ERROR = 4
};

/*** Structures ******************************************************/

class ThreadManager
{
private:
    // structures
    struct ForLoop
    {
        uint32_t schedType {0};
        int increment {0};
        int initValue {0};
        int finalValue {0};
        void *pParam {nullptr};
        DWORD(*threadProc)
        (void *pParam, uint32_t index); // pointer to the user function
                                        // to be executed by the threads
        ThreadManager *threadManager {nullptr};
    };

    // Variables
    uint32_t threadCount {0};  // number of threads
    HANDLE *hThread {nullptr}; // array of size 'threadCount' containing the
                               // thread
                               // handles
    DWORD *threadId {nullptr}; // array of size 'threadCount' containing the
                               // thread ids
    bool termineAllThreads {false};
    bool execPaused {false};    // switch for the
    bool execCancelled {false}; // true when cancelExec() was called

    // barrier stuff
    HANDLE hEventBarrierPassedByEverybody {nullptr};
    HANDLE *hBarrier {nullptr}; // array of size 'threadCount' containing the
                                // event
                                // handles for the barrier
    uint32_t threadPassedBarrierCount {0};
    CRITICAL_SECTION csBarrier;

    // functions
    static DWORD WINAPI threadForLoop(LPVOID lpParam);

public:
    class ThreadVarsArrayItem
    {
    public:
        uint32_t curThreadNo {0};

        virtual void initElement() { }

        virtual void destroyElement() { }

        virtual void reduce() { }
    };

    template <class varType>
    class ThreadVarsArray
    {
    public:
        uint32_t threadCount {0};
        varType *item {nullptr};

        ThreadVarsArray(uint32_t threadCnt, varType &master)
        {
            this->threadCount = threadCnt;
            this->item = new varType[threadCnt];
            // std::memset(this->item, 0, sizeof(varType) * threadCnt);

            for (uint32_t thd = 0; thd < threadCnt; thd++) {
                item[thd].curThreadNo = thd;
                item[thd].initElement(master);
                // if 'curThreadNo' is overwritten in 'initElement()'
                item[thd].curThreadNo = thd;
            }
        }

        ~ThreadVarsArray()
        {
            for (uint32_t thd = 0; thd < threadCount; thd++) {
                item[thd].destroyElement();
            }

            delete[] item;
        }

        void *getPointerToArray() const { return static_cast<void *>(item); }

        static uint32_t getArraySize() { return sizeof(varType); }

        void reduce()
        {
            for (uint32_t thd = 0; thd < threadCount; thd++) {
                item[thd].reduce();
            }
        }
    };

    // Constructor / destructor
    ThreadManager();
    ~ThreadManager();

    // Functions
    uint32_t getThreadNumber() const;
    uint32_t getThreadCount() const;

    bool setThreadCount(uint32_t newThreadCount);
    void waitForOtherThreads(uint32_t threadNo);
    void pauseExec();  // un-/suspend all threads
    void cancelExec(); // termineAllThreads auf true
    bool wasExecCancelled() const;

    // sets execCancelled to false, otherwise execParallelLoop returns
    // immediately
    void uncancelExec();

    // a user function which is called every x-milliseconds during
    // exec between two iterations
#if 0
    void setCallBackFunction(void userFunction(void *pUser), void *pUser,
                             DWORD milliseconds);
#endif

    // execute
    uint32_t execInParallel(DWORD threadProc(void *pParam), void *pParam,
                            uint32_t paramStructSize);
    uint32_t execParallelLoop(DWORD threadProc(void *pParam, uint32_t index),
                              void *pParam, uint32_t paramStructSize,
                              uint32_t schedType, int initValue, int finalValue,
                              int increment);
};

#endif // THREADMANAGER_H_INCLUDED
