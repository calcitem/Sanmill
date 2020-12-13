/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifdef TRAINING_MODE
#include "game.h"
#include "trainer.h"

int main(int argc, char *argv[])
{
    loggerDebug("Training start...\n");

    Game *game = new Game();
    
    game->gameReset();
    game->gameStart();

    game->isAiPlayer[BLACK] = game->isAiPlayer[WHITE] = true;

    game->setEngine(1, true);
    game->setEngine(2, true);

#ifdef WIN32
    system("pause");
#endif

    return 0;
}

#endif // TRAINING_MODE
