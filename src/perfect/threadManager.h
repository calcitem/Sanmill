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
    TM_RETURN_VALUE_EXECUTION_CANCELLED = 2,
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
        int initialValue;
        int finalValue;
        void *pParameter;
        DWORD(*threadProc)
        (void *pParameter, unsigned int index); // pointer to the user function
                                                // to be executed by the threads
        ThreadManager *threadManager;
    };

    // Variables
    unsigned int threadCount; // number of threads
    HANDLE *hThread; // array of size 'threadCount' containing the thread
                     // handles
    DWORD *threadId; // array of size 'threadCount' containing the thread ids
    bool termineAllThreads;
    bool executionPaused;    // switch for the
    bool executionCancelled; // true when cancelExecution() was called

    // barier stuff
    HANDLE hEventBarrierPassedByEveryBody;
    HANDLE *hBarrier; // array of size 'threadCount' containing the event
                      // handles for the barrier
    unsigned int threadPassedBarrierCount;
    CRITICAL_SECTION csBarrier;

    // functions
    static DWORD WINAPI threadForLoop(LPVOID lpParameter);

public:
    class ThreadVarsArrayItem
    {
    public:
        unsigned int curThreadNo;

        virtual void initializeElement() { }

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
                item[threadCounter].initializeElement(master);
                item[threadCounter].curThreadNo =
                    threadCounter; // if 'curThreadNo' is overwritten in
                                   // 'initializeElement()'
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
    void pauseExecution();  // un-/suspend all threads
    void cancelExecution(); // termineAllThreads auf true
    bool wasExecutionCancelled();

    // sets executionCancelled to false, otherwise executeParallelLoop returns
    // immediately
    void unCancelExecution();

// a user function which is called every x-milliseconds during
// execution between two iterations
#if 0
    void setCallBackFunction(void userFunction(void *pUser), void *pUser,
                             DWORD milliseconds);
#endif

    // execute
    unsigned int executeInParallel(DWORD threadProc(void *pParameter),
                                   void *pParameter,
                                   unsigned int parameterStructSize);
    unsigned int
    executeParallelLoop(DWORD threadProc(void *pParameter, unsigned int index),
                        void *pParameter, unsigned int parameterStructSize,
                        unsigned int schedType, int initialValue,
                        int finalValue, int increment);
};

#endif // THREADMANAGER_H_INCLUDED
