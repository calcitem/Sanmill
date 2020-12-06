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

#ifndef OPTION_H
#define OPTION_H

#include "config.h"

class GameOptions
{
public:
    void setAutoRestart(bool enabled);
    bool getAutoRestart();

    void setAutoChangeFirstMove(bool enabled);
    bool getAutoChangeFirstMove();

    void setResignIfMostLose(bool enabled);
    bool getResignIfMostLose();

    void setRandomMoveEnabled(bool enabled);
    bool getRandomMoveEnabled();

    void setLearnEndgameEnabled(bool enabled);
    bool getLearnEndgameEnabled();

    void setIDSEnabled(bool enabled);
    bool getIDSEnabled();

    // DepthExtension
    void setDepthExtension(bool enabled);
    bool getDepthExtension();

    // OpeningBook
    void setOpeningBook(bool enabled);
    bool getOpeningBook();

protected:

private:
    bool isAutoRestart { false };
    bool isAutoChangeFirstMove { false };
    bool resignIfMostLose { false };
    bool randomMoveEnabled { true };
#ifdef ENDGAME_LEARNING_FORCE
    bool learnEndgame { true };
#else
    bool learnEndgame { false };
#endif
    bool IDSEnabled { false };
    bool depthExtension {true};
    bool openingBook { false };
};

extern GameOptions gameOptions;

#endif /* OPTION_H */
