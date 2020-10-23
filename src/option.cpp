/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

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

#include "option.h"

GameOptions gameOptions;

void GameOptions::setAutoRestart(bool enabled)
{
    isAutoRestart = enabled;
}

bool GameOptions::getAutoRestart()
{
    return isAutoRestart;
}

void GameOptions::setAutoChangeFirstMove(bool enabled)
{
    isAutoChangeFirstMove = enabled;
}

bool GameOptions::getAutoChangeFirstMove()
{
    return isAutoChangeFirstMove;
}

void GameOptions::setResignIfMostLose(bool enabled)
{
    resignIfMostLose = enabled;
}

bool GameOptions::getResignIfMostLose()
{
    return resignIfMostLose;
}

void GameOptions::setRandomMoveEnabled(bool enabled)
{
    randomMoveEnabled = enabled;
}

bool GameOptions::getRandomMoveEnabled()
{
    return randomMoveEnabled;
}

void GameOptions::setLearnEndgameEnabled(bool enabled)
{
#ifdef ENDGAME_LEARNING_FORCE
    learnEndgame = true;
#else
    learnEndgame = enabled;
#endif
}

bool GameOptions::getLearnEndgameEnabled()
{
#ifdef ENDGAME_LEARNING_FORCE
    return  true;
#else
    return learnEndgame;
#endif
}

void GameOptions::setIDSEnabled(bool enabled)
{
    IDSEnabled = enabled;
}

bool GameOptions::getIDSEnabled()
{
    return IDSEnabled;
}

// DepthExtension

void GameOptions::setDepthExtension(bool enabled)
{
    depthExtension = enabled;
}

bool GameOptions::getDepthExtension()
{
    return depthExtension;
}

// OpeningBook

void GameOptions::setOpeningBook(bool enabled)
{
    openingBook = enabled;
}

bool GameOptions::getOpeningBook()
{
    return openingBook;
}
