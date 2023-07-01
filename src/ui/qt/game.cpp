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

#ifdef MADWEASEL_MUEHLE_PERFECT_AI
#include "perfect/perfect.h"
#endif

using std::to_string;

Game::Game(GameScene &scene, QObject *parent)
    : QObject(parent)
    , scene(scene)
    , timeLimit(gameOptions.getMoveTime())
{
    // The background has been added to the style sheet of view, but not to
    // scene The difference is that the background in view does not change with
    // the view transformation, and the background in scene changes with the
    // view transformation
    // scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));
#ifdef QT_MOBILE_APP_UI
    scene.setBackgroundBrush(QColor(239, 239, 239));
#endif /* QT_MOBILE_APP_UI */

    // resetAiPlayers();
    createAiThreads();

    loadSettings();

    gameReset();

    gameTest = new Test();

    qRegisterMetaType<std::string>("string");

#ifdef QT_GUI_LIB
    // The command line of AI and controller
    connect(aiThread[WHITE], SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
    connect(aiThread[BLACK], SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));

    connect(this->gameTest, SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
#endif // QT_GUI_LIB

#ifdef NET_FIGHT_SUPPORT
    server = new Server(nullptr,
                        30001); // TODO(calcitem): WARNING: ThreadSanitizer:
                                // data race
    uint16_t clientPort = server->getPort() == 30001 ? 30002 : 30001;
    client = new Client(nullptr, clientPort);

    // The command line of AI and network
    connect(getClient(), SIGNAL(command(const string &, bool)), this,
            SLOT(command(const string &, bool)));
#endif // NET_FIGHT_SUPPORT

#ifdef ENDGAME_LEARNING_FORCE
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::loadEndgameFileToHashMap();
    }
#endif

    moveHistory.reserve(256);
}

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
    setPerfectAi(empty ? false : settings->value("Options/PerfectAI").toBool());
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

Game::~Game()
{
    if (timeID != 0)
        killTimer(timeID);

    pauseAndWaitThreads();
    deleteAiThreads();

#ifdef ENDGAME_LEARNING
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::saveEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */

    moveHistory.clear();

    delete settings;
    settings = nullptr;
}

map<int, QStringList> Game::getActions()
{
    // Main window update menu bar
    // The reason why we don't use the mode of signal and slot is that
    // it's too late for the slot to be associated when the signal is sent
    map<int, QStringList> actions;

    for (int i = 0; i < N_RULES; i++) {
        // The key of map stores int index value, and value stores rule name and
        // rule prompt
        QStringList strList;
        strList.append(tr(RULES[i].name));
        strList.append(tr(RULES[i].description));
        actions.insert(map<int, QStringList>::value_type(i, strList));
    }

    return actions;
}

#ifdef OPENING_BOOK
extern deque<int> openingBookDeque;
extern deque<int> openingBookDequeBak;
#endif

#ifdef NNUE_GENERATE_TRAINING_DATA
extern int nnueTrainingDataIndex;
#endif /* NNUE_GENERATE_TRAINING_DATA */

void Game::gameStart()
{
    // moveHistory.clear();
    position.start();
    startTime = time(nullptr);

    // The timer handler is called every 100 milliseconds
    if (timeID == 0) {
        timeID = startTimer(100);
    }

    gameStartTime = now();
    gameStartCycle = stopwatch::rdtscp_clock::now();

#ifdef OPENING_BOOK
    if (openingBookDeque.empty() && !openingBookDequeBak.empty()) {
        openingBookDeque = openingBookDequeBak;
        openingBookDequeBak.clear();
    }
#endif
}

void Game::gameReset()
{
    while (aiThread[WHITE]->searching || aiThread[BLACK]->searching) {
        debugPrintf(".");
        QThread::msleep(100);
    }

    debugPrintf("\n");

    if (timeID != 0)
        killTimer(timeID);

    timeID = 0;

    // Reset game
    // WAR
    if (moveHistory.size() > 1) {
        string bak = moveHistory[0];
        moveHistory.clear();
        moveHistory.emplace_back(bak);
    }

#ifdef MADWEASEL_MUEHLE_PERFECT_AI
    if (gameOptions.getPerfectAiEnabled()) {
        perfect_reset();
    }
#endif

    position.reset();
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;
    sideToMove = position.side_to_move();

    // Stop threads
    if (!gameOptions.getAutoRestart()) {
        pauseThreads();
        // resetAiPlayers();
    }

    // Clear pieces
    qDeleteAll(pieceList);
    pieceList.clear();
    currentPiece = nullptr;

    // Redraw pieces
    scene.setDiagonal(rule.hasDiagonalLines);

    // Draw all the pieces and put them in the starting position
    // 0: the first piece in the first hand; 1: the first piece in the second
    // hand 2: the first second piece; 3: the second piece
    // ......

    for (int i = 0; i < rule.pieceCount; i++) {
        // The first piece
        PieceItem::Models md = isInverted ? PieceItem::Models::blackPiece :
                                            PieceItem::Models::whitePiece;
        auto newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p1);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);

        // Backhand piece
        md = isInverted ? PieceItem::Models::whitePiece :
                          PieceItem::Models::blackPiece;
        newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p2);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);
    }

    timeLimit = gameOptions.getMoveTime();

    // If the rule does not require timing, time1 and time2 represent the time
    // used
    if (timeLimit <= 0) {
        // Clear the player's used time
        remainingTime[WHITE] = remainingTime[BLACK] = 0;
    } else {
        // Set the player's remaining time to a limited time
        remainingTime[WHITE] = remainingTime[BLACK] = timeLimit;
    }

    // Update move history
    moveListModel.removeRows(0, moveListModel.rowCount());
    moveListModel.insertRow(0);
    moveListModel.setData(moveListModel.index(0), position.get_record());
    currentRow = 0;

    // Signal the main window to update the LCD display
    const QTime qtime = QTime(0, 0, 0, 0)
                            .addSecs(static_cast<int>(remainingTime[WHITE]));
    emit time1Changed(qtime.toString("hh:mm:ss"));
    emit time2Changed(qtime.toString("hh:mm:ss"));

    // Signal update status bar
    updateScene();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // Update LCD display
    emit nGamesPlayedChanged(QString::number(position.gamesPlayedCount, 10));
    emit score1Changed(QString::number(position.score[WHITE], 10));
    emit score2Changed(QString::number(position.score[BLACK], 10));
    emit scoreDrawChanged(QString::number(position.score_draw, 10));

    // Update winning rate LCD display
    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] +
                                position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;
    if (position.gamesPlayedCount != 0) {
        winningRate_1 = position.score[WHITE] * 10000 /
                        position.gamesPlayedCount;
        winningRate_2 = position.score[BLACK] * 10000 /
                        position.gamesPlayedCount;
        winningRate_draw = position.score_draw * 10000 /
                           position.gamesPlayedCount;
    }

    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));

    // Sound effects play
    // playSound(":/sound/resources/sound/newgame.wav");
}

