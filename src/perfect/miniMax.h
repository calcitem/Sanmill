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
example depending on number of pieces on the board.
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

// minimum float point knot value
#define FPKV_MIN_VALUE -100000.0f

// maximum float point knot value
#define FPKV_MAX_VALUE 100000.0f

// threshold used when choosing best move. knot values differing less
// than this threshold will be regarded as legal
#define FPKV_THRESHOLD 0.001f

enum SkvValue {
    // short knot value: knot value is invalid
    SKV_VALUE_INVALID = 0,

    // game lost means that there is no perfect move possible
    SKV_VALUE_GAME_LOST = 1,

    // the perfect move leads at least to a drawn game
    SKV_VALUE_GAME_DRAWN = 2,

    // the perfect move will lead to a won game
    SKV_VALUE_GAME_WON = 3,

    // highest short knot value
    SKV_MAX_VALUE = SKV_VALUE_GAME_WON,

    // number of different short knot values
    SKV_VALUE_COUNT = 4,
};

// four short knot values are stored in one byte. so all four knot values
// are invalid
constexpr auto SKV_WHOLE_BYTE_IS_INVALID = 0;

// expected maximum number of plies -> user for vector initialization
constexpr auto PLYINFO_EXP_VALUE = 1000;

enum PlayInfoValue {
    // knot value is drawn. since drawn means a never ending game, this is
    // a special ply info
    PLYINFO_VALUE_DRAWN = 65001,

    // ply info is not calculated yet for this game state
    PLYINFO_VALUE_UNCALCULATED = 65002,

    // ply info is invalid, since knot value is invalid
    PLYINFO_VALUE_INVALID = 65003,
};

// each layer must have at maximum two preceding layers
constexpr auto PRED_LAYER_COUNT_MAX = 2;

// constant to identify the header
constexpr auto SKV_FILE_HEADER_CODE = 0xF4F5;
constexpr auto PLYINFO_HEADER_CODE = 0xF3F2;

// print progress every n-thread processed knot
constexpr auto OUTPUT_EVERY_N_STATES = 10000000;

// BLOCK_SIZE_IN_CYCLIC_ARRAY*sizeof(stateAdressStruct) = block size
// in bytes for the cyclic arrays
constexpr auto BLOCK_SIZE_IN_CYCLIC_ARRAY = 10000;

// maximum number of predecessors. important for array sizes
constexpr auto PREDECESSOR_COUNT_MAX = 10000;

// size in bytes
constexpr auto FILE_BUFFER_SIZE = 1000000;

// player to move changed - second index of the 2D-array
// skvPerspectiveMatrix[][]
constexpr auto PL_TO_MOVE_CHANGED = 1;

// player to move is still the same - second index of the 2D-array
// skvPerspectiveMatrix[][]
constexpr auto PL_TO_MOVE_UNCHANGED = 0;

// for io operations per second: measure time every n-thread operations
constexpr auto MEASURE_TIME_FREQUENCY = 100000;

// true or false - for measurement of the input/output operations per
// second
constexpr auto MEASURE_IOPS = false;

// true or false - to indicate if only the io-operation shall be
// considered or also the calculating time in-between
constexpr auto MEASURE_ONLY_IO = false;

enum MmAction {
    MM_ACTION_INIT_RETRO_ANAL = 1,
    MM_ACTION_PREPARE_COUNT_ARRAY = 2,
    MM_ACTION_PERFORM_RETRO_ANAL = 3,
    MM_ACTION_PERFORM_ALPHA_BETA = 4,
    MM_ACTION_TESTING_LAYER = 5,
    MM_ACTION_SAVING_LAYER_TO_FILE = 6,
    MM_ACTION_CALC_LAYER_STATS = 7,
    MM_ACTION_NONE = 8,
};

/*** Macros
 * ****************************************************************************/
#define SAFE_DELETE(p) \
    { \
        if (p) { \
            delete (p); \
            (p) = nullptr; \
        } \
    }

#define SAFE_DELETE_ARRAY(p) \
    { \
        if (p) { \
            delete[](p); \
            (p) = nullptr; \
        } \
    }

