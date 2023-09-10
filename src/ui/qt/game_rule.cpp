// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include <iomanip>
#include <map>
#include <string>

#include <QAbstractButton>
#include <QApplication>
#include <QDir>
#include <QFileInfo>
#include <QGraphicsSceneMouseEvent>
#include <QGraphicsView>
#include <QKeyEvent>
#include <QMessageBox>
#include <QParallelAnimationGroup>
#include <QPropertyAnimation>
#include <QSoundEffect>
#include <QThread>
#include <QTimer>

#include "boarditem.h"
#include "client.h"
#include "game.h"
#include "graphicsconst.h"
#include "option.h"
#include "server.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

void Game::setRule(int ruleNo, int stepLimited, int timeLimited)
{
    rule.nMoveRule = stepLimited;

    // TODO(calcitem)

    if (!updateRuleIndex(ruleNo))
        return;
    updateLimits(stepLimited, timeLimited);

    // Set model rules, reset game
    if (set_rule(ruleNo) == false) {
        return;
    }

    resetElapsedSeconds();
    recordRuleInfo(ruleNo);
    gameReset();
    saveRuleSetting(ruleNo);
}

bool Game::updateRuleIndex(int ruleNo)
{
    if (ruleNo < 0 || ruleNo >= N_RULES)
        return false;
    ruleIndex = ruleNo;
    return true;
}

void Game::updateLimits(int stepLimited, int timeLimited)
{
    if (stepLimited != INT_MAX && timeLimited != 0) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }
}

void Game::recordRuleInfo(int ruleNo)
{
    constexpr int bufferLen = 64;
    char record[bufferLen] = {0};
    int r = ruleNo;
    if (snprintf(record, bufferLen, "r%1d s%03u t%02d", r + 1, rule.nMoveRule,
                 0) <= 0) {
        assert(false); // Replace with a proper error handling strategy
    }
    string cmd(record);
    moveHistory.clear();
    moveHistory.emplace_back(cmd);
}

std::pair<int, QStringList> Game::createRuleEntry(int index)
{
    QStringList strList;
    strList.append(tr(RULES[index].name));
    strList.append(tr(RULES[index].description));
    return {index, strList};
}