void Game::setEditing(bool arg) noexcept
{
    isEditing = arg;
}

void Game::setInvert(bool arg)
{
    isInverted = arg;

    // For all pieces
    for (PieceItem *pieceItem : pieceList) {
        if (pieceItem) {
            // White -> Black
            if (pieceItem->getModel() == PieceItem::Models::whitePiece)
                pieceItem->setModel(PieceItem::Models::blackPiece);

            // Black -> White
            else if (pieceItem->getModel() == PieceItem::Models::blackPiece)
                pieceItem->setModel(PieceItem::Models::whitePiece);

            // Refresh checkerboard display
            pieceItem->update();
        }
    }
}

void Game::setRule(int ruleNo, int stepLimited /*= -1*/,
                   int timeLimited /*= 0 TODO(calcitem): Unused */)
{
    rule.nMoveRule = stepLimited;

    // TODO(calcitem)

    // Update the rule, the original time limit and step limit remain unchanged
    if (ruleNo < 0 || ruleNo >= N_RULES)
        return;
    this->ruleIndex = ruleNo;

    if (stepLimited != INT_MAX && timeLimited != 0) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }

    // Set model rules, reset game
    if (set_rule(ruleNo) == false) {
        return;
    }

    const int r = ruleNo;
    elapsedSeconds[WHITE] = elapsedSeconds[BLACK] = 0;

    char record[64] = {0};
    if (snprintf(record, Position::RECORD_LEN_MAX, "r%1d s%03u t%02d", r + 1,
                 rule.nMoveRule, 0) <= 0) {
        assert(0);
    }
    string cmd(record);
    moveHistory.clear();
    moveHistory.emplace_back(cmd);

    // Reset game
    gameReset();

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

void Game::setAnimation(bool arg) noexcept
{
    hasAnimation = arg;

    // The default animation time is 500ms
    if (hasAnimation)
        durationTime = 500;
    else
        durationTime = 0;

    settings->setValue("Options/Animation", arg);
}

void Game::setSound(bool arg) const noexcept
{
    hasSound = arg;
    settings->setValue("Options/Sound", arg);
}

