/*********************************************************************
	miniMaxWin.h													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/
#ifndef MINIMAXWIN_H
#define MINIMAXWIN_H

// Windows Header Files:
#include "miniMax\\miniMax.h"
#include <queue>
#include <thread>
#include <mutex>
#include <condition_variable>

class miniMaxGuiField
{
public:
	virtual void								setAlignment						(wildWeasel::alignment& newAlignment) {};
	virtual void								setVisibility						(bool visible) {};
	virtual void								setState							(unsigned int curShowedLayer, miniMax::stateNumberVarType curShowedState) {};
};

/*------------------------------------------------------------------------------------

|	-------------------------------------		---------------------------------	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|		pTreeViewInspect			|		|		miniMaxGuiField			|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	-------------------------------------		---------------------------------	|
|																					|
-----------------------------------------------------------------------------------*/

class miniMaxWinInspectDb
{
protected:

	// General Variables
	miniMax *									pMiniMax							= nullptr;					// pointer to perfect KI class granting the access to the database
	miniMaxGuiField*							pGuiField							= nullptr;
	bool										showingInspectionControls			= false;
	unsigned int								curShowedLayer						= 0;						// current showed layer
	miniMax::stateNumberVarType					curShowedState						= 0;						// current showed state
	const unsigned int							scrollBarWidth						= 20;

public:

	// Constructor / destructor
												miniMaxWinInspectDb					(wildWeasel::masterMind* ww, miniMax* pMiniMax, wildWeasel::alignment& amInspectDb, wildWeasel::font2D* font, wildWeasel::texture* textureLine, miniMaxGuiField& guiField);
												~miniMaxWinInspectDb				();

	// Generals Functions
	bool										createControls						();
	bool										showControls						(bool visible);
	void										resize								(wildWeasel::alignment &rcNewArea);
};

/*------------------------------------------------------------------------------------
|	-----------------------------------------------------------------------------	|
|	|																			|	|
|	|																			|	|
|	|		hListViewLayer														|	|
|	|																			|	|
|	|																			|	|
|	|																			|	|
|	|																			|	|
|	-----------------------------------------------------------------------------	|
|																					|
|	-------------------------------------		---------------------------------	|
|	|									|		|								|	|
|	|									|		|		hEditOutputBox			|	|
|	|		hListViewArray				|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	|									|		|								|	|
|	-------------------------------------		---------------------------------	|
|																					|
|	hLabelCalculationRunning	hLabelCalculatingLayer	hLabelCalculationAction		|
|																					|
|	-------------------  -----------------  ----------------  ---------------		|
|	hButtonCalcContinue	 hButtonCalcCancel  hButtonCalcPause  hButtonCalcTest		|
|	-------------------  -----------------  ----------------  ---------------		|
-----------------------------------------------------------------------------------*/

class miniMaxWinCalcDb
{
protected:

	// Calculation variables
	wildWeasel::masterMind *					ww									= nullptr;					// pointer to engine
	miniMax *									pMiniMax							= nullptr;					// pointer to perfect KI class granting the access to the database
	ostream *									outputStream						= nullptr;					// pointer to a stream for the console output of the calculation done by the class miniMax
	stringbuf									outputStringBuf;												// buffer linked to the stream, for reading out of the stream into the buffer
	locale										myLocale;														// for formatting the output
	queue<unsigned int>							layersToTest;													// layer numbers to be tested
	thread										hThreadSolve;
	thread										hThreadTestLayer;
	bool										showingCalculationControls			= false;
	bool										threadSolveIsRunning				= false;
	bool										threadTestLayerIsRunning			= false;
	condition_variable							threadConditionVariable;
	mutex										threadMutex;

	// positions, metrics, sizes, dimensions
	unsigned int								listViewRowHeight					= 20;						// height in pixel of a single row
	const float									defPixelDist						= 15;						//
	const float									labelHeight							= 30;						//
	const float									buttonHeight						= 30;						//



	// Calculation Functions
	void										buttonFuncCalcStartOrContinue		(void* pUser);
	void										buttonFuncCalcCancel				(void* pUser);
	void										buttonFuncCalcPause					(void* pUser);
	void										buttonFuncCalcTest					();
	void										buttonFuncCalcTestAll				(void* pUser);
	void										buttonFuncCalcTestLayer				(void* pUser);
	void										lvSelectedLayerChanged				(unsigned int row, unsigned int col, wildWeasel::guiElemEvFol* guiElem, void* pUser);
	static void									updateOutputControls				(void* pUser);
	void										updateListItemLayer					(unsigned int layerNumber);
	void										updateListItemArray					(miniMax::arrayInfoChange infoChange);
	void										threadSolve							();
	void										threadProcTestLayer					();

public:

	// Constructor / destructor
												miniMaxWinCalcDb					(wildWeasel::masterMind* ww, miniMax* pMiniMax, wildWeasel::alignment& amCalculation, wildWeasel::font2D* font, wildWeasel::texture* textureLine);
												~miniMaxWinCalcDb					();

	// Generals Functions
	bool										createControls						();
	void										resize								(wildWeasel::alignment &amNewArea);
	bool										showControls						(bool visible);
	bool										isCalculationOngoing				();
	miniMax *									getMinimaxPointer 					() { return pMiniMax;					};
	CRITICAL_SECTION *							getCriticalSectionOutput			() { return &pMiniMax->csOsPrint;		};
};

#endif