#include <cstdio>
#include <iostream>
#include <windows.h>
#include "position.h"
#include "miniMaxAI.h"
#include "randomAI.h"
#include "perfectAI.h"

#include "config.h"

using namespace std;

unsigned int startTestFromLayer = 0;
unsigned int endTestAtLayer = NUM_LAYERS - 1;
#ifdef _DEBUG
char databaseDirectory[] = "D:\\database";
#elif _RELEASE_X64
char databaseDirectory[] = "";
#endif
bool calculateDatabase = false;

int main(void)
{
    // locals
    bool playerOneHuman = false;
    bool playerTwoHuman = false;
    char ch[100];
    unsigned int pushFrom, pushTo;
    Position *pos = new Position();
    PerfectAI *ai = new PerfectAI(databaseDirectory);

    SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
    srand(GetTickCount());

    // intro
    cout << "*************************" << endl;
    cout << "* Muehle                *" << endl;
    cout << "*************************" << endl
        << endl;

    ai->setDatabasePath(databaseDirectory);

    // begin
#ifdef SELF_PLAY
    pos->beginNewGame(ai, ai, fieldStruct::playerOne);
#else
    pos->beginNewGame(ai, ai, (rand() % 2) ? fieldStruct::playerOne : fieldStruct::playerTwo);
#endif // SELF_PLAY

    if (calculateDatabase) {

        // calculate
        ai->calculateDatabase(MAX_DEPTH_OF_TREE, false);

        // test database
        cout << endl
            << "Begin test starting from layer: ";
        startTestFromLayer;
        cout << endl
            << "End test at layer: ";
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
            cout << "\n\n\n\n\n\n\n\n\n\n\n";
            pos->getComputersChoice(&pushFrom, &pushTo);
            cout << "\n\n";
            cout << "\nlast move was from " << (char)(pos->getLastMoveFrom() + 97) << " to " << (char)(pos->getLastMoveTo() + 97) << "\n\n";

#ifdef SELF_PLAY
            moveCount++;
            if (moveCount > 99) {
                goto out;
            }
#endif // SELF_PLAY

            pos->printBoard();

            // Human
            if ((pos->getCurrentPlayer() == fieldStruct::playerOne && playerOneHuman) || (pos->getCurrentPlayer() == fieldStruct::playerTwo && playerTwoHuman)) {
                do {
                    // Show text
                    if (pos->mustStoneBeRemoved())
                        cout << "\n   Which stone do you want to remove? [a-x]: \n\n\n";
                    else if (pos->inSettingPhase())
                        cout << "\n   Where are you going? [a-x]: \n\n\n";
                    else
                        cout << "\n   Your train? [a-x][a-x]: \n\n\n";

                    // get input
                    cin >> ch;
                    if ((ch[0] >= 'a') && (ch[0] <= 'x'))
                        pushFrom = ch[0] - 'a';
                    else
                        pushFrom = fieldStruct::size;

                    if (pos->inSettingPhase()) {
                        if ((ch[0] >= 'a') && (ch[0] <= 'x'))
                            pushTo = ch[0] - 'a';
                        else
                            pushTo = fieldStruct::size;
                    } else {
                        if ((ch[1] >= 'a') && (ch[1] <= 'x'))
                            pushTo = ch[1] - 'a';
                        else
                            pushTo = fieldStruct::size;
                    }

                    // undo
                    if (ch[0] == 'u' && ch[1] == 'n' && ch[2] == 'd' && ch[3] == 'o') {

                        // undo moves until a human player shall move
                        do {
                            pos->undo_move();
                        } while (!((pos->getCurrentPlayer() == fieldStruct::playerOne && playerOneHuman) || (pos->getCurrentPlayer() == fieldStruct::playerTwo && playerTwoHuman)));

                        // reprint board
                        break;
                    }

                } while (pos->do_move(pushFrom, pushTo) == false);

                // Computer
            } else {
                cout << "\n";
                pos->do_move(pushFrom, pushTo);
            }

        } while (pos->getWinner() == 0);

        // end
        cout << "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n";

        pos->printBoard();

        if (pos->getWinner() == fieldStruct::playerOne)
            cout << "\n   Player 1 (o) won after " << pos->getMovesDone() << " move.\n\n";
        else if (pos->getWinner() == fieldStruct::playerTwo)
            cout << "\n   Player 2 (x) won after " << pos->getMovesDone() << " move.\n\n";
        else if (pos->getWinner() == fieldStruct::gameDrawn)
            cout << "\n   Draw!\n\n";
        else
            cout << "\n   A program error has occurred!\n\n";
    }

out:
    char end;
    cin >> end;

    return 0;
}
