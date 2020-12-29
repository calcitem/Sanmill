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
#include <QThread>
#include <iomanip>

#include "game.h"
#include "graphicsconst.h"
#include "boarditem.h"
#include "server.h"
#include "client.h"
#include "option.h"

using namespace std;

Game::Game(
#ifndef TRAINING_MODE
    GameScene & scene,
#endif
    QObject * parent
) :
    QObject(parent),
#ifndef TRAINING_MODE
    scene(scene),
#endif
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
    timeLimit(0),
    stepsLimit(50)
{
    // 已在view的样式表中添加背景，scene中不用添加背景
    // 区别在于，view中的背景不随视图变换而变换，scene中的背景随视图变换而变换
    //scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));
#ifdef MOBILE_APP_UI
    scene.setBackgroundBrush(QColor(239, 239, 239));
#endif /* MOBILE_APP_UI */

    resetAiPlayers();
    createAiThreads();

    gameReset();

    gameTest = new Test();

    qRegisterMetaType<std::string>("string");

#ifdef QT_GUI_LIB
    // 关联AI和控制器的着法命令行
    connect(aiThread[BLACK], SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));
    connect(aiThread[WHITE], SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));

    connect(this->gameTest, SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));
#endif // QT_GUI_LIB

#ifdef NET_FIGHT_SUPPORT
#ifndef TRAINING_MODE
    server = new Server(nullptr, 30001);    // TODO: WARNING: ThreadSanitizer: data race
    uint16_t clientPort = server->getPort() == 30001 ? 30002 : 30001;
    client = new Client(nullptr, clientPort);

    // 关联AI和网络类的着法命令行
    connect(getClient(), SIGNAL(command(const string &, bool)),
            this, SLOT(command(const string &, bool)));
#endif  // TRAINING_MODE
#endif // NET_FIGHT_SUPPORT

#ifdef ENDGAME_LEARNING_FORCE
    if (gameOptions.getLearnEndgameEnabled()) {
        AIAlgorithm::loadEndgameFileToHashMap();
    }
#endif

    cmdlist.reserve(256);

    // 安装事件过滤器监视scene的各个事件，
    // 由于我重载了QGraphicsScene，相关事件在重载函数中已设定，不必安装监视器。
    //scene.installEventFilter(this);    
}

Game::~Game()
{
    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);

    // 停掉线程
    pauseAndWaitThreads();
    deleteAiThreads();

#ifdef ENDGAME_LEARNING
    if (gameOptions.getLearnEndgameEnabled()) {
        AIAlgorithm::recordEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */

    cmdlist.clear();
}

const map<int, QStringList> Game::getActions()
{
    // 主窗口更新菜单栏
    // 之所以不用信号和槽的模式，是因为发信号的时候槽还来不及关联
    map<int, QStringList> actions;

#ifndef TRAINING_MODE
    for (int i = 0; i < N_RULES; i++) {
        // map的key存放int索引值，value存放规则名称和规则提示
        QStringList strlist;
        strlist.append(tr(RULES[i].name));
        strlist.append(tr(RULES[i].description));
        actions.insert(map<int, QStringList>::value_type(i, strlist));
    }
#endif // TRAINING_MODE

    return actions;
}

#ifdef OPENING_BOOK
extern deque<int> openingBookDeque;
extern deque<int> openingBookDequeBak;
#endif

void Game::gameStart()
{
    //cmdlist.clear();
    position.start();
    startTime = time(nullptr);

    // 每隔100毫秒调用一次定时器处理函数
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
    while (aiThread[BLACK]->searching || aiThread[WHITE]->searching) {
        loggerDebug(".");
        QThread::msleep(100);
    }

    loggerDebug("\n");

    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);

    // 定时器ID为0
    timeID = 0;

    // 重置游戏
    // WAR
    if (cmdlist.size() > 1) {
        string bak = cmdlist[0];
        cmdlist.clear();
        cmdlist.emplace_back(bak);
    }    

    position.reset();
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;
    sideToMove = position.side_to_move();

    // 停掉线程
    if (!gameOptions.getAutoRestart()) {
        pauseThreads();
        resetAiPlayers();
    }

