/*******************************************************************************
    miniMax.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
*******************************************************************************/

#ifndef MINIMAX_H_INCLUDED
#define MINIMAX_H_INCLUDED

#include "Shlwapi.h"
#include "bufferedFile.h"
#include "cyclicArray.h"
#include "strLib.h"
#include "threadManager.h"
#include <algorithm>
#include <cstdio>
#include <intrin.h>
#include <iostream>
#include <list>
#include <sstream>
#include <time.h>
#include <vector>
#include <windows.h>

#pragma warning(disable : 4100)
#pragma warning(disable : 4238)
#pragma warning(disable : 4244)

#pragma intrinsic(_rotl8, _rotr8) // for shifting bits

using std::iostream; // use standard library namespace

/*** Wiki
********************************************************************************
player:
layer: The states are divided in layers. For
example depending on number of stones on the board.
state: A unique game state representing a
current game situation. situation: Used as synonym
to state.
knot: Each knot of the graph corresponds to a
game state. The knots are connected by possible valid moves. ply info:
Number of plies/moves necessary to win the game. state address:
A state is identified by the corresponding layer and the state number within the
layer.
short knot value: Each knot/state can have the value
SKV_VALUE_INVALID, SKV_VALUE_GAME_LOST, SKV_VALUE_GAME_DRAWN or
SKV_VALUE_GAME_WON. float point knot value: Each knot/state can be evaluated
by a floating point value. High positive values represents winning situations.
Negative values stand for loosing situations.
database: The database contains the arrays with
the short knot values and the ply infos.

/*** Constants
*******************************************************************************/
#define FPKV_MIN_VALUE -100000.0f // minimum float point knot value
#define FPKV_MAX_VALUE 100000.0f // maximum float point knot value
#define FPKV_THRESHOLD                                                         \
    0.001f // threshold used when choosing best move. knot values differing less
           // than this threshold will be regarded as legal

#define SKV_VALUE_INVALID 0 // short knot value: knot value is invalid
#define SKV_VALUE_GAME_LOST                                                    \
    1 // game lost means that there is no perfect move possible
#define SKV_VALUE_GAME_DRAWN                                                   \
    2 // the perfect move leads at least to a drawn game
#define SKV_VALUE_GAME_WON 3 // the perfect move will lead to a won game
#define SKV_MAX_VALUE 3 // highest short knot value
#define SKV_NUM_VALUES 4 // number of different short knot values
#define SKV_WHOLE_BYTE_IS_INVALID                                              \
    0 // four short knot values are stored in one byte. so all four knot values
      // are invalid

#define PLYINFO_EXP_VALUE                                                      \
    1000 // expected maximum number of plies -> user for vector initialization
#define PLYINFO_VALUE_DRAWN                                                    \
    65001 // knot value is drawn. since drawn means a never ending game, this is
          // a special ply info
#define PLYINFO_VALUE_UNCALCULATED                                             \
    65002 // ply info is not calculated yet for this game state
#define PLYINFO_VALUE_INVALID                                                  \
    65003 // ply info is invalid, since knot value is invalid

#define MAX_NUM_PRED_LAYERS                                                    \
    2 // each layer must have at maximum two preceding layers

#define SKV_FILE_HEADER_CODE 0xF4F5 // constant to identify the header
#define PLYINFO_HEADER_CODE 0xF3F2 //     ''

#define OUTPUT_EVERY_N_STATES                                                  \
    10000000 // print progress every n-th processed knot
#define BLOCK_SIZE_IN_CYCLIC_ARRAY                                             \
    10000 // BLOCK_SIZE_IN_CYCLIC_ARRAY*sizeof(stateAdressStruct) = block size
          // in bytes for the cyclic arrays
#define MAX_NUM_PREDECESSORS                                                   \
    10000 // maximum number of predecessors. important for array sizes
#define FILE_BUFFER_SIZE 1000000 // size in bytes

#define PL_TO_MOVE_CHANGED                                                     \
    1 // player to move changed - second index of the 2D-array
      // skvPerspectiveMatrix[][]
#define PL_TO_MOVE_UNCHANGED                                                   \
    0 // player to move is still the same - second index of the 2D-array
      // skvPerspectiveMatrix[][]

#define MEASURE_TIME_FREQUENCY                                                 \
    100000 // for io operations per second: measure time every n-th operations
#define MEASURE_IOPS                                                           \
    false // true or false - for measurement of the input/output operations per
          // second
#define MEASURE_ONLY_IO                                                        \
    false // true or false - to indicate if only the io-operation shall be
          // considered or also the calculating time in-between

