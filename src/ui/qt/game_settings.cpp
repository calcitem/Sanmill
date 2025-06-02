// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_settings.cpp

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

#include "game.h"
#include "option.h"
#include "thread_pool.h"
#include "search_engine.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

QString getExecutableDirectory()
{
    QString executablePath = QCoreApplication::applicationFilePath();
    QFileInfo fileInfo(executablePath);
    return QDir::toNativeSeparators(fileInfo.absolutePath());
}

QString buildSettingsFilePath(const QString &settingsFile)
{
    QString executableDir = getExecutableDirectory();
    QDir dir(executableDir);
    QString settingsFilename = dir.filePath(settingsFile);
    return QDir::toNativeSeparators(settingsFilename);
}

QString Game::getSettingsFilePath() const
{
    return buildSettingsFilePath(SETTINGS_FILE);
}

void Game::loadGameSettings()
{
    bool empty = false;

    QString settingsFilename = buildSettingsFilePath(SETTINGS_FILE);

    qDebug() << "Settings File Path:" << settingsFilename;

    const QFileInfo file(settingsFilename);
    if (!file.exists()) {
        cout << settingsFilename.toStdString() << " is not exists, create it."
             << std::endl;
        empty = true;
    }

    settings = new QSettings(settingsFilename, QSettings::IniFormat);

    setWhiteIsAiPlayer(
        empty ? false : settings->value("Options/WhiteIsAiPlayer").toBool());
    setBlackIsAiPlayer(
        empty ? true : settings->value("Options/BlackIsAiPlayer").toBool());
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
    setFocusOnBlockingPaths(
        empty ? true :
                settings->value("Options/FocusOnBlockingPaths").toBool());
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

    // Load player time limits (new system)
    int whiteTime = empty ?
                        0 :
                        settings->value("Options/WhiteTimeLimit", 0).toInt();
    int blackTime = empty ?
                        0 :
                        settings->value("Options/BlackTimeLimit", 0).toInt();
    setPlayerTimeLimits(whiteTime, blackTime);

    // Load move limit
    int moveLimitValue = empty ?
                             100 :
                             settings->value("Options/MoveLimit", 100).toInt();
    setMoveLimit(moveLimitValue);

    applyRule(empty ? DEFAULT_RULE_NUMBER :
                      settings->value("Options/RuleNo").toInt());

    // Load AI time limits
    // int time1 = empty ? 1 : settings->value("Options/AiTimeLimit1",
    // 1).toInt(); int time2 = empty ? 1 :
    // settings->value("Options/AiTimeLimit2", 1).toInt();

    // Remove unsupported setoption commands that cause "Unknown command" errors
    // The time limits should be handled through the Game class methods instead
    // of UCI commands engineController.handleCommand("setoption name
    // WhiteTimeLimit value " +
    //                                    std::to_string(time1),
    //                                nullptr);
    // engineController.handleCommand("setoption name BlackTimeLimit value " +
    //                                    std::to_string(time2),
    //                                nullptr);
}

void Game::cleanupSettings()
{
    delete settings;
    settings = nullptr;
}

void Game::storeRuleSetting(int ruleNo)
{
    settings->setValue("Options/RuleNo", ruleNo);
}

void Game::setEngineControl(Color color, bool enabled)
{
    // Mark whether this color is controlled by AI
    isAiPlayer[color] = enabled;
}

void Game::setWhiteIsAiPlayer(bool enabled)
{
    setEngineControl(WHITE, enabled);
    settings->setValue("Options/WhiteIsAiPlayer", enabled);
    processGameOutcome();
}

void Game::setBlackIsAiPlayer(bool enabled)
{
    setEngineControl(BLACK, enabled);
    settings->setValue("Options/BlackIsAiPlayer", enabled);
    processGameOutcome();
}

void Game::setAiTimeLimits(int time1, int time2)
{
    // Store AI time limits in settings
    settings->setValue("Options/AiTimeLimit1", time1);
    settings->setValue("Options/AiTimeLimit2", time2);

    // Pass the time limits to the engine controller
    // engineController.handleCommand("setoption name WhiteTimeLimit value " +
    // std::to_string(time1), nullptr);
    // engineController.handleCommand("setoption name BlackTimeLimit value " +
    // std::to_string(time2), nullptr);

    // Update the UI with the new time limits
    emit statusBarChanged("AI time limits updated");
}

