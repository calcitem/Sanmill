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
#include "types.h"
#include <cstdio>
#include <iostream>
#include <math.h>

// using namespace std;

// values of states/situations
#define VALUE_GAME_LOST -1000.0f
#define VALUE_GAME_WON 1000.0f

// since a state must be saved two times,
// one time where no piece must be removed,
// one time where a piece must be removed
constexpr auto MAX_NUM_PIECES_REMOVED_MINUS_1 = 2;

// 10 x 10 since each color can range from 0 to 9 pieces
// x2 since there is the placing phase and the moving phase
constexpr auto NUM_LAYERS = 200;
constexpr auto MAX_NUM_SUB_LAYERS = 100;
constexpr auto LAYER_INDEX_PLACING_PHASE = 1;
constexpr auto LAYER_INDEX_MOVING_PHASE = 0;
constexpr auto NOT_INDEXED = 4294967295;
constexpr auto MAX_DEPTH_OF_TREE = 100;
constexpr auto NUM_PIECES_PER_PLAYER = 9;
constexpr auto NUM_PIECES_PER_PLAYER_PLUS_ONE = 10;

// The Four Groups (the board position is divided in four groups A,B,C,D)
constexpr auto nSquaresGroupA = 4;
constexpr auto nSquaresGroupB = 4;
constexpr auto nSquaresGroupC = 8;
constexpr auto nSquaresGroupD = 8;

enum Group { GROUP_A = 0, GROUP_B = 1, GROUP_C = 2, GROUP_D = 3 };

constexpr auto MAX_ANZ_POSITION_A = 81;
constexpr auto MAX_ANZ_POSITION_B = 81;
constexpr auto MAX_ANZ_POSITION_C = (81 * 81);
constexpr auto MAX_ANZ_POSITION_D = (81 * 81);

constexpr auto FREE_SQUARE = 0;

// Symmetry Operations
enum SymOperation {
    SO_TURN_LEFT = 0,
    SO_TURN_180 = 1,
    SO_TURN_RIGHT = 2,
    SO_DO_NOTHING = 3,
    SO_INVERT = 4,
    SO_MIRROR_VERT = 5,
    SO_MIRROR_HORI = 6,
    SO_MIRROR_DIAG_1 = 7,
    SO_MIRROR_DIAG_2 = 8,
    SO_INV_LEFT = 9,
    SO_INV_RIGHT = 10,
    SO_INV_180 = 11,
    SO_INV_MIR_VERT = 12,
    SO_INV_MIR_HORI = 13,
    SO_INV_MIR_DIAG_1 = 14,
    SO_INV_MIR_DIAG_2 = 15,
    SO_COUNT = 16,
};

class PerfectAI : public MillAI, public MiniMax
{
protected:
    // struct
    struct SubLayer
    {
        unsigned int minIndex;
        unsigned int maxIndex;
        unsigned int nWhitePiecesGroupCD, nBlackPiecesGroupCD;
        unsigned int nWhitePiecesGroupAB, nBlackPiecesGroupAB;
    };

    struct Layer
    {
        unsigned int whitePieceCount;
        unsigned int blackPieceCount;
        unsigned int subLayerCount;
        unsigned int subLayerIndexAB[NUM_PIECES_PER_PLAYER_PLUS_ONE]
                                    [NUM_PIECES_PER_PLAYER_PLUS_ONE];
        unsigned int subLayerIndexCD[NUM_PIECES_PER_PLAYER_PLUS_ONE]
                                    [NUM_PIECES_PER_PLAYER_PLUS_ONE];
        SubLayer subLayer[MAX_NUM_SUB_LAYERS];
    };

    struct Possibility
    {
        unsigned int from[POSIBILE_MOVE_COUNT_MAX];
        unsigned int to[POSIBILE_MOVE_COUNT_MAX];
    };

    struct Backup
    {
        float floatValue;
        TwoBit shortValue;
        bool gameHasFinished;
        bool placingPhase;
        int fieldFrom, fieldTo; // value of board
        unsigned int from, to;  // index of board
        unsigned int curPieceCount, oppPieceCount;
        unsigned int curPosMoves, oppPosMoves;
        unsigned int curMissPieces, oppMissPieces;
        unsigned int piecesSet;
        unsigned int pieceMustBeRemoved;
        unsigned int piecePartOfMill[SQUARE_NB];
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

    // indices of layer [moving/placing phase][number of white pieces][number of
    // black pieces]
    unsigned int layerIndex[2][NUM_PIECES_PER_PLAYER_PLUS_ONE]
                           [NUM_PIECES_PER_PLAYER_PLUS_ONE];

    unsigned int nPositionsCD[NUM_PIECES_PER_PLAYER_PLUS_ONE]
                             [NUM_PIECES_PER_PLAYER_PLUS_ONE];

    unsigned int nPositionsAB[NUM_PIECES_PER_PLAYER_PLUS_ONE]
                             [NUM_PIECES_PER_PLAYER_PLUS_ONE];

