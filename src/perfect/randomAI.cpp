/*********************************************************************
    RandomAI.cpp
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the GPLv3 License.
    https://github.com/madweasel/Muehle
\*********************************************************************/

#include "config.h"

#ifdef MADWEASEL_MUEHLE_PERFECT_AI

#include "randomAI.h"

//-----------------------------------------------------------------------------
// RandomAI()
// RandomAI class constructor
//-----------------------------------------------------------------------------
RandomAI::RandomAI()
{
    // Init
    srand((unsigned)time(nullptr));
}

//-----------------------------------------------------------------------------
// ~RandomAI()
// RandomAI class destructor
//-----------------------------------------------------------------------------
RandomAI::~RandomAI()
{
    // Locals
}

//-----------------------------------------------------------------------------
// play()
//
//-----------------------------------------------------------------------------
void RandomAI::play(fieldStruct *theField, unsigned int *pushFrom,
                    unsigned int *pushTo)
{
    // locals
    unsigned int from, to, direction;
    bool allowedToSpring = (theField->curPlayer->numStones == 3) ? true : false;

    // must stone be removed ?
    if (theField->stoneMustBeRemoved) {
        // search a stone from the enemy
        do {
            from = rand() % theField->size;
            to = theField->size;
        } while (theField->board[from] != theField->oppPlayer->id ||
                 theField->stonePartOfMill[from]);

        // still in setting phase ?
    } else if (theField->settingPhase) {
        // search a free square
        do {
            from = theField->size;
            to = rand() % theField->size;
        } while (theField->board[to] != theField->squareIsFree);

        // try to push randomly
    } else {
        do {
            // search an own stone
            do {
                from = rand() % theField->size;
            } while (theField->board[from] != theField->curPlayer->id);

            // select a free square
            if (allowedToSpring) {
                do {
                    to = rand() % theField->size;
                } while (theField->board[to] != theField->squareIsFree);

                // select a connected square
            } else {
                do {
                    direction = rand() % 4;
                    to = theField->connectedSquare[from][direction];
                } while (to == theField->size);
            }
        } while (theField->board[to] != theField->squareIsFree);
    }

    *pushFrom = from;
    *pushTo = to;
}

#endif // MADWEASEL_MUEHLE_PERFECT_AI
