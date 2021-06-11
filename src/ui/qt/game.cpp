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

#include <map>

#include <QGraphicsView>
#include <QGraphicsSceneMouseEvent>
#include <QKeyEvent>
#include <QApplication>
#include <QTimer>
#include <QSound>
#include <QMessageBox>
#include <QAbstractButton>
#include <QPropertyAnimation>
#include <QParallelAnimationGroup>
#include <QDir>
#include <QFileInfo>
#include <QThread>
#include <iomanip>

#include "game.h"
#include "graphicsconst.h"
#include "boarditem.h"
#include "server.h"
#include "client.h"
#include "option.h"

#ifdef PERFECT_AI_SUPPORT
#include "perfect/perfect.h"
#endif

using namespace std;

Game::Game(
    GameScene & scene,
    QObject * parent
) :
    QObject(parent),
    scene(scene),
    currentPiece(nullptr),
    currentRow(-1),
    isEditing(false),
    isInverted(false),
    hasAnimation(true),
    durationTime(500),
    gameStartTime(0),
    gameEndTime(0),
    gameDurationTime(0),
    gameDurationCycle(0),
    timeID(0),
    ruleIndex(-1),
    timeLimit(gameOptions.getMoveTime()),
    stepsLimit(50)
{
    // The background has been added to the style sheet of view, but not to scene
    // The difference is that the background in view does not change with the view transformation, 
    // and the background in scene changes with the view transformation
    //scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));
#ifdef MOBILE_APP_UI
    scene.setBackgroundBrush(QColor(239, 239, 239));
#endif /* MOBILE_APP_UI */

    //resetAiPlayers();
    createAiThreads();

    loadSettings();

    gameReset();

    gameTest = new Test();

    qRegisterMetaType<std::string>("string");

#ifdef QT_GUI_LIB
    // The command line of AI and controller
    connect(aiThread[WHITE], SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));
    connect(aiThread[BLACK], SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));

    connect(this->gameTest, SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));
#endif // QT_GUI_LIB

#ifdef NET_FIGHT_SUPPORT
    server = new Server(nullptr, 30001);    // TODO: WARNING: ThreadSanitizer: data race
    uint16_t clientPort = server->getPort() == 30001 ? 30002 : 30001;
    client = new Client(nullptr, clientPort);

    // The command line of AI andnetwork
    connect(getClient(), SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));
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

    QFileInfo file(SETTINGS_FILE);
    if (!file.exists()) {
        cout << SETTINGS_FILE.toStdString() << " is not exists, create it." << endl;
        empty = true;
    }

    settings = new QSettings(SETTINGS_FILE, QSettings::IniFormat);

    setEngineWhite(empty? false : settings->value("Options/WhiteIsAiPlayer").toBool());
    setEngineBlack(empty ? true : settings->value("Options/BlackIsAiPlayer").toBool());
    setFixWindowSize(empty ? false : settings->value("Options/FixWindowSize").toBool());
    setSound(empty ? true : settings->value("Options/Sound").toBool());
    setAnimation(empty ? true : settings->value("Options/Animation").toBool());
    setSkillLevel(empty ? 1 : settings->value("Options/SkillLevel").toInt());
    setMoveTime(empty ? 1 : settings->value("Options/MoveTime").toInt());
    setDrawOnHumanExperience(empty ? true : settings->value("Options/DrawOnHumanExperience").toBool());
    setAiIsLazy(empty ? false : settings->value("Options/AiIsLazy").toBool());
    setShuffling(empty ? true : settings->value("Options/Shuffling").toBool());
    setResignIfMostLose(empty ? false : settings->value("Options/ResignIfMostLose").toBool());
    setOpeningBook(empty ? false : settings->value("Options/OpeningBook").toBool());
    setLearnEndgame(empty ? false : settings->value("Options/LearnEndgameEnabled").toBool());
    setPerfectAi(empty ? false : settings->value("Options/PerfectAI").toBool());
    setIDS(empty ? false : settings->value("Options/IDS").toBool());
    setDepthExtension(empty ? true : settings->value("Options/DepthExtension").toBool());
    setAutoRestart(empty ? false : settings->value("Options/AutoRestart").toBool());
    setAutoChangeFirstMove(empty ? false : settings->value("Options/AutoChangeFirstMove").toBool());
    setDeveloperMode(empty ? false : settings->value("Options/DeveloperMode").toBool());

    setRule(empty ? DEFAULT_RULE_NUMBER : settings->value("Options/RuleNo").toInt());
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

