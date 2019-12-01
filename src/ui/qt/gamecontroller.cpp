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
#include "gamecontroller.h"
#include "graphicsconst.h"
#include "boarditem.h"
#include "server.h"
#include "client.h"
#include "option.h"

using namespace std;

GameController::GameController(
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
    hasSound(true),
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

    // 关联AI和控制器的着法命令行
    connect(aiThread[BLACK], SIGNAL(command(const QString &, bool)),
            this, SLOT(command(const QString &, bool)));
    connect(aiThread[WHITE], SIGNAL(command(const QString &, bool)),
            this, SLOT(command(const QString &, bool)));

#ifndef TRAINING_MODE
    // 关联AI和网络类的着法命令行
    connect(aiThread[BLACK]->getClient(), SIGNAL(command(const QString &, bool)),
            this, SLOT(command(const QString &, bool)));
#endif // TRAINING_MODE

    // 安装事件过滤器监视scene的各个事件，
    // 由于我重载了QGraphicsScene，相关事件在重载函数中已设定，不必安装监视器。
    //scene.installEventFilter(this);    
}

GameController::~GameController()
{
    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);

    // 停掉线程
    stopAndWaitThreads();
    deleteAiThreads();

#ifdef ENDGAME_LEARNING
    if (options.getLearnEndgameEnabled()) {
        AIAlgorithm::recordEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */
}

const map<int, QStringList> GameController::getActions()
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


void GameController::gameStart()
{
    game.start();
    tempGame = game;

    // 每隔100毫秒调用一次定时器处理函数
    if (timeID == 0) {
        timeID = startTimer(100);
    }

    gameStartTime = now();
    gameStartCycle = stopwatch::rdtscp_clock::now();
}

void GameController::gameReset()
{
    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);

    // 定时器ID为0
    timeID = 0;

    // 棋未下完，则算对手得分
    if (game.getPhase() == PHASE_MOVING &&
        game.whoWin() == PLAYER_NOBODY) {
        giveUp();
    }

    // 重置游戏
    game.reset();
    tempGame = game;

    // 停掉线程
    if (!gameOptions.getAutoRestart()) {
        stopThreads();
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
    // 2：先手嫡2子； 3：后手第2子
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

        // 如果重复三连不可用，则显示棋子序号，九连棋专用玩法
        if (!(rule.allowRemovePiecesRepeatedly))
            newP->setShowNum(true);

        pieceList.push_back(newP);
        scene.addItem(newP);

        // 后手的棋子
        md = isInverted ? PieceItem::blackPiece : PieceItem::whitePiece;
        newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p2);
        newP->setNum(i + 1);

        // 如果重复三连不可用，则显示棋子序号，九连棋专用玩法
        if (!(rule.allowRemovePiecesRepeatedly))
            newP->setShowNum(true);

        pieceList.push_back(newP);
        scene.addItem(newP);
    }

    // 读取规则限时要求
    timeLimit = rule.maxTimeLedToLose;

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
    manualListModel.setData(manualListModel.index(0), game.getCmdLine());
    currentRow = 0;

    // 发出信号通知主窗口更新LCD显示
    QTime qtime = QTime(0, 0, 0, 0).addSecs(remainingTime[BLACK]);
    emit time1Changed(qtime.toString("hh:mm:ss"));
    emit time2Changed(qtime.toString("hh:mm:ss"));

    // 发信号更新状态栏
    message = QString::fromStdString(game.getTips());
    emit statusBarChanged(message);

    // 更新比分 LCD 显示
    emit score1Changed(QString::number(game.score[BLACK], 10));
    emit score2Changed(QString::number(game.score[WHITE], 10));
    emit scoreDrawChanged(QString::number(game.score_draw, 10));

    // 播放音效
    //playSound(":/sound/resources/sound/newgame.wav");
#endif // TRAINING_MODE
}

void GameController::setEditing(bool arg)
{
#ifndef TRAINING_MODE
    isEditing = arg;
#endif
}