#define MM_ACTION_INIT_RETRO_ANAL 1
#define MM_ACTION_PREPARE_COUNT_ARRAY 2
#define MM_ACTION_PERFORM_RETRO_ANAL 3
#define MM_ACTION_PERFORM_ALPHA_BETA 4
#define MM_ACTION_TESTING_LAYER 5
#define MM_ACTION_SAVING_LAYER_TO_FILE 6
#define MM_ACTION_CALC_LAYER_STATS 7
#define MM_ACTION_NONE 8

/*** Macros
 * ****************************************************************************/
#define SAFE_DELETE(p)                                                         \
    {                                                                          \
        if (p) {                                                               \
            delete (p);                                                        \
            (p) = nullptr;                                                     \
        }                                                                      \
    }

#define SAFE_DELETE_ARRAY(p)                                                   \
    {                                                                          \
        if (p) {                                                               \
            delete[](p);                                                       \
            (p) = nullptr;                                                     \
        }                                                                      \
    }

// here a macro is used instead of a function because the text 't' is passed
// like "blabla" << endl << aVariable
#define PRINT(v, c, t)                                                         \
    {                                                                          \
        if (c->verbosity > v) {                                                \
            EnterCriticalSection(&c->csOsPrint);                               \
            *c->osPrint << endl << t;                                          \
            if (c->userPrintFunc != nullptr) {                                 \
                c->userPrintFunc(c->pDataForUserPrintFunc);                    \
            }                                                                  \
            LeaveCriticalSection(&c->csOsPrint);                               \
        }                                                                      \
    }

/*** Classes
 * ****************************************************************************/
class MiniMax {
    friend class MiniMaxWinInspectDb;
    friend class MiniMaxWinCalcDb;

public:
    /*** typedefines
     * ************************************************************************/
    typedef unsigned char TwoBit; // 2-Bit variable ranging from 0 to 3
    typedef unsigned short PlyInfoVarType; // 2 Bytes for saving the ply info
    typedef unsigned char CountArrayVarType; // 1 Byte for counting predecessors
    typedef unsigned int
        StateNumberVarType; // 4 Bytes for addressing states within a layer

    /*** protected structures
     * ************************************************************************/

    struct SkvFileHeader // header of the short knot value file
    {
        bool completed; // true if all states have been calculated
        unsigned int numLayers; // number of layers
        unsigned int headerCode; // = SKV_FILE_HEADER_CODE
        unsigned int
            headerAndStatsSize; // size in bytes of this struct plus the stats
    };

    struct PlyInfoFileHeader {
        bool plyInfoCompleted; // true if ply information has been calculated
                               // for all game states
        unsigned int numLayers; // number of layers
        unsigned int headerCode; // = PLYINFO_HEADER_CODE
        unsigned int
            headerAndPlyInfosSize; // size in bytes of this struct plus ...
    };

    struct PlyInfo // this struct is created for each layer
    {
        bool plyInfoIsLoaded; // the array plyInfo[] exists in memory. does not
                              // necessary mean that it contains only valid
                              // values
        bool plyInfoIsCompletedAndInFile; // the array plyInfo[] contains only
                                          // fully calculated valid values
        int64_t layerOffset; // position of this struct in the ply info file
        unsigned int
            sizeInBytes; // size of this struct plus the array plyInfo[]
        StateNumberVarType
            knotsInLayer; // number of knots of the corresponding layer
        PlyInfoVarType* plyInfo; // array of size [knotsInLayer] containing the
                                 // ply info for each knot in this layer
        // compressorClass::compressedArrayClass* plyInfoCompressed; //
        // compressed array containing the ply info for each knot in this layer
        void* plyInfoCompressed; // dummy pointer for padding
    };

    struct LayerStats {
        bool layerIsLoaded; // the array shortKnotValueByte[] exists in memory.
                            // does not necessary mean that it contains only
                            // valid values
        bool layerIsCompletedAndInFile; // the array shortKnotValueByte[]
                                        // contains only fully calculated valid
                                        // values
        int64_t
            layerOffset; // position of this struct in the short knot value file
        unsigned int
            numSuccLayers; // number of succeeding layers. states of other
                           // layers are connected by a move of a player
        unsigned int
            succLayers[MAX_NUM_PRED_LAYERS]; // array containing the layer ids
                                             // of the succeeding layers
        unsigned int partnerLayer; // layer id relevant when switching current
                                   // and opponent player
        StateNumberVarType
            knotsInLayer; // number of knots of the corresponding layer
        StateNumberVarType numWonStates; // number of won states in this layer
        StateNumberVarType numLostStates; // number of lost states in this layer
        StateNumberVarType
            numDrawnStates; // number of drawn states in this layer
        StateNumberVarType
            numInvalidStates; // number of invalid states in this layer
        unsigned int sizeInBytes; // (knotsInLayer + 3) / 4
        TwoBit* shortKnotValueByte; // array of size [sizeInBytes] containing
                                    // the short knot values
        // compressorClass::compressedArrayClass* skvCompressed; // compressed
        // array containing the short knot values
        void* skvCompressed; // dummy pointer for padding
    };

