/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019 Calcitem <calcitem@outlook.com>

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

class Options
{
public:
    void setAutoRestart(bool enabled);
    bool getAutoRestart();

    void setGiveUpIfMostLose(bool enabled);
    bool getGiveUpIfMostLose();

    void setRandomMoveEnabled(bool enabled);
    bool getRandomMoveEnabled();

    void setLearnEndgameEnabled(bool enabled);
    bool getLearnEndgameEnabled();
protected:

private:
    // 是否棋局结束后自动重新开局
    bool isAutoRestart { false };

    // 是否必败时认输
    bool giveUpIfMostLose { false };

    // AI 是否随机走子
    bool randomMoveEnabled { true };

    // AI 是否生成残局库
    bool learnEndgame { false };
};

extern Options gameOptions;

#endif /* OPTION_H */
