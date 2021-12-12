/*********************************************************************\
    MiniMaxAI.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#ifndef MINIMAX_AI_H_INCLUDED
#define MINIMAX_AI_H_INCLUDED

#include "millAI.h"
#include "miniMax.h"
#include <cstdio>
#include <iostream>
#include <math.h>

// using namespace std;

#define VALUE_GAME_LOST -1000.0f
#define VALUE_GAME_WON 1000.0f

class MiniMaxAI : public MillAI, MiniMax
{
protected:
    // structs
    struct Possibility
    {
        unsigned int from[POSIBILE_MOVE_COUNT_MAX];
        unsigned int to[POSIBILE_MOVE_COUNT_MAX];
    };

    struct Backup
    {
        float value;
        bool gameHasFinished;
        bool settingPhase;
        int fieldFrom, fieldTo; // value of board
        unsigned int from, to;  // index of board
        unsigned int curPieceCount, oppPieceCount;
        unsigned int curPosMoves, oppPosMoves;
        unsigned int curMissPieces, oppMissPieces;
        unsigned int piecesSet;
        unsigned int pieceMustBeRemoved;
        unsigned int piecePartOfMill[SQUARE_NB];
        unsigned int warnings[SQUARE_NB];
        Player *curPlayer, *oppPlayer;
    };

    // Variables

    // pointer of the current board [changed by move()]
    fieldStruct *field;

    // value of current situation for board->currentPlayer
    float currentValue;

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

    // Functions
    unsigned int *getPossSettingPhase(unsigned int *possibilityCount,
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
    inline void normalMove(unsigned int from, unsigned int to, Backup *backup);

    // Virtual Functions
    void prepareBestChoiceCalculation();
    unsigned int *getPossibilities(unsigned int threadNo,
                                   unsigned int *possibilityCount,
                                   bool *opponentsMove, void **pPossibilities);
    void deletePossibilities(unsigned int threadNo, void *pPossibilities);
    void move(unsigned int threadNo, unsigned int idPossibility,
              bool opponentsMove, void **pBackup, void *pPossibilities);
    void undo(unsigned int threadNo, unsigned int idPossibility,
              bool opponentsMove, void *pBackup, void *pPossibilities);
    void getValueOfSituation(unsigned int threadNo, float &floatValue,
                             TwoBit &shortValue);
    void printMoveInformation(unsigned int threadNo, unsigned int idPossibility,
                              void *pPossibilities);

    unsigned int getNumberOfLayers() { return 0; }

    unsigned int getNumberOfKnotsInLayer(unsigned int layerNum) { return 0; }

    void getSuccLayers(unsigned int layerNum, unsigned int *amountOfSuccLayers,
                       unsigned int *succeedingLayers)
    { }

    unsigned int getPartnerLayer(unsigned int layerNum) { return 0; }

    string getOutputInformation(unsigned int layerNum) { return string(""); }

    void setOpponentLevel(unsigned int threadNo, bool isOpponentLevel) { }

    bool setSituation(unsigned int threadNo, unsigned int layerNum,
                      unsigned int stateNumber)
    {
        return false;
    };

    bool getOpponentLevel(unsigned int threadNo) { return false; }

    unsigned int getLayerAndStateNumber(unsigned int threadNo,
                                        unsigned int &layerNum,
                                        unsigned int &stateNumber)
    {
        return 0;
    };

    unsigned int getLayerNumber(unsigned int threadNo) { return 0; }

    void getSymStateNumWithDoubles(unsigned int threadNo,
                                   unsigned int *nSymmetricStates,
                                   unsigned int **symStateNumbers)
    { }

    void getPredecessors(unsigned int threadNo, unsigned int *amountOfPred,
                         RetroAnalysisPredVars *predVars)
    { }

    void printBoard(unsigned int threadNo, unsigned char value) { }

    void prepareDatabaseCalculation() { }

    void wrapUpDatabaseCalculation(bool calculationAborted) { }

public:
    // Constructor / destructor
    MiniMaxAI();
    ~MiniMaxAI();

    // Functions
    void play(fieldStruct *theField, unsigned int *pushFrom,
              unsigned int *pushTo);
    void setSearchDepth(unsigned int depth);
};

#endif // MINIMAX_AI_H_INCLUDED
