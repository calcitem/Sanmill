/*********************************************************************\
    threadManager.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
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
        unsigned int schedType;
        int increment;
        int initValue;
        int finalValue;
        void *pParam;
        DWORD(*threadProc)
        (void *pParam, unsigned int index); // pointer to the user function
                                                // to be executed by the threads
        ThreadManager *threadManager;
    };

    // Variables
    unsigned int threadCount; // number of threads
    HANDLE *hThread; // array of size 'threadCount' containing the thread
                     // handles
    DWORD *threadId; // array of size 'threadCount' containing the thread ids
    bool termineAllThreads;
    bool execPaused;    // switch for the
    bool execCancelled; // true when cancelExec() was called

    // barrier stuff
    HANDLE hEventBarrierPassedByEverybody;
    HANDLE *hBarrier; // array of size 'threadCount' containing the event
                      // handles for the barrier
    unsigned int threadPassedBarrierCount;
    CRITICAL_SECTION csBarrier;

    // functions
    static DWORD WINAPI threadForLoop(LPVOID lpParam);

public:
    class ThreadVarsArrayItem
    {
    public:
        unsigned int curThreadNo;

        virtual void initElement() { }

        virtual void destroyElement() { }

        virtual void reduce() { }
    };

    template <class varType>
    class ThreadVarsArray
    {
    public:
        unsigned int threadCount;
        varType *item;

        ThreadVarsArray(unsigned int threadCnt, varType &master)
        {
            this->threadCount = threadCnt;
            this->item = new varType[threadCnt];

            for (unsigned int th = 0; th < threadCnt;
                 th++) {
                item[th].curThreadNo = th;
                item[th].initElement(master);
                // if 'curThreadNo' is overwritten in 'initElement()'
                item[th].curThreadNo = th; 
            }
        };

        ~ThreadVarsArray()
        {
            for (unsigned int th = 0; th < threadCount;
                 th++) {
                item[th].destroyElement();
            }

            delete[] item;
        };

        void *getPointerToArray() { return (void *)item; }

        unsigned int getArraySize() { return sizeof(varType); }

        void reduce()
        {
            for (unsigned int th = 0; th < threadCount;
                 th++) {
                item[th].reduce();
            }
        };
    };

    // Constructor / destructor
    ThreadManager();
    ~ThreadManager();

    // Functions
    unsigned int getThreadNumber();
    unsigned int getThreadCount();

    bool setThreadCount(unsigned int newThreadCount);
    void waitForOtherThreads(unsigned int threadNo);
    void pauseExec();  // un-/suspend all threads
    void cancelExec(); // termineAllThreads auf true
    bool wasExecCancelled();

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
    unsigned int execInParallel(DWORD threadProc(void *pParam),
                                   void *pParam,
                                   unsigned int paramStructSize);
    unsigned int
    execParallelLoop(DWORD threadProc(void *pParam, unsigned int index),
                        void *pParam, unsigned int paramStructSize,
                        unsigned int schedType, int initValue,
                        int finalValue, int increment);
};

#endif // THREADMANAGER_H_INCLUDED