    struct StateAdress {
        StateNumberVarType
            stateNumber; // state id within the corresponding layer
        unsigned char layerNumber; // layer id
    };

    struct Knot {
        bool isOpponentLevel; // the current considered knot belongs to an
                              // opponent game state
        float floatValue; // Value of knot (for normal mode)
        TwoBit shortValue; // Value of knot (for database)
        unsigned int bestMoveId; // for calling class
        unsigned int bestBranch; // branch with highest value
        unsigned int numPossibilities; // number of branches
        PlyInfoVarType plyInfo; // number of moves till win/lost
        Knot* branches; // pointer to branches
    };

    struct RetroAnalysisPredVars {
        unsigned int predStateNumbers; //
        unsigned int predLayerNumbers; //
        unsigned int predSymOperation; //
        bool playerToMoveChanged; //
    };

    struct ArrayInfo {
        unsigned int type; //
        int64_t sizeInBytes; //
        int64_t compressedSizeInBytes; //
        unsigned int belongsToLayer; //
        unsigned int updateCounter;

        static const unsigned int arrayType_invalid = 0;
        static const unsigned int arrayType_knotAlreadyCalculated = 1;
        static const unsigned int arrayType_countArray = 2;
        static const unsigned int arrayType_plyInfos = 3;
        static const unsigned int arrayType_layerStats = 4;
        static const unsigned int numArrayTypes = 5;

        static const unsigned int updateCounterThreshold = 100;
    };

    struct ArrayInfoChange {
        unsigned int itemIndex; //
        ArrayInfo* arrayInfo; //
    };

    struct ArrayInfoContainer {
        MiniMax* c;
        list<ArrayInfoChange> arrayInfosToBeUpdated; //
        list<ArrayInfo> listArrays; // [itemIndex]
        vector<list<ArrayInfo>::iterator>
            vectorArrays; // [layerNumber*ArrayInfo::numArrayTypes + type]

        void addArray(unsigned int layerNumber, unsigned int type, int64_t size,
            int64_t compressedSize);
        void removeArray(unsigned int layerNumber, unsigned int type,
            int64_t size, int64_t compressedSize);
        void updateArray(unsigned int layerNumber, unsigned int type);
    };

    /*** public functions
     * ************************************************************************/

    // Constructor / destructor
    MiniMax();
    virtual ~MiniMax();

    // Testing functions
    bool testState(unsigned int layerNumber, unsigned int stateNumber);
    bool testLayer(unsigned int layerNumber);
    bool testIfSymStatesHaveSameValue(unsigned int layerNumber);
    bool testSetSituationAndGetPoss(unsigned int layerNumber);

    // Statistics
    bool calcLayerStatistics(char* statisticsFileName);
    void showMemoryStatus();
    unsigned int getNumThreads();
    bool anyFreshlyCalculatedLayer();
    unsigned int getLastCalculatedLayer();
    StateNumberVarType getNumWonStates(unsigned int layerNum);
    StateNumberVarType getNumLostStates(unsigned int layerNum);
    StateNumberVarType getNumDrawnStates(unsigned int layerNum);
    StateNumberVarType getNumInvalidStates(unsigned int layerNum);
    bool isLayerInDatabase(unsigned int layerNum);
    int64_t getLayerSizeInBytes(unsigned int layerNum);
    void setOutputStream(ostream* theStream, void (*printFunc)(void* pUserData),
        void* pUserData);
    bool anyArrayInfoToUpdate();
    ArrayInfoChange getArrayInfoForUpdate();
    void getCurrentCalculatedLayer(vector<unsigned int>& layers);
    LPWSTR getCurrentActionStr();

    // Main function for getting the best choice
    void* getBestChoice(unsigned int tilLevel, unsigned int* choice,
        unsigned int maximumNumberOfBranches);