#ifndef TRAINING_MODE
    // 清除棋子
    qDeleteAll(pieceList);
    pieceList.clear();
    currentPiece = nullptr;

    // 重新绘制棋盘
    scene.setDiagonal(rule.hasObliqueLines);

    // 绘制所有棋子，放在起始位置
    // 0: 先手第1子； 1：后手第1子
    // 2：先手第2子； 3：后手第2子
    // ......
    PieceItem::Models md;
    PieceItem *newP;

    for (int i = 0; i < rule.nTotalPiecesEachSide; i++) {
        // 先手的棋子
        md = isInverted ? PieceItem::whitePiece : PieceItem::blackPiece;
        newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p1);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);

        // 后手的棋子
        md = isInverted ? PieceItem::blackPiece : PieceItem::whitePiece;
        newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p2);
        newP->setNum(i + 1);
        newP->setShowNum(false);

        pieceList.push_back(newP);
        scene.addItem(newP);
    }

    // 读取规则限时要求
    timeLimit = 0; // TODO: rule.maxTimeLedToLose;

    // 如果规则不要求计时，则time1和time2表示已用时间
    if (timeLimit <= 0) {
        // 将玩家的已用时间清零
        remainingTime[BLACK] = remainingTime[WHITE] = 0;
    } else {
        // 将玩家的剩余时间置为限定时间
        remainingTime[BLACK] = remainingTime[WHITE] = timeLimit * 60;
    }

    // 更新棋谱
    manualListModel.removeRows(0, manualListModel.rowCount());
    manualListModel.insertRow(0);
    manualListModel.setData(manualListModel.index(0), position.cmd_line());
    currentRow = 0;

    // 发出信号通知主窗口更新LCD显示
    QTime qtime = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[BLACK]));
    emit time1Changed(qtime.toString("hh:mm:ss"));
    emit time2Changed(qtime.toString("hh:mm:ss"));

    // 发信号更新状态栏
    updateScence();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // 更新比分 LCD 显示
    emit nGamesPlayedChanged(QString::number(position.nPlayed, 10));
    emit score1Changed(QString::number(position.score[BLACK], 10));
    emit score2Changed(QString::number(position.score[WHITE], 10));
    emit scoreDrawChanged(QString::number(position.score_draw, 10));

    // 更新胜率 LCD 显示
    position.nPlayed = position.score[BLACK] + position.score[WHITE] + position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;
    if (position.nPlayed != 0) {
        winningRate_1 = position.score[BLACK] * 10000 / position.nPlayed;
        winningRate_2 = position.score[WHITE] * 10000 / position.nPlayed;
        winningRate_draw = position.score_draw * 10000 / position.nPlayed;
    }
    
    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));

    // 播放音效
    //playSound(":/sound/resources/sound/newgame.wav");
#endif // TRAINING_MODE
}

void Game::setEditing(bool arg)
{
#ifndef TRAINING_MODE
    isEditing = arg;
#endif
}

void Game::setInvert(bool arg)
{
#ifndef TRAINING_MODE
    isInverted = arg;

    // 遍历所有棋子
    for (PieceItem *pieceItem : pieceList) {
        if (pieceItem) {
            // 黑子变白
            if (pieceItem->getModel() == PieceItem::blackPiece)
                pieceItem->setModel(PieceItem::whitePiece);

            // 白子变黑
            else if (pieceItem->getModel() == PieceItem::whitePiece)
                pieceItem->setModel(PieceItem::blackPiece);

            // 刷新棋子显示
            pieceItem->update();
        }
    }
#endif // TRAINING_MODE
}

void Game::setRule(int ruleNo, int stepLimited /*= -1*/, int timeLimited /*= -1*/)
{
    // 更新规则，原限时和限步不变
    if (ruleNo < 0 || ruleNo >= N_RULES)
        return;
    this->ruleIndex = ruleNo;

    if (stepLimited != std::numeric_limits<uint16_t>::max() && timeLimited != -1) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }

    // 设置模型规则，重置游戏
    if (set_rule(ruleNo) == false) {
        return;
    }

    int r = ruleNo;
    elapsedSeconds[BLACK] = elapsedSeconds[WHITE] = 0;

    char cmdline[64] = { 0 };
    if (sprintf(cmdline, "r%1u s%03u t%02u", r + 1, rule.maxStepsLedToDraw, 0) <= 0) {
        assert(0);
    }
    string cmd(cmdline);
    cmdlist.clear();
    cmdlist.emplace_back(cmd);

    // 重置游戏
    gameReset();
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

void Game::setEngineBlack(bool enabled)
{
    setEngine(BLACK, enabled);
}

void Game::setEngineWhite(bool enabled)
{
    setEngine(WHITE, enabled);
}

void Game::setAiDepthTime(int time1, int time2)
{
    stopAndWaitAiThreads();

    aiThread[BLACK]->setAi(&position,  time1);
    aiThread[WHITE]->setAi(&position, time2);

    startAiThreads();
}

void Game::getAiDepthTime(int &time1, int &time2)
{
    time1 = aiThread[BLACK]->getTimeLimit();
    time2 = aiThread[WHITE]->getTimeLimit();
}

void Game::setAnimation(bool arg)
{
#ifndef TRAINING_MODE
    hasAnimation = arg;

    // 默认动画时间500ms
    if (hasAnimation)
        durationTime = 500;
    else
        durationTime = 0;
#endif // TRAINING_MODE
}

void Game::setSound(bool arg)
{
#ifndef TRAINING_MODE
    hasSound = arg;
#endif // TRAINING_MODE
}

