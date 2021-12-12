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

struct RetroAnalysisQueueState
{
    // state stored in the retro analysis queue. the queue is a buffer
    // containing states to be passed to
    // 'RetroAnalysisThreadVars::statesToProcess'
    StateNumberVarType stateNumber;

    // ply number for the stored state
    PlyInfoVarType plyTillCurStateCount;
};

// thread specific variables for each thread in the retro analysis
struct RetroAnalysisThreadVars
{
    // vector-queue containing the states, whose short knot value are known for
    // sure. they have to be processed. if processed the state will be removed
    // from list. indexing: [threadNo][plyNumber]
    vector<CyclicArray *> statesToProcess;

    // Queue containing states, whose 'count value' shall be increased by one.
    // Before writing 'count value' to 'count array' the writing positions are
    // sorted for faster processing.
    vector<vector<RetroAnalysisQueueState>> stateQueue;

    // Number of states in 'statesToProcess' which have to be processed
    int64_t stateToProcessCount;

    unsigned int threadNo;
};

// constant during calculation
struct RetroAnalysisVars
{
    // One count array for each layer in 'layersToCalculate'. (For the nine
    // men's morris game two layers have to considered at once.)
    vector<CountArrayVarType *> countArrays;

    // '' but compressed
    vector<compressorClass::compressedArrayClass *> countArraysCompr;

    vector<bool> layerInitialized;

    // layers which shall be calculated
    vector<unsigned int> layersToCalculate;

    // total numbers of knots which have to be stored in memory
    int64_t totalKnotCount;

    // number of knots of all layers to be calculated
    int64_t knotToCalcCount;

    vector<RetroAnalysisThreadVars> thread;
};

struct InitRetroAnalysisVars
{
    MiniMax *pMiniMax;
    unsigned int curThreadNo;
    unsigned int layerNumber;
    LONGLONG statesProcessed;
    unsigned int statsValueCounter[SKV_VALUE_COUNT];
    BufferedFile *bufferedFile;
    RetroAnalysisVars *retroVars;
    bool initAlreadyDone; // true if the initialization information is already
                          // available in a file
};

struct addSuccLayersVars
{
    MiniMax *pMiniMax;
    unsigned int curThreadNo;
    unsigned int statsValueCounter[SKV_VALUE_COUNT];
    unsigned int layerNumber;
    RetroAnalysisVars *retroVars;
};

struct RetroAnalysisPredVars
{
    unsigned int predStateNumbers;
    unsigned int predLayerNumbers;
    unsigned int predSymOperation;
    bool playerToMoveChanged;
};

struct AddNumSucceedersVars
{
    MiniMax *pMiniMax;
    unsigned int curThreadNo;
    unsigned int layerNumber;
    LONGLONG statesProcessed;
    RetroAnalysisVars *retroVars;
    RetroAnalysisPredVars *predVars;
};

#endif // MINIMAX_RETROANALYSIS_H_INCLUDED
