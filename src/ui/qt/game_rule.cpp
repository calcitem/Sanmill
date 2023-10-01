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

// Validate the rule index.
bool Game::isValidRuleIndex(int ruleNo)
{
    return (ruleNo >= 0 && ruleNo < N_RULES);
}

// Update limited steps and time.
void Game::updateLimits(int stepLimited, int timeLimited)
{
    if (stepLimited != INT_MAX && timeLimited != 0) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }
}

// Record the rule info in move list.
void Game::recordRuleInfo(int ruleNo)
{
    constexpr int bufferLen = 64;
    char record[bufferLen] = {0};
    if (snprintf(record, bufferLen, "r%1d s%03u t%02d", ruleNo + 1,
                 rule.nMoveRule, 0) <= 0) {
        assert(false); // Replace with proper error handling.
    }
    gameMoveList.clear();
    gameMoveList.emplace_back(string(record));
}

// Set a new game rule.
void Game::setRule(int ruleNo, int stepLimited, int timeLimited)
{
    // Validate the rule number.
    if (!isValidRuleIndex(ruleNo))
        return;

    // Update rule index.
    ruleIndex = ruleNo;

    // Update move rule.
    rule.nMoveRule = stepLimited;

    // Update other game settings.
    updateLimits(stepLimited, timeLimited);

    // Reset the model and the game.
    if (!set_rule(ruleNo))
        return;

    // Update internal game state.
    gameReset();

    // Record and save the new rule setting.
    recordRuleInfo(ruleNo);
    saveRuleSetting(ruleNo);
}

// Create a list entry for the game rule.
std::pair<int, QStringList> Game::createRuleEntry(int index)
{
    QStringList strList;
    strList.append(tr(RULES[index].name));
    strList.append(tr(RULES[index].description));
    return {index, strList};
}
