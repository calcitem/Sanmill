/*********************************************************************\
    PerfectAI.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef PERFECT_AI_H_INCLUDED
#define PERFECT_AI_H_INCLUDED

#include "millAI.h"
#include "miniMax.h"
#include <cstdio>
#include <iostream>
#include <math.h>

// using namespace std;

// values of states/situations
#define VALUE_GAME_LOST -1000.0f
#define VALUE_GAME_WON 1000.0f

// since a state must be saved two times,
// one time where no stone must be removed,
// one time where a stone must be removed
#define MAX_NUM_STONES_REMOVED_MINUS_1 2

// 10 x 10 since each color can range from 0 to 9 stones
// x2 since there is the setting phase and the moving phase
#define NUM_LAYERS 200
#define MAX_NUM_SUB_LAYERS 100
#define LAYER_INDEX_SETTING_PHASE 1
#define LAYER_INDEX_MOVING_PHASE 0
#define NOT_INDEXED 4294967295
#define MAX_DEPTH_OF_TREE 100
#define NUM_STONES_PER_PLAYER 9
#define NUM_STONES_PER_PLAYER_PLUS_ONE 10

// The Four Groups (the board position is divided in four groups A,B,C,D)
#define numSquaresGroupA 4
#define numSquaresGroupB 4
#define numSquaresGroupC 8
#define numSquaresGroupD 8
#define GROUP_A 0
#define GROUP_B 1
#define GROUP_C 2
#define GROUP_D 3
#define MAX_ANZ_POSITION_A 81
#define MAX_ANZ_POSITION_B 81
#define MAX_ANZ_POSITION_C (81 * 81)
#define MAX_ANZ_POSITION_D (81 * 81)

#define FREE_SQUARE 0
#define WHITE_STONE 1
#define BLACK_STONE 2

// Symmetry Operations
#define SO_TURN_LEFT 0
#define SO_TURN_180 1
#define SO_TURN_RIGHT 2
#define SO_DO_NOTHING 3
#define SO_INVERT 4
#define SO_MIRROR_VERT 5
#define SO_MIRROR_HORI 6
#define SO_MIRROR_DIAG_1 7
#define SO_MIRROR_DIAG_2 8
#define SO_INV_LEFT 9
#define SO_INV_RIGHT 10
#define SO_INV_180 11
#define SO_INV_MIR_VERT 12
#define SO_INV_MIR_HORI 13
#define SO_INV_MIR_DIAG_1 14
#define SO_INV_MIR_DIAG_2 15
#define NUM_SYM_OPERATIONS 16

class PerfectAI : public MillAI, public MiniMax
{
protected:
    // structs
    struct SubLayer
    {
        unsigned int minIndex;
        unsigned int maxIndex;
        unsigned int numWhiteStonesGroupCD, numBlackStonesGroupCD;
        unsigned int numWhiteStonesGroupAB, numBlackStonesGroupAB;
    };

    struct Layer
    {
        unsigned int numWhiteStones;
        unsigned int numBlackStones;
        unsigned int numSubLayers;
        unsigned int subLayerIndexAB[NUM_STONES_PER_PLAYER_PLUS_ONE]
                                    [NUM_STONES_PER_PLAYER_PLUS_ONE];
        unsigned int subLayerIndexCD[NUM_STONES_PER_PLAYER_PLUS_ONE]
                                    [NUM_STONES_PER_PLAYER_PLUS_ONE];
        SubLayer subLayer[MAX_NUM_SUB_LAYERS];
    };

    struct Possibility
    {
        unsigned int from[MAX_NUM_POS_MOVES];
        unsigned int to[MAX_NUM_POS_MOVES];
    };

    struct Backup
    {
        float floatValue;
        TwoBit shortValue;
        bool gameHasFinished;
        bool settingPhase;
        int fieldFrom, fieldTo; // value of board
        unsigned int from, to;  // index of board
        unsigned int curNumStones, oppNumStones;
        unsigned int curPosMoves, oppPosMoves;
        unsigned int curMissStones, oppMissStones;
        unsigned int stonesSet;
        unsigned int stoneMustBeRemoved;
        unsigned int stonePartOfMill[fieldStruct::size];
        Player *curPlayer, *oppPlayer;
    };

    // preCalcedVars.dat
    struct PreCalcedVarsFileHeader
    {
        unsigned int sizeInBytes;
    };

    // constant variables for state addressing in the database

    // the layers
    Layer layer[NUM_LAYERS];

    // indices of layer [moving/setting phase][number of white stones][number of
    // black stones]
    unsigned int layerIndex[2][NUM_STONES_PER_PLAYER_PLUS_ONE]
                           [NUM_STONES_PER_PLAYER_PLUS_ONE];

    unsigned int numPositionsCD[NUM_STONES_PER_PLAYER_PLUS_ONE]
                               [NUM_STONES_PER_PLAYER_PLUS_ONE];

    unsigned int numPositionsAB[NUM_STONES_PER_PLAYER_PLUS_ONE]
                               [NUM_STONES_PER_PLAYER_PLUS_ONE];

    unsigned int indexAB[MAX_ANZ_POSITION_A * MAX_ANZ_POSITION_B];

    unsigned int indexCD[MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D];

    // index of symmetry operation used to get from the original state to the
    // current one
    unsigned char symmetryOperationCD[MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D];

    // 3^0, 3^1, 3^2, ...
    unsigned int powerOfThree[numSquaresGroupC + numSquaresGroupD];

    // Matrix used for application of the symmetry operations
    unsigned int symmetryOperationTable[NUM_SYM_OPERATIONS][fieldStruct::size];

    unsigned int *originalStateCD[NUM_STONES_PER_PLAYER_PLUS_ONE]
                                 [NUM_STONES_PER_PLAYER_PLUS_ONE];

    unsigned int *originalStateAB[NUM_STONES_PER_PLAYER_PLUS_ONE]
                                 [NUM_STONES_PER_PLAYER_PLUS_ONE];

    // index of the reverse symmetry operation
    unsigned int reverseSymOperation[NUM_SYM_OPERATIONS];

    // symmetry operation, which is identical to applying those two in the index
    unsigned int concSymOperation[NUM_SYM_OPERATIONS][NUM_SYM_OPERATIONS];

    // m over n
    unsigned int mOverN[fieldStruct::size + 1][fieldStruct::size + 1];

    // contains the value of the situation, which will be achieved by that move
    unsigned char valueOfMove[fieldStruct::size * fieldStruct::size];

    // contains the value of the situation, which will be achieved by that move
    unsigned short plyInfoForOutput[fieldStruct::size * fieldStruct::size];

    // contains the number of ...
    unsigned int incidencesValuesSubMoves[fieldStruct::size * fieldStruct::size]
                                         [4];

    // array for state numbers
    unsigned int symmetricStateNumberArray[NUM_SYM_OPERATIONS];

    // directory containing the database files
    string databaseDirectory;

    // Variables used individually by each single thread
    class ThreadVars
    {
    public:
        // pointer of the current board [changed by move()]
        fieldStruct *field;

        // value of current situation for board->currentPlayer
        float floatValue;

        TwoBit shortValue;

        // someone has won or current board is full
        bool gameHasFinished;

        // id of the player who called the play()-function
        int ownId;

        // current level
        unsigned int curSearchDepth;

        // search depth where the whole tree is explored
        unsigned int depthOfFullTree;

        // returned pointer of getPossibilities()-function
        unsigned int *idPossibilities;

        // for undo()-function
        Backup *oldStates;

        // for getPossNormalMove()-function
        Possibility *possibilities;

        PerfectAI *parent;

        // constructor
        ThreadVars();

        // Functions
        unsigned int *getPossSettingPhase(unsigned int *numPossibilities,
                                          void **pPossibilities);
        unsigned int *getPossNormalMove(unsigned int *numPossibilities,
                                        void **pPossibilities);
        unsigned int *getPossStoneRemove(unsigned int *numPossibilities,
                                         void **pPossibilities);

        // move functions
        inline void updatePossibleMoves(unsigned int stone, Player *stoneOwner,
                                        bool stoneRemoved,
                                        unsigned int ignoreStone);
        inline void updateWarning(unsigned int firstStone,
                                  unsigned int secondStone);
        inline void setWarning(unsigned int stoneOne, unsigned int stoneTwo,
                               unsigned int stoneThree);
        inline void removeStone(unsigned int from, Backup *backup);
        inline void setStone(unsigned int to, Backup *backup);
        inline void normalMove(unsigned int from, unsigned int to,
                               Backup *backup);

        // database functions
        unsigned int getLayerAndStateNumber(unsigned int &layerNum,
                                            unsigned int &stateNumber);
        void setWarningAndMill(unsigned int stone, unsigned int firstNeighbour,
                               unsigned int secondNeighbour);
        bool fieldIntegrityOK(unsigned int numberOfMillsCurrentPlayer,
                              unsigned int numberOfMillsOpponentPlayer,
                              bool aStoneCanBeRemovedFromCurPlayer);
        void calcPossibleMoves(Player *player);
        void storePredecessor(unsigned int numberOfMillsCurrentPlayer,
                              unsigned int numberOfMillsOpponentPlayer,
                              unsigned int *amountOfPred,
                              RetroAnalysisPredVars *predVars);
    };

    ThreadVars *threadVars;

    // database functions
    unsigned int getNumberOfLayers();
    unsigned int getNumberOfKnotsInLayer(unsigned int layerNum);
    int64_t mOverN_Function(unsigned int m, unsigned int n);
    void applySymmetryOperationOnField(unsigned char symmetryOperationNumber,
                                       unsigned int *sourceField,
                                       unsigned int *destField);
    bool isSymOperationInvariantOnGroupCD(unsigned int symmetryOperation,
                                          int *theField);
    bool shallRetroAnalysisBeUsed(unsigned int layerNum);
    void getSuccLayers(unsigned int layerNum, unsigned int *amountOfSuccLayers,
                       unsigned int *succLayers);
    void getPredecessors(unsigned int threadNo, unsigned int *amountOfPred,
                         RetroAnalysisPredVars *predVars);
    bool setSituation(unsigned int threadNo, unsigned int layerNum,
                      unsigned int stateNumber);
    unsigned int getLayerNumber(unsigned int threadNo);
    unsigned int getLayerAndStateNumber(unsigned int threadNo,
                                        unsigned int &layerNum,
                                        unsigned int &stateNumber);

    // integrity test functions
    bool checkMoveAndSetSituation();
    bool checkGetPossThanGetPred();
    bool checkGetPredThanGetPoss();

    // Virtual Functions
    void prepareBestChoiceCalculation();
    void getValueOfSituation(unsigned int threadNo, float &floatValue,
                             TwoBit &shortValue);
    void setOpponentLevel(unsigned int threadNo, bool isOpponentLevel);
    bool getOpponentLevel(unsigned int threadNo);
    void deletePossibilities(unsigned int threadNo, void *pPossibilities);
    unsigned int *getPossibilities(unsigned int threadNo,
                                   unsigned int *numPossibilities,
                                   bool *opponentsMove, void **pPossibilities);
    void undo(unsigned int threadNo, unsigned int idPossibility,
              bool opponentsMove, void *pBackup, void *pPossibilities);
    void move(unsigned int threadNo, unsigned int idPossibility,
              bool opponentsMove, void **pBackup, void *pPossibilities);
    void printMoveInformation(unsigned int threadNo, unsigned int idPossibility,
                              void *pPossibilities);
    void storeValueOfMove(unsigned int threadNo, unsigned int idPossibility,
                          void *pPossibilities, unsigned char value,
                          unsigned int *freqValuesSubMoves,
                          PlyInfoVarType plyInfo);
    void getSymStateNumWithDoubles(unsigned int threadNo,
                                   unsigned int *numSymmetricStates,
                                   unsigned int **symStateNumbers);
    void printBoard(unsigned int threadNo, unsigned char value);
    string getOutputInformation(unsigned int layerNum);
    unsigned int getPartnerLayer(unsigned int layerNum);
    void prepareDatabaseCalculation();
    void wrapUpDatabaseCalculation(bool calculationAborted);

public:
    // Constructor / destructor
    explicit PerfectAI(const char *directory);
    ~PerfectAI();

    // Functions
    bool setDatabasePath(const char *directory);
    void play(fieldStruct *theField, unsigned int *pushFrom,
              unsigned int *pushTo);
    void getValueOfMoves(unsigned char *moveValue,
                         unsigned int *freqValuesSubMoves,
                         PlyInfoVarType *plyInfo, unsigned int *moveQuality,
                         unsigned char &knotValue,
                         PlyInfoVarType &bestAmountOfPlies);
    void getField(unsigned int layerNum, unsigned int stateNumber,
                  fieldStruct *field, bool *gameHasFinished);
    void getLayerAndStateNumber(unsigned int &layerNum,
                                unsigned int &stateNumber);

    // Testing functions
    bool testLayers(unsigned int startTestFromLayer,
                    unsigned int endTestAtLayer);
};

#endif // PERFECT_AI_H_INCLUDED