// here a macro is used instead of a function because the text 't' is passed
// like "blabla" << endl << aVariable
#define PRINT(v, c, t) \
    { \
        if (c->verbosity > v) { \
            EnterCriticalSection(&c->csOsPrint); \
            *c->osPrint << endl << t; \
            if (c->userPrintFunc != nullptr) { \
                c->userPrintFunc(c->pDataForUserPrintFunc); \
            } \
            LeaveCriticalSection(&c->csOsPrint); \
        } \
    }

/*** Classes
 * ****************************************************************************/
class MiniMax
{
    friend class MiniMaxWinInspectDb;
    friend class MiniMaxWinCalcDb;

public:
    /*** typedefines
     * ************************************************************************/
    // 2-Bit variable ranging from 0 to 3
    typedef unsigned char TwoBit;

    // 2 Bytes for saving the ply info
    typedef unsigned short PlyInfoVarType;

    // 1 Byte for counting predecessors
    typedef unsigned char CountArrayVarType;

    // 4 Bytes for addressing states within a layer
    typedef uint32_t StateNumberVarType;

    /*** protected structures
     * ************************************************************************/

    // header of the short knot value file
    struct SkvFileHeader
    {
        // true if all states have been calculated
        bool completed;

        // number of layers
        uint32_t LayerCount;

        // = SKV_FILE_HEADER_CODE
        uint32_t headerCode;

        // size in bytes of this struct plus the stats
        uint32_t headerAndStatsSize;
    };

    struct PlyInfoFileHeader
    {
        // true if ply info has been calculated for all game states
        bool plyInfoCompleted;

        // number of layers
        uint32_t LayerCount;

        // = PLYINFO_HEADER_CODE
        uint32_t headerCode;

        // size in bytes of this struct plus...
        uint32_t headerAndPlyInfosSize;
    };

    // this struct is created for each layer
    struct PlyInfo
    {
        // the array plyInfo[] exists in memory. does not necessary mean that it
        // contains only valid values
        bool plyInfoIsLoaded;

        // the array plyInfo[] contains only fully calculated valid values
        bool plyInfoIsCompletedAndInFile;

        // position of this struct in the ply info file
        int64_t layerOffset;

        // size of this struct plus the array plyInfo[]
        uint32_t sizeInBytes;

        // number of knots of the corresponding layer
        StateNumberVarType knotsInLayer;

        // array of size [knotsInLayer] containing the ply info for each knot in
        // this layer
        PlyInfoVarType *plyInfo;

        // compressed array containing the ply info for each knot in this layer
        // compressorClass::compressedArrayClass* plyInfoCompressed;

        void *plyInfoCompressed; // dummy pointer for padding
    };

    struct LayerStats
    {
        // the array shortKnotValueByte[] exists in memory. does not necessary
        // mean that it contains only valid values
        bool layerIsLoaded;

        // the array shortKnotValueByte[] contains only fully calculated valid
        // values
        bool layerIsCompletedAndInFile;

        // position of this struct in the short knot value file
        int64_t layerOffset;

        // number of succeeding layers. states of other layers are connected by
        // a move of a player
        uint32_t succeedingLayerCount;

        // array containing the layer ids of the succeeding layers
        uint32_t succeedingLayers[PRED_LAYER_COUNT_MAX];

        // layer id relevant when switching current and opponent player
        uint32_t partnerLayer;

        // number of knots of the corresponding layer
        StateNumberVarType knotsInLayer;

        // number of won states in this layer
        StateNumberVarType wonStateCount;

        // number of lost states in this layer
        StateNumberVarType lostStateCount;

        // number of drawn states in this layer
        StateNumberVarType drawnStateCount;

        // number of invalid states in this layer
        StateNumberVarType invalidStateCount;

        // (knotsInLayer + 3) / 4
        uint32_t sizeInBytes;

        // array of size [sizeInBytes] containing the short knot values
        TwoBit *shortKnotValueByte;

        // compressed array containing the short knot values
        // compressorClass::compressedArrayClass* skvCompressed;

        // dummy pointer for padding
        void *skvCompressed;
    };

    struct StateAdress
    {
        StateNumberVarType stateNumber; // state id within the corresponding
                                        // layer
        unsigned char layerNumber;      // layer id
    };

