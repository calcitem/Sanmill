// This file is part of Sanmill.
// Copyright (C) 2019-2024 The Sanmill developers (see AUTHORS file)
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

void Game::loadSettings()
{
    bool empty = false;

    const QFileInfo file(SETTINGS_FILE);
    if (!file.exists()) {
        cout << SETTINGS_FILE.toStdString() << " is not exists, create it."
             << std::endl;
        empty = true;
    }

    settings = new QSettings(SETTINGS_FILE, QSettings::IniFormat);

    setEngineWhite(empty ? false :
                           settings->value("Options/WhiteIsAiPlayer").toBool());
    setEngineBlack(empty ? true :
                           settings->value("Options/BlackIsAiPlayer").toBool());
    setFixWindowSize(empty ? false :
                             settings->value("Options/FixWindowSize").toBool());
    setSound(empty ? true : settings->value("Options/Sound").toBool());
    setAnimation(empty ? true : settings->value("Options/Animation").toBool());
    setSkillLevel(empty ? 1 : settings->value("Options/SkillLevel").toInt());
    setMoveTime(empty ? 1 : settings->value("Options/MoveTime").toInt());
    setAlgorithm(empty ? 2 : settings->value("Options/Algorithm").toInt());
    setUsePerfectDatabase(
        empty ? false : settings->value("Options/UsePerfectDatabase").toBool());
    setPerfectDatabasePath(empty ? "." :
                                   settings
                                       ->value("Options/"
                                               "PerfectDatabasePath")
                                       .toString()
                                       .toStdString());
    setDrawOnHumanExperience(
        empty ? true :
                settings->value("Options/DrawOnHumanExperience").toBool());
    setConsiderMobility(
        empty ? true : settings->value("Options/ConsiderMobility").toBool());
    setAiIsLazy(empty ? false : settings->value("Options/AiIsLazy").toBool());
    setShuffling(empty ? true : settings->value("Options/Shuffling").toBool());
    setResignIfMostLose(
        empty ? false : settings->value("Options/ResignIfMostLose").toBool());
    setOpeningBook(empty ? false :
                           settings->value("Options/OpeningBook").toBool());
    setLearnEndgame(
        empty ? false :
                settings->value("Options/LearnEndgameEnabled").toBool());
    setIDS(empty ? false : settings->value("Options/IDS").toBool());
    setDepthExtension(
        empty ? true : settings->value("Options/DepthExtension").toBool());
    setAutoRestart(empty ? false :
                           settings->value("Options/AutoRestart").toBool());
    setAutoChangeFirstMove(
        empty ? false :
                settings->value("Options/AutoChangeFirstMove").toBool());
    setDeveloperMode(empty ? false :
                             settings->value("Options/DeveloperMode").toBool());

    setRule(empty ? DEFAULT_RULE_NUMBER :
                    settings->value("Options/RuleNo").toInt());
}

void Game::destroySettings()
{
    delete settings;
    settings = nullptr;
}

void Game::saveRuleSetting(int ruleNo)
{
    settings->setValue("Options/RuleNo", ruleNo);
}

void Game::setEngine(Color color, bool enabled)
{
    isAiPlayer[color] = enabled;

    if (enabled == true) {
        aiThread[color]->setAi(&position);
        aiThread[color]->start_searching();

    } else {
        aiThread[color]->pause();
    }
}

void Game::setEngineWhite(bool enabled)
{
    setEngine(WHITE, enabled);
    settings->setValue("Options/WhiteIsAiPlayer", enabled);
}

void Game::setEngineBlack(bool enabled)
{
    setEngine(BLACK, enabled);
    settings->setValue("Options/BlackIsAiPlayer", enabled);
}

void Game::setAiDepthTime(int time1, int time2)
{
    stopAndWaitAiThreads();

    aiThread[WHITE]->setAi(&position, time1);
    aiThread[BLACK]->setAi(&position, time2);

    startAiThreads();
}

void Game::getAiDepthTime(int &time1, int &time2) const
{
    time1 = aiThread[WHITE]->getTimeLimit();
    time2 = aiThread[BLACK]->getTimeLimit();
}

void Game::setFixWindowSize(bool arg) noexcept
{
    fixWindowSize = arg;
    settings->setValue("Options/FixWindowSize", arg);
}

void Game::setSkillLevel(int val) const
{
    gameOptions.setSkillLevel(val);
    settings->setValue("Options/SkillLevel", val);
}

void Game::setMoveTime(int val) const
{
    gameOptions.setMoveTime(val);
    settings->setValue("Options/MoveTime", val);
}

void Game::setAlphaBetaAlgorithm(bool enabled) const
{
    if (enabled) {
        gameOptions.setAlgorithm(0);
        settings->setValue("Options/Algorithm", 0);
        debugPrintf("Algorithm is changed to Alpha-Beta.\n");
    }
}

void Game::setPvsAlgorithm(bool enabled) const
{
    if (enabled) {
        gameOptions.setAlgorithm(1);
        settings->setValue("Options/Algorithm", 1);
        debugPrintf("Algorithm is changed to PVS.\n");
    }
}