void Game::playSound(GameSound soundType, Color c)
{
    string soundDir = ":/sound/resources/sound/";
    string sideStr = c == WHITE ? "W" : "B";
    string opponentStr = c == BLACK ? "W" : "B";
    string filename;

    switch (soundType) {
    case GameSound::blockMill:
        filename = "BlockMill_" + sideStr + ".wav";
        break;
    case GameSound::remove:
        filename = "Remove_" + opponentStr + ".wav";
        break;
    case GameSound::select:
        filename = "Select.wav";
        break;
    case GameSound::draw:
        filename = "Draw.wav";
        break;
    case GameSound::drag:
        filename = "drag.wav";
        break;
    case GameSound::banned:
        filename = "forbidden.wav";
        break;
    case GameSound::gameStart:
        filename = "GameStart.wav";
        break;
    case GameSound::resign:
        filename = "Resign_" + sideStr + ".wav";
        break;
    case GameSound::loss:
        filename = "loss.wav";
        break;
    case GameSound::mill:
        filename = "Mill_" + sideStr + ".wav";
        break;
    case GameSound::millRepeatedly:
        filename = "MillRepeatedly_" + sideStr + ".wav";
        break;
    case GameSound::move:
        filename = "move.wav";
        break;
    case GameSound::newGame:
        filename = "newgame.wav";
        break;
    case GameSound::nextMill:
        filename = "NextMill_" + sideStr + ".wav";
        break;
    case GameSound::obvious:
        filename = "Obvious.wav";
        break;
    case GameSound::repeatThreeDraw:
        filename = "RepeatThreeDraw.wav";
        break;
    case GameSound::side:
        filename = "Side_" + sideStr + ".wav";
        break;
    case GameSound::star:
        filename = "Star_" + sideStr + ".wav";
        break;
    case GameSound::suffocated:
        filename = "Suffocated_" + sideStr + ".wav";
        break;
    case GameSound::vantage:
        filename = "Vantage.wav";
        break;
    case GameSound::very:
        filename = "Very.wav";
        break;
    case GameSound::warning:
        filename = "warning.wav";
        break;
    case GameSound::win:
        if (c == DRAW) {
            filename = "Draw.wav";
        } else {
            filename = "Win_" + sideStr + ".wav";
        }
        break;
    case GameSound::winAndLossesAreObvious:
        filename = "WinsAndLossesAreObvious.wav";
        break;
    case GameSound::none:
        filename = "";
        break;
    }

#ifndef DO_NOT_PLAY_SOUND
    QString soundPath = QString::fromStdString(soundDir + filename);

    if (soundPath == "") {
        return;
    }

    if (hasSound) {
        auto *effect = new QSoundEffect;
        effect->setSource(QUrl::fromLocalFile(soundPath));
        effect->setLoopCount(1);
        effect->play();
    }
#endif /* ! DO_NOT_PLAY_SOUND */
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

void Game::setAlgorithm(int val) const
{
    gameOptions.setAlgorithm(val);
    settings->setValue("Options/Algorithm", val);
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

void Game::setPerfectAi(bool enabled) const
{
    gameOptions.setPerfectAiEnabled(enabled);
    settings->setValue("Options/PerfectAI", enabled);

#ifdef MADWEASEL_MUEHLE_PERFECT_AI
    if (enabled) {
        perfect_reset();
    } else {
        perfect_exit();
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

void Game::flip()
{
    stopAndWaitAiThreads();

    position.mirror(moveHistory);
    position.rotate(moveHistory, 180);

    // Update move history
    int row = 0;
    for (const auto &str : *move_history()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }

    // Refresh display
    if (currentRow == row - 1)
        updateScene();
    else
        phaseChange(currentRow, true);

    threadsSetAi(&position);
    startAiThreads();
}

void Game::mirror()
{
    stopAndWaitAiThreads();

    position.mirror(moveHistory);

    // Update move history
    int row = 0;

    for (const auto &str : *move_history()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }

    debugPrintf("list: %d\n", row);

    // Update display
    if (currentRow == row - 1)
        updateScene();
    else
        phaseChange(currentRow, true);

    threadsSetAi(&position);
    startAiThreads();
}

void Game::turnRight()
{
    stopAndWaitAiThreads();

    position.rotate(moveHistory, -90);

    // Update move history
    int row = 0;

    for (const auto &str : *move_history()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }

    // Update display
    if (currentRow == row - 1)
        updateScene();
    else
        phaseChange(currentRow, true);

    threadsSetAi(&position);
    startAiThreads();
}

void Game::turnLeft()
{
    stopAndWaitAiThreads();

    position.rotate(moveHistory, 90);

    // Update move history
    int row = 0;
    for (const auto &str : *move_history()) {
        moveListModel.setData(moveListModel.index(row++), str.c_str());
    }

    // Update display
    updateScene();

    threadsSetAi(&position);
    startAiThreads();
}

void Game::updateTime()
{
    constexpr int timePoint = -1;
    time_t *ourSeconds = &elapsedSeconds[sideToMove];
    const time_t theirSeconds = elapsedSeconds[~sideToMove];

    currentTime = time(nullptr);

    if (timePoint >= *ourSeconds) {
        *ourSeconds = timePoint;
        startTime = currentTime -
                    (elapsedSeconds[WHITE] + elapsedSeconds[BLACK]);
    } else {
        *ourSeconds = currentTime - startTime - theirSeconds;
    }
}

void Game::timerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    static QTime qt1, qt2;

    // Player's time spent
    updateTime();
    remainingTime[WHITE] = get_elapsed_time(WHITE);
    remainingTime[BLACK] = get_elapsed_time(BLACK);

    // If the rule requires a timer, time1 and time2 indicate a countdown
    if (timeLimit > 0) {
        // Player's remaining time
        remainingTime[WHITE] = timeLimit - remainingTime[WHITE];
        remainingTime[BLACK] = timeLimit - remainingTime[BLACK];
    }

    qt1 = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[WHITE]));
    qt2 = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[BLACK]));

    emit time1Changed(qt1.toString("hh:mm:ss"));
    emit time2Changed(qt2.toString("hh:mm:ss"));

    // If it's divided
    const Color winner = position.get_winner();
    if (winner != NOBODY) {
        // Stop the clock
        killTimer(timeID);

        // Timer ID is 0
        timeID = 0;

        // Signal update status bar
        updateScene();
        message = QString::fromStdString(getTips());
        emit statusBarChanged(message);

#ifndef DO_NOT_PLAY_WIN_SOUND
        playSound(GameSound::win, winner);
#endif
    }

    // For debugging
#if 0
    int ti = time.elapsed();
    static QTime t;
    if (ti < 0) {
        // Prevent the time error caused by 24:00,
        // plus the total number of seconds in a day
        ti += 86400;
    }
    if (timeWho == 1) {
        time1 = ti - time2;
        // A temporary variable used to display the time.
        // The extra 50 ms is used to eliminate the beat caused
        // by the timer error
        t = QTime(0, 0, 0, 50).addMSecs(time1);
        emit time1Changed(t.toString("hh:mm:ss"));
    } else if (timeWho == 2) {
        time2 = ti - time1;
        // A temporary variable used to display the time.
        // The extra 50 ms is used to eliminate the beat
        // caused by the timer error
        t = QTime(0, 0, 0, 50).addMSecs(time2);
        emit time2Changed(t.toString("hh:mm:ss"));
    }
#endif
}

bool Game::isAIsTurn() const
{
    return isAiPlayer[sideToMove];
}