    // Database functions
    bool openDatabase(
        const char* directory, unsigned int maximumNumberOfBranches);
    void calculateDatabase(unsigned int maxDepthOfTree, bool onlyPrepareLayer);
    bool isCurrentStateInDatabase(unsigned int threadNo);
    void closeDatabase();
    void unloadAllLayers();
    void unloadAllPlyInfos();
    void pauseDatabaseCalculation();
    void cancelDatabaseCalculation();
    bool wasDatabaseCalculationCancelled();

    // Virtual Functions
    virtual void prepareBestChoiceCalculation()
    {
        while (true) {
        }
    }; // is called once before building the tree

    virtual unsigned int* getPossibilities(unsigned int threadNo,
        unsigned int* numPossibilities, bool* opponentsMove,
        void** pPossibilities)
    {
        while (true) {
        }
        return 0;
    }; // returns a pointer to the possibility-IDs

    virtual void deletePossibilities(
        unsigned int threadNo, void* pPossibilities)
    {
        while (true) {
        }
    };

    virtual void storeValueOfMove(unsigned int threadNo,
        unsigned int idPossibility, void* pPossibilities, TwoBit value,
        unsigned int* freqValuesSubMoves, PlyInfoVarType plyInfo)
    {
    }

    virtual void move(unsigned int threadNo, unsigned int idPossibility,
        bool opponentsMove, void** pBackup, void* pPossibilities)
    {
        while (true) {
        }
    };

    virtual void undo(unsigned int threadNo, unsigned int idPossibility,
        bool opponentsMove, void* pBackup, void* pPossibilities)
    {
        while (true) {
        }
    };

    virtual bool shallRetroAnalysisBeUsed(unsigned int layerNum)
    {
        return false;
    };

    virtual unsigned int getNumberOfLayers()
    {
        while (true) {
        }
        return 0;
    };

    virtual unsigned int getNumberOfKnotsInLayer(unsigned int layerNum)
    {
        while (true) {
        }
        return 0;
    };

    virtual void getSuccLayers(unsigned int layerNum,
        unsigned int* amountOfSuccLayers, unsigned int* succLayers)
    {
        while (true) {
        }
    };

    virtual unsigned int getPartnerLayer(unsigned int layerNum)
    {
        while (true) {
        }
        return 0;
    };

    virtual string getOutputInformation(unsigned int layerNum)
    {
        while (true) {
        }
        return string("");
    };

    virtual void setOpponentLevel(unsigned int threadNo, bool isOpponentLevel)
    {
        while (true) {
        }
    };

    virtual bool setSituation(
        unsigned int threadNo, unsigned int layerNum, unsigned int stateNumber)
    {
        while (true) {
        }
        return false;
    };

    virtual void getValueOfSituation(
        unsigned int threadNo, float& floatValue, TwoBit& shortValue)
    {
        while (true) {
        }
    }; // value of situation for the initial current player

    virtual bool getOpponentLevel(unsigned int threadNo)
    {
        while (true) {
        }
        return false;
    };

    virtual unsigned int getLayerAndStateNumber(unsigned int threadNo,
        unsigned int& layerNum, unsigned int& stateNumber)
    {
        while (true) {
        }
        return 0;
    };
    virtual unsigned int getLayerNumber(unsigned int threadNo)
    {
        while (true) {
        }
        return 0;
    };

    virtual void getSymStateNumWithDoubles(unsigned int threadNo,
        unsigned int* numSymmetricStates, unsigned int** symStateNumbers)
    {
        while (true) {
        }
    };

    virtual void getPredecessors(unsigned int threadNo,
        unsigned int* amountOfPred, RetroAnalysisPredVars* predVars)
    {
        while (true) {
        }
    };

    virtual void printBoard(unsigned int threadNo, unsigned char value)
    {
        while (true) {
        }
    };

    virtual void printMoveInformation(
        unsigned int threadNo, unsigned int idPossibility, void* pPossibilities)
    {
        while (true) {
        }
    };

    virtual void prepareDatabaseCalculation()
    {
        while (true) {
        }
    };

    virtual void wrapUpDatabaseCalculation(bool calculationAborted)
    {
        while (true) {
        }
    };

private:
    /*** classes for testing
     * *****************************************************************************************/

    struct TestLayersVars {
        MiniMax* pMiniMax;
        unsigned int curThreadNo;
        unsigned int layerNumber;
        LONGLONG statesProcessed;
        TwoBit* subValueInDatabase;
        PlyInfoVarType* subPlyInfos;
        bool* hasCurPlayerChanged;
    };

    /*** classes for the alpha beta algorithmn
     * ************************************************************************/

