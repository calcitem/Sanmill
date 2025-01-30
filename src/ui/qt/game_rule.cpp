// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_rule.cpp

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
bool Game::isRuleIndexValid(int ruleNo)
{
    return (ruleNo >= 0 && ruleNo < N_RULES);
}

// Update limited steps and time.
void Game::setMoveAndTimeLimits(int stepLimited, int timeLimited)
{
    if (stepLimited != INT_MAX && timeLimited != 0) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }
}

// Set a new game rule.
void Game::applyRule(int ruleNo, int stepLimited, int timeLimited)
{
    // Validate the rule number.
    if (!isRuleIndexValid(ruleNo))
        return;

    // Update rule index.
    ruleIndex = ruleNo;

    // Update move rule.
    rule.nMoveRule = stepLimited;

    // Update other game settings.
    setMoveAndTimeLimits(stepLimited, timeLimited);

    // Reset the model and the game.
    if (!set_rule(ruleNo))
        return;

    // Update internal game state.
    gameReset();

    // Record and save the new rule setting.
    storeRuleSetting(ruleNo);
}

// Create a list entry for the game rule.
std::pair<int, QStringList> Game::buildRuleEntry(int index)
{
    QStringList strList;
    strList.append(tr(RULES[index].name));
    strList.append(tr(RULES[index].description));
    return {index, strList};
}