// Key slot function, according to the signal and state of qgraphics scene to
// select, drop or remove sub
bool Game::actionPiece(QPointF p)
{
    // Click non drop point, do not execute
    File f;
    Rank r;

    if (!scene.pos2polar(p, f, r)) {
        return false;
    }

    // When the computer is playing or searching, the click is invalid
    if (isAIsTurn() || aiThread[WHITE]->searching ||
        aiThread[BLACK]->searching) {
        return false;
    }

    // When you click the board while browsing the history, it is considered
    // repentance
    if (currentRow != moveListModel.rowCount() - 1) {
#ifndef QT_MOBILE_APP_UI
        // Define new dialog box
        QMessageBox msgBox;
        msgBox.setIcon(QMessageBox::Question);
        msgBox.setMinimumSize(600, 400);
        msgBox.setText(tr("You are looking back at an old position."));
        msgBox.setInformativeText(tr("Do you want to retract your moves?"));
        msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
        msgBox.setDefaultButton(QMessageBox::Cancel);
        (msgBox.button(QMessageBox::Ok))->setText(tr("Yes"));
        (msgBox.button(QMessageBox::Cancel))->setText(tr("No"));

        if (QMessageBox::Ok == msgBox.exec()) {
#endif /* !QT_MOBILE_APP_UI */
            const int rowCount = moveListModel.rowCount();
            const int removeCount = rowCount - currentRow - 1;
            moveListModel.removeRows(currentRow + 1, rowCount - currentRow - 1);

            for (int i = 0; i < removeCount; i++) {
                moveHistory.pop_back();
            }

            // If you regret the game, restart the timing
            if (position.get_winner() == NOBODY) {
                // Restart timing
                timeID = startTimer(100);

                // Signal update status bar
                updateScene();
                message = QString::fromStdString(getTips());
                emit statusBarChanged(message);
#ifndef QT_MOBILE_APP_UI
            }
        } else {
            return false;
#endif /* !QT_MOBILE_APP_UI */
        }
    }

    // If not, start
    if (position.get_phase() == Phase::ready)
        gameStart();

    // Judge whether to select, drop or remove the seed
    bool result = false;
    PieceItem *piece;
    QGraphicsItem *item = scene.itemAt(p, QTransform());

    switch (position.get_action()) {
    case Action::place:
        if (position.put_piece(f, r)) {
            if (position.get_action() == Action::remove) {
                // Play form mill sound effects
                playSound(GameSound::mill, position.side_to_move());
            } else {
                // Playing the sound effect of moving pieces
                playSound(GameSound::drag, position.side_to_move());
            }
            result = true;
            break;
        }

        // If the moving is not successful, try to reselect. There is no break
        // here
        [[fallthrough]];

    case Action::select:
        piece = qgraphicsitem_cast<PieceItem *>(item);
        if (!piece)
            break;
        if (position.select_piece(f, r)) {
            playSound(GameSound::select, position.side_to_move());
            result = true;
        } else {
            playSound(GameSound::banned, position.side_to_move());
        }
        break;

    case Action::remove:
        if (position.remove_piece(f, r)) {
            playSound(GameSound::remove, position.side_to_move());
            result = true;
        } else {
            playSound(GameSound::banned, position.side_to_move());
        }
        break;

    case Action::none:
        // If it is game over state, no response will be made
        break;
    }

    if (result) {
#ifdef MADWEASEL_MUEHLE_PERFECT_AI
        if (gameOptions.getPerfectAiEnabled()) {
            perfect_command(position.record);
        }
#endif

        moveHistory.emplace_back(position.record);

        if (strlen(position.record) > strlen("-(1,2)")) {
            posKeyHistory.push_back(position.key());
        } else {
            posKeyHistory.clear();
        }

        // Signal update status bar
        updateScene();
        message = QString::fromStdString(getTips());
        emit statusBarChanged(message);

        // Insert the new score line into list model
        currentRow = moveListModel.rowCount() - 1;
        int k = 0;

        // Output command line
        for (const auto &i : *move_history()) {
            // Skip added because the standard list container has no subscripts
            if (k++ <= currentRow)
                continue;
            moveListModel.insertRow(++currentRow);
            moveListModel.setData(moveListModel.index(currentRow), i.c_str());
        }

        // Play win or lose sound
#ifndef DO_NOT_PLAY_WIN_SOUND
        const Color winner = position.get_winner();
        if (winner != NOBODY &&
            moveListModel.data(moveListModel.index(currentRow - 1))
                .toString()
                .contains("Time over."))
            playSound(GameSound::win, winner);
#endif

        // AI settings
        // If it's not decided yet
        if (position.get_winner() == NOBODY) {
            resumeAiThreads(position.sideToMove);
        } else {
            // If it's decided
            if (gameOptions.getAutoRestart()) {
#ifdef NNUE_GENERATE_TRAINING_DATA
                position.nnueWriteTrainingData();
#endif /* NNUE_GENERATE_TRAINING_DATA */

                saveScore();

                gameReset();
                gameStart();

                if (isAiPlayer[WHITE]) {
                    setEngine(WHITE, true);
                }
                if (isAiPlayer[BLACK]) {
                    setEngine(BLACK, true);
                }
            } else {
                pauseThreads();
            }
        }
    }

    sideToMove = position.side_to_move();
    updateScene();
    return result;
}

bool Game::resign()
{
    const bool result = position.resign(position.sideToMove);

    if (!result) {
        return false;
    }

    // Insert the new record line into list model
    currentRow = moveListModel.rowCount() - 1;
    int k = 0;

    // Output command line
    for (const auto &i : *move_history()) {
        // Skip added because the standard list container has no index
        if (k++ <= currentRow)
            continue;
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow), i.c_str());
    }

    if (position.get_winner() != NOBODY) {
        playSound(GameSound::resign, position.side_to_move());
    }

    return result;
}