    struct AlphaBetaThreadVars // thread specific variables for each thread in
                               // the alpha beta algorithm
    {
        int64_t numStatesToProcess; // Number of states in 'statesToProcess'
                                    // which have to be processed
        unsigned int threadNo;
    };

    struct AlphaBetaGlobalVars // constant during calculation
    {
        unsigned int layerNumber; // layer number of the current process layer
        int64_t totalNumKnots; // total numbers of knots which have to be stored
                               // in memory
        int64_t
            numKnotsToCalc; // number of knots of all layers to be calculated
        vector<AlphaBetaThreadVars> thread;
        unsigned int statsValueCounter[SKV_NUM_VALUES];
        MiniMax* pMiniMax;

        AlphaBetaGlobalVars(MiniMax* pMiniMax, unsigned int layerNumber)
        {
            this->thread.resize(pMiniMax->threadManager.getNumThreads());
            for (unsigned int threadNo = 0;
                 threadNo < pMiniMax->threadManager.getNumThreads();
                 threadNo++) {
                this->thread[threadNo].numStatesToProcess = 0;
                this->thread[threadNo].threadNo = threadNo;
            }
            this->layerNumber = layerNumber;
            this->pMiniMax = pMiniMax;
            if (pMiniMax->layerStats) {
                this->numKnotsToCalc
                    = pMiniMax->layerStats[layerNumber].knotsInLayer;
                this->totalNumKnots
                    = pMiniMax->layerStats[layerNumber].knotsInLayer;
            }
            this->statsValueCounter[SKV_VALUE_GAME_WON] = 0;
            this->statsValueCounter[SKV_VALUE_GAME_LOST] = 0;
            this->statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
            this->statsValueCounter[SKV_VALUE_INVALID] = 0;
        }
    };

    struct AlphaBetaDefaultThreadVars {
        MiniMax* pMiniMax;
        AlphaBetaGlobalVars* alphaBetaVars;
        unsigned int layerNumber;
        LONGLONG statesProcessed;
        unsigned int statsValueCounter[SKV_NUM_VALUES];

        AlphaBetaDefaultThreadVars() {}

        AlphaBetaDefaultThreadVars(MiniMax* pMiniMax,
            AlphaBetaGlobalVars* alphaBetaVars, unsigned int layerNumber)
        {
            this->statesProcessed = 0;
            this->layerNumber = layerNumber;
            this->pMiniMax = pMiniMax;
            this->alphaBetaVars = alphaBetaVars;
            for (unsigned int curStateValue = 0; curStateValue < SKV_NUM_VALUES;
                 curStateValue++) {
                this->statsValueCounter[curStateValue] = 0;
            }
        };

        void reduceDefault()
        {
            pMiniMax->numStatesProcessed += this->statesProcessed;
            for (unsigned int curStateValue = 0; curStateValue < SKV_NUM_VALUES;
                 curStateValue++) {
                alphaBetaVars->statsValueCounter[curStateValue]
                    += this->statsValueCounter[curStateValue];
            }
        };
    };

    struct InitAlphaBetaVars : public ThreadManager::ThreadVarsArrayItem,
                               public AlphaBetaDefaultThreadVars {
        BufferedFile* bufferedFile;
        bool initAlreadyDone;

        InitAlphaBetaVars() {}

        InitAlphaBetaVars(MiniMax* pMiniMax, AlphaBetaGlobalVars* alphaBetaVars,
            unsigned int layerNumber, BufferedFile* initArray,
            bool initAlreadyDone)
            : AlphaBetaDefaultThreadVars(pMiniMax, alphaBetaVars, layerNumber)
        {
            this->bufferedFile = initArray;
            this->initAlreadyDone = initAlreadyDone;
        };

        void initializeElement(InitAlphaBetaVars& master) { *this = master; }

        void reduce() { reduceDefault(); }
    };