    struct Knot
    {
        bool isOpponentLevel;      // the current considered knot belongs to an
                                   // opponent game state
        float floatValue;          // Value of knot (for normal mode)
        TwoBit shortValue;         // Value of knot (for database)
        uint32_t bestMoveId;       // for calling class
        uint32_t bestBranch;       // branch with highest value
        uint32_t possibilityCount; // number of branches
        PlyInfoVarType plyInfo;    // number of moves till win/lost
        Knot *branches;            // pointer to branches
    };

    struct RetroAnalysisPredVars
    {
        uint32_t predStateNumbers;
        uint32_t predLayerNumbers;
        uint32_t predSymOp;
        bool playerToMoveChanged;
    };

    struct ArrayInfo
    {
        uint32_t type;
        int64_t sizeInBytes;
        int64_t compressedSizeInBytes;
        uint32_t belongsToLayer;
        uint32_t updateCounter;

        static const uint32_t arrayType_invalid = 0;
        static const uint32_t arrayType_knotAlreadyCalculated = 1;
        static const uint32_t arrayType_countArray = 2;
        static const uint32_t arrayType_plyInfos = 3;
        static const uint32_t arrayType_layerStats = 4;
        static const uint32_t arrayTypeCount = 5;

        static const uint32_t updateCounterThreshold = 100;
    };

    struct ArrayInfoChange
    {
        uint32_t itemIndex;
        ArrayInfo *arrayInfo;
    };

    struct ArrayInfoContainer
    {
        MiniMax *c;
        list<ArrayInfoChange> arrayInfosToBeUpdated;

        // [itemIndex]
        list<ArrayInfo> listArrays;

        // [layerNumber*ArrayInfo::arrayTypeCount + type]

        vector<list<ArrayInfo>::iterator> vectorArrays;

        void addArray(uint32_t layerNumber, uint32_t type, int64_t size,
                      int64_t compressedSize);
        void removeArray(uint32_t layerNumber, uint32_t type, int64_t size,
                         int64_t compressedSize);
    };

    /*** public functions
     * ************************************************************************/

    // Constructor / destructor
    MiniMax();
    virtual ~MiniMax();

    // Testing functions
    bool testLayer(uint32_t layerNumber);
    bool testIfSymStatesHaveSameValue(uint32_t layerNumber);

    // Statistics
    bool calcLayerStatistics(char *statisticsFileName);
    uint32_t getThreadCount();

    // Main function for getting the best choice
    void *getBestChoice(uint32_t tilLevel, uint32_t *choice,
                        uint32_t branchCountMax);

    // Database functions
    bool openDatabase(const char *dir, uint32_t branchCountMax);
    void calculateDatabase(uint32_t maxDepthOfTree, bool onlyPrepareLayer);
    bool isCurStateInDatabase(uint32_t threadNo);
    void closeDatabase();
    void unloadAllLayers();
    void unloadAllPlyInfos();

    // Virtual Functions
    virtual void prepareBestChoiceCalc()
    {
        while (true) {
        }
    }; // is called once before building the tree

    virtual uint32_t *getPossibilities(uint32_t threadNo,
                                       uint32_t *possibilityCount,
                                       bool *opponentsMove,
                                       void **pPossibilities)
    {
        while (true) {
        }
        return 0;
    }; // returns a pointer to the possibility-IDs

    virtual void deletePossibilities(uint32_t threadNo, void *pPossibilities)
    {
        while (true) {
        }
    };

    virtual void storeMoveValue(uint32_t threadNo, uint32_t idPossibility,
                                void *pPossibilities, TwoBit value,
                                uint32_t *freqValuesSubMoves,
                                PlyInfoVarType plyInfo)
    { }

    virtual void move(uint32_t threadNo, uint32_t idPossibility,
                      bool opponentsMove, void **pBackup, void *pPossibilities)
    {
        while (true) {
        }
    };

    virtual void undo(uint32_t threadNo, uint32_t idPossibility,
                      bool opponentsMove, void *pBackup, void *pPossibilities)
    {
        while (true) {
        }
    };

    virtual bool shallRetroAnalysisBeUsed(uint32_t layerNum) { return false; };

    virtual uint32_t getNumberOfLayers()
    {
        while (true) {
        }
        return 0;
    };