const map<int, QStringList> Game::getActions()
{
    // Main window update menu bar
    // The reason why we don't use the mode of signal and slot is that
    // it's too late for the slot to be associated when the signal is sent
    map<int, QStringList> actions;

    for (int i = 0; i < N_RULES; i++) {
        //The key of map stores int index value, and value stores rule name and rule prompt
        QStringList strlist;
        strlist.append(tr(RULES[i].name));
        strlist.append(tr(RULES[i].description));
        actions.insert(map<int, QStringList>::value_type(i, strlist));
    }

    return actions;
}

#ifdef OPENING_BOOK
extern deque<int> openingBookDeque;
extern deque<int> openingBookDequeBak;
#endif

void Game::gameStart()
{
    //moveHistory.clear();
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
        loggerDebug(".");
        QThread::msleep(100);
    }

    loggerDebug("\n");

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

#ifdef PERFECT_AI_SUPPORT
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
        //resetAiPlayers();
    }

    // Clear pieces
    qDeleteAll(pieceList);
    pieceList.clear();
    currentPiece = nullptr;

    // Redraw pieces
    scene.setDiagonal(rule.hasDiagonalLines);

    // Draw all the pieces and put them in the starting position
    // 0: the first piece in the first hand; 1: the first piece in the second hand
    // 2: the first second piece; 3: the second piece
    // ......
    PieceItem::Models md;

    for (int i = 0; i < rule.piecesCount; i++) {
        // The first piece
        md = isInverted ? PieceItem::Models::blackPiece : PieceItem::Models::whitePiece;
        PieceItem *newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p1);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);

        // Backhand piece
        md = isInverted ? PieceItem::Models::whitePiece : PieceItem::Models::blackPiece;
        newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p2);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);
    }

    timeLimit = gameOptions.getMoveTime();

    // If the rule does not require timing, time1 and time2 represent the time used
    if (timeLimit <= 0) {
        // Clear the player's used time
        remainingTime[WHITE] = remainingTime[BLACK] = 0;
    } else {
        // Set the player's remaining time to a limited time
        remainingTime[WHITE] = remainingTime[BLACK] = timeLimit;
    }

    // Update move history
    manualListModel.removeRows(0, manualListModel.rowCount());
    manualListModel.insertRow(0);
    manualListModel.setData(manualListModel.index(0), position.get_record());
    currentRow = 0;

    // Signal the main window to update the LCD display
    const QTime qtime = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[WHITE]));
    emit time1Changed(qtime.toString("hh:mm:ss"));
    emit time2Changed(qtime.toString("hh:mm:ss"));

    // Signal update status bar
    updateScence();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // Update LCD display
    emit nGamesPlayedChanged(QString::number(position.gamesPlayedCount, 10));
    emit score1Changed(QString::number(position.score[WHITE], 10));
    emit score2Changed(QString::number(position.score[BLACK], 10));
    emit scoreDrawChanged(QString::number(position.score_draw, 10));

    // Update winning rate LCD display
    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] + position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;
    if (position.gamesPlayedCount != 0) {
        winningRate_1 = position.score[WHITE] * 10000 / position.gamesPlayedCount;
        winningRate_2 = position.score[BLACK] * 10000 / position.gamesPlayedCount;
        winningRate_draw = position.score_draw * 10000 / position.gamesPlayedCount;
    }
    
    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));

    // Sound effects play
    //playSound(":/sound/resources/sound/newgame.wav");
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