    struct RunAlphaBetaVars : public ThreadManager::ThreadVarsArrayItem,
                              public AlphaBetaDefaultThreadVars {
        Knot* branchArray = nullptr; // array of size [(depthOfFullTree -
                                     // tilLevel) * maxNumBranches] for storage
                                     // of the branches at each search depth
        unsigned int* freqValuesSubMovesBranchWon = nullptr; // ...
        unsigned int freqValuesSubMoves[4]; // ...

        RunAlphaBetaVars() {}

        RunAlphaBetaVars(MiniMax* pMiniMax, AlphaBetaGlobalVars* alphaBetaVars,
            unsigned int layerNumber)
            : AlphaBetaDefaultThreadVars(pMiniMax, alphaBetaVars, layerNumber)
        {
            initializeElement(*this);
        };

        ~RunAlphaBetaVars()
        {
            SAFE_DELETE_ARRAY(branchArray);
            SAFE_DELETE_ARRAY(freqValuesSubMovesBranchWon);
        }

        void reduce() { reduceDefault(); }

        void initializeElement(RunAlphaBetaVars& master)
        {
            *this = master;
            branchArray = new Knot[alphaBetaVars->pMiniMax->maxNumBranches
                * alphaBetaVars->pMiniMax->depthOfFullTree];
            freqValuesSubMovesBranchWon
                = new unsigned int[alphaBetaVars->pMiniMax->maxNumBranches];
        };
    };

    /*** classes for the retro analysis
     * *******************************************************************************/

    struct RetroAnalysisQueueState {
        StateNumberVarType
            stateNumber; // state stored in the retro analysis queue. the queue
                         // is a buffer containing states to be passed to
                         // 'RetroAnalysisThreadVars::statesToProcess'
        PlyInfoVarType numPliesTillCurState; // ply number for the stored state
    };

    struct RetroAnalysisThreadVars // thread specific variables for each thread
                                   // in the retro analysis
    {
        vector<CyclicArray*>
            statesToProcess; // vector-queue containing the states, whose short
                             // knot value are known for sure. they have to be
                             // processed. if processed the state will be
                             // removed from list. indexing:
                             // [threadNo][plyNumber]
        vector<vector<RetroAnalysisQueueState>>
            stateQueue; // Queue containing states, whose 'count value' shall be
                        // increased by one. Before writing 'count value' to
                        // 'count array' the writing positions are sorted for
                        // faster processing.
        int64_t numStatesToProcess; // Number of states in 'statesToProcess'
                                    // which have to be processed
        unsigned int threadNo;
    };

    struct retroAnalysisGlobalVars // constant during calculation
    {
        vector<CountArrayVarType*>
            countArrays; // One count array for each layer in
                         // 'layersToCalculate'. (For the nine men's morris game
                         // two layers have to considered at once.)
        vector<bool> layerInitialized; //
        vector<unsigned int>
            layersToCalculate; // layers which shall be calculated
        int64_t totalNumKnots; // total numbers of knots which have to be stored
                               // in memory
        int64_t
            numKnotsToCalc; // number of knots of all layers to be calculated
        vector<RetroAnalysisThreadVars> thread;
        unsigned int statsValueCounter[SKV_NUM_VALUES];
        MiniMax* pMiniMax;
    };

    struct RetroAnalysisDefaultThreadVars {
        MiniMax* pMiniMax;
        retroAnalysisGlobalVars* retroVars;
        unsigned int layerNumber;
        LONGLONG statesProcessed;
        unsigned int statsValueCounter[SKV_NUM_VALUES];

        RetroAnalysisDefaultThreadVars() {}

        RetroAnalysisDefaultThreadVars(MiniMax* pMiniMax,
            retroAnalysisGlobalVars* retroVars, unsigned int layerNumber)
        {
            this->statesProcessed = 0;
            this->layerNumber = layerNumber;
            this->pMiniMax = pMiniMax;
            this->retroVars = retroVars;
            for (unsigned int curStateValue = 0; curStateValue < SKV_NUM_VALUES;
                 curStateValue++) {
                this->statsValueCounter[curStateValue] = 0;
            }
        };

        void reduceDefault()
        {
            pMiniMax->numStatesProcessed += this->statesProcessed;
            for (unsigned int curStateValue = 0; curStateValue < SKV_NUM_VALUES;
                 curStateValue++) {
                retroVars->statsValueCounter[curStateValue]
                    += this->statsValueCounter[curStateValue];
            }
        };
    };

    struct InitRetroAnalysisVars : public ThreadManager::ThreadVarsArrayItem,
                                   public RetroAnalysisDefaultThreadVars {
        BufferedFile* bufferedFile;
        bool initAlreadyDone;

        InitRetroAnalysisVars() {}

        InitRetroAnalysisVars(MiniMax* pMiniMax,
            retroAnalysisGlobalVars* retroVars, unsigned int layerNumber,
            BufferedFile* initArray, bool initAlreadyDone)
            : RetroAnalysisDefaultThreadVars(pMiniMax, retroVars, layerNumber)
        {
            this->bufferedFile = initArray;
            this->initAlreadyDone = initAlreadyDone;
        };

        void initializeElement(InitRetroAnalysisVars& master)
        {
            *this = master;
        };

        void reduce() { reduceDefault(); }
    };