    virtual uint32_t getNumberOfKnotsInLayer(uint32_t layerNum)
    {
        while (true) {
        }
        return 0;
    };

    virtual void getSuccLayers(uint32_t layerNum, uint32_t *amountOfSuccLayers,
                               uint32_t *succeedingLayers)
    {
        while (true) {
        }
    };

    virtual uint32_t getPartnerLayer(uint32_t layerNum)
    {
        while (true) {
        }
        return 0;
    };

    virtual string getOutputInfo(uint32_t layerNum)
    {
        while (true) {
        }
        return string("");
    };

    virtual void setOpponentLevel(uint32_t threadNo, bool isOpponentLevel)
    {
        while (true) {
        }
    };

    virtual bool setSituation(uint32_t threadNo, uint32_t layerNum,
                              uint32_t stateNumber)
    {
        while (true) {
        }
        return false;
    };

    virtual void getSituationValue(uint32_t threadNo, float &floatValue,
                                   TwoBit &shortValue)
    {
        while (true) {
        }
    }; // value of situation for the initial current player

    virtual bool getOpponentLevel(uint32_t threadNo)
    {
        while (true) {
        }
        return false;
    };

    virtual uint32_t getLayerAndStateNumber(uint32_t threadNo,
                                            uint32_t &layerNum,
                                            uint32_t &stateNumber)
    {
        while (true) {
        }
        return 0;
    };
    virtual uint32_t getLayerNumber(uint32_t threadNo)
    {
        while (true) {
        }
        return 0;
    };

    virtual void getSymStateNumWithDoubles(uint32_t threadNo,
                                           uint32_t *nSymStates,
                                           uint32_t **symStateNumbers)
    {
        while (true) {
        }
    };

    virtual void getPredecessors(uint32_t threadNo, uint32_t *amountOfPred,
                                 RetroAnalysisPredVars *predVars)
    {
        while (true) {
        }
    };

    virtual void printBoard(uint32_t threadNo, unsigned char value)
    {
        while (true) {
        }
    };

    virtual void printMoveInfo(uint32_t threadNo, uint32_t idPossibility,
                               void *pPossibilities)
    {
        while (true) {
        }
    };

    virtual void prepareDatabaseCalc()
    {
        while (true) {
        }
    };

    virtual void wrapUpDatabaseCalc(bool calcAborted)
    {
        while (true) {
        }
    };

private:
    /*** classes for testing
     * *****************************************************************************************/

    struct TestLayersVars
    {
        MiniMax *pMiniMax;
        uint32_t curThreadNo;
        uint32_t layerNumber;
        LONGLONG statesProcessed;
        TwoBit *subValueInDatabase;
        PlyInfoVarType *subPlyInfos;
        bool *hasCurPlayerChanged;
    };

    /*** classes for the alpha beta algorithmn
     * ************************************************************************/

    // thread specific variables for each thread in the alpha beta algorithm
    struct AlphaBetaThreadVars
    {
        // thread specific variables for each thread in the alpha beta algorithm
        int64_t stateToProcessCount;

        uint32_t threadNo;
    };

    // constant during calculation
    struct AlphaBetaGlobalVars
    {
        // layer number of the current process layer
        uint32_t layerNumber;

        // total numbers of knots which have to be stored in memory
        int64_t totalKnotCount;

        // number of knots of all layers to be calculated
        int64_t knotToCalcCount;

        vector<AlphaBetaThreadVars> thread;
        uint32_t statsValueCounter[SKV_VALUE_COUNT];
        MiniMax *pMiniMax;

        AlphaBetaGlobalVars(MiniMax *pMiniMax, uint32_t layerNumber)
        {
            this->thread.resize(pMiniMax->threadManager.getThreadCount());
            for (uint32_t threadNo = 0;
                 threadNo < pMiniMax->threadManager.getThreadCount();
                 threadNo++) {
                this->thread[threadNo].stateToProcessCount = 0;
                this->thread[threadNo].threadNo = threadNo;
            }
            this->layerNumber = layerNumber;
            this->pMiniMax = pMiniMax;
            if (pMiniMax->layerStats) {
                this->knotToCalcCount = pMiniMax->layerStats[layerNumber]
                                            .knotsInLayer;
                this->totalKnotCount = pMiniMax->layerStats[layerNumber]
                                           .knotsInLayer;
            }
            this->statsValueCounter[SKV_VALUE_GAME_WON] = 0;
            this->statsValueCounter[SKV_VALUE_GAME_LOST] = 0;
            this->statsValueCounter[SKV_VALUE_GAME_DRAWN] = 0;
            this->statsValueCounter[SKV_VALUE_INVALID] = 0;
        }
    };