void Game::setRule(int ruleNo, int stepLimited /*= -1*/, int timeLimited /*= 0*/)
{
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

    char record[64] = { 0 };
    if (snprintf(record, Position::RECORD_LEN_MAX, "r%1d s%03zu t%02d", r + 1, rule.maxStepsLedToDraw, 0) <= 0) {
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

    aiThread[WHITE]->setAi(&position,  time1);
    aiThread[BLACK]->setAi(&position, time2);

    startAiThreads();
}

void Game::getAiDepthTime(int &time1, int &time2)
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

void Game::setSound(bool arg) noexcept
{
    hasSound = arg;
    settings->setValue("Options/Sound", arg);
}

void Game::playSound(GameSound soundType, Color c)
{
    string soundDir = ":/sound/resources/sound/";
    string sideStr = c == WHITE ? "W" : "B";
    string oppenentStr = c == BLACK? "W" : "B";
    string filename;

    switch (soundType) {
    case GameSound::blockMill:
        filename = "BlockMill_" + sideStr + ".wav";
        break;
    case GameSound::remove:
        filename = "Remove_" + oppenentStr + ".wav";
        break;
    case GameSound::select:
        filename = "Select.wav";
        break;
    case GameSound::draw:
        filename = "Draw.wav";
        break;
    case GameSound::drog:
        filename = "drog.wav";
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
    case GameSound::millRepeatly:
        filename = "MillRepeatly_" + sideStr + ".wav";
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
    default:
        filename = "";
        break;
    };

#ifndef DONOT_PLAY_SOUND
    QString soundPath = QString::fromStdString(soundDir + filename);

    if (soundPath == "") {
        return;
    }

    if (hasSound) {
        QSound::play(soundPath);
    }
#endif /* ! DONOT_PLAY_SOUND */
}

void Game::setSkillLevel(int val)
{
    gameOptions.setSkillLevel(val);
    settings->setValue("Options/SkillLevel", val);
}

void Game::setMoveTime(int val)
{
    gameOptions.setMoveTime(val);
    settings->setValue("Options/MoveTime", val);
}

void Game::setDrawOnHumanExperience(bool enabled)
{
    gameOptions.setDrawOnHumanExperience(enabled);
    settings->setValue("Options/DrawOnHumanExperience", enabled);
}

void Game::setAiIsLazy(bool enabled)
{
    gameOptions.setAiIsLazy(enabled);
    settings->setValue("Options/AiIsLazy", enabled);
}

void Game::setResignIfMostLose(bool enabled)
{
    gameOptions.setResignIfMostLose(enabled);
    settings->setValue("Options/ResignIfMostLose", enabled);
}

void Game::setAutoRestart(bool enabled)
{
    gameOptions.setAutoRestart(enabled);
    settings->setValue("Options/AutoRestart", enabled);
}

void Game::setAutoChangeFirstMove(bool enabled)
{
    gameOptions.setAutoChangeFirstMove(enabled);
    settings->setValue("Options/AutoChangeFirstMove", enabled);
}

void Game::setShuffling(bool enabled)
{
    gameOptions.setShufflingEnabled(enabled);
    settings->setValue("Options/Shuffling", enabled);
}

void Game::setLearnEndgame(bool enabled)
{
    gameOptions.setLearnEndgameEnabled(enabled);
    settings->setValue("Options/LearnEndgameEnabled", enabled);

#ifdef ENDGAME_LEARNING
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::loadEndgameFileToHashMap();
    }
#endif
}

void Game::setPerfectAi(bool enabled)
{
    gameOptions.setPerfectAiEnabled(enabled);
    settings->setValue("Options/PerfectAI", enabled);

#ifdef PERFECT_AI_SUPPORT
    if (enabled) {
        perfect_reset();
    } else {
        perfect_exit();
    }
#endif
}

void Game::setIDS(bool enabled)
{
    gameOptions.setIDSEnabled(enabled);
    settings->setValue("Options/IDS", enabled);
}

// DepthExtension
void Game::setDepthExtension(bool enabled)
{
    gameOptions.setDepthExtension(enabled);
    settings->setValue("Options/DepthExtension", enabled);
}

// OpeningBook
void Game::setOpeningBook(bool enabled)
{
    gameOptions.setOpeningBook(enabled);
    settings->setValue("Options/OpeningBook", enabled);
}

