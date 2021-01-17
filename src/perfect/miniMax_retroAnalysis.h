/*********************************************************************\
	strLib.h													  
 	Copyright (c) Thomas Weber. All rights reserved.				
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

	struct retroAnalysisQueueState
	{
		stateNumberVarType	stateNumber;					// state stored in the retro analysis queue. the queue is a buffer containing states to be passed to 'retroAnalysisThreadVars::statesToProcess'
		plyInfoVarType		numPliesTillCurState;			// ply number for the stored state
	};
		
	struct retroAnalysisThreadVars											// thread specific variables for each thread in the retro analysis
	{
		vector<cyclicArray*>							statesToProcess;	// vector-queue containing the states, whose short knot value are known for sure. they have to be processed. if processed the state will be removed from list. indexing: [threadNo][plyNumber]
		vector<vector<retroAnalysisQueueState>>			stateQueue;			// Queue containing states, whose 'count value' shall be increased by one. Before writing 'count value' to 'count array' the writing positions are sorted for faster processing.
		long long										numStatesToProcess;	// Number of states in 'statesToProcess' which have to be processed 
		unsigned int									threadNo;
	};

	struct retroAnalysisVars												// constant during calculation
	{
		vector<countArrayVarType *>						countArrays;		// One count array for each layer in 'layersToCalculate'. (For the nine men's morris game two layers have to considered at once.)
		vector<compressorClass::compressedArrayClass *>	countArraysCompr;	// '' but compressed
		vector<bool>									layerInitialized;	// 
		vector<unsigned int> 							layersToCalculate;	// layers which shall be calculated
		long long										totalNumKnots;		// total numbers of knots which have to be stored in memory
		long long										numKnotsToCalc;		// number of knots of all layers to be calculated
		vector<retroAnalysisThreadVars>					thread;
	};

	struct initRetroAnalysisVars
	{
		miniMax *			pMiniMax;
		unsigned int		curThreadNo;
		unsigned int		layerNumber;
		LONGLONG			statesProcessed;
		unsigned int		statsValueCounter[SKV_NUM_VALUES];
		bufferedFileClass *	bufferedFile;
		retroAnalysisVars *	retroVars;
		bool				initAlreadyDone;								// true if the initialization information is already available in a file
	};

	struct addSuccLayersVars
	{
		miniMax *			pMiniMax;
		unsigned int		curThreadNo;
		unsigned int		statsValueCounter[SKV_NUM_VALUES];
		unsigned int		layerNumber;
		retroAnalysisVars *	retroVars;
	};

	struct retroAnalysisPredVars
	{
		unsigned int  		predStateNumbers;
		unsigned int  		predLayerNumbers;
		unsigned int  		predSymOperation;
		bool          		playerToMoveChanged;
	};	
	
	struct addNumSuccedorsVars
	{
		miniMax *			pMiniMax;
		unsigned int		curThreadNo;
		unsigned int		layerNumber;
		LONGLONG			statesProcessed;
		retroAnalysisVars *	retroVars;
		retroAnalysisPredVars * predVars;
	};