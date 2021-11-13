/*********************************************************************\
    strLib.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef MINIMAX_RETROANALYSIS_H_INCLUDED
#define MINIMAX_RETROANALYSIS_H_INCLUDED

#include "miniMax.h"

struct RetroAnalysisQueueState {
    StateNumberVarType stateNumber; // state stored in the retro analysis queue. the queue is a buffer containing states to be passed to 'RetroAnalysisThreadVars::statesToProcess'
    PlyInfoVarType numPliesTillCurState; // ply number for the stored state
};

struct RetroAnalysisThreadVars // thread specific variables for each thread in the retro analysis
{
    vector<CyclicArray*> statesToProcess; // vector-queue containing the states, whose short knot value are known for sure. they have to be processed. if processed the state will be removed from list. indexing: [threadNo][plyNumber]
    vector<vector<RetroAnalysisQueueState>> stateQueue; // Queue containing states, whose 'count value' shall be increased by one. Before writing 'count value' to 'count array' the writing positions are sorted for faster processing.
    long long numStatesToProcess; // Number of states in 'statesToProcess' which have to be processed
    unsigned int threadNo;
};

struct RetroAnalysisVars // constant during calculation
{
    vector<CountArrayVarType*> countArrays; // One count array for each layer in 'layersToCalculate'. (For the nine men's morris game two layers have to considered at once.)
    vector<compressorClass::compressedArrayClass*> countArraysCompr; // '' but compressed
    vector<bool> layerInitialized; //
    vector<unsigned int> layersToCalculate; // layers which shall be calculated
    long long totalNumKnots; // total numbers of knots which have to be stored in memory
    long long numKnotsToCalc; // number of knots of all layers to be calculated
    vector<RetroAnalysisThreadVars> thread;
};

struct InitRetroAnalysisVars {
    MiniMax* pMiniMax;
    unsigned int curThreadNo;
    unsigned int layerNumber;
    LONGLONG statesProcessed;
    unsigned int statsValueCounter[SKV_NUM_VALUES];
    BufferedFile* bufferedFile;
    RetroAnalysisVars* retroVars;
    bool initAlreadyDone; // true if the initialization information is already available in a file
};

struct addSuccLayersVars {
    MiniMax* pMiniMax;
    unsigned int curThreadNo;
    unsigned int statsValueCounter[SKV_NUM_VALUES];
    unsigned int layerNumber;
    RetroAnalysisVars* retroVars;
};

struct RetroAnalysisPredVars {
    unsigned int predStateNumbers;
    unsigned int predLayerNumbers;
    unsigned int predSymOperation;
    bool playerToMoveChanged;
};

struct AddNumSucceedersVars {
    MiniMax* pMiniMax;
    unsigned int curThreadNo;
    unsigned int layerNumber;
    LONGLONG statesProcessed;
    RetroAnalysisVars* retroVars;
    RetroAnalysisPredVars* predVars;
};

#endif // MINIMAX_RETROANALYSIS_H_INCLUDED