#ifdef NNUE_GENERATE_TRAINING_DATA
extern string nnueTrainingDataBestMove;
#endif /* NNUE_GENERATE_TRAINING_DATA */

// Key slot function, command line execution of score, independent of
// actionPiece
bool Game::command(const string &cmd, bool update /* = true */)
{
    int total;
    float blackWinRate, whiteWinRate, drawRate;

    Q_UNUSED(hasSound)

#ifdef QT_GUI_LIB
    // Prevents receiving instructions sent by threads that end late
    if (sender() == aiThread[WHITE] && !isAiPlayer[WHITE])
        return false;

    if (sender() == aiThread[BLACK] && !isAiPlayer[BLACK])
        return false;
#endif // QT_GUI_LIB

    auto soundType = GameSound::none;

    switch (position.get_action()) {
    case Action::select:
    case Action::place:
        soundType = GameSound::drag;
        break;
    case Action::remove:
        soundType = GameSound::remove;
        break;
    case Action::none:
        break;
    }

    if (position.get_phase() == Phase::ready) {
        gameStart();
    }

#ifdef MADWEASEL_MUEHLE_RULE
    if (position.get_phase() != Phase::gameOver) {
#endif // MADWEASEL_MUEHLE_RULE

        debugPrintf("Computer: %s\n\n", cmd.c_str());

        moveHistory.emplace_back(cmd);

#ifdef NNUE_GENERATE_TRAINING_DATA
        nnueTrainingDataBestMove = cmd;
#endif /* NNUE_GENERATE_TRAINING_DATA */

        if (cmd.size() > strlen("-(1,2)")) {
            posKeyHistory.push_back(position.key());
        } else {
            posKeyHistory.clear();
        }

        if (!position.command(cmd.c_str()))
            return false;
#ifdef MADWEASEL_MUEHLE_RULE
    }
#endif // MADWEASEL_MUEHLE_RULE

    sideToMove = position.side_to_move();

    if (soundType == GameSound::drag &&
        position.get_action() == Action::remove) {
        soundType = GameSound::mill;
    }

    if (update) {
        playSound(soundType, position.side_to_move());
        updateScene(position);
    }

    // Signal update status bar
    updateScene();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // For opening
    if (move_history()->size() <= 1) {
        moveListModel.removeRows(0, moveListModel.rowCount());
        moveListModel.insertRow(0);
        moveListModel.setData(moveListModel.index(0), position.get_record());
        currentRow = 0;
    } else {
        // For the current position
        currentRow = moveListModel.rowCount() - 1;
        // Skip the added rows. The iterator does not support the + operator and
        // can only skip one by one++
        auto i = move_history()->begin();
        for (int r = 0; i != move_history()->end(); ++i) {
            if (r++ > currentRow)
                break;
        }
        // Insert the new score line into list model
        while (i != move_history()->end()) {
            moveListModel.insertRow(++currentRow);
            moveListModel.setData(moveListModel.index(currentRow),
                                  (*i++).c_str());
        }
    }

    // Play win or lose sound
#ifndef DO_NOT_PLAY_WIN_SOUND
    const Color winner = position.get_winner();
    if (winner != NOBODY &&
        moveListModel.data(moveListModel.index(currentRow - 1))
            .toString()
            .contains("Time over.")) {
        playSound(GameSound::win, winner);
    }
#endif

    // AI Settings
    // If it's not decided yet
    if (position.get_winner() == NOBODY) {
        resumeAiThreads(position.sideToMove);
    } else {
        // If it's decided
        pauseThreads();

        gameEndTime = now();
        gameDurationTime = gameEndTime - gameStartTime;

        gameEndCycle = stopwatch::rdtscp_clock::now();

        debugPrintf("Game Duration Time: %lldms\n", gameDurationTime);

#ifdef TIME_STAT
        debugPrintf("Sort Time: %I64d + %I64d = %I64dms\n",
                    aiThread[WHITE]->sortTime, aiThread[BLACK]->sortTime,
                    (aiThread[WHITE]->sortTime + aiThread[BLACK]->sortTime));
        aiThread[WHITE]->sortTime = aiThread[BLACK]->sortTime = 0;
#endif // TIME_STAT

#ifdef CYCLE_STAT
        debugPrintf("Sort Cycle: %ld + %ld = %ld\n", aiThread[WHITE]->sortCycle,
                    aiThread[BLACK]->sortCycle,
                    (aiThread[WHITE]->sortCycle + aiThread[BLACK]->sortCycle));
        aiThread[WHITE]->sortCycle = aiThread[BLACK]->sortCycle = 0;
#endif // CYCLE_STAT

#if 0
            gameDurationCycle = gameEndCycle - gameStartCycle;
            debugPrintf("Game Start Cycle: %u\n", gameStartCycle);
            debugPrintf("Game End Cycle: %u\n", gameEndCycle);
            debugPrintf("Game Duration Cycle: %u\n", gameDurationCycle);
#endif

#ifdef TRANSPOSITION_TABLE_DEBUG
        size_t hashProbeCount_1 = aiThread[WHITE]->ttHitCount +
                                  aiThread[WHITE]->ttMissCount;
        size_t hashProbeCount_2 = aiThread[BLACK]->ttHitCount +
                                  aiThread[BLACK]->ttMissCount;

        debugPrintf("[key 1] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                    "%llu%%\n",
                    hashProbeCount_1, aiThread[WHITE]->ttHitCount,
                    aiThread[WHITE]->ttMissCount,
                    aiThread[WHITE]->ttHitCount * 100 / hashProbeCount_1);

        debugPrintf("[key 2] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                    "%llu%%\n",
                    hashProbeCount_2, aiThread[BLACK]->ttHitCount,
                    aiThread[BLACK]->ttMissCount,
                    aiThread[BLACK]->ttHitCount * 100 / hashProbeCount_2);

        debugPrintf(
            "[key +] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
            hashProbeCount_1 + hashProbeCount_2,
            aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount,
            aiThread[WHITE]->ttMissCount + aiThread[BLACK]->ttMissCount,
            (aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount) * 100 /
                (hashProbeCount_1 + hashProbeCount_2));
#endif // TRANSPOSITION_TABLE_DEBUG

        if (gameOptions.getAutoRestart()) {
#ifdef NNUE_GENERATE_TRAINING_DATA
            position.nnueWriteTrainingData();
#endif /* NNUE_GENERATE_TRAINING_DATA */

            saveScore();

            gameReset();
            gameStart();

            if (isAiPlayer[WHITE]) {
                setEngine(WHITE, true);
            }
            if (isAiPlayer[BLACK]) {
                setEngine(BLACK, true);
            }
        }

#ifdef MESSAGE_BOX_ENABLE
        message = QString::fromStdString(position.get_tips());
        QMessageBox::about(NULL, "Game Result", message);
#endif
    }

    gameTest->writeToMemory(QString::fromStdString(cmd));

#ifdef NET_FIGHT_SUPPORT
    // Network: put the method in the server's send list
    getServer()->setAction(QString::fromStdString(cmd));
#endif

#ifdef ANALYZE_POSITION
    if (!gameOptions.getPerfectAiEnabled()) {
        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->analyze(WHITE);
        } else if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->analyze(BLACK);
        }
    }