void Game::playSound(sound_t soundType, Color c)
{
    string soundDir = ":/sound/resources/sound/";
    string sideStr = c == BLACK ? "B" : "W";
    string oppenentStr = c == WHITE? "B" : "W";
    string filename;

    switch (soundType) {
    case GAME_SOUND_BLOCK_MILL:
        filename = "BlockMill_" + sideStr + ".wav";
        break;
    case GAME_SOUND_REMOVE:
        filename = "Remove_" + oppenentStr + ".wav";
        break;
    case GAME_SOUND_SELECT:
        filename = "Select.wav";
        break;
    case GAME_SOUND_DRAW:
        filename = "Draw.wav";
        break;
    case GAME_SOUND_DROG:
        filename = "drog.wav";
        break;
    case GAME_SOUND_BANNED:
        filename = "forbidden.wav";
        break;
    case GAME_SOUND_GAME_START:
        filename = "GameStart.wav";
        break;
    case GAME_SOUND_RESIGN:
        filename = "Resign_" + sideStr + ".wav";
        break;
    case GAME_SOUND_LOSS:
        filename = "loss.wav";
        break;
    case GAME_SOUND_MILL:
        filename = "Mill_" + sideStr + ".wav";
        break;
    case GAME_SOUND_MILL_REPEATLY:
        filename = "MillRepeatly_" + sideStr + ".wav";
        break;
    case GAME_SOUND_MOVE:
        filename = "move.wav";
        break;
    case GAME_SOUND_NEW_GAME:
        filename = "newgame.wav";
        break;
    case GAME_SOUND_NEXT_MILL:
        filename = "NextMill_" + sideStr + ".wav";
        break;
    case GAME_SOUND_OBVIOUS:
        filename = "Obvious.wav";
        break;
    case GAME_SOUND_REPEAT_THREE_DRAW:
        filename = "RepeatThreeDraw.wav";
        break;
    case GAME_SOUND_SIDE:
        filename = "Side_" + sideStr + ".wav";
        break;
    case GAME_SOUND_STAR:
        filename = "Star_" + sideStr + ".wav";
        break;
    case GAME_SOUND_SUFFOCATED:
        filename = "Suffocated_" + sideStr + ".wav";
        break;
    case GAME_SOUND_VANTAGE:
        filename = "Vantage.wav";
        break;
    case GAME_SOUND_VERY:
        filename = "Very.wav";
        break;
    case GAME_SOUND_WARNING:
        filename = "warning.wav";
        break;
    case GAME_SOUND_WIN:        
        if (c == DRAW) {
            filename = "Draw.wav";
        } else {
            filename = "Win_" + sideStr + ".wav";
        }
        break;
    case GAME_SOUND_WIN_AND_LOSSES_ARE_OBVIOUS:
        filename = "WinsAndLossesAreObvious.wav";
        break;
    default:
        filename = "";
        break;
    };

    QString soundPath = QString::fromStdString(soundDir + filename);

#ifndef TRAINING_MODE
    if (soundPath == "") {
        return;
    }

#ifndef DONOT_PLAY_SOUND
    if (hasSound) {
        QSound::play(soundPath);
    }
#endif /* ! DONOT_PLAY_SOUND */
#endif // TRAINING_MODE
}

void Game::setResignIfMostLose(bool enabled)
{
    gameOptions.setResignIfMostLose(enabled);
}

void Game::setAutoRestart(bool enabled)
{
    gameOptions.setAutoRestart(enabled);
}

void Game::setAutoChangeFirstMove(bool enabled)
{
    gameOptions.setAutoChangeFirstMove(enabled);
}

void Game::setRandomMove(bool enabled)
{
    gameOptions.setRandomMoveEnabled(enabled);
}

void Game::setLearnEndgame(bool enabled)
{
    gameOptions.setLearnEndgameEnabled(enabled);

#ifdef ENDGAME_LEARNING
    if (gameOptions.getLearnEndgameEnabled()) {
        AIAlgorithm::loadEndgameFileToHashMap();
    }
#endif
}

void Game::setIDS(bool enabled)
{
    gameOptions.setIDSEnabled(enabled);
}

// DepthExtension
void Game::setDepthExtension(bool enabled)
{
    gameOptions.setDepthExtension(enabled);
}

// OpeningBook
void Game::setOpeningBook(bool enabled)
{
    gameOptions.setOpeningBook(enabled);
}

// 上下翻转
void Game::flip()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    position.mirror(cmdlist);
    position.rotate(cmdlist, 180);

    // 更新棋谱
    int row = 0;
    for (const auto &str : *(cmd_list())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    threadsSetAi(&position);
    startAiThreads();
#endif // TRAINING_MODE
}

// 左右镜像
void Game::mirror()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    position.mirror(cmdlist);

    // 更新棋谱
    int row = 0;

    for (const auto &str : *(cmd_list())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    loggerDebug("list: %d\n", row);

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    threadsSetAi(&position);
    startAiThreads();
#endif // TRAINING_MODE
}

// 视图须时针旋转90°
void Game::turnRight()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    position.rotate(cmdlist, -90);

    // 更新棋谱
    int row = 0;

    for (const auto &str : *(cmd_list())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    threadsSetAi(&position);
    startAiThreads();
#endif
}

// 视图逆时针旋转90°
void Game::turnLeft()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    position.rotate(cmdlist, 90);

    // 更新棋谱
    int row = 0;
    for (const auto &str : *(cmd_list())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    updateScence();

    threadsSetAi(&position);
    startAiThreads();
#endif // TRAINING_MODE
}

