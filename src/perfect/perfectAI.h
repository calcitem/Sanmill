/*********************************************************************\
    PerfectAI.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef PERFECT_AI_H_INCLUDED
#define PERFECT_AI_H_INCLUDED

#include "millAI.h"
#include "miniMax.h"
#include "types.h"
#include <cmath>
#include <cstdio>
#include <iostream>

// using namespace std;

// values of states/situations
#define VALUE_GAME_LOST (-1000.0f)
#define VALUE_GAME_WON 1000.0f

// since a state must be saved two times,
// one time where no piece must be removed,
// one time where a piece must be removed
constexpr auto MAX_NUM_PIECES_REMOVED_MINUS_1 = 2;

// 10 x 10 since each color can range from 0 to 9 pieces
// x2 since there is the placing phase and the moving phase
constexpr auto LAYER_COUNT = 200;
constexpr auto SUB_LAYER_COUNT_MAX = 100;

constexpr auto LAYER_INDEX_PLACING_PHASE = 1;
constexpr auto LAYER_INDEX_MOVING_PHASE = 0;
constexpr auto NOT_INDEXED = UINT_MAX;

constexpr auto TREE_DEPTH_MAX = 100;

constexpr auto PIECE_PER_PLAYER_COUNT = 9;
constexpr auto PIECE_PER_PLAYER_PLUS_ONE_COUNT = 10;

// The Four Groups (the board position is divided in four groups A,B,C,D)
constexpr auto nSquaresGroupA = 4;
constexpr auto nSquaresGroupB = 4;
constexpr auto nSquaresGroupC = 8;
constexpr auto nSquaresGroupD = 8;

enum Group { GROUP_A = 0, GROUP_B = 1, GROUP_C = 2, GROUP_D = 3 };

constexpr auto MAX_ANZ_POSITION_A = 81;
constexpr auto MAX_ANZ_POSITION_B = 81;
constexpr auto MAX_ANZ_POSITION_C = 81 * 81;
constexpr auto MAX_ANZ_POSITION_D = 81 * 81;

constexpr auto FREE_SQUARE = 0;

// Symmetry Ops
enum SymOp {
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
    SO_INV_MIRROR_VERT = 12,
    SO_INV_MIRROR_HORI = 13,
    SO_INV_MIRROR_DIAG_1 = 14,
    SO_INV_MIRROR_DIAG_2 = 15,
    SO_COUNT = 16,
};

class PerfectAI final : public MillAI, public MiniMax
{
protected:
    // struct
    struct SubLayer
    {
        uint32_t minIndex {0};
        uint32_t maxIndex {0};
        uint32_t nWhitePiecesGroupCD {0};
        uint32_t nBlackPiecesGroupCD {0};
        uint32_t nWhitePiecesGroupAB {0};
        uint32_t nBlackPiecesGroupAB {0};
    };

    struct Layer
    {
        uint32_t whitePieceCount {0};
        uint32_t blackPieceCount {0};
        uint32_t subLayerCount {0};
        uint32_t subLayerIndexAB[PIECE_PER_PLAYER_PLUS_ONE_COUNT]
                                [PIECE_PER_PLAYER_PLUS_ONE_COUNT] {{0}};
        uint32_t subLayerIndexCD[PIECE_PER_PLAYER_PLUS_ONE_COUNT]
                                [PIECE_PER_PLAYER_PLUS_ONE_COUNT] {{0}};
        SubLayer subLayer[SUB_LAYER_COUNT_MAX] {};
    };

    struct Possibility
    {
        uint32_t from[POSIBILE_MOVE_COUNT_MAX] {0};
        uint32_t to[POSIBILE_MOVE_COUNT_MAX] {0};
    };

    struct Backup
    {
        float floatValue {0.0f};
        TwoBit shortValue {0};
        bool gameHasFinished {false};
        bool isPlacingPhase {false};
        int fieldFrom {0}, fieldTo {0}; // value of board
        uint32_t from {0}, to {0};      // index of board
        uint32_t curPieceCount {0}, oppPieceCount {0};
        uint32_t curPosMoves {0}, oppPosMoves {0};
        uint32_t curMissPieces {0}, oppMissPieces {0};
        uint32_t piecePlacedCount {0};
        uint32_t pieceMustBeRemovedCount {0};
        uint32_t piecePartOfMillCount[SQUARE_NB] {0};
        Player *curPlayer {nullptr}, *oppPlayer {nullptr};
    };

    // preCalcedVars.dat
    struct PreCalcedVarsFileHeader
    {
        uint32_t sizeInBytes {0};
    };

    // constant variables for state addressing in the database

    // the layers
    Layer layer[LAYER_COUNT] {0};

    // indices of layer [moving/placing phase][number of white pieces][number of
    // black pieces]
    uint32_t layerIndex[2][PIECE_PER_PLAYER_PLUS_ONE_COUNT]
                       [PIECE_PER_PLAYER_PLUS_ONE_COUNT] {{{0}}};

    uint32_t nPositionsCD[PIECE_PER_PLAYER_PLUS_ONE_COUNT]
                         [PIECE_PER_PLAYER_PLUS_ONE_COUNT] {{0}};

    uint32_t nPositionsAB[PIECE_PER_PLAYER_PLUS_ONE_COUNT]
                         [PIECE_PER_PLAYER_PLUS_ONE_COUNT] {{0}};

    uint32_t indexAB[MAX_ANZ_POSITION_A * MAX_ANZ_POSITION_B] {0};

    uint32_t indexCD[MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D] {0};

    // index of symmetry operation used to get from the orig state to the
    // current one
    unsigned char symOpCD[MAX_ANZ_POSITION_C * MAX_ANZ_POSITION_D] {0};

    // 3^0, 3^1, 3^2, ...
    uint32_t powerOfThree[nSquaresGroupC + nSquaresGroupD] {0};

    // Matrix used for application of the symmetry operations
    uint32_t symOpTable[SO_COUNT][SQUARE_NB] {{0}};

    uint32_t *origStateCD[PIECE_PER_PLAYER_PLUS_ONE_COUNT]
                         [PIECE_PER_PLAYER_PLUS_ONE_COUNT] {{nullptr}};

    uint32_t *origStateAB[PIECE_PER_PLAYER_PLUS_ONE_COUNT]
                         [PIECE_PER_PLAYER_PLUS_ONE_COUNT] {{nullptr}};

    // index of the reverse symmetry operation
    uint32_t reverseSymOp[SO_COUNT] {0};

    // symmetry operation, which is identical to applying those two in the index
    uint32_t concSymOp[SO_COUNT][SO_COUNT] {{0}};

    // m over n
    uint32_t mOverN[SQUARE_NB + 1][SQUARE_NB + 1] {{0}};

    // contains the value of the situation, which will be achieved by that move
    unsigned char moveValue[SQUARE_NB * SQUARE_NB] {0};

    // contains the value of the situation, which will be achieved by that move
    unsigned short plyInfoForOutput[SQUARE_NB * SQUARE_NB] {0};

    // contains the number of ...
    uint32_t incidencesValuesSubMoves[SQUARE_NB * SQUARE_NB][4] {{0}};

    // array for state numbers
    uint32_t symStateNumberArray[SO_COUNT] {0};

    // dir containing the database files
    string databaseDir;

    // Variables used individually by each single thread
    class ThreadVars
    {
    public:
        // pointer of the current board [changed by move()]
        fieldStruct *field {nullptr};

        // value of current situation for board->curPlayer
        float floatValue {0.0f};

        TwoBit shortValue {0};

        // someone has won or current board is full
        bool gameHasFinished {false};

        // id of the player who called the play()-function
        int ownId {0};

        // current level
        uint32_t curSearchDepth {0};

        // search depth where the whole tree is explored
        uint32_t fullTreeDepth {0};

        // returned pointer of getPossibilities()-function
        uint32_t *idPossibilities {nullptr};

        // for undo()-function
        Backup *oldStates {nullptr};

        // for getPossNormalMove()-function
        Possibility *possibilities {nullptr};

        PerfectAI *parent {nullptr};

        // constructor
        ThreadVars();

        // Functions
        uint32_t *getPossPlacingPhase(uint32_t *possibilityCount,
                                      void **pPossibilities) const;
        uint32_t *getPossNormalMove(uint32_t *possibilityCount,
                                    void **pPossibilities) const;
        uint32_t *getPossPieceRemove(uint32_t *possibilityCount,
                                     void **pPossibilities) const;

        // move functions
        inline void updatePossibleMoves(uint32_t piece, Player *pieceOwner,
                                        bool pieceRemoved,
                                        uint32_t ignorePiece) const;
        inline void updateWarning(uint32_t firstPiece,
                                  uint32_t secondPiece) const;
        inline void setWarning(uint32_t pieceOne, uint32_t pieceTwo,
                               uint32_t pieceThree) const;
        inline void removePiece(uint32_t from, Backup *backup);
        inline void setPiece(uint32_t to, Backup *backup) const;
        inline void normalMove(uint32_t from, uint32_t to,
                               Backup *backup) const;

        // database functions
        uint32_t getLayerAndStateNumber(uint32_t &layerNum,
                                        uint32_t &stateNumber) const;
        void setWarningAndMill(uint32_t piece, uint32_t firstNeighbor,
                               uint32_t secondNeighbor) const;
        bool fieldIntegrityOK(uint32_t nMillsCurPlayer,
                              uint32_t nMillsOpponentPlayer,
                              bool aPieceCanBeRemovedFromCurPlayer) const;
        void generateMoves(Player *player) const;
        void storePredecessor(uint32_t nMillsCurPlayer,
                              uint32_t nMillsOpponentPlayer,
                              uint32_t *amountOfPred,
                              RetroAnalysisPredVars *predVars) const;
    };

    ThreadVars *threadVars;

    // database functions
    uint32_t getNumberOfLayers() override;
    uint32_t getNumberOfKnotsInLayer(uint32_t layerNum) override;
    static int64_t mOverN_Function(uint32_t m, uint32_t n);
    void applySymOpOnField(unsigned char symOpNumber,
                           const uint32_t *sourceField,
                           uint32_t *destField) const;
    bool isSymOpInvariantOnGroupCD(uint32_t symOp, const int *theField) const;
    bool shallRetroAnalysisBeUsed(uint32_t layerNum) override;
    void getSuccLayers(uint32_t layerNum, uint32_t *amountOfSuccLayers,
                       uint32_t *succeedingLayers) override;
    void getPredecessors(uint32_t threadNo, uint32_t *amountOfPred,
                         RetroAnalysisPredVars *predVars) override;
    bool setSituation(uint32_t threadNo, uint32_t layerNum,
                      uint32_t stateNumber) override;
    uint32_t getLayerNumber(uint32_t threadNo) override;
    uint32_t getLayerAndStateNumber(uint32_t threadNo, uint32_t &layerNum,
                                    uint32_t &stateNumber) override;

    // Virtual Functions
    void prepareBestChoiceCalc() override;
    void getSituationValue(uint32_t threadNo, float &floatValue,
                           TwoBit &shortValue) override;
    void setOpponentLevel(uint32_t threadNo, bool isOpponentLevel) override;
    bool getOpponentLevel(uint32_t threadNo) override;
    void deletePossibilities(uint32_t threadNo, void *pPossibilities) override;
    uint32_t *getPossibilities(uint32_t threadNo, uint32_t *possibilityCount,
                               bool *opponentsMove,
                               void **pPossibilities) override;
    void undo(uint32_t threadNo, uint32_t idPossibility, bool opponentsMove,
              void *pBackup, void *pPossibilities) override;
    void move(uint32_t threadNo, uint32_t idPossibility, bool opponentsMove,
              void **pBackup, void *pPossibilities) override;
    void printMoveInfo(uint32_t threadNo, uint32_t idPossibility,
                       void *pPossibilities) override;
    void storeMoveValue(uint32_t threadNo, uint32_t idPossibility,
                        void *pPossibilities, unsigned char value,
                        uint32_t *freqValuesSubMoves,
                        PlyInfoVarType plyInfo) override;
    void getSymStateNumWithDoubles(uint32_t threadNo, uint32_t *nSymStates,
                                   uint32_t **symStateNumbers) override;
    void printBoard(uint32_t threadNo, unsigned char value) override;
    string getOutputInfo(uint32_t layerNum) override;
    uint32_t getPartnerLayer(uint32_t layerNum) override;
    void prepareDatabaseCalc() override;
    void wrapUpDatabaseCalc(bool calcuAborted) override;

public:
    // Constructor / destructor
    explicit PerfectAI(const char *dir);
    ~PerfectAI() override;

    // Functions
    bool setDatabasePath(const char *dir);
    void play(fieldStruct *theField, uint32_t *pushFrom,
              uint32_t *pushTo) override;
    void getLayerAndStateNumber(uint32_t &layerNum,
                                uint32_t &stateNumber) const;

    // Testing functions
    bool testLayers(uint32_t startTestFromLayer, uint32_t endTestAtLayer);
};

#endif // PERFECT_AI_H_INCLUDED