#endif // ANALYZE_POSITION

    total = position.score[WHITE] + position.score[BLACK] + position.score_draw;

    if (total == 0) {
        blackWinRate = 0;
        whiteWinRate = 0;
        drawRate = 0;
    } else {
        blackWinRate = static_cast<float>(position.score[WHITE]) * 100 / total;
        whiteWinRate = static_cast<float>(position.score[BLACK]) * 100 / total;
        drawRate = static_cast<float>(position.score_draw) * 100 / total;
    }

    const auto flags = cout.flags();
    cout << "Score: " << position.score[WHITE] << " : " << position.score[BLACK]
         << " : " << position.score_draw << "\ttotal: " << total << std::endl;
    cout << std::fixed << std::setprecision(2) << blackWinRate
         << "% : " << whiteWinRate << "% : " << drawRate << "%" << std::endl;
    cout.flags(flags);

#ifdef NNUE_GENERATE_TRAINING_DATA
    position.nnueGenerateTrainingFen();
#endif /* NNUE_GENERATE_TRAINING_DATA */

    return true;
}

// Browse the historical situation and refresh the situation display through the
// command function
bool Game::phaseChange(int row, bool forceUpdate)
{
    // If row is the currently viewed score line, there is no need to refresh it
    if (currentRow == row && !forceUpdate)
        return false;

    // Need to refresh
    currentRow = row;
    const int rows = moveListModel.rowCount();
    const QStringList mlist = moveListModel.stringList();

    debugPrintf("rows: %d current: %d\n", rows, row);

    for (int i = 0; i <= row; i++) {
        debugPrintf("%s\n", mlist.at(i).toStdString().c_str());
        position.command(mlist.at(i).toStdString().c_str());
    }

    // The key step is to let the penitent bear the loss of time
    set_start_time(static_cast<int>(start_timeb()));

    // Refresh the scene
    updateScene(position);

    return true;
}

bool Game::updateScene()
{
    return updateScene(position);
}

