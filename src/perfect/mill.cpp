/*********************************************************************
    Mill.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "mill.h"
#include <cassert>

//-----------------------------------------------------------------------------
// Mill()
// Mill class constructor
//-----------------------------------------------------------------------------
Mill::Mill()
{
    srand((unsigned)time(nullptr));

    moveLogFrom = nullptr;
    moveLogTo = nullptr;
    playerOneAI = nullptr;
    playerTwoAI = nullptr;
    movesDone = 0;

    winner = 0;
    beginningPlayer = 0;

    field.createBoard();
    initialField.createBoard();
}

//-----------------------------------------------------------------------------
// ~Mill()
// Mill class destructor
//-----------------------------------------------------------------------------
Mill::~Mill()
{
    exit();
}

//-----------------------------------------------------------------------------
// deleteArrays()
// Deletes all arrays the Mill class has created.
//-----------------------------------------------------------------------------
void Mill::exit()
{
    SAFE_DELETE_ARRAY(moveLogFrom);
    SAFE_DELETE_ARRAY(moveLogTo);

    field.deleteBoard();
    initialField.deleteBoard();
}

//-----------------------------------------------------------------------------
// resetGame()
// Reset the Mill object.
//-----------------------------------------------------------------------------
void Mill::resetGame()
{
    std::memset(moveLogFrom, 0, MAX_NUM_MOVES);
    std::memset(moveLogTo, 0, MAX_NUM_MOVES);
    initialField.copyBoard(&field);

    winner = 0;
    movesDone = 0;
}

//-----------------------------------------------------------------------------
// beginNewGame()
// Reinitializes the Mill object.
//-----------------------------------------------------------------------------
void Mill::beginNewGame(MillAI* firstPlayerAI, MillAI* secondPlayerAI, int currentPlayer)
{
    // free memory
    exit();

    // create arrays
    field.createBoard();
    initialField.createBoard();

    // calculate beginning player
    if (currentPlayer == field.playerOne || currentPlayer == field.playerTwo) {
        beginningPlayer = currentPlayer;
    } else {
        beginningPlayer = (rand() % 2) ? field.playerOne : field.playerTwo;
    }

    field.curPlayer->id = beginningPlayer;
    field.oppPlayer->id = (field.curPlayer->id == field.playerTwo) ? field.playerOne : field.playerTwo;

    winner = 0;
    movesDone = 0;
    playerOneAI = firstPlayerAI;
    playerTwoAI = secondPlayerAI;
    moveLogFrom = new unsigned int[MAX_NUM_MOVES];
    moveLogTo = new unsigned int[MAX_NUM_MOVES];

    // remember initialField
    field.copyBoard(&initialField);
}

//-----------------------------------------------------------------------------
// startSettingPhase()
//
//-----------------------------------------------------------------------------
bool Mill::startSettingPhase(MillAI* firstPlayerAI, MillAI* secondPlayerAI, int currentPlayer, bool settingPhase)
{
    beginNewGame(firstPlayerAI, secondPlayerAI, currentPlayer);

    field.settingPhase = settingPhase;

    return true;
}

//-----------------------------------------------------------------------------
// setUpCalcPossibleMoves()
// Calculates and set the number of possible moves for the passed player
// considering the game state stored in the 'board' variable.
//-----------------------------------------------------------------------------
void Mill::setUpCalcPossibleMoves(Player* player)
{
    // locals
    unsigned int i, j, k, movingDirection;

    for (player->numPossibleMoves = 0, i = 0; i < fieldStruct::size; i++) {
        for (j = 0; j < fieldStruct::size; j++) {

            // is stone from player ?
            if (field.board[i] != player->id)
                continue;

            // is destination free ?
            if (field.board[j] != field.squareIsFree)
                continue;

            // when current player has only 3 stones he is allowed to spring his stone
            if (player->numStones > 3 || field.settingPhase) {

                // determine moving direction
                for (k = 0, movingDirection = 4; k < 4; k++)
                    if (field.connectedSquare[i][k] == j)
                        movingDirection = k;

                // are both squares connected ?
                if (movingDirection == 4)
                    continue;
            }

            // everything is ok
            player->numPossibleMoves++;
        }
    }
}

//-----------------------------------------------------------------------------
// setUpSetWarningAndMill()
//
//-----------------------------------------------------------------------------
void Mill::setUpSetWarningAndMill(unsigned int stone, unsigned int firstNeighbour, unsigned int secondNeighbour)
{
    // locals
    int rowOwner = field.board[stone];

    // mill closed ?
    if (rowOwner != field.squareIsFree && field.board[firstNeighbour] == rowOwner && field.board[secondNeighbour] == rowOwner) {

        field.stonePartOfMill[stone]++;
        field.stonePartOfMill[firstNeighbour]++;
        field.stonePartOfMill[secondNeighbour]++;
    }
}

//-----------------------------------------------------------------------------
// putPiece()
// Put a stone onto the board during the setting phase.
//-----------------------------------------------------------------------------
bool Mill::putPiece(unsigned int pos, int player)
{
    // locals
    unsigned int i;
    unsigned int numberOfMillsCurrentPlayer = 0, numberOfMillsOpponentPlayer = 0;
    Player* myPlayer = (player == field.curPlayer->id) ? field.curPlayer : field.oppPlayer;

    // check parameters
    if (player != fieldStruct::playerOne && player != fieldStruct::playerTwo)
        return false;
    if (pos >= fieldStruct::size)
        return false;
    if (field.board[pos] != field.squareIsFree)
        return false;

    // set stone
    field.board[pos] = player;
    myPlayer->numStones++;
    field.stonesSet++;

    // setting phase finished ?
    if (field.stonesSet == 18)
        field.settingPhase = false;

    // calc possible moves
    setUpCalcPossibleMoves(field.curPlayer);
    setUpCalcPossibleMoves(field.oppPlayer);

    // zero
    for (i = 0; i < fieldStruct::size; i++)
        field.stonePartOfMill[i] = 0;

    // go in every direction
    for (i = 0; i < fieldStruct::size; i++) {
        setUpSetWarningAndMill(i, field.neighbour[i][0][0], field.neighbour[i][0][1]);
        setUpSetWarningAndMill(i, field.neighbour[i][1][0], field.neighbour[i][1][1]);
    }

    // since every mill was detected 3 times
    for (i = 0; i < fieldStruct::size; i++)
        field.stonePartOfMill[i] /= 3;

    // count completed mills
    for (i = 0; i < fieldStruct::size; i++) {
        if (field.board[i] == field.curPlayer->id)
            numberOfMillsCurrentPlayer += field.stonePartOfMill[i];
        else
            numberOfMillsOpponentPlayer += field.stonePartOfMill[i];
    }
    numberOfMillsCurrentPlayer /= 3;
    numberOfMillsOpponentPlayer /= 3;

    // stonesSet & numStonesMissing
    if (field.settingPhase) {
        // ... This calculation is not correct! It is possible that some mills did not cause a stone removal.
        field.curPlayer->numStonesMissing = numberOfMillsOpponentPlayer;
        field.oppPlayer->numStonesMissing = numberOfMillsCurrentPlayer - field.stoneMustBeRemoved;
        field.stonesSet = field.curPlayer->numStones + field.oppPlayer->numStones + field.curPlayer->numStonesMissing + field.oppPlayer->numStonesMissing;
    } else {
        field.stonesSet = 18;
        field.curPlayer->numStonesMissing = 9 - field.curPlayer->numStones;
        field.oppPlayer->numStonesMissing = 9 - field.oppPlayer->numStones;
    }

    // when opponent is unable to move than current player has won
    if ((!field.curPlayer->numPossibleMoves) && (!field.settingPhase) && (!field.stoneMustBeRemoved) && (field.curPlayer->numStones > 3))
        winner = field.oppPlayer->id;
    else if ((field.curPlayer->numStones < 3) && (!field.settingPhase))
        winner = field.oppPlayer->id;
    else if ((field.oppPlayer->numStones < 3) && (!field.settingPhase))
        winner = field.curPlayer->id;
    else
        winner = 0;

    // everything is ok
    return true;
}

//-----------------------------------------------------------------------------
// settingPhaseHasFinished()
// This function has to be called when the setting phase has finished.
//-----------------------------------------------------------------------------
bool Mill::settingPhaseHasFinished()
{
    // remember initialField
    field.copyBoard(&initialField);

    return true;
}

//-----------------------------------------------------------------------------
// getField()
// Copy the current board state into the array 'pField'.
//-----------------------------------------------------------------------------
bool Mill::getField(int* pField)
{
    unsigned int index;

    // if no log is available than no game is in progress and board is invalid
    if (moveLogFrom == nullptr)
        return false;

    for (index = 0; index < field.size; index++) {
        if (field.warnings[index] != field.noWarning)
            pField[index] = (int)field.warnings[index];
        else
            pField[index] = field.board[index];
    }

    return true;
}

//-----------------------------------------------------------------------------
// getLog()
// Copy the whole history of moves into the passed arrays, which must be of size [MAX_NUM_MOVES].
//-----------------------------------------------------------------------------
void Mill::getLog(unsigned int& numMovesDone, unsigned int* from, unsigned int* to)
{
    unsigned int index;

    numMovesDone = movesDone;

    for (index = 0; index < movesDone; index++) {
        from[index] = moveLogFrom[index];
        to[index] = moveLogTo[index];
    }
}

//-----------------------------------------------------------------------------
// setNextPlayer()
// Current player and opponent player are switched in the board struct.
//-----------------------------------------------------------------------------
void Mill::setNextPlayer()
{
    Player* tmpPlayer;

    tmpPlayer = field.curPlayer;
    field.curPlayer = field.oppPlayer;
    field.oppPlayer = tmpPlayer;
}

//-----------------------------------------------------------------------------
// isCurrentPlayerHuman()
// Returns true if the current player is not assigned to an AI.
//-----------------------------------------------------------------------------
bool Mill::isCurrentPlayerHuman()
{
    if (field.curPlayer->id == field.playerOne)
        return (playerOneAI == nullptr) ? true : false;
    else
        return (playerTwoAI == nullptr) ? true : false;
}

//-----------------------------------------------------------------------------
// isOpponentPlayerHuman()
// Returns true if the opponent player is not assigned to an AI.
//-----------------------------------------------------------------------------
bool Mill::isOpponentPlayerHuman()
{
    if (field.oppPlayer->id == field.playerOne)
        return (playerOneAI == nullptr) ? true : false;
    else
        return (playerTwoAI == nullptr) ? true : false;
}

//-----------------------------------------------------------------------------
// setAI()
// Assigns an AI to a player.
//-----------------------------------------------------------------------------
void Mill::setAI(int player, MillAI* AI)
{
    if (player == field.playerOne) {
        playerOneAI = AI;
    }
    if (player == field.playerTwo) {
        playerTwoAI = AI;
    }
}

//-----------------------------------------------------------------------------
// getChoiceOfSpecialAI()
// Returns the move the passed AI would do.
//-----------------------------------------------------------------------------
void Mill::getChoiceOfSpecialAI(MillAI* AI, unsigned int* pushFrom, unsigned int* pushTo)
{
    fieldStruct theField;
    *pushFrom = field.size;
    *pushTo = field.size;
    theField.createBoard();
    field.copyBoard(&theField);
    if (AI != nullptr && (field.settingPhase || field.curPlayer->numPossibleMoves > 0) && winner == 0)
        AI->play(&theField, pushFrom, pushTo);
    theField.deleteBoard();
}

//-----------------------------------------------------------------------------
// getComputersChoice()
// Returns the move the AI of the current player would do.
//-----------------------------------------------------------------------------
void Mill::getComputersChoice(unsigned int* pushFrom, unsigned int* pushTo)
{
    fieldStruct theField;
    *pushFrom = field.size;
    *pushTo = field.size;
    theField.createBoard();
    //assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id <= 1);

    field.copyBoard(&theField);

    //assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id <= 1);

    if ((field.settingPhase || field.curPlayer->numPossibleMoves > 0) && winner == 0) {
        if (field.curPlayer->id == field.playerOne) {
            if (playerOneAI != nullptr)
                playerOneAI->play(&theField, pushFrom, pushTo);
            //assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id <= 1);
        } else {
            if (playerTwoAI != nullptr)
                playerTwoAI->play(&theField, pushFrom, pushTo);
            //assert(theField.oppPlayer->id >= -1 && theField.oppPlayer->id <= 1);
        }
    }

    if (*pushFrom == 24 && *pushTo == 24) {
        assert(false);
    }

    theField.deleteBoard();
}

//-----------------------------------------------------------------------------
// isNormalMovePossible()
// 'Normal' in this context means, by moving the stone along a connection without jumping.
//-----------------------------------------------------------------------------
bool Mill::isNormalMovePossible(unsigned int from, unsigned int to, Player* player)
{
    // locals
    unsigned int movingDirection, i;

    // parameter ok ?
    if (from >= field.size)
        return false;
    if (to >= field.size)
        return false;

    // is stone from player ?
    if (field.board[from] != player->id)
        return false;

    // is destination free ?
    if (field.board[to] != field.squareIsFree)
        return false;

    // when current player has only 3 stones he is allowed to spring his stone
    if (player->numStones > 3 || field.settingPhase) {

        // determine moving direction
        for (i = 0, movingDirection = 4; i < 4; i++)
            if (field.connectedSquare[from][i] == to)
                movingDirection = i;

        // are both squares connected ?
        if (movingDirection == 4)
            return false;
    }

    // everything is ok
    return true;
}

//-----------------------------------------------------------------------------
// calcPossibleMoves()
// ...
//-----------------------------------------------------------------------------
void Mill::calcPossibleMoves(Player* player)
{
    // locals
    unsigned int i, j;

    // zero
    for (i = 0; i < MAX_NUM_POS_MOVES; i++)
        player->posTo[i] = field.size;
    for (i = 0; i < MAX_NUM_POS_MOVES; i++)
        player->posFrom[i] = field.size;

    // calc
    for (player->numPossibleMoves = 0, i = 0; i < field.size; i++) {
        for (j = 0; j < field.size; j++) {
            if (isNormalMovePossible(i, j, player)) {
                player->posFrom[player->numPossibleMoves] = i;
                player->posTo[player->numPossibleMoves] = j;
                player->numPossibleMoves++;
            }
        }
    }

    // stoneMoveAble
    for (i = 0; i < field.size; i++) {
        for (j = 0; j < 4; j++) {
            if (field.board[i] == player->id)
                field.stoneMoveAble[i][j] = isNormalMovePossible(i, field.connectedSquare[i][j], player);
            else
                field.stoneMoveAble[i][j] = false;
        }
    }
}

//-----------------------------------------------------------------------------
// setWarningAndMill()
//
//-----------------------------------------------------------------------------
void Mill::setWarningAndMill(unsigned int stone,
    unsigned int firstNeighbour,
    unsigned int secondNeighbour,
    bool isNewStone)
{
    // locals
    int rowOwner = field.board[stone];
    unsigned int rowOwnerWarning = (rowOwner == field.playerOne) ? field.playerOneWarning : field.playerTwoWarning;

    // mill closed ?
    if (rowOwner != field.squareIsFree && field.board[firstNeighbour] == rowOwner && field.board[secondNeighbour] == rowOwner) {

        field.stonePartOfMill[stone]++;
        field.stonePartOfMill[firstNeighbour]++;
        field.stonePartOfMill[secondNeighbour]++;
        if (isNewStone)
            field.stoneMustBeRemoved = 1;
    }

    //warning ?
    if (rowOwner != field.squareIsFree && field.board[firstNeighbour] == field.squareIsFree && field.board[secondNeighbour] == rowOwner)
        field.warnings[firstNeighbour] |= rowOwnerWarning;

    if (rowOwner != field.squareIsFree && field.board[secondNeighbour] == field.squareIsFree && field.board[firstNeighbour] == rowOwner)
        field.warnings[secondNeighbour] |= rowOwnerWarning;
}

//-----------------------------------------------------------------------------
// updateMillsAndWarnings()
//
//-----------------------------------------------------------------------------
void Mill::updateMillsAndWarnings(unsigned int newStone)
{
    // locals
    unsigned int i;
    bool atLeastOneStoneRemoveAble;

    // zero
    for (i = 0; i < field.size; i++)
        field.stonePartOfMill[i] = 0;

    for (i = 0; i < field.size; i++)
        field.warnings[i] = field.noWarning;

    field.stoneMustBeRemoved = 0;

    // go in every direction
    for (i = 0; i < field.size; i++) {

        setWarningAndMill(i, field.neighbour[i][0][0], field.neighbour[i][0][1], i == newStone);
        setWarningAndMill(i, field.neighbour[i][1][0], field.neighbour[i][1][1], i == newStone);
    }

    // since every mill was detected 3 times
    for (i = 0; i < field.size; i++)
        field.stonePartOfMill[i] /= 3;

    // no stone must be removed if each belongs to a mill
    for (atLeastOneStoneRemoveAble = false, i = 0; i < field.size; i++)
        if (field.stonePartOfMill[i] == 0 && field.board[i] == field.oppPlayer->id)
            atLeastOneStoneRemoveAble = true;
    if (!atLeastOneStoneRemoveAble)
        field.stoneMustBeRemoved = 0;
}

//-----------------------------------------------------------------------------
// doMove()
//
//-----------------------------------------------------------------------------
bool Mill::doMove(unsigned int pushFrom, unsigned int pushTo)
{
    // avoid index override
    if (movesDone >= MAX_NUM_MOVES)
        return false;

    // is game still running ?
    if (winner)
        return false;

    // handle the remove of a stone
    if (field.stoneMustBeRemoved) {

        // parameter ok ?
        if (pushFrom >= field.size)
            return false;

        // is it stone from the opponent ?
        if (field.board[pushFrom] != field.oppPlayer->id)
            return false;

        // is stone not part of mill?
        if (field.stonePartOfMill[pushFrom])
            return false;

        // remove stone
        moveLogFrom[movesDone] = pushFrom;
        moveLogTo[movesDone] = field.size;
        field.board[pushFrom] = field.squareIsFree;
        field.oppPlayer->numStonesMissing++;
        field.oppPlayer->numStones--;
        field.stoneMustBeRemoved--;
        movesDone++;

        // is the game finished ?
        if ((field.oppPlayer->numStones < 3) && (!field.settingPhase))
            winner = field.curPlayer->id;

        // update warnings & mills
        updateMillsAndWarnings(field.size);

        // calc possibilities
        calcPossibleMoves(field.curPlayer);
        calcPossibleMoves(field.oppPlayer);

        // is opponent unable to move ?
        if (field.oppPlayer->numPossibleMoves == 0 && !field.settingPhase)
            winner = field.curPlayer->id;

        // next player
        if (!field.stoneMustBeRemoved)
            setNextPlayer();

        // everything is ok
        return true;

        // handle setting phase
    } else if (field.settingPhase) {

        // parameter ok ?
        if (pushTo >= field.size)
            return false;

        // is destination free ?
        if (field.board[pushTo] != field.squareIsFree)
            return false;

        // set stone
        moveLogFrom[movesDone] = field.size;
        moveLogTo[movesDone] = pushTo;
        field.board[pushTo] = field.curPlayer->id;
        field.curPlayer->numStones++;
        field.stonesSet++;
        movesDone++;

        // update warnings & mills
        updateMillsAndWarnings(pushTo);

        // calc possibilities
        calcPossibleMoves(field.curPlayer);
        calcPossibleMoves(field.oppPlayer);

        // setting phase finished ?
        if (field.stonesSet == 18)
            field.settingPhase = false;

        // is opponent unable to move ?
        if (field.oppPlayer->numPossibleMoves == 0 && !field.settingPhase)
            winner = field.curPlayer->id;

        // next player
        if (!field.stoneMustBeRemoved)
            setNextPlayer();

        // everything is ok
        return true;

        // normal move
    } else {

        // is move possible ?
        if (!isNormalMovePossible(pushFrom, pushTo, field.curPlayer))
            return false;

        // move stone
        moveLogFrom[movesDone] = pushFrom;
        moveLogTo[movesDone] = pushTo;
        field.board[pushFrom] = field.squareIsFree;
        field.board[pushTo] = field.curPlayer->id;
        movesDone++;

        // update warnings & mills
        updateMillsAndWarnings(pushTo);

        // calc possibilities
        calcPossibleMoves(field.curPlayer);
        calcPossibleMoves(field.oppPlayer);

        // is opponent unable to move ?
        if (field.oppPlayer->numPossibleMoves == 0 && !field.settingPhase)
            winner = field.curPlayer->id;

        // next player
        if (!field.stoneMustBeRemoved)
            setNextPlayer();

        // everything is ok
        return true;
    }
}

//-----------------------------------------------------------------------------
// setCurrentGameState()
// Set an arbitrary game state as the current one.
//-----------------------------------------------------------------------------
bool Mill::setCurrentGameState(fieldStruct* curState)
{
    curState->copyBoard(&field);

    winner = 0;
    movesDone = 0;

    if ((field.curPlayer->numStones < 3) && (!field.settingPhase))
        winner = field.oppPlayer->id;

    if ((field.oppPlayer->numStones < 3) && (!field.settingPhase))
        winner = field.curPlayer->id;

    if ((field.curPlayer->numPossibleMoves == 0) && (!field.settingPhase))
        winner = field.oppPlayer->id;

    return true;
}

//-----------------------------------------------------------------------------
// compareWithField()
// Compares the current 'board' variable with the passed one. 'stoneMoveAble[]' is ignored.
//-----------------------------------------------------------------------------
bool Mill::compareWithField(fieldStruct* compareField)
{
    unsigned int i, j;
    bool ret = true;

    if (!comparePlayers(field.curPlayer, compareField->curPlayer)) {
        cout << "error - curPlayer differs!" << endl;
        ret = false;
    }

    if (!comparePlayers(field.oppPlayer, compareField->oppPlayer)) {
        cout << "error - oppPlayer differs!" << endl;
        ret = false;
    }

    if (field.stonesSet != compareField->stonesSet) {
        cout << "error - stonesSet differs!" << endl;
        ret = false;
    }

    if (field.settingPhase != compareField->settingPhase) {
        cout << "error - settingPhase differs!" << endl;
        ret = false;
    }

    if (field.stoneMustBeRemoved != compareField->stoneMustBeRemoved) {
        cout << "error - stoneMustBeRemoved differs!" << endl;
        ret = false;
    }

    for (i = 0; i < field.size; i++) {
        if (field.board[i] != compareField->board[i]) {
            cout << "error - board[] differs!" << endl;
            ret = false;
        }

        if (field.warnings[i] != compareField->warnings[i]) {
            cout << "error - warnings[] differs!" << endl;
            ret = false;
        }

        if (field.stonePartOfMill[i] != compareField->stonePartOfMill[i]) {
            cout << "error - stonePart[] differs!" << endl;
            ret = false;
        }

        for (j = 0; j < 4; j++) {
            if (field.connectedSquare[i][j] != compareField->connectedSquare[i][j]) {
                cout << "error - connectedSquare[] differs!" << endl;
                ret = false;
            }

            // if (board.stoneMoveAble[i][j] != compareField->stoneMoveAble[i][j])
            //     { cout << "error - stoneMoveAble differs!" << endl; ret = false; }

            if (field.neighbour[i][j / 2][j % 2] != compareField->neighbour[i][j / 2][j % 2]) {
                cout << "error - neighbour differs!" << endl;
                ret = false;
            }
        }
    }

    return ret;
}

//-----------------------------------------------------------------------------
// comparePlayers()
// Compares the two passed players and returns false if they differ.
//-----------------------------------------------------------------------------
bool Mill::comparePlayers(Player* playerA, Player* playerB)
{
    //	unsigned int i;
    bool ret = true;

    if (playerA->numStonesMissing != playerB->numStonesMissing) {
        cout << "error - numStonesMissing differs!" << endl;
        ret = false;
    }

    if (playerA->numStones != playerB->numStones) {
        cout << "error - numStones differs!" << endl;
        ret = false;
    }

    if (playerA->id != playerB->id) {
        cout << "error - id differs!" << endl;
        ret = false;
    }

    if (playerA->warning != playerB->warning) {
        cout << "error - warning differs!" << endl;
        ret = false;
    }

    if (playerA->numPossibleMoves != playerB->numPossibleMoves) {
        cout << "error - numPossibleMoves differs!" << endl;
        ret = false;
    }

    //	for (i=0; i<MAX_NUM_POS_MOVES; i++) if (playerA->posFrom[i]	= playerB->posFrom[i]) return false;
    //	for (i=0; i<MAX_NUM_POS_MOVES; i++) if (playerA->posTo  [i]	= playerB->posTo  [i]) return false;

    return ret;
}

//-----------------------------------------------------------------------------
// printBoard()
// Calls the printBoard() function of the current board.
//       Prints the current game state on the screen.
//-----------------------------------------------------------------------------
void Mill::printBoard()
{
    field.printBoard();
}

//-----------------------------------------------------------------------------
// undoMove()
// Sets the initial board as the current one and apply all (minus one) moves from the move history.
//-----------------------------------------------------------------------------
void Mill::undoMove(void)
{
    // locals
    unsigned int* moveLogFrom_bak = new unsigned int[movesDone];
    unsigned int* moveLogTo_bak = new unsigned int[movesDone];
    unsigned int movesDone_bak = movesDone;
    unsigned int i;

    // at least one move must be done
    if (movesDone) {

        // make backup of log
        for (i = 0; i < movesDone; i++) {
            moveLogFrom_bak[i] = moveLogFrom[i];
            moveLogTo_bak[i] = moveLogTo[i];
        }

        // reset
        initialField.copyBoard(&field);
        winner = 0;
        movesDone = 0;

        // and play again
        for (i = 0; i < movesDone_bak - 1; i++) {
            doMove(moveLogFrom_bak[i], moveLogTo_bak[i]);
        }
    }

    // free mem
    delete[] moveLogFrom_bak;
    delete[] moveLogTo_bak;
}

//-----------------------------------------------------------------------------
// calcNumberOfRestingStones()
//
//-----------------------------------------------------------------------------
void Mill::calcNumberOfRestingStones(int& numWhiteStonesResting, int& numBlackStonesResting)
{
    if (getCurrentPlayer() == fieldStruct::playerTwo) {
        numWhiteStonesResting = fieldStruct::numStonesPerPlayer - field.curPlayer->numStonesMissing - field.curPlayer->numStones;
        numBlackStonesResting = fieldStruct::numStonesPerPlayer - field.oppPlayer->numStonesMissing - field.oppPlayer->numStones;
    } else {
        numWhiteStonesResting = fieldStruct::numStonesPerPlayer - field.oppPlayer->numStonesMissing - field.oppPlayer->numStones;
        numBlackStonesResting = fieldStruct::numStonesPerPlayer - field.curPlayer->numStonesMissing - field.curPlayer->numStones;
    }
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
