/*********************************************************************\
    RandomAI.h
    Copyright (c) Thomas Weber. All rights reserved.
    Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
    Licensed under the MIT License.
    https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#ifndef RANDOM_AI_H
#define RANDOM_AI_H

#include <stdlib.h>
#include <time.h>
#include "millAI.h"

/*** Klassen *********************************************************/

class RandomAI : public MillAI
{
public:
    // Constructor / destructor
    RandomAI();
    ~RandomAI();

    // Functions
    void play(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo);
};

#endif