void Game::updateTime()
{
    int timePoint = -1;
    time_t *ourSeconds = &elapsedSeconds[sideToMove];
    time_t theirSeconds = elapsedSeconds[~sideToMove];

//     if (!(phase == Phase::placing || phase == Phase::moving)) {
//         return;
//     }

    currentTime = time(NULL);

    if (timePoint >= *ourSeconds) {
        *ourSeconds = timePoint;
        startTime = currentTime - (elapsedSeconds[BLACK] + elapsedSeconds[WHITE]);
    } else {
        *ourSeconds = currentTime - startTime - theirSeconds;
    }
}

void Game::timerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    static QTime qt1, qt2;

    // 玩家的已用时间
    updateTime();
    remainingTime[BLACK] = get_elapsed_time(BLACK);
    remainingTime[WHITE] = get_elapsed_time(WHITE);

    // 如果规则要求计时，则time1和time2表示倒计时
    if (timeLimit > 0) {
        // 玩家的剩余时间
        remainingTime[BLACK] = timeLimit * 60 - remainingTime[BLACK];
        remainingTime[WHITE] = timeLimit * 60 - remainingTime[WHITE];
    }

    qt1 = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[BLACK]));
    qt2 = QTime(0, 0, 0, 0).addSecs(static_cast<int>(remainingTime[WHITE]));

    emit time1Changed(qt1.toString("hh:mm:ss"));
    emit time2Changed(qt2.toString("hh:mm:ss"));

    // 如果胜负已分
    Color winner = position.get_winner();
    if (winner != NOBODY) {
        // 停止计时
        killTimer(timeID);

        // 定时器ID为0
        timeID = 0;

#ifndef TRAINING_MODE
        // 发信号更新状态栏
        updateScence();
        message = QString::fromStdString(getTips());
        emit statusBarChanged(message);

        // 弹框
        //QMessageBox::about(NULL, "游戏结果", message);

        // 播放音效
#ifndef DONOT_PLAY_WIN_SOUND
        playSound(GAME_SOUND_WIN, winner);
#endif
#endif // TRAINING_MODE
    }

    // 测试用代码
#if 0
    int ti = time.elapsed();
    static QTime t;
    if (ti < 0)
        ti += 86400; // 防止过24:00引起的时间误差，加上一天中总秒数
    if (timeWhos == 1)
    {
        time1 = ti - time2;
        // 用于显示时间的临时变量，多出的50毫秒用于消除计时器误差产生的跳动
        t = QTime(0, 0, 0, 50).addMSecs(time1);
        emit time1Changed(t.toString("hh:mm:ss"));
    }
    else if (timeWhos == 2)
    {
        time2 = ti - time1;
        // 用于显示时间的临时变量，多出的50毫秒用于消除计时器误差产生的跳动
        t = QTime(0, 0, 0, 50).addMSecs(time2);
        emit time2Changed(t.toString("hh:mm:ss"));
    }
#endif
}

bool Game::isAIsTurn()
{
    return isAiPlayer[sideToMove];
}

