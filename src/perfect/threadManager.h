/*********************************************************************\
	threadManager.h												  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/
#ifndef THREADMANAGER_H
#define THREADMANAGER_H

// standard library & win32 api
#include <windows.h>
#include <cstdio>
#include <iostream>

using namespace std;										// use standard library namespace

/*** Konstanten ******************************************************/
#define TM_SCHEDULE_USER_DEFINED					0
#define TM_SCHEDULE_STATIC							1
#define TM_SCHEDULE_DYNAMIC							2
#define TM_SCHEDULE_GUIDED							3
#define TM_SCHEDULE_RUNTIME							4
#define TM_SCHEDULE_NUM_TYPES						5

#define TM_RETURN_VALUE_OK							0
#define TM_RETURN_VALUE_TERMINATE_ALL_THREADS		1
#define TM_RETURN_VALUE_EXECUTION_CANCELLED			2
#define TM_RETURN_VALUE_INVALID_PARAM				3
#define TM_RETURN_VALUE_UNEXPECTED_ERROR			4

/*** Makros ******************************************************/

/*** Strukturen ******************************************************/

/*** Klassen *********************************************************/

class threadManagerClass
{
private:
	
	// structures
	struct forLoopStruct
	{
		unsigned int		scheduleType;
		int					inkrement;
		int					initialValue;
		int					finalValue;
		void *				pParameter;
		DWORD				(*threadProc)(void* pParameter, int index);		// pointer to the user function to be executed by the threads
		threadManagerClass *threadManager;
	};
	
	// Variables
	unsigned int			numThreads;										// number of threads
	HANDLE	*				hThread;										// array of size 'numThreads' containing the thread handles
	DWORD	*				threadId;										// array of size 'numThreads' containing the thread ids
	bool					termineAllThreads;
	bool					executionPaused;								// switch for the 
	bool					executionCancelled;								// true when cancelExecution() was called

	// barier stuff
	HANDLE					hEventBarrierPassedByEveryBody;				
	HANDLE	*				hBarrier;										// array of size 'numThreads' containing the event handles for the barrier
	unsigned int			numThreadsPassedBarrier;
	CRITICAL_SECTION		csBarrier;

	// functions
	static DWORD WINAPI		threadForLoop					(LPVOID lpParameter);

public:

	class threadVarsArrayItem
	{
	public:
		unsigned int									curThreadNo;

		virtual void									initializeElement () {};
		virtual void									destroyElement	  () {};
		virtual void									reduce			  () {};
	};

	template <class varType> class threadVarsArray
	{
	public:
		unsigned int									numberOfThreads;
		varType *										item;

		threadVarsArray(unsigned int numberOfThreads, varType& master)
		{
			this->numberOfThreads	= numberOfThreads;
			this->item				= new varType[numberOfThreads];

			for (unsigned int threadCounter=0; threadCounter<numberOfThreads; threadCounter++) {
				item[threadCounter].curThreadNo		= threadCounter;
				item[threadCounter].initializeElement(master);
				item[threadCounter].curThreadNo		= threadCounter;		// if 'curThreadNo' is overwritten in 'initializeElement()'
			}
		};

		~threadVarsArray()
		{
			for (unsigned int threadCounter=0; threadCounter<numberOfThreads; threadCounter++) {
				item[threadCounter].destroyElement();
			}
			delete [] item;
		};

		void *	getPointerToArray() 
		{
			return (void*) item;
		};

		unsigned int getSizeOfArray()
		{
			return sizeof(varType);
		};

		void reduce()
		{
			for (unsigned int threadCounter=0; threadCounter<numberOfThreads; threadCounter++) {
				item[threadCounter].reduce();
			}
		};	
	};

    // Constructor / destructor
    threadManagerClass();
    ~threadManagerClass();

	// Functions
	unsigned int			getThreadNumber					();
	unsigned int			getNumThreads					();
	
	bool					setNumThreads					(unsigned int newNumThreads);
	void					waitForOtherThreads				(unsigned int threadNo);
	void					pauseExecution					();		// un-/suspend all threads
	void					cancelExecution					();		// termineAllThreads auf true
	bool					wasExecutionCancelled			();
	void					uncancelExecution				();		// sets executionCancelled	to false, otherwise executeParellelLoop returns immediatelly
//... void					setCallBackFunction				(void userFunction(void* pUser), void* pUser, DWORD milliseconds);		// a user function which is called every x-milliseconds during execution between two iterations
	
	// execute
	unsigned int 			executeInParallel				(DWORD threadProc(void* pParameter			 ), void *pParameter, unsigned int parameterStructSize);
	unsigned int			executeParallelLoop				(DWORD threadProc(void* pParameter, int index), void *pParameter, unsigned int parameterStructSize, unsigned int scheduleType, int initialValue, int finalValue, int inkrement);
};

#endif
