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
    TM_SCHED_NUM_TYPES = 5
};

enum ThreadManagerReturnValue {
    TM_RETURN_VALUE_OK = 0,
    TM_RETURN_VALUE_TERMINATE_ALL_THREADS = 1,
    TM_RETURN_VALUE_EXEC_CANCELLED = 2,
    TM_RETURN_VALUE_INVALID_PARAM = 3,
    TM_RETURN_VALUE_UNEXPECTED_ERROR = 4
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
    HANDLE hEventBarrierPassedByEveryBody;
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

        ThreadVarsArray(unsigned int threadCount, varType &master)
        {
            this->threadCount = threadCount;
            this->item = new varType[threadCount];

            for (unsigned int threadCounter = 0; threadCounter < threadCount;
                 threadCounter++) {
                item[threadCounter].curThreadNo = threadCounter;
                item[threadCounter].initElement(master);
                item[threadCounter].curThreadNo =
                    threadCounter; // if 'curThreadNo' is overwritten in
                                   // 'initElement()'
            }
        };

        ~ThreadVarsArray()
        {
            for (unsigned int threadCounter = 0; threadCounter < threadCount;
                 threadCounter++) {
                item[threadCounter].destroyElement();
            }
            delete[] item;
        };

        void *getPointerToArray() { return (void *)item; }

        unsigned int getSizeOfArray() { return sizeof(varType); }

        void reduce()
        {
            for (unsigned int threadCounter = 0; threadCounter < threadCount;
                 threadCounter++) {
                item[threadCounter].reduce();
            }
        };
    };

    // Constructor / destructor
    ThreadManager();
    ~ThreadManager();

    // Functions
    unsigned int getThreadNumber();
    unsigned int getThreadCount();

    bool setNumThreads(unsigned int newNumThreads);
    void waitForOtherThreads(unsigned int threadNo);
    void pauseExec();  // un-/suspend all threads
    void cancelExec(); // termineAllThreads auf true
    bool wasExecCancelled();

    // sets execCancelled to false, otherwise executeParallelLoop returns
    // immediately
    void unCancelExec();

// a user function which is called every x-milliseconds during
// exec between two iterations
#if 0
    void setCallBackFunction(void userFunction(void *pUser), void *pUser,
                             DWORD milliseconds);
#endif

    // execute
    unsigned int executeInParallel(DWORD threadProc(void *pParam),
                                   void *pParam,
                                   unsigned int paramStructSize);
    unsigned int
    executeParallelLoop(DWORD threadProc(void *pParam, unsigned int index),
                        void *pParam, unsigned int paramStructSize,
                        unsigned int schedType, int initValue,
                        int finalValue, int increment);
};

#endif // THREADMANAGER_H_INCLUDED