void Game::setMtdfAlgorithm(bool enabled) const
{
    if (enabled) {
        gameOptions.setAlgorithm(2);
        settings->setValue("Options/Algorithm", 2);
        debugPrintf("Algorithm is changed to MTD(f).\n");
    }
}

void Game::setMctsAlgorithm(bool enabled) const
{
    if (enabled) {
        gameOptions.setAlgorithm(3);
        settings->setValue("Options/Algorithm", 3);
        debugPrintf("Algorithm is changed to MCTS.\n");
    }
}

void Game::setRandomAlgorithm(bool enabled) const
{
    if (enabled) {
        gameOptions.setAlgorithm(4);
        settings->setValue("Options/Algorithm", 4);
        debugPrintf("Algorithm is changed to Random.\n");
    }
}

void Game::setAlgorithm(int val) const
{
    gameOptions.setAlgorithm(val);
    settings->setValue("Options/Algorithm", val);
}

void Game::setUsePerfectDatabase(bool arg) noexcept
{
    // TODO: If it is checked,
    // the box will still pop up once when opening the program.
    if (gameOptions.getUsePerfectDatabase() == false && arg == true) {
        QMessageBox msgBox;
        msgBox.setText(tr("Please visit the following link for detailed "
                          "operating "
                          "instructions:"));

        QString url = "<a "
                      "href='https://github.com/calcitem/Sanmill/blob/HEAD/src/"
                      "perfect/README.md'>User Guide for Setting Up and "
                      "Running Perfect AI</a>";
        msgBox.setInformativeText(url);
        msgBox.setTextFormat(Qt::RichText);
        msgBox.setTextInteractionFlags(Qt::TextBrowserInteraction);
        msgBox.exec();
    }

    gameOptions.setUsePerfectDatabase(arg);
    settings->setValue("Options/UsePerfectDatabase", arg);
}

void Game::setPerfectDatabasePath(string val) const
{
    gameOptions.setPerfectDatabasePath(val);
    settings->setValue("Options/PerfectDatabasePath",
                       QString::fromStdString(val));
}

// TODO: When call this? Same as setUsePerfectDatabase above?
void Game::setUsePerfectDatabase(bool enabled) const
{
#if 0
    // TODO: Show dialog twice when launching

    if (enabled && databaseDialog->exec() == QDialog::Accepted) {
        std::string path = databaseDialog->getPath().toStdString();
        setPerfectDatabase(path);
    }
#endif

    gameOptions.setUsePerfectDatabase(enabled);
    settings->setValue("Options/UsePerfectDatabase", enabled);

#if defined(GABOR_MALOM_PERFECT_AI)
    if (enabled) {
        perfect_reset();
    } else {
        perfect_exit();
    }
#endif
}

void Game::setDrawOnHumanExperience(bool enabled) const
{
    gameOptions.setDrawOnHumanExperience(enabled);
    settings->setValue("Options/DrawOnHumanExperience", enabled);
}

void Game::setConsiderMobility(bool enabled) const
{
    gameOptions.setConsiderMobility(enabled);
    settings->setValue("Options/ConsiderMobility", enabled);
}

void Game::setAiIsLazy(bool enabled) const
{
    gameOptions.setAiIsLazy(enabled);
    settings->setValue("Options/AiIsLazy", enabled);
}

void Game::setResignIfMostLose(bool enabled) const
{
    gameOptions.setResignIfMostLose(enabled);
    settings->setValue("Options/ResignIfMostLose", enabled);
}

void Game::setAutoRestart(bool enabled) const
{
    gameOptions.setAutoRestart(enabled);
    settings->setValue("Options/AutoRestart", enabled);
}

void Game::setAutoChangeFirstMove(bool enabled) const
{
    gameOptions.setAutoChangeFirstMove(enabled);
    settings->setValue("Options/AutoChangeFirstMove", enabled);
}

void Game::setShuffling(bool enabled) const
{
    gameOptions.setShufflingEnabled(enabled);
    settings->setValue("Options/Shuffling", enabled);
}

void Game::setLearnEndgame(bool enabled) const
{
    gameOptions.setLearnEndgameEnabled(enabled);
    settings->setValue("Options/LearnEndgameEnabled", enabled);

#ifdef ENDGAME_LEARNING
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::loadEndgameFileToHashMap();
    }
#endif
}

void Game::setIDS(bool enabled) const
{
    gameOptions.setIDSEnabled(enabled);
    settings->setValue("Options/IDS", enabled);
}

// DepthExtension
void Game::setDepthExtension(bool enabled) const
{
    gameOptions.setDepthExtension(enabled);
    settings->setValue("Options/DepthExtension", enabled);
}

// OpeningBook
void Game::setOpeningBook(bool enabled) const
{
    gameOptions.setOpeningBook(enabled);
    settings->setValue("Options/OpeningBook", enabled);
}

void Game::setDeveloperMode(bool enabled) const
{
    gameOptions.setDeveloperMode(enabled);
    settings->setValue("Options/DeveloperMode", enabled);
}