void GameController::setInvert(bool arg)
{
#ifndef TRAINING_MODE
    isInverted = arg;

    // 遍历所有棋子
    for (PieceItem *p : pieceList) {
        if (p) {
            // 黑子变白
            if (p->getModel() == PieceItem::blackPiece)
                p->setModel(PieceItem::whitePiece);

            // 白子变黑
            else if (p->getModel() == PieceItem::whitePiece)
                p->setModel(PieceItem::blackPiece);

            // 刷新棋子显示
            p->update();
        }
    }
#endif // TRAINING_MODE
}

void GameController::setRule(int ruleNo, step_t stepLimited /*= -1*/, int timeLimited /*= -1*/)
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
    game.setPosition(&RULES[ruleNo]);
    tempGame = game;

    // 重置游戏
    gameReset();
}

void GameController::setEngine(int id, bool arg)
{
    isAiPlayer[id] = arg;

    if (arg) {
        aiThread[id]->setAi(game);
        if (aiThread[id]->isRunning())
            aiThread[id]->resume();
        else
            aiThread[id]->start();
    } else {
        aiThread[id]->stop();
    }
}

void GameController::setEngine1(bool arg)
{
    setEngine(1, arg);
}

void GameController::setEngine2(bool arg)
{
    setEngine(2, arg);
}

void GameController::setAiDepthTime(depth_t depth1, int time1, depth_t depth2, int time2)
{
    stopAndWaitAiThreads();

    aiThread[BLACK]->setAi(game, depth1, time1);
    aiThread[WHITE]->setAi(game, depth2, time2);

    startAiThreads();
}

void GameController::getAiDepthTime(depth_t &depth1, int &time1, depth_t &depth2, int &time2)
{
    depth1 = aiThread[BLACK]->getDepth();
    time1 = aiThread[BLACK]->getTimeLimit();

    depth2 = aiThread[WHITE]->getDepth();
    time2 = aiThread[WHITE]->getTimeLimit();
}

void GameController::setAnimation(bool arg)
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

void GameController::setSound(bool arg)
{
#ifndef TRAINING_MODE
    hasSound = arg;
#endif // TRAINING_MODE
}