    unsigned int indexAB[MAX_ANZ_POSITION_A * MAX_ANZ_POSITION_B];

    unsigned int indexCD[MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D];

    // index of symmetry operation used to get from the original state to the
    // current one
    unsigned char symmetryOperationCD[MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D];

    // 3^0, 3^1, 3^2, ...
    unsigned int powerOfThree[nSquaresGroupC + nSquaresGroupD];

    // Matrix used for application of the symmetry operations
    unsigned int symmetryOperationTable[SO_COUNT][SQUARE_NB];

    unsigned int *originalStateCD[NUM_PIECES_PER_PLAYER_PLUS_ONE]
                                 [NUM_PIECES_PER_PLAYER_PLUS_ONE];

    unsigned int *originalStateAB[NUM_PIECES_PER_PLAYER_PLUS_ONE]
                                 [NUM_PIECES_PER_PLAYER_PLUS_ONE];

    // index of the reverse symmetry operation
    unsigned int reverseSymOperation[SO_COUNT];

    // symmetry operation, which is identical to applying those two in the index
    unsigned int concSymOperation[SO_COUNT][SO_COUNT];

    // m over n
    unsigned int mOverN[SQUARE_NB + 1][SQUARE_NB + 1];

    // contains the value of the situation, which will be achieved by that move
    unsigned char valueOfMove[SQUARE_NB * SQUARE_NB];

    // contains the value of the situation, which will be achieved by that move
    unsigned short plyInfoForOutput[SQUARE_NB * SQUARE_NB];

    // contains the number of ...
    unsigned int incidencesValuesSubMoves[SQUARE_NB * SQUARE_NB][4];

    // array for state numbers
    unsigned int symmetricStateNumberArray[SO_COUNT];

    // dir containing the database files
    string databaseDir;

    // Variables used individually by each single thread
    class ThreadVars
    {
    public:
        // pointer of the current board [changed by move()]
        fieldStruct *field;

        // value of current situation for board->curPlayer
        float floatValue;

        TwoBit shortValue;

        // someone has won or current board is full
        bool gameHasFinished;

        // id of the player who called the play()-function
        int ownId;

        // current level
        unsigned int curSearchDepth;

        // search depth where the whole tree is explored
        unsigned int fullTreeDepth;

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
        unsigned int *getPossPlacingPhase(unsigned int *possibilityCount,
                                          void **pPossibilities);
        unsigned int *getPossNormalMove(unsigned int *possibilityCount,
                                        void **pPossibilities);
        unsigned int *getPossPieceRemove(unsigned int *possibilityCount,
                                         void **pPossibilities);

        // move functions
        inline void updatePossibleMoves(unsigned int piece, Player *pieceOwner,
                                        bool pieceRemoved,
                                        unsigned int ignorePiece);
        inline void updateWarning(unsigned int firstPiece,
                                  unsigned int secondPiece);
        inline void setWarning(unsigned int pieceOne, unsigned int pieceTwo,
                               unsigned int pieceThree);
        inline void removePiece(unsigned int from, Backup *backup);
        inline void setPiece(unsigned int to, Backup *backup);
        inline void normalMove(unsigned int from, unsigned int to,
                               Backup *backup);

        // database functions
        unsigned int getLayerAndStateNumber(unsigned int &layerNum,
                                            unsigned int &stateNumber);
        void setWarningAndMill(unsigned int piece, unsigned int firstNeighbor,
                               unsigned int secondNeighbor);
        bool fieldIntegrityOK(unsigned int nMillsCurPlayer,
                              unsigned int nMillsOpponentPlayer,
                              bool aPieceCanBeRemovedFromCurPlayer);
        void generateMoves(Player *player);
        void storePredecessor(unsigned int nMillsCurPlayer,
                              unsigned int nMillsOpponentPlayer,
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
                       unsigned int *succeedingLayers);
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
    void getSituationValue(unsigned int threadNo, float &floatValue,
                             TwoBit &shortValue);
    void setOpponentLevel(unsigned int threadNo, bool isOpponentLevel);
    bool getOpponentLevel(unsigned int threadNo);
    void deletePossibilities(unsigned int threadNo, void *pPossibilities);
    unsigned int *getPossibilities(unsigned int threadNo,
                                   unsigned int *possibilityCount,
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
                                   unsigned int *nSymmetricStates,
                                   unsigned int **symStateNumbers);
    void printBoard(unsigned int threadNo, unsigned char value);
    string getOutputInformation(unsigned int layerNum);
    unsigned int getPartnerLayer(unsigned int layerNum);
    void prepareDatabaseCalculation();
    void wrapUpDatabaseCalculation(bool calculationAborted);

public:
    // Constructor / destructor
    explicit PerfectAI(const char *dir);
    ~PerfectAI();

    // Functions
    bool setDatabasePath(const char *dir);
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
