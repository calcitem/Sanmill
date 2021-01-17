/*********************************************************************\
	randomKI.h
	Copyright (c) Thomas Weber. All rights reserved.
	Copyright (C) 2021 The Sanmill developers (see AUTHORS file)
	Licensed under the MIT License.
	https://github.com/madweasel/madweasels-cpp
\*********************************************************************/

#ifndef RANDOM_KI_H
#define RANDOM_KI_H

#include <stdlib.h>
#include <time.h>
#include "muehleKI.h"

/*** Klassen *********************************************************/

class randomKI : public muehleKI
{
public:
	// Constructor / destructor
	randomKI();
	~randomKI();

	// Functions
	void play(fieldStruct *theField, unsigned int *pushFrom, unsigned int *pushTo);
};

#endif