    struct AlphaBetaDefaultThreadVars
    {
        MiniMax *pMiniMax;
        AlphaBetaGlobalVars *alphaBetaVars;
        uint32_t layerNumber;
        LONGLONG statesProcessed;
        uint32_t statsValueCounter[SKV_VALUE_COUNT];

        AlphaBetaDefaultThreadVars() { }

        AlphaBetaDefaultThreadVars(MiniMax *pMiniMax,
                                   AlphaBetaGlobalVars *alphaBetaVars,
                                   uint32_t layerNumber)
        {
            this->statesProcessed = 0;
            this->layerNumber = layerNumber;
            this->pMiniMax = pMiniMax;
            this->alphaBetaVars = alphaBetaVars;
            for (uint32_t curStateValue = 0; curStateValue < SKV_VALUE_COUNT;
                 curStateValue++) {
                this->statsValueCounter[curStateValue] = 0;
            }
        };

        void reduceDefault()
        {
            pMiniMax->stateProcessedCount += this->statesProcessed;
            for (uint32_t curStateValue = 0; curStateValue < SKV_VALUE_COUNT;
                 curStateValue++) {
                alphaBetaVars->statsValueCounter[curStateValue] +=
                    this->statsValueCounter[curStateValue];
            }
        };
    };

    struct InitAlphaBetaVars : public ThreadManager::ThreadVarsArrayItem,
                               public AlphaBetaDefaultThreadVars
    {
        BufferedFile *bufferedFile;
        bool initAlreadyDone;

        InitAlphaBetaVars() { }

        InitAlphaBetaVars(MiniMax *pMiniMax, AlphaBetaGlobalVars *alphaBetaVars,
                          uint32_t layerNumber, BufferedFile *initArray,
                          bool initAlreadyDone)
            : AlphaBetaDefaultThreadVars(pMiniMax, alphaBetaVars, layerNumber)
        {
            this->bufferedFile = initArray;
            this->initAlreadyDone = initAlreadyDone;
        };

        void initElement(InitAlphaBetaVars &master) { *this = master; }

        void reduce() { reduceDefault(); }
    };

    struct RunAlphaBetaVars : public ThreadManager::ThreadVarsArrayItem,
                              public AlphaBetaDefaultThreadVars
    {
        // array of size [(fullTreeDepth - tilLevel) * maxNumBranches] for
        // storage of the branches at each search depth
        Knot *branchArray = nullptr;

        uint32_t *freqValuesSubMovesBranchWon = nullptr;
        uint32_t freqValuesSubMoves[4];

        RunAlphaBetaVars() { }

        RunAlphaBetaVars(MiniMax *pMiniMax, AlphaBetaGlobalVars *alphaBetaVars,
                         uint32_t layerNumber)
            : AlphaBetaDefaultThreadVars(pMiniMax, alphaBetaVars, layerNumber)
        {
            initElement(*this);
        };

        ~RunAlphaBetaVars()
        {
            SAFE_DELETE_ARRAY(branchArray);
            SAFE_DELETE_ARRAY(freqValuesSubMovesBranchWon);
        }

        void reduce() { reduceDefault(); }

        void initElement(RunAlphaBetaVars &master)
        {
            *this = master;
            branchArray = new Knot[alphaBetaVars->pMiniMax->maxNumBranches *
                                   alphaBetaVars->pMiniMax->fullTreeDepth];
            freqValuesSubMovesBranchWon =
                new uint32_t[alphaBetaVars->pMiniMax->maxNumBranches];
        };
    };

    /*** classes for the retro analysis
     * *******************************************************************************/