void GameController::playSound(const QString &soundPath)
{
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

void GameController::setGiveUpIfMostLose(bool enabled)
{
    gameOptions.setGiveUpIfMostLose(enabled);
}

void GameController::setAutoRestart(bool enabled)
{
    gameOptions.setAutoRestart(enabled);
}

void GameController::setRandomMove(bool enabled)
{
    gameOptions.setRandomMoveEnabled(enabled);
}

void GameController::setLearnEndgame(bool enabled)
{
    gameOptions.setLearnEndgameEnabled(enabled);
}

// 上下翻转
void GameController::flip()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    game.position.board.mirror(game.cmdlist, game.cmdline, game.move, game.currentSquare);
    game.position.board.rotate(180, game.cmdlist, game.cmdline, game.move, game.currentSquare);
    tempGame = game;

    // 更新棋谱
    int row = 0;
    for (const auto &str : *(game.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    threadsSetAi(game);
    startAiThreads();
#endif // TRAINING_MODE
}

// 左右镜像
void GameController::mirror()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    game.position.board.mirror(game.cmdlist, game.cmdline, game.move, game.currentSquare);
    tempGame = game;

    // 更新棋谱
    int row = 0;

    for (const auto &str : *(game.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    loggerDebug("list: %d\n", row);

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    threadsSetAi(game);
    startAiThreads();
#endif // TRAINING_MODE
}

// 视图须时针旋转90°
void GameController::turnRight()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    game.position.board.rotate(-90, game.cmdlist, game.cmdline, game.move, game.currentSquare);
    tempGame = game;

    // 更新棋谱
    int row = 0;

    for (const auto &str : *(game.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    threadsSetAi(game);
    startAiThreads();
#endif
}

// 视图逆时针旋转90°
void GameController::turnLeft()
{
#ifndef TRAINING_MODE
    stopAndWaitAiThreads();

    game.position.board.rotate(90, game.cmdlist, game.cmdline, game.move, game.currentSquare);
    tempGame = game;

    // 更新棋谱
    int row = 0;
    for (const auto &str : *(game.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    updateScence();

    threadsSetAi(game);
    startAiThreads();
#endif // TRAINING_MODE
}

void GameController::timerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    static QTime qt1, qt2;

    // 玩家的已用时间
    game.update();
    remainingTime[BLACK] = game.getElapsedTime(BLACK);
    remainingTime[WHITE] = game.getElapsedTime(WHITE);

    // 如果规则要求计时，则time1和time2表示倒计时
    if (timeLimit > 0) {
        // 玩家的剩余时间
        remainingTime[BLACK] = timeLimit * 60 - remainingTime[BLACK];
        remainingTime[WHITE] = timeLimit * 60 - remainingTime[WHITE];
    }

    qt1 = QTime(0, 0, 0, 0).addSecs(remainingTime[BLACK]);
    qt2 = QTime(0, 0, 0, 0).addSecs(remainingTime[WHITE]);

    emit time1Changed(qt1.toString("hh:mm:ss"));
    emit time2Changed(qt2.toString("hh:mm:ss"));

    // 如果胜负已分
    if (game.whoWin() != PLAYER_NOBODY) {
        // 停止计时
        killTimer(timeID);

        // 定时器ID为0
        timeID = 0;

#ifndef TRAINING_MODE
        // 发信号更新状态栏
        message = QString::fromStdString(game.getTips());
        emit statusBarChanged(message);

        // 弹框
        //QMessageBox::about(NULL, "游戏结果", message);

        // 播放音效
#ifndef DONOT_PLAY_WIN_SOUND
        playSound(":/sound/resources/sound/win.wav");
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

bool GameController::isAIsTurn()
{
    return isAiPlayer[game.position.sideId];
}

// 关键槽函数，根据QGraphicsScene的信号和状态来执行选子、落子或去子
bool GameController::actionPiece(QPointF pos)
{
#ifndef TRAINING_MODE
    // 点击非落子点，不执行
    int r, s;
    if (!scene.pos2rs(pos, r, s)) {
        return false;
    }

    // 电脑走棋时，点击无效
    if (isAIsTurn()) {
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
        msgBox.setInformativeText(tr("是否在此局面下重新开始？悔棋者将承担时间损失！"));
        msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
        msgBox.setDefaultButton(QMessageBox::Cancel);
        (msgBox.button(QMessageBox::Ok))->setText(tr("确定"));
        (msgBox.button(QMessageBox::Cancel))->setText(tr("取消"));

        if (QMessageBox::Ok == msgBox.exec()) {
#endif /* !MOBILE_APP_UI */
            game = tempGame;
            manualListModel.removeRows(currentRow + 1, manualListModel.rowCount() - currentRow - 1);

            // 如果再决出胜负后悔棋，则重新启动计时
            if (game.whoWin() == PLAYER_NOBODY) {

                // 重新启动计时
                timeID = startTimer(100);

                // 发信号更新状态栏
                message = QString::fromStdString(game.getTips());
                emit statusBarChanged(message);
#ifndef MOBILE_APP_UI
            }
        } else {
            return false;
#endif /* !MOBILE_APP_UI */
        }
    }

    // 如果未开局则开局
    if (game.getPhase() == PHASE_READY)
        gameStart();

    // 判断执行选子、落子或去子
    bool result = false;
    PieceItem *piece = nullptr;
    QGraphicsItem *item = scene.itemAt(pos, QTransform());

    switch (game.getAction()) {
    case ACTION_PLACE:
        if (game._place(r, s)) {
            if (game.getAction() == ACTION_CAPTURE) {
                // 播放成三音效
                playSound(":/sound/resources/sound/capture.wav");
            } else {
                // 播放移动棋子音效
                playSound(":/sound/resources/sound/drog.wav");
            }
            result = true;
            break;
        }

     // 如果移子不成功，尝试重新选子，这里不break
        [[fallthrough]];

    case ACTION_CHOOSE:
        piece = qgraphicsitem_cast<PieceItem *>(item);
        if (!piece)
            break;
        if (game.choose(r, s)) {
            // 播放选子音效
            playSound(":/sound/resources/sound/choose.wav");
            result = true;
        } else {
            // 播放禁止音效
            playSound(":/sound/resources/sound/forbidden.wav");
        }
        break;

    case ACTION_CAPTURE:
        if (game._capture(r, s)) {
            // 播放音效
            playSound(":/sound/resources/sound/remove.wav");
            result = true;
        } else {
            // 播放禁止音效
            playSound(":/sound/resources/sound/forbidden.wav");
        }
        break;

    default:
        // 如果是结局状态，不做任何响应
        break;
    }

    if (result) {
        // 发信号更新状态栏
        message = QString::fromStdString(game.getTips());
        emit statusBarChanged(message);

        // 将新增的棋谱行插入到ListModel
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;

        // 输出命令行        
        for (const auto & i : *(game.getCmdList())) {
            // 跳过已添加的，因标准list容器没有下标
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), i.c_str());
        }

        // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
        if (game.whoWin() != PLAYER_NOBODY &&
            (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over."))
            playSound(":/sound/resources/sound/win.wav");
#endif

        // AI设置
        // 如果还未决出胜负
        if (game.whoWin() == PLAYER_NOBODY) {
            resumeAiThreads(game.position.sideToMove);
        }
        // 如果已经决出胜负
        else {
            stopThreads();
        }
    }

    updateScence();
    return result;
#else
    return true;
#endif // TRAINING_MODE
}


bool GameController::giveUp()
{
    bool result = game.giveup(game.position.sideToMove);
        
    if (!result) {
        return false;
    }

#ifndef TRAINING_MODE

    // 将新增的棋谱行插入到ListModel
    currentRow = manualListModel.rowCount() - 1;
    int k = 0;

    // 输出命令行
    for (const auto & i : *(game.getCmdList())) {
        // 跳过已添加的，因标准list容器没有下标
        if (k++ <= currentRow)
            continue;
        manualListModel.insertRow(++currentRow);
        manualListModel.setData(manualListModel.index(currentRow), i.c_str());
    }

    if (game.whoWin() != PLAYER_NOBODY)
        playSound(":/sound/resources/sound/loss.wav");

#endif // TRAINING_MODE

    return result;
}

// 关键槽函数，棋谱的命令行执行，与actionPiece独立
bool GameController::command(const QString &cmd, bool update /* = true */)
{
#ifndef TRAINING_MODE
    Q_UNUSED(hasSound)
#endif

    // 防止接收滞后结束的线程发送的指令
    if (sender() == aiThread[BLACK] && !isAiPlayer[BLACK])
        return false;

    if (sender() == aiThread[WHITE] && !isAiPlayer[WHITE])
        return false;

#ifndef TRAINING_MODE
    // 声音
    QString sound;

    switch (game.getAction()) {
    case ACTION_CHOOSE:
    case ACTION_PLACE:
        sound = ":/sound/resources/sound/drog.wav";
        break;
    case ACTION_CAPTURE:
        sound = ":/sound/resources/sound/remove.wav";
        break;
    default:
        break;
    }
#endif

    // 如果未开局则开局
    if (game.getPhase() == PHASE_READY) {
        gameStart();
    }

    if (!game.command(cmd.toStdString().c_str()))
        return false;

#ifndef TRAINING_MODE
    if (sound == ":/sound/resources/sound/drog.wav" && game.getAction() == ACTION_CAPTURE) {
        sound = ":/sound/resources/sound/capture.wav";
    }

    if (update) {
        playSound(sound);
        updateScence(game);
    }

    // 发信号更新状态栏
    message = QString::fromStdString(game.getTips());
    emit statusBarChanged(message);

    // 对于新开局
    if (game.getCmdList()->size() <= 1) {
        manualListModel.removeRows(0, manualListModel.rowCount());
        manualListModel.insertRow(0);
        manualListModel.setData(manualListModel.index(0), game.getCmdLine());
        currentRow = 0;
    }
    // 对于当前局
    else {
        currentRow = manualListModel.rowCount() - 1;
        // 跳过已添加行,迭代器不支持+运算符,只能一个个++
        auto i = (game.getCmdList()->begin());
        for (int r = 0; i != (game.getCmdList())->end(); i++) {
            if (r++ > currentRow)
                break;
        }
        // 将新增的棋谱行插入到ListModel
        while (i != game.getCmdList()->end()) {
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i++).c_str());
        }
    }

    // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
    if (game.whoWin() != PLAYER_NOBODY &&
        (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over.")) {
        playSound(":/sound/resources/sound/win.wav");
    }
#endif
#endif // TRAINING_MODE

    // AI设置
    // 如果还未决出胜负
    if (game.whoWin() == PLAYER_NOBODY) {
        resumeAiThreads(game.position.sideToMove);
    }
    // 如果已经决出胜负
    else {           
            stopThreads();

            gameEndTime = now();
            gameDurationTime = gameEndTime - gameStartTime;

            gameEndCycle = stopwatch::rdtscp_clock::now();

            loggerDebug("Game Duration Time: %lldms\n", gameDurationTime);

#ifdef TIME_STAT
            loggerDebug("Sort Time: %ld + %ld = %ldms\n",
                        aiThread[BLACK]->ai.sortTime, aiThread[WHITE]->ai.sortTime,
                        (aiThread[BLACK]->ai.sortTime + aiThread[WHITE]->ai.sortTime));
            aiThread[BLACK]->ai.sortTime = aiThread[WHITE]->ai.sortTime = 0;
#endif // TIME_STAT
#ifdef CYCLE_STAT
            loggerDebug("Sort Cycle: %ld + %ld = %ld\n",
                        aiThread[BLACK]->ai.sortCycle, aiThread[WHITE]->ai.sortCycle,
                        (aiThread[BLACK]->ai.sortCycle + aiThread[WHITE]->ai.sortCycle));
            aiThread[BLACK]->ai.sortCycle = aiThread[WHITE]->ai.sortCycle = 0;
#endif // CYCLE_STAT

#if 0
            gameDurationCycle = gameEndCycle - gameStartCycle;
            loggerDebug("Game Start Cycle: %u\n", gameStartCycle);
            loggerDebug("Game End Cycle: %u\n", gameEndCycle);
            loggerDebug("Game Duration Cycle: %u\n", gameDurationCycle);
#endif

#ifdef TRANSPOSITION_TABLE_DEBUG                
            size_t hashProbeCount_1 = aiThread[BLACK]->ai.hashHitCount + aiThread[BLACK]->ai.hashMissCount;
            size_t hashProbeCount_2 = aiThread[WHITE]->ai.hashHitCount + aiThread[WHITE]->ai.hashMissCount;
                
            loggerDebug("[hash 1] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_1,
                        aiThread[BLACK]->ai.hashHitCount,
                        aiThread[BLACK]->ai.hashMissCount,
                        aiThread[BLACK]->ai.hashHitCount * 100 / hashProbeCount_1);

            loggerDebug("[hash 2] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_2,
                        aiThread[WHITE]->ai.hashHitCount,
                        aiThread[WHITE]->ai.hashMissCount,
                        aiThread[WHITE]->ai.hashHitCount * 100 / hashProbeCount_2);

            loggerDebug("[hash +] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
                        hashProbeCount_1 + hashProbeCount_2,
                        aiThread[BLACK]->ai.hashHitCount + aiThread[WHITE]->ai.hashHitCount,
                        aiThread[BLACK]->ai.hashMissCount + aiThread[WHITE]->ai.hashMissCount,
                        (aiThread[BLACK]->ai.hashHitCount + aiThread[WHITE]->ai.hashHitCount ) * 100 / (hashProbeCount_1 + hashProbeCount_2));
#endif // TRANSPOSITION_TABLE_DEBUG

            if (gameOptions.getAutoRestart()) {
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
        message = QString::fromStdString(game.getTips());
        QMessageBox::about(NULL, "游戏结果", message);
#endif
    }

#ifndef TRAINING_MODE
    // 网络: 将着法放到服务器的发送列表中
    if (isAiPlayer[BLACK]) {
        aiThread[BLACK]->getServer()->setAction(cmd);
    } else if (isAiPlayer[WHITE]) {
        aiThread[BLACK]->getServer()->setAction(cmd);    // 注意: 同样是AI1
    }
#endif // TRAINING_MODE

    return true;
}

// 浏览历史局面，通过command函数刷新局面显示
bool GameController::phaseChange(int row, bool forceUpdate)
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
        tempGame.command(mlist.at(i).toStdString().c_str());
    }

    // 下面这步关键，会让悔棋者承担时间损失
    tempGame.setStartTime(game.getStartTimeb());

    // 刷新棋局场景
    updateScence(tempGame);
#endif // TRAINING_MODE

    return true;
}

bool GameController::updateScence()
{
#ifndef TRAINING_MODE
    return updateScence(game);
#else
    return true;
#endif
}

bool GameController::updateScence(Game &g)
{
#ifndef TRAINING_MODE
    const location_t *board = g.getBoardLocations();
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
        piece = pieceList.at(i);

        piece->setSelected(false);

        // 将pieceList的下标转换为game的棋子代号
        key = (i % 2) ? (i / 2 + PIECE_W1) : (i / 2 + PIECE_B1);

        int j;

        // 遍历棋盘，查找并放置棋盘上的棋子
        for (j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == key) {
                pos = scene.rs2pos(j / Board::N_SEATS, j % Board::N_SEATS + 1);
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
        if (j == (Board::N_SEATS) * (Board::N_RINGS + 1)) {
            // 判断是被吃掉的子，还是未安放的子
            if (key & PIECE_BLACK) {
                pos = (key - 0x11 < nTotalPieces / 2 - g.getPiecesInHandCount(BLACK)) ?
                        scene.pos_p2_g : scene.pos_p1;
            } else {
                pos = (key - 0x21 < nTotalPieces / 2 - g.getPiecesInHandCount(WHITE)) ?
                        scene.pos_p1_g : scene.pos_p2;
            }

            if (piece->pos() != pos) {
                // 为了对最近移除的棋子置为选择状态作准备
                deletedPiece = piece;

#ifdef GAME_PLACING_SHOW_CAPTURED_PIECES
                if (game.getPhase() == GAME_MOVING) {
#endif
                    QPropertyAnimation *animation = new QPropertyAnimation(piece, "pos");
                    animation->setDuration(durationTime);
                    animation->setStartValue(piece->pos());
                    animation->setEndValue(pos);
                    animation->setEasingCurve(QEasingCurve::InOutQuad);
                    animationGroup->addAnimation(animation);
#ifdef GAME_PLACING_SHOW_CAPTURED_PIECES
                }
#endif
            }
        }

        piece->setSelected(false);
    }

    // 添加摆棋阶段禁子点
    if (rule.hasForbiddenLocations && g.getPhase() == PHASE_PLACING) {
        for (int j = SQ_BEGIN; j < SQ_END; j++) {
            if (board[j] == PIECE_FORBIDDEN) {
                pos = scene.rs2pos(j / Board::N_SEATS, j % Board::N_SEATS + 1);
                if (nTotalPieces < pieceList.size()) {
                    pieceList.at(nTotalPieces++)->setPos(pos);
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
    if (rule.hasForbiddenLocations && g.getPhase() != PHASE_PLACING) {
        while (nTotalPieces < pieceList.size()) {
            delete pieceList.at(pieceList.size() - 1);
            pieceList.pop_back();
        }
    }

    // 选中当前棋子
    int ipos = g.getCurrentSquare();
    if (ipos) {
        key = board[g.getCurrentSquare()];
        ipos = key & PIECE_BLACK ? (key - PIECE_B1) * 2 : (key - PIECE_W1) * 2 + 1;
        if (ipos >= 0 && ipos < nTotalPieces) {
            currentPiece = pieceList.at(ipos);
            currentPiece->setSelected(true);
        }
    }

    // 对最近移除的棋子置为选择状态
    if (deletedPiece) {
        deletedPiece->setSelected(true);
    }

    animationGroup->start(QAbstractAnimation::DeleteWhenStopped);

    // 更新比分 LCD 显示
    emit score1Changed(QString::number(g.score[BLACK], 10));
    emit score2Changed(QString::number(g.score[WHITE], 10));
    emit scoreDrawChanged(QString::number(g.score_draw, 10));
#endif  TRAINING_MODE
    return true;
}

void GameController::showNetworkWindow()
{
#ifndef TRAINING_MODE
    aiThread[BLACK]->getServer()->show();
    aiThread[BLACK]->getClient()->show();
#endif // TRAINING_MODE
}