bool Game::updateScene(Position &p)
{
    const Piece *board = p.get_board();
    QPointF pos;

    // Chess code in game class
    int key;

    // Total number of pieces
    int nTotalPieces = rule.pieceCount * 2;

    // Animation group
    auto *animationGroup = new QParallelAnimationGroup;

    // The deleted pieces are in place
    PieceItem *deletedPiece = nullptr;

    for (int i = 0; i < nTotalPieces; i++) {
        const auto piece = pieceList.at(static_cast<size_t>(i));

        piece->setSelected(false);

        // Convert the subscript of pieceList to the code of game
        key = (i % 2) ? (i / 2 + B_PIECE_1) : (i / 2 + W_PIECE_1);

        int j;

        // Traverse the board, find and place the pieces on the board
        for (j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == key) {
                pos = scene.polar2pos(static_cast<File>(j / RANK_NB),
                                      static_cast<Rank>(j % RANK_NB + 1));
                if (piece->pos() != pos) {
                    // Let the moving pieces be at the top level
                    piece->setZValue(1);

                    // Pieces movement animation
                    auto *animation = new QPropertyAnimation(piece, "pos");
                    animation->setDuration(durationTime);
                    animation->setStartValue(piece->pos());
                    animation->setEndValue(pos);
                    animation->setEasingCurve(QEasingCurve::InOutQuad);
                    animationGroup->addAnimation(animation);
                } else {
                    // Let the still pieces be at the bottom
                    piece->setZValue(0);
                }
                break;
            }
        }

        // If not, place the pieces outside the board
        if (j == RANK_NB * (FILE_NB + 1)) {
            // Judge whether it is a removing seed or an unplaced one
            if (key & W_PIECE) {
                pos = (key - 0x11 <
                       nTotalPieces / 2 - p.count<IN_HAND>(WHITE)) ?
                          scene.pos_p2_g :
                          scene.pos_p1;
            } else {
                pos = (key - 0x21 <
                       nTotalPieces / 2 - p.count<IN_HAND>(BLACK)) ?
                          scene.pos_p1_g :
                          scene.pos_p2;
            }

            if (piece->pos() != pos) {
                // In order to prepare for the selection of the recently removed
                // pieces
                deletedPiece = piece;

#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
                if (position.get_phase() == Phase::moving) {
#endif
                    auto *animation = new QPropertyAnimation(piece, "pos");
                    animation->setDuration(durationTime);
                    animation->setStartValue(piece->pos());
                    animation->setEndValue(pos);
                    animation->setEasingCurve(QEasingCurve::InOutQuad);
                    animationGroup->addAnimation(animation);
#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
                }
#endif
            }
        }

        piece->setSelected(false);
    }

    // Add banned points in placing phase
    if (rule.hasBannedLocations && p.get_phase() == Phase::placing) {
        for (int sq = SQ_BEGIN; sq < SQ_END; sq++) {
            if (board[sq] == BAN_PIECE) {
                pos = scene.polar2pos(static_cast<File>(sq / RANK_NB),
                                      static_cast<Rank>(sq % RANK_NB + 1));
                if (nTotalPieces < static_cast<int>(pieceList.size())) {
                    pieceList.at(static_cast<size_t>(nTotalPieces++))
                        ->setPos(pos);
                } else {
                    auto *newP = new PieceItem;
                    newP->setDeleted();
                    newP->setPos(pos);
                    pieceList.push_back(newP);
                    nTotalPieces++;
                    scene.addItem(newP);
                }
            }
        }
    }

    // Clear banned points in moving phase
    if (rule.hasBannedLocations && p.get_phase() != Phase::placing) {
        while (nTotalPieces < static_cast<int>(pieceList.size())) {
            delete pieceList.at(pieceList.size() - 1);
            pieceList.pop_back();
        }
    }

    // Select the current piece
    int ipos = p.current_square();
    if (ipos) {
        key = board[p.current_square()];
        ipos = key & W_PIECE ? (key - W_PIECE_1) * 2 :
                               (key - B_PIECE_1) * 2 + 1;
        if (ipos >= 0 && ipos < nTotalPieces) {
            currentPiece = pieceList.at(static_cast<size_t>(ipos));
            currentPiece->setSelected(true);
        }
    }

    // Set the most recently removed pieces to select action
    if (deletedPiece) {
        deletedPiece->setSelected(true);
    }

    animationGroup->start(QAbstractAnimation::DeleteWhenStopped);

    // Update LCD display
    emit score1Changed(QString::number(p.score[WHITE], 10));
    emit score2Changed(QString::number(p.score[BLACK], 10));
    emit scoreDrawChanged(QString::number(p.score_draw, 10));

    // Update winning rate LCD display
    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] +
                                position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;
    if (position.gamesPlayedCount != 0) {
        winningRate_1 = position.score[WHITE] * 10000 /
                        position.gamesPlayedCount;
        winningRate_2 = position.score[BLACK] * 10000 /
                        position.gamesPlayedCount;
        winningRate_draw = position.score_draw * 10000 /
                           position.gamesPlayedCount;
    }

    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));

    setTips();

    return true;
}

#ifdef NET_FIGHT_SUPPORT
void Game::showNetworkWindow()
{
    getServer()->show();
    getClient()->show();
}
#endif

void Game::showTestWindow() const
{
    gameTest->show();
}

void Game::humanResign()
{
    if (position.get_winner() == NOBODY) {
        resign();
    }
}

void Game::saveScore()
{
    const QString strDate = QDateTime::currentDateTime().toString("yyyy-MM-dd");
    const qint64 pid = QCoreApplication::applicationPid();

    const QString path = QDir::currentPath() + "/" + tr("Score-MillPro_") +
                         strDate + "_" + QString::number(pid) + ".txt";

    QFile file;

    file.setFileName(path);

    if (file.isOpen()) {
        file.close();
    }

    if (!file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
        return;
    }

    QTextStream textStream(&file);

    textStream << QCoreApplication::applicationFilePath() << "\n"
               << "\n";

    textStream << gameTest->getKey() << "\n"
               << "\n";

    if (isAiPlayer[WHITE]) {
        textStream << "White:\tAI Player"
                   << "\n";
    } else {
        textStream << "White:\tHuman Player"
                   << "\n";
    }

    if (isAiPlayer[BLACK]) {
        textStream << "Black:\tAI Player"
                   << "\n";
    } else {
        textStream << "Black:\tHuman Player"
                   << "\n";
    }

    textStream << ""
               << "\n";

    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] +
                                position.score_draw;

    if (position.gamesPlayedCount == 0) {
        goto out;
    }

    textStream << "Sum\t" + QString::number(position.gamesPlayedCount) << "\n";
    textStream << "White\t" + QString::number(position.score[WHITE]) + "\t" +
                      QString::number(position.score[WHITE] * 10000 /
                                      position.gamesPlayedCount)
               << "\n";
    textStream << "Black\t" + QString::number(position.score[BLACK]) + "\t" +
                      QString::number(position.score[BLACK] * 10000 /
                                      position.gamesPlayedCount)
               << "\n";
    textStream << "Draw\t" + QString::number(position.score_draw) + "\t" +
                      QString::number(position.score_draw * 10000 /
                                      position.gamesPlayedCount)
               << "\n";

out:
    file.flush();
    file.close();
}

inline char Game::color_to_char(Color color)
{
    return static_cast<char>('0' + color);
}

inline std::string Game::char_to_string(char ch)
{
    if (ch == '1') {
        return "White";
    }

    return "Black";
}