    struct RetroAnalysisQueueState
    {
        // state stored in the retro analysis queue. the queue is a buf
        // containing states to be passed to
        // 'RetroAnalysisThreadVars::statesToProcess'
        StateNumberVarType stateNumber;

        // ply number for the stored state
        PlyInfoVarType plyTillCurStateCount;
    };

    // thread specific variables for each thread in the retro analysis
    struct RetroAnalysisThreadVars
    {
        // vector-queue containing the states, whose short knot value are known
        // for sure. they have to be processed. if processed the state will be
        // removed from list. indexing: [threadNo][plyNumber]
        vector<CyclicArray *> statesToProcess;

        // Queue containing states, whose 'count value' shall be increased by
        // one. Before writing 'count value' to 'count array' the writing
        // positions are sorted for faster processing.
        vector<vector<RetroAnalysisQueueState>> stateQueue;

        // Number of states in 'statesToProcess' which have to be processed
        int64_t stateToProcessCount;

        uint32_t threadNo;
    };

    // constant during calculation
    struct retroAnalysisGlobalVars
    {
        // One count array for each layer in 'layersToCalculate'. (For the nine
        // men's morris game two layers have to considered at once.)
        vector<CountArrayVarType *> countArrays;

        vector<bool> layerInitialized;

        // layers which shall be calculated
        vector<uint32_t> layersToCalculate;

        // total numbers of knots which have to be stored in memory
        int64_t totalKnotCount;

        // number of knots of all layers to be calculated
        int64_t knotToCalcCount;

        vector<RetroAnalysisThreadVars> thread;
        uint32_t statsValueCounter[SKV_VALUE_COUNT];
        MiniMax *pMiniMax;
    };

    struct RetroAnalysisDefaultThreadVars
    {
        MiniMax *pMiniMax;
        retroAnalysisGlobalVars *retroVars;
        uint32_t layerNumber;
        LONGLONG statesProcessed;
        uint32_t statsValueCounter[SKV_VALUE_COUNT];

        RetroAnalysisDefaultThreadVars() { }

        RetroAnalysisDefaultThreadVars(MiniMax *pMiniMax,
                                       retroAnalysisGlobalVars *retroVars,
                                       uint32_t layerNumber)
        {
            this->statesProcessed = 0;
            this->layerNumber = layerNumber;
            this->pMiniMax = pMiniMax;
            this->retroVars = retroVars;
            for (uint32_t curStateValue = 0; curStateValue < SKV_VALUE_COUNT;
                 curStateValue++) {
                this->statsValueCounter[curStateValue] = 0;
            }
        };

        void reduceDefault()
        {
            pMiniMax->stateProcessedCount += this->statesProcessed;
            for (uint32_t curStateValue = 0; curStateValue < SKV_VALUE_COUNT;
                 curStateValue++) {
                retroVars->statsValueCounter[curStateValue] +=
                    this->statsValueCounter[curStateValue];
            }
        };
    };

    struct InitRetroAnalysisVars : public ThreadManager::ThreadVarsArrayItem,
                                   public RetroAnalysisDefaultThreadVars
    {
        BufferedFile *bufferedFile;
        bool initAlreadyDone;

        InitRetroAnalysisVars() { }

        InitRetroAnalysisVars(MiniMax *pMiniMax,
                              retroAnalysisGlobalVars *retroVars,
                              uint32_t layerNumber, BufferedFile *initArray,
                              bool initAlreadyDone)
            : RetroAnalysisDefaultThreadVars(pMiniMax, retroVars, layerNumber)
        {
            this->bufferedFile = initArray;
            this->initAlreadyDone = initAlreadyDone;
        };

        void initElement(InitRetroAnalysisVars &master) { *this = master; };

        void reduce() { reduceDefault(); }
    };

    struct AddNumSucceedersVars : public ThreadManager::ThreadVarsArrayItem,
                                  public RetroAnalysisDefaultThreadVars
    {
        RetroAnalysisPredVars predVars[PREDECESSOR_COUNT_MAX];

        AddNumSucceedersVars() { }

        AddNumSucceedersVars(MiniMax *pMiniMax,
                             retroAnalysisGlobalVars *retroVars,
                             uint32_t layerNumber)
            : RetroAnalysisDefaultThreadVars(pMiniMax, retroVars, layerNumber)
        { }

        void initElement(AddNumSucceedersVars &master) { *this = master; };

        void reduce() { reduceDefault(); }
    };

