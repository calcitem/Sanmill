/*********************************************************************\
    PerfectAI.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "mill.h"
#include "perfect.h"
#include "perfectAI.h"

#include <cstdio>
#include <iostream>
#include <windows.h>

#include "rule.h"
#include "types.h"

using std::iostream;

extern Mill *mill;
extern PerfectAI *ai;

constexpr uint32_t startTestFromLayer = 0;

constexpr uint32_t endTestAtLayer = LAYER_COUNT - 1;

#ifdef MADWEASEL_MUEHLE_PERFECT_AI_CALCULATE_DATABASE
const bool calculateDatabase = true;
#else
constexpr bool calculateDatabase = false;
#endif

#ifdef MADWEASEL_MUEHLE_PERFECT_AI_TEST
int main(void)
#else
int perfect_main()
#endif
{
    // locals
    bool playerOneHuman = false;
    bool playerTwoHuman = false;
    char ch[100];
    uint32_t from;
    uint32_t to;

    mill = new Mill();
    ai = new PerfectAI(PERFECT_AI_DATABASE_DIR);

    SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
    srand(GetTickCount64());

    // intro
    cout << "*************************" << endl;
    cout << "* Muehle                *" << endl;
    cout << "*************************" << endl << endl;

    ai->setDatabasePath(PERFECT_AI_DATABASE_DIR);

    // begin
#ifdef SELF_PLAY
    mill->beginNewGame(ai, ai, fieldStruct::playerOne);
#else
    mill->beginNewGame(
        ai, ai, (rand() % 2) ? fieldStruct::playerOne : fieldStruct::playerTwo);
#endif // SELF_PLAY

    if (calculateDatabase) {
        // calculate
        ai->calculateDatabase(TREE_DEPTH_MAX, false);

        // test database
        cout << endl << "Begin test starting from layer: ";

        startTestFromLayer;

        cout << endl << "End test at layer: ";

        endTestAtLayer;

        ai->testLayers(startTestFromLayer, endTestAtLayer);

    } else {
#ifdef SELF_PLAY
        int moveCount = 0;
#else
        cout << "Is Player 1 human? (y/n):";

        cin >> ch;

        if (ch[0] == 'y')
            playerOneHuman = true;

        cout << "Is Player 2 human? (y/n):";

        cin >> ch;

        if (ch[0] == 'y')
            playerTwoHuman = true;
#endif // SELF_PLAY

        // play
        do {
            // print board
            cout << "\n\n\n";
            mill->getComputersChoice(&from, &to);
            cout << "\n\n";
            cout << "\nlast move was from "
                 << static_cast<char>(mill->getLastMoveFrom() + 'a') << " to "
                 << static_cast<char>(mill->getLastMoveTo() + 'a') << "\n\n";

#ifdef SELF_PLAY
            moveCount++;
            if (moveCount > rule.nMoveRule) {
                goto out;
            }
#endif // SELF_PLAY

            mill->printBoard();

            // Human
            if ((mill->getCurPlayer() == fieldStruct::playerOne &&
                 playerOneHuman) ||
                (mill->getCurPlayer() == fieldStruct::playerTwo &&
                 playerTwoHuman)) {
                do {
                    // Show text
                    if (mill->mustPieceBeRemoved())
                        cout << "\n   Which piece do you want to remove? "
                                "[a-x]: \n\n\n";
                    else if (mill->inPlacingPhase())
                        cout << "\n   Where are you going? [a-x]: \n\n\n";
                    else
                        cout << "\n   Your train? [a-x][a-x]: \n\n\n";

                    // get input
                    cin >> ch;
                    if ((ch[0] >= 'a') && (ch[0] <= 'x'))
                        from = ch[0] - 'a';
                    else
                        from = SQUARE_NB;

                    if (mill->inPlacingPhase()) {
                        if ((ch[0] >= 'a') && (ch[0] <= 'x'))
                            to = ch[0] - 'a';
                        else
                            to = SQUARE_NB;
                    } else {
                        if ((ch[1] >= 'a') && (ch[1] <= 'x'))
                            to = ch[1] - 'a';
                        else
                            to = SQUARE_NB;
                    }

                    // undo
                    if (ch[0] == 'u' && ch[1] == 'n' && ch[2] == 'd' &&
                        ch[3] == 'o') {
                        // undo moves until a human player shall move
                        do {
                            mill->undoMove();
                        } while (
                            !((mill->getCurPlayer() == fieldStruct::playerOne &&
                               playerOneHuman) ||
                              (mill->getCurPlayer() == fieldStruct::playerTwo &&
                               playerTwoHuman)));

                        // reprint board
                        break;
                    }
                } while (mill->doMove(from, to) == false);

                // Computer
            } else {
                cout << "\n";
                mill->doMove(from, to);
            }
        } while (mill->getWinner() == 0);

        // end
        cout << "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";

        mill->printBoard();

        if (mill->getWinner() == fieldStruct::playerOne)
            cout << "\n   Player 1 (o) won after " << mill->getMovesDone()
                 << " move.\n\n";
        else if (mill->getWinner() == fieldStruct::playerTwo)
            cout << "\n   Player 2 (x) won after " << mill->getMovesDone()
                 << " move.\n\n";
        else if (mill->getWinner() == fieldStruct::gameDrawn)
            cout << "\n   Draw!\n\n";
        else
            cout << "\n   A program error has occurred!\n\n";
    }

    char end;
    cin >> end;

    return 0;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
