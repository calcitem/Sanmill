/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include "gamecontroller.h"
#include "trainer.h"

#ifdef TRAINING_MODE

int main(int argc, char *argv[])
{
    loggerDebug("Training start...\n");

    GameController *gameController = new GameController();
    
    gameController->gameReset();
    gameController->gameStart();

    gameController->isAiPlayer[1] = gameController->isAiPlayer[2] = true;

    gameController->setEngine(1, true);
    gameController->setEngine(2, true);

#ifdef WIN32
    system("pause");
#endif

    return 0;
}

#endif // TRAINING_MODE