void Game::getAiTimeLimits(int &time1, int &time2) const
{
    // Retrieve AI time limits from settings with default values of 1 second
    time1 = settings->value("Options/AiTimeLimit1", 1).toInt();
    time2 = settings->value("Options/AiTimeLimit2", 1).toInt();
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
    if (!gameOptions.getUsePerfectDatabase() && arg == true) {
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

// Variation of setUsePerfectDatabase that also handles perfect_reset/exit
void Game::setUsePerfectDatabase(bool enabled) const
{
#if 0
    // If you want to pop up a dialog:
    // if (enabled && databaseDialog->exec() == QDialog::Accepted) {
    //     std::string path = databaseDialog->getPath().toStdString();
    //     setPerfectDatabase(path);
    // }
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

void Game::setFocusOnBlockingPaths(bool enabled) const
{
    gameOptions.setFocusOnBlockingPaths(enabled);
    settings->setValue("Options/FocusOnBlockingPaths", enabled);
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
        // Under the old code, we called Thread::loadEndgameFileToHashMap().
        // Now that Thread is replaced, you might have a different loading
        // mechanism, or you could keep a static function call like so:
        loadEndgameFileToHashMap();
    }
#endif
}

void Game::setIDS(bool enabled) const
{
    gameOptions.setIDSEnabled(enabled);
    settings->setValue("Options/IDS", enabled);
}

void Game::setDepthExtension(bool enabled) const
{
    gameOptions.setDepthExtension(enabled);
    settings->setValue("Options/DepthExtension", enabled);
}

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

void Game::setPlayerTimeLimits(int whiteTime, int blackTime)
{
    // Store player time limits
    playerTimeLimit[WHITE] = whiteTime;
    playerTimeLimit[BLACK] = blackTime;

    // Save to settings
    settings->setValue("Options/WhiteTimeLimit", whiteTime);
    settings->setValue("Options/BlackTimeLimit", blackTime);

    // Enable timer if either time limit is 0 (no limit with 60min countdown) or
    // greater than 0
    timerEnabled = (whiteTime >= 0 || blackTime >= 0);

    // Initialize remaining time
    // For 0 (no limit), start with 60 minutes (3600 seconds) countdown
    playerRemainingTime[WHITE] = (whiteTime == 0) ? 3600 : whiteTime;
    playerRemainingTime[BLACK] = (blackTime == 0) ? 3600 : blackTime;

    // Update LCD displays
    emitTimeChangedSignals();
}

void Game::getPlayerTimeLimits(int &whiteTime, int &blackTime) const
{
    whiteTime = playerTimeLimit[WHITE];
    blackTime = playerTimeLimit[BLACK];
}

void Game::startPlayerTimer(Color player)
{
    // For time limit 0 (no limit), we still run timer for 60-minute countdown
    // display For other values, check if time limit is greater than 0
    if (!timerEnabled && playerTimeLimit[player] == 0) {
        // Special case: no time limit, but we still want 60-minute countdown
        // display
        timerEnabled = true;
    } else if (!timerEnabled || playerTimeLimit[player] < 0) {
        return;
    }

    // Stop any existing timer
    stopPlayerTimer();

    // Don't start timer for human player's first move
    // AI can start timer on first move
    if (isFirstMoveOfGame && !isAiPlayer[player]) {
        return;
    }

    // Create timer if it doesn't exist
    if (!playerTimer) {
        playerTimer = new QTimer(this);
        connect(playerTimer, &QTimer::timeout, [this]() {
            // Decrease remaining time
            if (playerRemainingTime[currentTimerPlayer] > 0) {
                playerRemainingTime[currentTimerPlayer]--;
                emitTimeChangedSignals();
            } else {
                // Time is up, handle timeout
                if (playerTimeLimit[currentTimerPlayer] == 0) {
                    // For no time limit (0), keep displaying 0 and don't
                    // trigger timeout
                    playerRemainingTime[currentTimerPlayer] = 0;
                    emitTimeChangedSignals();
                } else {
                    // For actual time limits, handle timeout
                    handlePlayerTimeout(currentTimerPlayer);
                }
            }
        });
    }

    // Set current timer player
    currentTimerPlayer = player;

    // Reset remaining time for this player if needed
    if (playerRemainingTime[player] <= 0) {
        if (playerTimeLimit[player] == 0) {
            // For no time limit, reset to 60 minutes
            playerRemainingTime[player] = 3600;
        } else {
            playerRemainingTime[player] = playerTimeLimit[player];
        }
    }

    // Start timer (1 second interval)
    playerTimer->start(1000);
}

void Game::stopPlayerTimer()
{
    if (playerTimer && playerTimer->isActive()) {
        playerTimer->stop();
    }
}

void Game::handlePlayerTimeout(Color player)
{
    // Don't handle timeout for no time limit (0)
    if (playerTimeLimit[player] == 0) {
        return;
    }

    // AI players never lose due to timeout, only human players do
    if (isAiPlayer[player]) {
        // For AI players, just reset the timer and continue
        // AI should never be penalized for timeout
        emit statusBarChanged("AI time limit reached - continuing without "
                              "penalty");
        playerRemainingTime[player] = playerTimeLimit[player];
        emitTimeChangedSignals();
        return;
    }

    // Stop the timer
    stopPlayerTimer();

    // Only human players can lose due to timeout
    // Color winner = (player == WHITE) ? BLACK : WHITE;
    QString playerName = (player == WHITE) ? "White" : "Black";
    emit statusBarChanged(
        QString("Player %1 lost due to timeout").arg(playerName));

    // Set game over
    // Note: This might need to be adapted to match the actual Position
    // class interface position.setGameOver(winner,
    // GameOverReason::timeout);

    // Play loss sound
    playGameSound(GameSound::loss);

    // Update game statistics
    processGameOutcome();
}

bool Game::isFirstMove() const
{
    return isFirstMoveOfGame;
}

void Game::setMoveLimit(int moves)
{
    moveLimit = moves;
    settings->setValue("Options/MoveLimit", moves);

    // Apply the move limit to the current rule
    if (settings) {
        applyRule(getRuleIndex(), moves, getTimeLimit());
    }
}

int Game::getMoveLimit() const
{
    return moveLimit;
}