    struct AddNumSucceedersVars : public ThreadManager::ThreadVarsArrayItem,
                                  public RetroAnalysisDefaultThreadVars {
        RetroAnalysisPredVars predVars[MAX_NUM_PREDECESSORS];

        AddNumSucceedersVars() {}

        AddNumSucceedersVars(MiniMax* pMiniMax,
            retroAnalysisGlobalVars* retroVars, unsigned int layerNumber)
            : RetroAnalysisDefaultThreadVars(pMiniMax, retroVars, layerNumber)
        {
        }

        void initializeElement(AddNumSucceedersVars& master)
        {
            *this = master;
        };

        void reduce() { reduceDefault(); }
    };

    /*** private variables
     * ********************************************************************************************/

    // variables, which are constant during database calculation
    int verbosity = 2; // output detail level. default is 2
    unsigned char
        skvPerspectiveMatrix[4]
                            [2]; // [short knot value][current or opponent
                                 // player] - A winning situation is a loosing
                                 // situation for the opponent and so on ...
    bool calcDatabase
        = false; // true, if the database is currently being calculated
    HANDLE hFileShortKnotValues
        = nullptr; // handle of the file for the short knot value
    HANDLE hFilePlyInfo = nullptr; // handle of the file for the ply info
    SkvFileHeader skvfHeader; // short knot value file header
    PlyInfoFileHeader plyInfoHeader; // header of the ply info file
    string fileDirectory; // path of the folder where the database files are
                          // located
    ostream* osPrint = nullptr; // stream for output. default is cout
    list<unsigned int> lastCalculatedLayer; //
    vector<unsigned int> layersToCalculate; // used in calcLayer() and
                                            // getCurrentCalculatedLayers()
    bool onlyPrepareLayer = false; //
    bool stopOnCriticalError
        = true; // if true then process will stay in while loop
    ThreadManager threadManager; //
    CRITICAL_SECTION csDatabase; //
    CRITICAL_SECTION
    csOsPrint; // for thread safety when output is passed to osPrint
    void (*userPrintFunc)(void*)
        = nullptr; // called every time output is passed to osPrint
    void* pDataForUserPrintFunc
        = nullptr; // pointer passed when calling userPrintFunc
    ArrayInfoContainer arrayInfos; // information about the arrays in memory

    // thread specific or non-constant variables
    LONGLONG memoryUsed2 = 0; // memory in bytes used for storing: ply
                              // information, short knot value and ...
    LONGLONG numStatesProcessed = 0; //
    unsigned int maxNumBranches = 0; // maximum number of branches/moves
    unsigned int depthOfFullTree = 0; // maximum search depth
    unsigned int curCalculatedLayer = 0; // id of the currently calculated layer
    unsigned int curCalculationActionId = 0; // one of ...
    bool layerInDatabase
        = false; // true if the current considered layer has already been
                 // calculated and stored in the database
    void* pRootPossibilities
        = nullptr; // pointer to the structure passed by getPossibilities() for
                   // the state at which getBestChoice() has been called
    LayerStats* layerStats
        = nullptr; // array of size [] containing general layer information and
                   // the skv of all layers
    PlyInfo* plyInfos = nullptr; // array of size [] containing ply information

    // variables concerning the compression of the database
    // compressorClass* compressor = nullptr;
    // unsigned int compressionAlgorithmnId = 0; // 0 or one of the
    // COMPRESSOR_ALG_... constants

    // database I/O operations per second
    int64_t numReadSkvOperations
        = 0; // number of read operations done since start of the program
    int64_t numWriteSkvOperations
        = 0; // number of write operations done since start of the program
    int64_t numReadPlyOperations
        = 0; // number of read operations done since start of the program
    int64_t numWritePlyOperations
        = 0; // number of write operations done since start of the program
    LARGE_INTEGER readSkvInterval; // time of interval for read operations
    LARGE_INTEGER writeSkvInterval; //  ''
    LARGE_INTEGER readPlyInterval; //  ''
    LARGE_INTEGER writePlyInterval; //  ''
    LARGE_INTEGER
    frequency; // performance-counter frequency, in counts per second

    /*** private functions
     * ************************************************************************/