void Game::appendGameOverReasonToMoveHistory()
{
    if (position.phase != Phase::gameOver) {
        return;
    }

    char record[64] = {0};
    switch (position.gameOverReason) {
    case GameOverReason::loseNoWay:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonNoWayStr,
                 position.sideToMove, position.winner);
        break;
    case GameOverReason::loseTimeOver:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonTimeOverStr,
                 position.winner);
        break;
    case GameOverReason::drawThreefoldRepetition:
        snprintf(record, Position::RECORD_LEN_MAX,
                 drawReasonThreefoldRepetitionStr);
        break;
    case GameOverReason::drawRule50:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonRule50Str);
        break;
    case GameOverReason::drawEndgameRule50:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonEndgameRule50Str);
        break;
    case GameOverReason::loseBoardIsFull:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonBoardIsFullStr);
        break;
    case GameOverReason::drawBoardIsFull:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonBoardIsFullStr);
        break;
    case GameOverReason::drawNoWay:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonNoWayStr);
        break;
    case GameOverReason::loseLessThanThree:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonlessThanThreeStr,
                 position.winner);
        break;
    case GameOverReason::loseResign:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonResignStr,
                 ~position.winner);
        break;
    case GameOverReason::none:
        debugPrintf("No Game Over Reason");
        break;
    }

    debugPrintf("%s\n", record);
    moveHistory.emplace_back(record);
}

#ifdef NNUE_GENERATE_TRAINING_DATA
extern string nnueTrainingDataGameResult;
#endif /* NNUE_GENERATE_TRAINING_DATA */

void Game::setTips()
{
    Position &p = position;

    string winnerStr, reasonStr, resultStr, scoreStr;
    string turnStr;

    if (isInverted) {
        turnStr = char_to_string(color_to_char(~p.sideToMove));
    } else {
        turnStr = char_to_string(color_to_char(p.sideToMove));
    }

#ifdef NNUE_GENERATE_TRAINING_DATA
    if (p.winner == WHITE) {
        nnueTrainingDataGameResult = "1-0";
    } else if (p.winner == BLACK) {
        nnueTrainingDataGameResult = "0-1";
    } else if (p.winner == DRAW) {
        nnueTrainingDataGameResult = "1/2-1/2";
    } else {
    }
#endif /* NNUE_GENERATE_TRAINING_DATA */

    switch (p.phase) {
    case Phase::ready:
        // TODO: Uncaught fun_call_w_exception:
        // Called function throws an exception of type std::bad_array_new_length.
        tips = turnStr + " to place, " +
               std::to_string(p.pieceInHandCount[WHITE]) +
               " pieces are unplaced." + "  Score " +
               to_string(p.score[WHITE]) + ":" + to_string(p.score[BLACK]) +
               ", Draw " + to_string(p.score_draw);
        break;

    case Phase::placing:
        if (p.action == Action::place) {
            tips = turnStr + " to place, " +
                   std::to_string(p.pieceInHandCount[p.sideToMove]) +
                   " pieces are unplaced.";
        } else if (p.action == Action::remove) {
            tips = turnStr + " to remove, " +
                   std::to_string(p.pieceToRemoveCount[p.sideToMove]) +
                   " pieces to remove.";
        }
        break;

    case Phase::moving:
        if (p.action == Action::place || p.action == Action::select) {
            tips = turnStr + " to move.";
        } else if (p.action == Action::remove) {
            tips = turnStr + " to remove, " +
                   std::to_string(p.pieceToRemoveCount[p.sideToMove]) +
                   " pieces to remove.";
        }
        break;

    case Phase::gameOver:
        appendGameOverReasonToMoveHistory();

        scoreStr = "Score " + to_string(p.score[WHITE]) + " : " +
                   to_string(p.score[BLACK]) + ", Draw " +
                   to_string(p.score_draw);

        switch (p.winner) {
        case WHITE:
        case BLACK:
            winnerStr = char_to_string(color_to_char(p.winner));
            resultStr = winnerStr + " won! ";
            break;
        case DRAW:
            resultStr = "Draw! ";
            break;
        case NOCOLOR:
        case COLOR_NB:
        case NOBODY:
            break;
        }

        switch (p.gameOverReason) {
        case GameOverReason::loseLessThanThree:
            break;
        case GameOverReason::loseNoWay:
#ifdef MADWEASEL_MUEHLE_RULE
            if (!isInverted) {
                turnStr = char_to_string(color_to_char(~p.sideToMove));
            } else {
                turnStr = char_to_string(color_to_char(p.sideToMove));
            }
#endif
            reasonStr = turnStr + " is blocked.";
            break;
        case GameOverReason::loseBoardIsFull:
            reasonStr = turnStr + " lose because board is full.";
            break;
        case GameOverReason::loseResign:
            reasonStr = turnStr + " resigned.";
            break;
        case GameOverReason::loseTimeOver:
            reasonStr = "Time over." + turnStr + " lost.";
            break;
        case GameOverReason::drawThreefoldRepetition:
            reasonStr = "Draw because of threefold repetition.";
            break;
        case GameOverReason::drawRule50:
            reasonStr = "Draw because of rule 50.";
            break;
        case GameOverReason::drawEndgameRule50:
            reasonStr = "Draw because of endgame rule 50.";
            break;
        case GameOverReason::drawBoardIsFull:
            reasonStr = "Draw because of board is full.";
            break;
        case GameOverReason::drawNoWay:
            reasonStr = "Draw because of stalemate.";
            break;
        case GameOverReason::none:
            break;
        }

        tips = reasonStr + resultStr + scoreStr;
        break;

    case Phase::none:
        break;
    }

    tips = to_string(position.bestvalue) + " | " + tips;
}

time_t Game::get_elapsed_time(int us) const
{
    return elapsedSeconds[us];
}