    /*** private variables
     * ********************************************************************************************/

    // variables, which are constant during database calculation
    int verbosity = 2; // output detail level. default is 2

    // [short knot value][current or opponent player] - A winning situation is a
    // loosing situation for the opponent and so on ...
    unsigned char skvPerspectiveMatrix[4][2];

    // true, if the database is currently being calculated
    bool calcDatabase = false;

    // handle of the file for the short knot value
    HANDLE hFileShortKnotValues = nullptr;

    // handle of the file for the ply info
    HANDLE hFilePlyInfo = nullptr;

    // short knot value file header
    SkvFileHeader skvfHeader;

    // header of the ply info file
    PlyInfoFileHeader plyInfoHeader;

    // path of the folder where the database files are located
    string fileDir;

    // stream for output. default is cout
    ostream *osPrint = nullptr;

    list<uint32_t> lastCalculatedLayer;

    // used in calcLayer() and getCurCalculatedLayers()
    vector<uint32_t> layersToCalculate;

    bool onlyPrepareLayer = false;

    // if true then process will stay in while loop
    bool stopOnCriticalError = true;

    ThreadManager threadManager;

    CRITICAL_SECTION csDatabase;

    // for thread safety when output is passed to osPrint
    CRITICAL_SECTION csOsPrint;

    // called every time output is passed to osPrint
    void (*userPrintFunc)(void *) = nullptr;

    // pointer passed when calling userPrintFunc
    void *pDataForUserPrintFunc = nullptr;

    // info about the arrays in memory
    ArrayInfoContainer arrayInfos;

    // thread specific or non-constant variables

    // memory in bytes used for storing: ply info, short knot value and
    // ...
    LONGLONG memoryUsed2 = 0;

    LONGLONG stateProcessedCount = 0;

    // maximum number of branches/moves
    uint32_t maxNumBranches = 0;

    // maximum search depth
    uint32_t fullTreeDepth = 0;

    // id of the currently calculated layer
    uint32_t curCalculatedLayer = 0;

    // one of ...
    uint32_t curCalcActionId = 0;

    // true if the current considered layer has already been calculated and
    // stored in the database
    bool layerInDatabase = false;

    // pointer to the structure passed by getPossibilities() for the state at
    // which getBestChoice() has been called
    void *pRootPossibilities = nullptr;

    // array of size [] containing general layer info and the skv of all
    // layers
    LayerStats *layerStats = nullptr;

    // array of size [] containing ply info
    PlyInfo *plyInfos = nullptr;

#if 0
    // variables concerning the compression of the database
    compressorClass *compressor = nullptr;

    // 0 or one of the COMPRESSOR_ALG_... constants
    uint32_t compressionAlgorithmnId = 0;
#endif

    // database I/O operations per second

    // number of read operations done since start of the program
    int64_t nReadSkvOps = 0;

    // number of write operations done since start of the program
    int64_t nWriteSkvOps = 0;

    // number of read operations done since start of the program
    int64_t nReadPlyOps = 0;

    // number of write operations done since start of the program
    int64_t nWritePlyOps = 0;

    // time of interval for read operations
    LARGE_INTEGER readSkvInterval;
    LARGE_INTEGER writeSkvInterval;
    LARGE_INTEGER readPlyInterval;
    LARGE_INTEGER writePlyInterval;

    // performance-counter frequency, in counts per second
    LARGE_INTEGER frequency;

    /*** private functions
     * ************************************************************************/

