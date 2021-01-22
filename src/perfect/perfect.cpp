#include <cstdio>
#include <iostream>
#include <windows.h>
#include "mill.h"
#include "miniMaxAI.h"
#include "randomAI.h"
#include "perfectAI.h"

using namespace std;

unsigned int startTestFromLayer = 0;

unsigned int endTestAtLayer = NUM_LAYERS - 1;

#ifdef _DEBUG
char databaseDirectory[] = "D:\\database";
#elif _RELEASE_X64
char databaseDirectory[] = "";
#endif

Mill *mill;
PerfectAI *ai;

int perfect_init(void)
{
    mill = new Mill();
    ai = new PerfectAI(databaseDirectory);
    ai->setDatabasePath(databaseDirectory);

    return 0;
}

int perfect_main(void)
{
    // locals
    bool playerOneHuman = false;
    bool playerTwoHuman = true;
    char ch[100];
    unsigned int from, to;

    mill->beginNewGame(ai, ai, fieldStruct::playerOne);

    // play
    do {
        mill->getComputersChoice(&from, &to);

        cout << "\nlast move was from " << (char)(mill->getLastMoveFrom() + 'a') << " to " << (char)(mill->getLastMoveTo() + 'a') << "\n\n";

        mill->printBoard();

        // Human
        if ((mill->getCurrentPlayer() == fieldStruct::playerOne && playerOneHuman) ||
            (mill->getCurrentPlayer() == fieldStruct::playerTwo && playerTwoHuman)) {

            do {
                // Show text
                if (mill->mustStoneBeRemoved())
                    cout << "\n   Which stone do you want to remove? [a-x]: \n\n\n";
                else if (mill->inSettingPhase())
                    cout << "\n   Where are you going? [a-x]: \n\n\n";
                else
                    cout << "\n   Your train? [a-x][a-x]: \n\n\n";

                // get input
                cin >> ch;
                if ((ch[0] >= 'a') && (ch[0] <= 'x'))
                    from = ch[0] - 'a';
                else
                    from = fieldStruct::size;

                if (mill->inSettingPhase()) {
                    if ((ch[0] >= 'a') && (ch[0] <= 'x'))
                        to = ch[0] - 'a';
                    else
                        to = fieldStruct::size;
                } else {
                    if ((ch[1] >= 'a') && (ch[1] <= 'x'))
                        to = ch[1] - 'a';
                    else
                        to = fieldStruct::size;
                }
            } while (mill->doMove(from, to) == false);

            // Computer
        }

    } while (mill->getWinner() == 0);


    return 0;
}
