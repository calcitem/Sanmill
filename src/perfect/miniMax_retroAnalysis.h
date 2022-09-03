/*********************************************************************\
    strLib.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef MINIMAX_RETROANALYSIS_H_INCLUDED
#define MINIMAX_RETROANALYSIS_H_INCLUDED

#include "miniMax.h"

struct RetroAnalysisQueueState
{
    // state stored in the retro analysis queue. the queue is a buf
    // containing states to be passed to
    // 'RetroAnalysisThreadVars::statesToProcess'
    StateNumberVarType stateNumber {0};

    // ply number for the stored state
    PlyInfoVarType plyTillCurStateCount {0};
};

// thread specific variables for each thread in the retro analysis
struct RetroAnalysisThreadVars
{
    // vector-queue containing the states, whose short knot value are known for
    // sure. they have to be processed. if processed the state will be removed
    // from list. indexing: [threadNo][plyNumber]
    vector<CyclicArray *> statesToProcess {};

    // Queue containing states, whose 'count value' shall be increased by one.
    // Before writing 'count value' to 'count array' the writing positions are
    // sorted for faster processing.
    vector<vector<RetroAnalysisQueueState>> stateQueue {};

    // Number of states in 'statesToProcess' which have to be processed
    int64_t stateToProcessCount {0};

    uint32_t threadNo {0};
};

// constant during calculation
struct RetroAnalysisVars
{
    // One count array for each layer in 'layersToCalculate'. (For the nine
    // men's morris game two layers have to considered at once.)
    vector<CountArrayVarType *> countArrays {};

    // '' but compressed
    vector<compressorClass::compressedArrayClass *> countArraysCompr {};

    vector<bool> layerInitialized {};

    // layers which shall be calculated
    vector<uint32_t> layersToCalculate {};

    // total numbers of knots which have to be stored in memory
    int64_t totalKnotCount {0};

    // number of knots of all layers to be calculated
    int64_t knotToCalcCount {0};

    vector<RetroAnalysisThreadVars> thread {};
};

struct InitRetroAnalysisVars
{
    MiniMax *pMiniMax {nullptr};
    uint32_t curThreadNo {0};
    uint32_t layerNumber {0};
    LONGLONG statesProcessed {0};
    uint32_t statsValueCounter[SKV_VALUE_COUNT] {0};
    BufferedFile *bufferedFile {nullptr};
    RetroAnalysisVars *retroVars {nullptr};
    bool initAlreadyDone {false}; // true if the initialization info is already
                                  // available in a file
};

struct addSuccLayersVars
{
    MiniMax *pMiniMax {nullptr};
    uint32_t curThreadNo {0};
    uint32_t statsValueCounter[SKV_VALUE_COUNT] {0};
    uint32_t layerNumber {0};
    RetroAnalysisVars *retroVars {nullptr};
};

struct RetroAnalysisPredVars
{
    uint32_t predStateNumbers {0};
    uint32_t predLayerNumbers {0};
    uint32_t predSymOp {0};
    bool playerToMoveChanged {false};
};

struct AddNumSucceedersVars
{
    MiniMax *pMiniMax {nullptr};
    uint32_t curThreadNo {0};
    uint32_t layerNumber {0};
    LONGLONG statesProcessed {0};
    RetroAnalysisVars *retroVars {nullptr};
    RetroAnalysisPredVars *predVars {nullptr};
};

#endif // MINIMAX_RETROANALYSIS_H_INCLUDED