// 关键槽函数，根据QGraphicsScene的信号和状态来执行选子、落子或去子
bool Game::actionPiece(QPointF pos)
{
#ifndef TRAINING_MODE
    // 点击非落子点，不执行
    File file;
    Rank rank;

    if (!scene.pos2polar(pos, file, rank)) {
        return false;
    }

    // 电脑走棋或正在搜索时，点击无效
    if (isAIsTurn() ||
        aiThread[BLACK]->searching ||
        aiThread[WHITE]->searching) {
        return false;
    }

    // 在浏览历史记录时点击棋盘，则认为是悔棋
    if (currentRow != manualListModel.rowCount() - 1) {
#ifndef MOBILE_APP_UI
        // 定义新对话框
        QMessageBox msgBox;
        msgBox.setIcon(QMessageBox::Question);
        msgBox.setMinimumSize(600, 400);
        msgBox.setText(tr("当前正在浏览历史局面。"));
        msgBox.setInformativeText(tr("您确定要悔棋？"));
        msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
        msgBox.setDefaultButton(QMessageBox::Cancel);
        (msgBox.button(QMessageBox::Ok))->setText(tr("确定"));
        (msgBox.button(QMessageBox::Cancel))->setText(tr("取消"));

        if (QMessageBox::Ok == msgBox.exec()) {
#endif /* !MOBILE_APP_UI */
            int rowCount = manualListModel.rowCount();
            int removeCount = rowCount - currentRow - 1;
            manualListModel.removeRows(currentRow + 1, rowCount - currentRow - 1);

            for (int i = 0; i < removeCount; i++) {
                cmdlist.pop_back();
            }

            // 如果再决出胜负后悔棋，则重新启动计时
            if (position.get_winner() == NOBODY) {

                // 重新启动计时
                timeID = startTimer(100);

                // 发信号更新状态栏
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

    // 如果未开局则开局
    if (position.get_phase() == Phase::ready)
        gameStart();

    // 判断执行选子、落子或去子
    bool result = false;
    PieceItem *piece = nullptr;
    QGraphicsItem *item = scene.itemAt(pos, QTransform());

    switch (position.get_action()) {
    case Act::place:
        if (position.put_piece(file, rank)) { 
            if (position.get_action() == Act::remove) {
                // 播放成三音效
                playSound(GAME_SOUND_MILL, position.side_to_move());
            } else {
                // 播放移动棋子音效
                playSound(GAME_SOUND_DROG, position.side_to_move());
            }
            result = true;
            break;
        }

     // 如果移子不成功，尝试重新选子，这里不break
        [[fallthrough]];

    case Act::select:
        piece = qgraphicsitem_cast<PieceItem *>(item);
        if (!piece)
            break;
        if (position.select_piece(file, rank)) {
            // 播放选子音效
            playSound(GAME_SOUND_SELECT, position.side_to_move());
            result = true;
        } else {
            // 播放禁止音效
            playSound(GAME_SOUND_BANNED, position.side_to_move());
        }
        break;

    case Act::remove:
        if (position.remove_piece(file, rank)) {
            // 播放音效
            playSound(GAME_SOUND_REMOVE, position.side_to_move());
            result = true;
        } else {
            // 播放禁止音效
            playSound(GAME_SOUND_BANNED, position.side_to_move());
        }
        break;

    default:
        // 如果是结局状态，不做任何响应
        break;
    }

    if (result) {
        cmdlist.emplace_back(position.cmdline);

        // 发信号更新状态栏
        updateScence();
        message = QString::fromStdString(getTips());
        emit statusBarChanged(message);

        // 将新增的棋谱行插入到ListModel
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;

        // 输出命令行        
        for (const auto & i : *(cmd_list())) {
            // 跳过已添加的，因标准list容器没有下标
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), i.c_str());
        }

        // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
        Color winner = position.get_winner();
        if (winner != NOBODY &&
            (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over."))
            playSound(GAME_SOUND_WIN, winner);
#endif

        // AI设置
        // 如果还未决出胜负
        if (position.get_winner() == NOBODY) {
            resumeAiThreads(position.sideToMove);
        }
        // 如果已经决出胜负
        else {
            pauseThreads();
        }
    }

    sideToMove = position.side_to_move();
    updateScence();
    return result;
#else
    return true;
#endif // TRAINING_MODE
}


bool Game::resign()
{
    bool result = position.resign(position.sideToMove);
        
    if (!result) {
        return false;
    }

#ifndef TRAINING_MODE

    // 将新增的棋谱行插入到ListModel
    currentRow = manualListModel.rowCount() - 1;
    int k = 0;

    // 输出命令行
    for (const auto & i : *(cmd_list())) {
        // 跳过已添加的，因标准list容器没有下标
        if (k++ <= currentRow)
            continue;
        manualListModel.insertRow(++currentRow);
        manualListModel.setData(manualListModel.index(currentRow), i.c_str());
    }

    if (position.get_winner() != NOBODY) {
        playSound(GAME_SOUND_RESIGN, position.side_to_move());
    }
#endif // TRAINING_MODE

    return result;
}

// 关键槽函数，棋谱的命令行执行，与actionPiece独立
bool Game::command(const string &cmd, bool update /* = true */)
{
    int total;
    float bwinrate, wwinrate, drawrate;

#ifndef TRAINING_MODE
    Q_UNUSED(hasSound)
#endif

#ifdef QT_GUI_LIB
    // 防止接收滞后结束的线程发送的指令
    if (sender() == aiThread[BLACK] && !isAiPlayer[BLACK])
        return false;

    if (sender() == aiThread[WHITE] && !isAiPlayer[WHITE])
        return false;
#endif // QT_GUI_LIB

#ifndef TRAINING_MODE
    // 声音
    sound_t soundType = GAME_SOUND_NONE;

    switch (position.get_action()) {
    case Act::select:
    case Act::place:
        soundType = GAME_SOUND_DROG;
        break;
    case Act::remove:
        soundType = GAME_SOUND_REMOVE;
        break;
    default:
        break;
    }
#endif

    // 如果未开局则开局
    if (position.get_phase() == Phase::ready) {
        gameStart();
    }

    loggerDebug("Computer: %s\n\n", cmd.c_str());

    cmdlist.emplace_back(cmd);

    if (!position.command(cmd.c_str()))
        return false;

    sideToMove = position.side_to_move();

#ifndef TRAINING_MODE
    if (soundType == GAME_SOUND_DROG && position.get_action() == Act::remove) {
        soundType = GAME_SOUND_MILL;
    }

    if (update) {
        playSound(soundType, position.side_to_move());
        updateScence(position);
    }

    // 发信号更新状态栏
    updateScence();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // 对于新开局
    if (cmd_list()->size() <= 1) {
        manualListModel.removeRows(0, manualListModel.rowCount());
        manualListModel.insertRow(0);
        manualListModel.setData(manualListModel.index(0), position.cmd_line());
        currentRow = 0;
    }
    // 对于当前局
    else {
        currentRow = manualListModel.rowCount() - 1;
        // 跳过已添加行,迭代器不支持+运算符,只能一个个++
        auto i = (cmd_list()->begin());
        for (int r = 0; i != (cmd_list())->end(); i++) {
            if (r++ > currentRow)
                break;
        }
        // 将新增的棋谱行插入到ListModel
        while (i != cmd_list()->end()) {
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i++).c_str());
        }
    }

    // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
    Color winner = position.get_winner();
    if (winner != NOBODY &&
        (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over.")) {
        playSound(GAME_SOUND_WIN, winner);
    }
#endif
#endif // TRAINING_MODE

    // AI设置
    // 如果还未决出胜负
    if (position.get_winner() == NOBODY) {
        resumeAiThreads(position.sideToMove);
    }
    // 如果已经决出胜负
    else {           
            pauseThreads();

            gameEndTime = now();
            gameDurationTime = gameEndTime - gameStartTime;

            gameEndCycle = stopwatch::rdtscp_clock::now();

            loggerDebug("Game Duration Time: %lldms\n", gameDurationTime);

#ifdef TIME_STAT
            loggerDebug("Sort Time: %I64d + %I64d = %I64dms\n",
                        aiThread[BLACK]->sortTime, aiThread[WHITE]->sortTime,
                        (aiThread[BLACK]->sortTime + aiThread[WHITE]->sortTime));
            aiThread[BLACK]->sortTime = aiThread[WHITE]->sortTime = 0;
#endif // TIME_STAT
#ifdef CYCLE_STAT
            loggerDebug("Sort Cycle: %ld + %ld = %ld\n",
                        aiThread[BLACK]->sortCycle, aiThread[WHITE]->sortCycle,
                        (aiThread[BLACK]->sortCycle + aiThread[WHITE]->sortCycle));
            aiThread[BLACK]->sortCycle = aiThread[WHITE]->sortCycle = 0;
#endif // CYCLE_STAT

#if 0
            gameDurationCycle = gameEndCycle - gameStartCycle;
            loggerDebug("Game Start Cycle: %u\n", gameStartCycle);
            loggerDebug("Game End Cycle: %u\n", gameEndCycle);
            loggerDebug("Game Duration Cycle: %u\n", gameDurationCycle);
#endif

#ifdef TRANSPOSITION_TABLE_DEBUG                
            size_t hashProbeCount_1 = aiThread[BLACK]->ttHitCount + aiThread[BLACK]->ttMissCount;
            size_t hashProbeCount_2 = aiThread[WHITE]->ttHitCount + aiThread[WHITE]->ttMissCount;
                
            loggerDebug("[key 1] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_1,
                        aiThread[BLACK]->ttHitCount,
                        aiThread[BLACK]->ttMissCount,
                        aiThread[BLACK]->ttHitCount * 100 / hashProbeCount_1);

            loggerDebug("[key 2] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_2,
                        aiThread[WHITE]->ttHitCount,
                        aiThread[WHITE]->ttMissCount,
                        aiThread[WHITE]->ttHitCount * 100 / hashProbeCount_2);

            loggerDebug("[key +] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_1 + hashProbeCount_2,
                        aiThread[BLACK]->ttHitCount + aiThread[WHITE]->ttHitCount,
                        aiThread[BLACK]->ttMissCount + aiThread[WHITE]->ttMissCount,
                        (aiThread[BLACK]->ttHitCount + aiThread[WHITE]->ttHitCount ) * 100 / (hashProbeCount_1 + hashProbeCount_2));
#endif // TRANSPOSITION_TABLE_DEBUG

            if (gameOptions.getAutoRestart()) {
                saveScore();

                gameReset();
                gameStart();

                if (isAiPlayer[BLACK]) {
                    setEngine(BLACK, true);
                }
                if (isAiPlayer[WHITE]) {
                    setEngine(WHITE, true);
                }
            }

#ifdef MESSAGEBOX_ENABLE
        // 弹框
        message = QString::fromStdString(position.get_tips());
        QMessageBox::about(NULL, "游戏结果", message);
#endif
    }
    
    gameTest->writeToMemory(QString::fromStdString(cmd));

#ifdef NET_FIGHT_SUPPORT
#ifndef TRAINING_MODE
    // 网络: 将着法放到服务器的发送列表中
    getServer()->setAction(QString::fromStdString(cmd));
#endif // TRAINING_MODE
#endif

    if (isAiPlayer[WHITE]) {
        aiThread[WHITE]->analyze(WHITE);
    } else if (isAiPlayer[BLACK]) {
        aiThread[BLACK]->analyze(BLACK);
    }

    total = position.score[BLACK] + position.score[WHITE] + position.score_draw;  

    if (total == 0) {
        bwinrate = 0;
        wwinrate = 0;
        drawrate = 0;
    } else {
        bwinrate = (float)position.score[BLACK] * 100 / total;
        wwinrate = (float)position.score[WHITE] * 100 / total;
        drawrate = (float)position.score_draw * 100 / total;
    }

    cout << "Score: " << position.score[BLACK] << " : " << position.score[WHITE] << " : " << position.score_draw << "\ttotal: " << total << endl;
    cout << fixed << setprecision(2) << bwinrate << "% : " << wwinrate << "% : " << drawrate << "%" << endl;

    return true;
}

// 浏览历史局面，通过command函数刷新局面显示
bool Game::phaseChange(int row, bool forceUpdate)
{
#ifndef TRAINING_MODE
    // 如果row是当前浏览的棋谱行，则不需要刷新
    if (currentRow == row && !forceUpdate)
        return false;

    // 需要刷新
    currentRow = row;
    int rows = manualListModel.rowCount();
    QStringList mlist = manualListModel.stringList();

    loggerDebug("rows: %d current: %d\n", rows, row);

    for (int i = 0; i <= row; i++) {
        loggerDebug("%s\n", mlist.at(i).toStdString().c_str());
        position.command(mlist.at(i).toStdString().c_str());
    }

    // 下面这步关键，会让悔棋者承担时间损失
    set_start_time(static_cast<int>(start_timeb()));

    // 刷新棋局场景
    updateScence(position);
#endif // TRAINING_MODE

    return true;
}

bool Game::updateScence()
{
#ifndef TRAINING_MODE
    return updateScence(position);
#else
    return true;
#endif
}

bool Game::updateScence(Position &p)
{
#ifndef TRAINING_MODE
    const Piece *board = p.get_board();
    QPointF pos;

    // game类中的棋子代码
    int key;

    // 棋子总数
    int nTotalPieces = rule.nTotalPiecesEachSide * 2;

    // 动画组
    auto *animationGroup = new QParallelAnimationGroup;

    // 棋子就位
    PieceItem *piece = nullptr;
    PieceItem *deletedPiece = nullptr;

    for (int i = 0; i < nTotalPieces; i++) {
        piece = pieceList.at(static_cast<size_t>(i));

        piece->setSelected(false);

        // 将pieceList的下标转换为game的棋子代号
        key = (i % 2) ? (i / 2 + W_STONE_1) : (i / 2 + B_STONE_1);

        int j;

        // 遍历棋盘，查找并放置棋盘上的棋子
        for (j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == key) {
                pos = scene.polar2pos(File(j / RANK_NB), Rank(j % RANK_NB + 1));
                if (piece->pos() != pos) {

                    // 让移动的棋子位于顶层
                    piece->setZValue(1);

                    // 棋子移动动画
                    QPropertyAnimation *animation = new QPropertyAnimation(piece, "pos");
                    animation->setDuration(durationTime);
                    animation->setStartValue(piece->pos());
                    animation->setEndValue(pos);
                    animation->setEasingCurve(QEasingCurve::InOutQuad);
                    animationGroup->addAnimation(animation);
                } else {
                    // 让静止的棋子位于底层
                    piece->setZValue(0);
                }
                break;
            }
        }

        // 如果没有找到，放置棋盘外的棋子
        if (j == (RANK_NB) * (FILE_NB + 1)) {
            // 判断是被吃掉的子，还是未安放的子
            if (key & B_STONE) {
                pos = (key - 0x11 < nTotalPieces / 2 - p.count<IN_HAND>(BLACK)) ?
                        scene.pos_p2_g : scene.pos_p1;
            } else {
                pos = (key - 0x21 < nTotalPieces / 2 - p.count<IN_HAND>(WHITE)) ?
                        scene.pos_p1_g : scene.pos_p2;
            }

            if (piece->pos() != pos) {
                // 为了对最近移除的棋子置为选择状态作准备
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

    // 添加摆棋阶段禁子点
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

    // 走棋阶段清除禁子点
    if (rule.hasBannedLocations && p.get_phase() != Phase::placing) {
        while (nTotalPieces < static_cast<int>(pieceList.size())) {
            delete pieceList.at(pieceList.size() - 1);
            pieceList.pop_back();
        }
    }

    // 选中当前棋子
    int ipos = p.current_square();
    if (ipos) {
        key = board[p.current_square()];
        ipos = key & B_STONE ? (key - B_STONE_1) * 2 : (key - W_STONE_1) * 2 + 1;
        if (ipos >= 0 && ipos < nTotalPieces) {
            currentPiece = pieceList.at(static_cast<size_t>(ipos));
            currentPiece->setSelected(true);
        }
    }

    // 对最近移除的棋子置为选择状态
    if (deletedPiece) {
        deletedPiece->setSelected(true);
    }

    animationGroup->start(QAbstractAnimation::DeleteWhenStopped);

    // 更新比分 LCD 显示
    emit score1Changed(QString::number(p.score[BLACK], 10));
    emit score2Changed(QString::number(p.score[WHITE], 10));
    emit scoreDrawChanged(QString::number(p.score_draw, 10));

    // 更新胜率 LCD 显示
    position.nPlayed = position.score[BLACK] + position.score[WHITE] + position.score_draw;
    int winningRate_1 = 0, winningRate_2 = 0, winningRate_draw = 0;
    if (position.nPlayed != 0) {
        winningRate_1 = position.score[BLACK] * 10000 / position.nPlayed;
        winningRate_2 = position.score[WHITE] * 10000 / position.nPlayed;
        winningRate_draw = position.score_draw * 10000 / position.nPlayed;
    }

    emit winningRate1Changed(QString::number(winningRate_1, 10));
    emit winningRate2Changed(QString::number(winningRate_2, 10));
    emit winningRateDrawChanged(QString::number(winningRate_draw, 10));

    setTips();

#endif // !TRAINING_MODE
    return true;
}

#ifdef NET_FIGHT_SUPPORT
void Game::showNetworkWindow()
{
#ifndef TRAINING_MODE
    getServer()->show();
    getClient()->show();
#endif // TRAINING_MODE
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

    // 文件对象
    file.setFileName(path);

    if (file.isOpen()) {
        file.close();
    }

    // 打开文件,只写方式打开
    if (!(file.open(QFileDevice::WriteOnly | QFileDevice::Text))) {
        return;
    }

    // 写文件
    QTextStream textStream(&file);

    textStream << QCoreApplication::applicationFilePath() << endl << endl;

    textStream << gameTest->getKey() << endl << endl;

    if (isAiPlayer[BLACK]) {
        textStream << "Black:\tAI Player" << endl;
    } else {
        textStream << "Black:\tHuman Player" << endl;
    }

    if (isAiPlayer[WHITE]) {
        textStream << "White:\tAI Player" << endl;
    } else {
        textStream << "White:\tHuman Player" << endl;
    }

    textStream << "" << endl;

    position.nPlayed = position.score[BLACK] + position.score[WHITE] + position.score_draw;

    if (position.nPlayed == 0) {
        goto out;
    }

    textStream << "Sum\t" + QString::number(position.nPlayed) << endl;
    textStream << "Black\t" + QString::number(position.score[BLACK])  + "\t" + QString::number(position.score[BLACK] * 10000 / position.nPlayed) << endl;
    textStream << "White\t" + QString::number(position.score[WHITE]) + "\t" + QString::number(position.score[WHITE] * 10000 / position.nPlayed) << endl;
    textStream << "Draw\t" + QString::number(position.score_draw) + "\t" + QString::number(position.score_draw * 10000 / position.nPlayed)  << endl;

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
        return "黑方";
    } else {
        return "白方";
    }
}

void Game::appendGameOverReasonToCmdlist()
{
    if (position.phase != Phase::gameOver) {
        return;
    }

    char cmdline[64] = { 0 };
    switch (position.gameOverReason) {
    case GameOverReason::loseReasonNoWay:
        sprintf(cmdline, "Player%d no way to go. Player%d win!", position.sideToMove, position.winner);
        break;
    case GameOverReason::loseReasonTimeOver:
        sprintf(cmdline, "Time over. Player%d win!", position.winner);
        break;
    case GameOverReason::drawReasonThreefoldRepetition:
        sprintf(cmdline, "Threefold Repetition. Draw!");
        break;
    case GameOverReason::drawReasonRule50:
        sprintf(cmdline, "Steps over. In draw!");
        break;
    case GameOverReason::loseReasonBoardIsFull:
        sprintf(cmdline, "Player2 win!");
        break;
    case GameOverReason::drawReasonBoardIsFull:
        sprintf(cmdline, "Full. In draw!");
        break;
    case GameOverReason::loseReasonlessThanThree:
        sprintf(cmdline, "Player%d win!", position.winner);
        break;
    case GameOverReason::loseReasonResign:
        sprintf(cmdline, "Player%d give up!", ~position.winner);
        break;
    default:
        loggerDebug("No Game Over Reason");
        break;
    }

    loggerDebug("%s\n", cmdline);
    cmdlist.emplace_back(cmdline);
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
        tips = "轮到" + turnStr + "落子，剩余" + std::to_string(p.pieceCountInHand[BLACK]) + "子" +
            "  比分 " + to_string(p.score[BLACK]) + ":" + to_string(p.score[WHITE]) + ", 和棋 " + to_string(p.score_draw);
        break;

    case Phase::placing:
        if (p.action == Act::place) {
            tips = "轮到" + turnStr + "落子，剩余" + std::to_string(p.pieceCountInHand[p.sideToMove]) + "子";
        } else if (p.action == Act::remove) {
            tips = "成三！轮到" + turnStr + "去子，需去" + std::to_string(p.pieceCountNeedRemove) + "子";
        }
        break;

    case Phase::moving:
        if (p.action == Act::place || p.action == Act::select) {
            tips = "轮到" + turnStr + "选子移动";
        } else if (p.action == Act::remove) {
            tips = "成三！轮到" + turnStr + "去子，需去" + std::to_string(p.pieceCountNeedRemove) + "子";
        }
        break;

    case Phase::gameOver:
        appendGameOverReasonToCmdlist();

        scoreStr = "比分 " + to_string(p.score[BLACK]) + " : " + to_string(p.score[WHITE]) + ", 和棋 " + to_string(p.score_draw);        

        switch (p.winner) {
        case BLACK:
        case WHITE:
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
            reasonStr = turnStr + "无子可走被闷。";
            break;
        case GameOverReason::loseReasonResign:
            reasonStr = turnStr + "投子认负。";
            break;
        case GameOverReason::loseReasonTimeOver:
            reasonStr = turnStr + "超时判负。";
            break;
        case GameOverReason::drawReasonThreefoldRepetition:
            tips = "三次重复局面判和。";
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