    // database functions
    void openSkvFile(const char *path, uint32_t branchCountMax);
    void openPlyInfoFile(const char *path);
    bool calcLayer(uint32_t layerNumber);
    void unloadPlyInfo(uint32_t layerNumber);
    void unloadLayer(uint32_t layerNumber);
    void saveHeader(SkvFileHeader *dbH, LayerStats *lStats);
    void saveHeader(PlyInfoFileHeader *piH, PlyInfo *pInfo);
    void readKnotValueFromDatabase(uint32_t threadNo, uint32_t &layerNumber,
                                   uint32_t &stateNumber, TwoBit &knotValue,
                                   bool &invalidLayerOrStateNumber,
                                   bool &layerInDatabaseAndCompleted);
    void readKnotValueFromDatabase(uint32_t layerNumber, uint32_t stateNumber,
                                   TwoBit &knotValue);
    void readPlyInfoFromDatabase(uint32_t layerNumber, uint32_t stateNumber,
                                 PlyInfoVarType &value);
    void saveKnotValueInDatabase(uint32_t layerNumber, uint32_t stateNumber,
                                 TwoBit knotValue);
    void savePlyInfoInDatabase(uint32_t layerNumber, uint32_t stateNumber,
                               PlyInfoVarType value);
    void loadBytesFromFile(HANDLE hFile, int64_t offset, uint32_t nBytes,
                           void *pBytes);
    void saveBytesToFile(HANDLE hFile, int64_t offset, uint32_t nBytes,
                         void *pBytes);
    void saveLayerToFile(uint32_t layerNumber);
    inline void measureIops(int64_t &nOps, LARGE_INTEGER &interval,
                            LARGE_INTEGER &curTimeBefore, char text[]);

    // Testing functions
    static DWORD testLayerThreadProc(void *pParam, uint32_t index);

    // Alpha-Beta-Algorithm
    bool calcKnotValuesByAlphaBeta(uint32_t layerNumber);
    bool initAlphaBeta(AlphaBetaGlobalVars &retroVars);
    bool runAlphaBeta(AlphaBetaGlobalVars &retroVars);
    void letTheTreeGrow(Knot *knot, RunAlphaBetaVars *rabVars,
                        uint32_t tilLevel, float alpha, float beta);
    bool alphaBetaTryDatabase(Knot *knot, RunAlphaBetaVars *rabVars,
                              uint32_t tilLevel, uint32_t &layerNumber,
                              uint32_t &stateNumber);
    void alphaBetaTryPossibilities(Knot *knot, RunAlphaBetaVars *rabVars,
                                   uint32_t tilLevel, uint32_t *idPossibility,
                                   void *pPossibilities,
                                   uint32_t &maxWonfreqValuesSubMoves,
                                   float &alpha, float &beta);
    void alphaBetaCalcPlyInfo(Knot *knot);
    void alphaBetaCalcKnotValue(Knot *knot);
    void alphaBetaChooseBestMove(Knot *knot, RunAlphaBetaVars *rabVars,
                                 uint32_t tilLevel, uint32_t *idPossibility,
                                 uint32_t maxWonfreqValuesSubMoves);
    void alphaBetaSaveInDatabase(uint32_t threadNo, uint32_t layerNumber,
                                 uint32_t stateNumber, TwoBit knotValue,
                                 PlyInfoVarType plyValue, bool invertValue);
    static DWORD initAlphaBetaThreadProc(void *pParam, uint32_t index);
    static DWORD runAlphaBetaThreadProc(void *pParam, uint32_t index);

    // Retro Analysis
    bool calcKnotValuesByRetroAnalysis(vector<uint32_t> &layersToCalculate);
    bool initRetroAnalysis(retroAnalysisGlobalVars &retroVars);
    bool prepareCountArrays(retroAnalysisGlobalVars &retroVars);
    bool calcNumSucceeders(retroAnalysisGlobalVars &retroVars);
    bool performRetroAnalysis(retroAnalysisGlobalVars &retroVars);
    bool addStateToProcessQueue(retroAnalysisGlobalVars &retroVars,
                                RetroAnalysisThreadVars &threadVars,
                                uint32_t plyNumber, StateAdress *pState);
    static bool retroAnalysisQueueStateComp(const RetroAnalysisQueueState &a,
                                            const RetroAnalysisQueueState &b)
    {
        return a.stateNumber < b.stateNumber;
    };
    static DWORD initRetroAnalysisThreadProc(void *pParam, uint32_t index);
    static DWORD addNumSucceedersThreadProc(void *pParam, uint32_t index);
    static DWORD performRetroAnalysisThreadProc(void *pParam);

    // Progress report functions
    void showLayerStats(uint32_t layerNumber);
    bool falseOrStop();
};

#endif // MINIMAX_H_INCLUDED