void Game::setDeveloperMode(bool enabled)
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
    for (const auto &str : *(move_hostory())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // Refresh display
    if (currentRow == row - 1)
        updateScence();
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

    for (const auto &str : *(move_hostory())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    loggerDebug("list: %d\n", row);

    // Update display
    if (currentRow == row - 1)
        updateScence();
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

    for (const auto &str : *(move_hostory())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // Update display
    if (currentRow == row - 1)
        updateScence();
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
    for (const auto &str : *(move_hostory())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // Update display
    updateScence();

    threadsSetAi(&position);
    startAiThreads();
}

void Game::updateTime()
{
    int timePoint = -1;
    time_t *ourSeconds = &elapsedSeconds[sideToMove];
    time_t theirSeconds = elapsedSeconds[~sideToMove];

    currentTime = time(NULL);

    if (timePoint >= *ourSeconds) {
        *ourSeconds = timePoint;
        startTime = currentTime - (elapsedSeconds[WHITE] + elapsedSeconds[BLACK]);
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
        updateScence();
        message = QString::fromStdString(getTips());
        emit statusBarChanged(message);

#ifndef DONOT_PLAY_WIN_SOUND
        playSound(GameSound::win, winner);
#endif
    }

    // For debugging
#if 0
    int ti = time.elapsed();
    static QTime t;
    if (ti < 0)
        ti += 86400; // Prevent the time error caused by 24:00, plus the total number of seconds in a day
    if (timeWhos == 1)
    {
        time1 = ti - time2;
        // A temporary variable used to display the time. The extra 50 ms is used to eliminate the beat caused by the timer error
        t = QTime(0, 0, 0, 50).addMSecs(time1);
        emit time1Changed(t.toString("hh:mm:ss"));
    }
    else if (timeWhos == 2)
    {
        time2 = ti - time1;
        // A temporary variable used to display the time. The extra 50 ms is used to eliminate the beat caused by the timer error
        t = QTime(0, 0, 0, 50).addMSecs(time2);
        emit time2Changed(t.toString("hh:mm:ss"));
    }
#endif
}

bool Game::isAIsTurn()
{
    return isAiPlayer[sideToMove];
}

// Key slot function, according to the signal and state of qgraphics scene to select, drop or remove sub
bool Game::actionPiece(QPointF p)
{
    // Click non drop point, do not execute
    File f;
    Rank r;

    if (!scene.pos2polar(p, f, r)) {
        return false;
    }

    // When the computer is playing chess or searching, the click is invalid
    if (isAIsTurn() ||
        aiThread[WHITE]->searching ||
        aiThread[BLACK]->searching) {
        return false;
    }

    // When you click the chessboard while browsing the history, it is considered repentance
    if (currentRow != manualListModel.rowCount() - 1) {
#ifndef MOBILE_APP_UI
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
#endif /* !MOBILE_APP_UI */
            const int rowCount = manualListModel.rowCount();
            const int removeCount = rowCount - currentRow - 1;
            manualListModel.removeRows(currentRow + 1, rowCount - currentRow - 1);

            for (int i = 0; i < removeCount; i++) {
                moveHistory.pop_back();
            }

            // If you regret the game, restart the timing
            if (position.get_winner() == NOBODY) {

                // Restart timing
                timeID = startTimer(100);

                // Signal update status bar
                updateScence();
                message = QString::fromStdString(getTips());
                emit statusBarChanged(message);
#ifndef MOBILE_APP_UI
            }
        } else {
            return false;
#endif /* !MOBILE_APP_UI */
        }
    }

     // If not, start
    if (position.get_phase() == Phase::ready)
        gameStart();

    // Judge whether to select, drop or remove the seed
    bool result = false;
    PieceItem *piece = nullptr;
    QGraphicsItem *item = scene.itemAt(p, QTransform());

    switch (position.get_action()) {
    case Action::place:
        if (position.put_piece(f, r)) { 
            if (position.get_action() == Action::remove) {
                // Play form mill sound effects
                playSound(GameSound::mill, position.side_to_move());
            } else {
                // Playing the sound effect of moving chess pieces
                playSound(GameSound::drog, position.side_to_move());
            }
            result = true;
            break;
        }

        // If the moving is not successful, try to reselect. There is no break here
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

    default:
        // If it is game over state, no response will be made
        break;
    }

    if (result) {
#ifdef PERFECT_AI_SUPPORT
        if (gameOptions.getPerfectAiEnabled()) {
            perfect_command((char *)position.record);
        }
#endif

        moveHistory.emplace_back(position.record);

        if (strlen(position.record) > strlen("-(1,2)")) {
            posKeyHistory.push_back(position.key());
        } else {
            posKeyHistory.clear();
        }

        // Signal update status bar
        updateScence();
        message = QString::fromStdString(getTips());
        emit statusBarChanged(message);

        // Insert the new chess score line into list model
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;

        // Output command line       
        for (const auto & i : *(move_hostory())) {
            // Skip added because the standard list container has no subscripts
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), i.c_str());
        }

        // Play win or lose sound
#ifndef DONOT_PLAY_WIN_SOUND
        const Color winner = position.get_winner();
        if (winner != NOBODY &&
            (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over."))
            playSound(GameSound::win, winner);
#endif

        // AI settings
        // If it's not decided yet
        if (position.get_winner() == NOBODY) {
            resumeAiThreads(position.sideToMove);
        }
        // If it's decided
        else {
            if (gameOptions.getAutoRestart()) {
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
    updateScence();
    return result;
}

bool Game::resign()
{
    const bool result = position.resign(position.sideToMove);
        
    if (!result) {
        return false;
    }

    // Insert the new record line into list model
    currentRow = manualListModel.rowCount() - 1;
    int k = 0;

    // Output command line
    for (const auto & i : *(move_hostory())) {
        // Skip added because the standard list container has no index
        if (k++ <= currentRow)
            continue;
        manualListModel.insertRow(++currentRow);
        manualListModel.setData(manualListModel.index(currentRow), i.c_str());
    }

    if (position.get_winner() != NOBODY) {
        playSound(GameSound::resign, position.side_to_move());
    }

    return result;
}

// Key slot function, command line execution of chess score, independent of actionPiece
bool Game::command(const string &cmd, bool update /* = true */)
{
    int total = 0;
    float bwinrate = 0.0f, wwinrate = 0.0f, drawrate = 0.0f;

    Q_UNUSED(hasSound)

#ifdef QT_GUI_LIB
    // Prevents receiving instructions sent by threads that end late
    if (sender() == aiThread[WHITE] && !isAiPlayer[WHITE])
        return false;

    if (sender() == aiThread[BLACK] && !isAiPlayer[BLACK])
        return false;
#endif // QT_GUI_LIB

    GameSound soundType = GameSound::none;

    switch (position.get_action()) {
    case Action::select:
    case Action::place:
        soundType = GameSound::drog;
        break;
    case Action::remove:
        soundType = GameSound::remove;
        break;
    default:
        break;
    }

    if (position.get_phase() == Phase::ready) {
        gameStart();
    }

#ifdef MUEHLE_NMM
    if (position.get_phase() != Phase::gameOver) {
#endif // MUEHLE_NMM
        loggerDebug("Computer: %s\n\n", cmd.c_str());

        moveHistory.emplace_back(cmd);

        if (cmd.size() > strlen("-(1,2)")) {
            posKeyHistory.push_back(position.key());
        } else {
            posKeyHistory.clear();
        }

        if (!position.command(cmd.c_str()))
            return false;
#ifdef MUEHLE_NMM
    }
#endif // MUEHLE_NMM

    sideToMove = position.side_to_move();

    if (soundType == GameSound::drog && position.get_action() == Action::remove) {
        soundType = GameSound::mill;
    }

    if (update) {
        playSound(soundType, position.side_to_move());
        updateScence(position);
    }

    // Signal update status bar
    updateScence();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // For opening
    if (move_hostory()->size() <= 1) {
        manualListModel.removeRows(0, manualListModel.rowCount());
        manualListModel.insertRow(0);
        manualListModel.setData(manualListModel.index(0), position.get_record());
        currentRow = 0;
    }
    // For the current position
    else {
        currentRow = manualListModel.rowCount() - 1;
        // Skip the added rows. The iterator does not support the + operator and can only skip one by one++
        auto i = (move_hostory()->begin());
        for (int r = 0; i != (move_hostory())->end(); i++) {
            if (r++ > currentRow)
                break;
        }
        // Insert the new chess score line into list model
        while (i != move_hostory()->end()) {
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i++).c_str());
        }
    }

    // Play win or lose sound
#ifndef DONOT_PLAY_WIN_SOUND
    const Color winner = position.get_winner();
    if (winner != NOBODY &&
        (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over.")) {
        playSound(GameSound::win, winner);
    }
#endif

    // AI Settings
    // If it's not decided yet
    if (position.get_winner() == NOBODY) {
        resumeAiThreads(position.sideToMove);
    }
    // If it's decided
    else {           
            pauseThreads();

            gameEndTime = now();
            gameDurationTime = gameEndTime - gameStartTime;

            gameEndCycle = stopwatch::rdtscp_clock::now();

            loggerDebug("Game Duration Time: %lldms\n", gameDurationTime);

#ifdef TIME_STAT
            loggerDebug("Sort Time: %I64d + %I64d = %I64dms\n",
                        aiThread[WHITE]->sortTime, aiThread[BLACK]->sortTime,
                        (aiThread[WHITE]->sortTime + aiThread[BLACK]->sortTime));
            aiThread[WHITE]->sortTime = aiThread[BLACK]->sortTime = 0;
#endif // TIME_STAT
#ifdef CYCLE_STAT
            loggerDebug("Sort Cycle: %ld + %ld = %ld\n",
                        aiThread[WHITE]->sortCycle, aiThread[BLACK]->sortCycle,
                        (aiThread[WHITE]->sortCycle + aiThread[BLACK]->sortCycle));
            aiThread[WHITE]->sortCycle = aiThread[BLACK]->sortCycle = 0;
#endif // CYCLE_STAT

#if 0
            gameDurationCycle = gameEndCycle - gameStartCycle;
            loggerDebug("Game Start Cycle: %u\n", gameStartCycle);
            loggerDebug("Game End Cycle: %u\n", gameEndCycle);
            loggerDebug("Game Duration Cycle: %u\n", gameDurationCycle);
#endif

#ifdef TRANSPOSITION_TABLE_DEBUG                
            size_t hashProbeCount_1 = aiThread[WHITE]->ttHitCount + aiThread[WHITE]->ttMissCount;
            size_t hashProbeCount_2 = aiThread[BLACK]->ttHitCount + aiThread[BLACK]->ttMissCount;
                
            loggerDebug("[key 1] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_1,
                        aiThread[WHITE]->ttHitCount,
                        aiThread[WHITE]->ttMissCount,
                        aiThread[WHITE]->ttHitCount * 100 / hashProbeCount_1);

            loggerDebug("[key 2] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_2,
                        aiThread[BLACK]->ttHitCount,
                        aiThread[BLACK]->ttMissCount,
                        aiThread[BLACK]->ttHitCount * 100 / hashProbeCount_2);

            loggerDebug("[key +] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_1 + hashProbeCount_2,
                        aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount,
                        aiThread[WHITE]->ttMissCount + aiThread[BLACK]->ttMissCount,
                        (aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount ) * 100 / (hashProbeCount_1 + hashProbeCount_2));
#endif // TRANSPOSITION_TABLE_DEBUG

            if (gameOptions.getAutoRestart()) {
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

#ifdef MESSAGEBOX_ENABLE
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
        bwinrate = 0;
        wwinrate = 0;
        drawrate = 0;
    } else {
        bwinrate = (float)position.score[WHITE] * 100 / total;
        wwinrate = (float)position.score[BLACK] * 100 / total;
        drawrate = (float)position.score_draw * 100 / total;
    }

    cout << "Score: " << position.score[WHITE] << " : " << position.score[BLACK] << " : " << position.score_draw << "\ttotal: " << total << endl;
    cout << fixed << setprecision(2) << bwinrate << "% : " << wwinrate << "% : " << drawrate << "%" << endl;

    return true;
}

// Browse the historical situation and refresh the situation display through the command function
bool Game::phaseChange(int row, bool forceUpdate)
{
    // If row is the currently viewed chess score line, there is no need to refresh it
    if (currentRow == row && !forceUpdate)
        return false;

    // Need to refresh
    currentRow = row;
    int rows = manualListModel.rowCount();
    QStringList mlist = manualListModel.stringList();

    loggerDebug("rows: %d current: %d\n", rows, row);

    for (int i = 0; i <= row; i++) {
        loggerDebug("%s\n", mlist.at(i).toStdString().c_str());
        position.command(mlist.at(i).toStdString().c_str());
    }

    // The key step is to let the penitent bear the loss of time
    set_start_time(static_cast<int>(start_timeb()));

    // Refresh the chess scene
    updateScence(position);

    return true;
}

bool Game::updateScence()
{
    return updateScence(position);
}

bool Game::updateScence(Position &p)
{
    const Piece *board = p.get_board();
    QPointF pos;

    // Chess code in game class
    int key;

    // Total number of pieces
    int nTotalPieces = rule.piecesCount * 2;

    // Animation group
    auto *animationGroup = new QParallelAnimationGroup;

    // The pieces are in place
    PieceItem *piece = nullptr;
    PieceItem *deletedPiece = nullptr;

    for (int i = 0; i < nTotalPieces; i++) {
        piece = pieceList.at(static_cast<size_t>(i));

        piece->setSelected(false);

        // Convert the subscript of pieceList to the chess code of game
        key = (i % 2) ? (i / 2 + B_STONE_1) : (i / 2 + W_STONE_1);

        int j;

        // Traverse the board, find and place the pieces on the board
        for (j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == key) {
                pos = scene.polar2pos(File(j / RANK_NB), Rank(j % RANK_NB + 1));
                if (piece->pos() != pos) {

                    // Let the moving pieces be at the top level
                    piece->setZValue(1);

                    // Pieces movement animation
                    QPropertyAnimation *animation = new QPropertyAnimation(piece, "pos");
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

        // If not, place the pieces outside the chessboard
        if (j == (RANK_NB) * (FILE_NB + 1)) {
            // Judge whether it is a removing seed or an unplaced one
            if (key & W_STONE) {
                pos = (key - 0x11 < nTotalPieces / 2 - p.count<IN_HAND>(WHITE)) ?
                        scene.pos_p2_g : scene.pos_p1;
            } else {
                pos = (key - 0x21 < nTotalPieces / 2 - p.count<IN_HAND>(BLACK)) ?
                        scene.pos_p1_g : scene.pos_p2;
            }

            if (piece->pos() != pos) {
                // In order to prepare for the selection of the recently removed pieces
                deletedPiece = piece;

#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
                if (position.get_phase() == Phase::moving) {
#endif
                    QPropertyAnimation *animation = new QPropertyAnimation(piece, "pos");
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
        for (int j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == BAN_STONE) {
                pos = scene.polar2pos(File(j / RANK_NB), Rank(j % RANK_NB + 1));
                if (nTotalPieces < static_cast<int>(pieceList.size())) {
                    pieceList.at(static_cast<size_t>(nTotalPieces++))->setPos(pos);
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
        ipos = (key & W_STONE) ? (key - W_STONE_1) * 2 : (key - B_STONE_1) * 2 + 1;
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
    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] + position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;
    if (position.gamesPlayedCount != 0) {
        winningRate_1 = position.score[WHITE] * 10000 / position.gamesPlayedCount;
        winningRate_2 = position.score[BLACK] * 10000 / position.gamesPlayedCount;
        winningRate_draw = position.score_draw * 10000 / position.gamesPlayedCount;
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

void Game::showTestWindow()
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
    QString strDate = QDateTime::currentDateTime().toString("yyyy-MM-dd");
    qint64 pid = QCoreApplication::applicationPid();

    QString path = QDir::currentPath()
        + "/" + tr("Score-MillGame_")
        + strDate + "_"
        + QString::number(pid)
        + ".txt";

    QFile file;

    file.setFileName(path);

    if (file.isOpen()) {
        file.close();
    }

    if (!(file.open(QFileDevice::WriteOnly | QFileDevice::Text))) {
        return;
    }

    QTextStream textStream(&file);

    textStream << QCoreApplication::applicationFilePath() << endl << endl;

    textStream << gameTest->getKey() << endl << endl;

    if (isAiPlayer[WHITE]) {
        textStream << "White:\tAI Player" << endl;
    } else {
        textStream << "White:\tHuman Player" << endl;
    }

    if (isAiPlayer[BLACK]) {
        textStream << "Black:\tAI Player" << endl;
    } else {
        textStream << "Black:\tHuman Player" << endl;
    }

    textStream << "" << endl;

    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] + position.score_draw;

    if (position.gamesPlayedCount == 0) {
        goto out;
    }

    textStream << "Sum\t" + QString::number(position.gamesPlayedCount) << endl;
    textStream << "White\t" + QString::number(position.score[WHITE])  + "\t" + QString::number(position.score[WHITE] * 10000 / position.gamesPlayedCount) << endl;
    textStream << "Black\t" + QString::number(position.score[BLACK]) + "\t" + QString::number(position.score[BLACK] * 10000 / position.gamesPlayedCount) << endl;
    textStream << "Draw\t" + QString::number(position.score_draw) + "\t" + QString::number(position.score_draw * 10000 / position.gamesPlayedCount)  << endl;

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
        return "白方";
    } else {
        return "黑方";
    }
}

void Game::appendGameOverReasonToMoveHistory()
{
    if (position.phase != Phase::gameOver) {
        return;
    }

    char record[64] = { 0 };
    switch (position.gameOverReason) {
    case GameOverReason::loseReasonNoWay:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonNoWayStr, position.sideToMove, position.winner);
        break;
    case GameOverReason::loseReasonTimeOver:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonTimeOverStr, position.winner);
        break;
    case GameOverReason::drawReasonThreefoldRepetition:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonThreefoldRepetitionStr);
        break;
    case GameOverReason::drawReasonRule50:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonRule50Str);
        break;
    case GameOverReason::loseReasonBoardIsFull:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonBoardIsFullStr);
        break;
    case GameOverReason::drawReasonBoardIsFull:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonBoardIsFullStr);
        break;
    case GameOverReason::loseReasonlessThanThree:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonlessThanThreeStr, position.winner);
        break;
    case GameOverReason::loseReasonResign:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonResignStr, ~position.winner);
        break;
    default:
        loggerDebug("No Game Over Reason");
        break;
    }

    loggerDebug("%s\n", record);
    moveHistory.emplace_back(record);
}

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
    

    switch (p.phase) {
    case Phase::ready:
        tips = "轮到" + turnStr + "落子，剩余" + std::to_string(p.pieceInHandCount[WHITE]) + "子" +
            "  比分 " + to_string(p.score[WHITE]) + ":" + to_string(p.score[BLACK]) + ", 和棋 " + to_string(p.score_draw);
        break;

    case Phase::placing:
        if (p.action == Action::place) {
            tips = "轮到" + turnStr + "落子，剩余" + std::to_string(p.pieceInHandCount[p.sideToMove]) + "子";
        } else if (p.action == Action::remove) {
            tips = "成三！轮到" + turnStr + "去子，需去" + std::to_string(p.pieceToRemoveCount) + "子";
        }
        break;

    case Phase::moving:
        if (p.action == Action::place || p.action == Action::select) {
            tips = "轮到" + turnStr + "选子移动";
        } else if (p.action == Action::remove) {
            tips = "成三！轮到" + turnStr + "去子，需去" + std::to_string(p.pieceToRemoveCount) + "子";
        }
        break;

    case Phase::gameOver:
        appendGameOverReasonToMoveHistory();

        scoreStr = "比分 " + to_string(p.score[WHITE]) + " : " + to_string(p.score[BLACK]) + ", 和棋 " + to_string(p.score_draw);        

        switch (p.winner) {
        case WHITE:
        case BLACK:
            winnerStr = char_to_string(color_to_char(p.winner));
            resultStr = winnerStr + "获胜！";
            break;
        case DRAW:
            resultStr = "双方平局！";
            break;
        default:
            break;
        }

        switch (p.gameOverReason) {
        case GameOverReason::loseReasonlessThanThree:
            break;
        case GameOverReason::loseReasonNoWay:
#ifdef MUEHLE_NMM
            if (!isInverted) {
                turnStr = char_to_string(color_to_char(~p.sideToMove));
            } else {
                turnStr = char_to_string(color_to_char(p.sideToMove));
            }
#endif
            reasonStr = turnStr + "无子可走被闷。";
            break;
        case GameOverReason::loseReasonResign:
            reasonStr = turnStr + "投子认负。";
            break;
        case GameOverReason::loseReasonTimeOver:
            reasonStr = turnStr + "超时判负。";
            break;
        case GameOverReason::drawReasonThreefoldRepetition:
            reasonStr = "三次重复局面判和。";
            break;
        case GameOverReason::drawReasonRule50:
            reasonStr = "连续50回合无吃子判和。";
            break;
        case GameOverReason::drawReasonBoardIsFull:
            reasonStr = "棋盘满判和。";
            break;
        default:
            break;
        }       

        tips = reasonStr + resultStr + scoreStr;
        break;

    default:
        break;
    }
}

time_t Game::get_elapsed_time(int us)
{
    return elapsedSeconds[us];
}