    // database functions
    void openSkvFile(const char* path, unsigned int maximumNumberOfBranches);
    void openPlyInfoFile(const char* path);
    bool calcLayer(unsigned int layerNumber);
    void unloadPlyInfo(unsigned int layerNumber);
    void unloadLayer(unsigned int layerNumber);
    void saveHeader(SkvFileHeader* dbH, LayerStats* lStats);
    void saveHeader(PlyInfoFileHeader* piH, PlyInfo* pInfo);
    void readKnotValueFromDatabase(unsigned int threadNo,
        unsigned int& layerNumber, unsigned int& stateNumber, TwoBit& knotValue,
        bool& invalidLayerOrStateNumber, bool& layerInDatabaseAndCompleted);
    void readKnotValueFromDatabase(
        unsigned int layerNumber, unsigned int stateNumber, TwoBit& knotValue);
    void readPlyInfoFromDatabase(unsigned int layerNumber,
        unsigned int stateNumber, PlyInfoVarType& value);
    void saveKnotValueInDatabase(
        unsigned int layerNumber, unsigned int stateNumber, TwoBit knotValue);
    void savePlyInfoInDatabase(unsigned int layerNumber,
        unsigned int stateNumber, PlyInfoVarType value);
    void loadBytesFromFile(
        HANDLE hFile, int64_t offset, unsigned int numBytes, void* pBytes);
    void saveBytesToFile(
        HANDLE hFile, int64_t offset, unsigned int numBytes, void* pBytes);
    void saveLayerToFile(unsigned int layerNumber);
    inline void measureIops(int64_t& numOperations, LARGE_INTEGER& interval,
        LARGE_INTEGER& curTimeBefore, char text[]);

    // Testing functions
    static DWORD testLayerThreadProc(void* pParameter, unsigned int index);
    static DWORD testSetSituationThreadProc(
        void* pParameter, unsigned int index);

    // Alpha-Beta-Algorithm
    bool calcKnotValuesByAlphaBeta(unsigned int layerNumber);
    bool initAlphaBeta(AlphaBetaGlobalVars& retroVars);
    bool runAlphaBeta(AlphaBetaGlobalVars& retroVars);
    void letTheTreeGrow(Knot* knot, RunAlphaBetaVars* rabVars,
        unsigned int tilLevel, float alpha, float beta);
    bool alphaBetaTryDataBase(Knot* knot, RunAlphaBetaVars* rabVars,
        unsigned int tilLevel, unsigned int& layerNumber,
        unsigned int& stateNumber);
    void alphaBetaTryPossibilities(Knot* knot, RunAlphaBetaVars* rabVars,
        unsigned int tilLevel, unsigned int* idPossibility,
        void* pPossibilities, unsigned int& maxWonfreqValuesSubMoves,
        float& alpha, float& beta);
    void alphaBetaCalcPlyInfo(Knot* knot);
    void alphaBetaCalcKnotValue(Knot* knot);
    void alphaBetaChooseBestMove(Knot* knot, RunAlphaBetaVars* rabVars,
        unsigned int tilLevel, unsigned int* idPossibility,
        unsigned int maxWonfreqValuesSubMoves);
    void alphaBetaSaveInDatabase(unsigned int threadNo,
        unsigned int layerNumber, unsigned int stateNumber, TwoBit knotValue,
        PlyInfoVarType plyValue, bool invertValue);
    static DWORD initAlphaBetaThreadProc(void* pParameter, unsigned int index);
    static DWORD runAlphaBetaThreadProc(void* pParameter, unsigned int index);

    // Retro Analysis
    bool calcKnotValuesByRetroAnalysis(vector<unsigned int>& layersToCalculate);
    bool initRetroAnalysis(retroAnalysisGlobalVars& retroVars);
    bool prepareCountArrays(retroAnalysisGlobalVars& retroVars);
    bool calcNumSucceeders(retroAnalysisGlobalVars& retroVars);
    bool performRetroAnalysis(retroAnalysisGlobalVars& retroVars);
    bool addStateToProcessQueue(retroAnalysisGlobalVars& retroVars,
        RetroAnalysisThreadVars& threadVars, unsigned int plyNumber,
        StateAdress* pState);
    static bool retroAnalysisQueueStateComp(
        const RetroAnalysisQueueState& a, const RetroAnalysisQueueState& b)
    {
        return a.stateNumber < b.stateNumber;
    };
    static DWORD initRetroAnalysisThreadProc(
        void* pParameter, unsigned int index);
    static DWORD addNumSucceedersThreadProc(
        void* pParameter, unsigned int index);
    static DWORD performRetroAnalysisThreadProc(void* pParameter);

    // Progress report functions
    void showLayerStats(unsigned int layerNumber);
    bool falseOrStop();
};

#endif // MINIMAX_H_INCLUDED
