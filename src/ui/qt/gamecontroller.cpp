/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

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

GameController::GameController(GameScene & scene, QObject * parent) :
    QObject(parent),
    scene(scene),
    currentPiece(nullptr),
    currentRow(-1),
    isEditing(false),
    isInverted(false),
    hasAnimation(true),
    durationTime(500),
    hasSound(true),
    timeID(0),
    ruleNo_(-1),
    timeLimit(0),
    stepsLimit(50)
{
    // 已在view的样式表中添加背景，scene中不用添加背景
    // 区别在于，view中的背景不随视图变换而变换，scene中的背景随视图变换而变换
    //scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));
#ifdef MOBILE_APP_UI
    scene.setBackgroundBrush(QColor(239, 239, 239));
#endif /* MOBILE_APP_UI */

    isAiPlayer[1] = false,
    isAiPlayer[2] = false,

    ai[1] = new AiThread(1);
    ai[2] = new AiThread(2);

    gameReset();

    // 关联AI和控制器的着法命令行
    connect(ai[1], SIGNAL(command(const QString &, bool)),
            this, SLOT(command(const QString &, bool)));
    connect(ai[2], SIGNAL(command(const QString &, bool)),
            this, SLOT(command(const QString &, bool)));

    // 关联AI和网络类的着法命令行
    connect(ai[1]->getClient(), SIGNAL(command(const QString &, bool)),
            this, SLOT(command(const QString &, bool)));

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
    ai[1]->stop();
    ai[2]->stop();
    ai[1]->wait();
    ai[2]->wait();

    delete ai[1];
    delete ai[2];

#ifdef ENDGAME_LEARNING
    if (options.getLearnEndgameEnabled()) {
        AIAlgorithm::recordEndgameHashMapToFile();
    }
#endif /* ENDGAME_LEARNING */
}

const QMap<int, QStringList> GameController::getActions()
{
    // 主窗口更新菜单栏
    // 之所以不用信号和槽的模式，是因为发信号的时候槽还来不及关联
    QMap<int, QStringList> actions;

    for (int i = 0; i < N_RULES; i++) {
        // QMap的key存放int索引值，value存放规则名称和规则提示
        QStringList strlist;
        strlist.append(tr(RULES[i].name));
        strlist.append(tr(RULES[i].description));
        actions.insert(i, strlist);
    }

    return actions;
}

void GameController::gameStart()
{
    game_.start();
    tempGame = game_;

    // 每隔100毫秒调用一次定时器处理函数
    if (timeID == 0) {
        timeID = startTimer(100);
    }
}

void GameController::gameReset()
{
    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);

    // 定时器ID为0
    timeID = 0;

    // 棋未下完，则算对手得分
    if (game_.getPhase() == PHASE_MOVING &&
        game_.whoWin() == PLAYER_NOBODY) {
        giveUp();
    }

    // 重置游戏
    game_.reset();
    tempGame = game_;

    // 停掉线程
    if (!options.getAutoRestart()) {
        ai[1]->stop();
        ai[2]->stop();
        isAiPlayer[1] = false;
        isAiPlayer[2] = false;
    }

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

        pieceList.append(newP);
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

        pieceList.append(newP);
        scene.addItem(newP);
    }

    // 读取规则限时要求
    timeLimit = rule.maxTimeLedToLose;

    // 如果规则不要求计时，则time1和time2表示已用时间
    if (timeLimit <= 0) {
        // 将玩家的已用时间清零
        remainingTime[1] = remainingTime[2] = 0;
    } else {
        // 将玩家的剩余时间置为限定时间
        remainingTime[1] = remainingTime[2] = timeLimit * 60;
    }

    // 更新棋谱
    manualListModel.removeRows(0, manualListModel.rowCount());
    manualListModel.insertRow(0);
    manualListModel.setData(manualListModel.index(0), game_.getCmdLine());
    currentRow = 0;

    // 发出信号通知主窗口更新LCD显示
    QTime qtime = QTime(0, 0, 0, 0).addSecs(remainingTime[1]);
    emit time1Changed(qtime.toString("hh:mm:ss"));
    emit time2Changed(qtime.toString("hh:mm:ss"));

    // 发信号更新状态栏
    message = QString::fromStdString(game_.getTips());
    emit statusBarChanged(message);

    // 更新比分 LCD 显示
    emit score1Changed(QString::number(game_.score[1], 10));
    emit score2Changed(QString::number(game_.score[2], 10));
    emit scoreDrawChanged(QString::number(game_.score_draw, 10));

    // 播放音效
    //playSound(":/sound/resources/sound/newgame.wav");
}

void GameController::setEditing(bool arg)
{
    isEditing = arg;
}

void GameController::setInvert(bool arg)
{
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
}

void GameController::setRule(int ruleNo, step_t stepLimited /*= -1*/, int timeLimited /*= -1*/)
{
    // 更新规则，原限时和限步不变
    if (ruleNo < 0 || ruleNo >= N_RULES)
        return;
    this->ruleNo_ = ruleNo;

    if (stepLimited != UINT16_MAX && timeLimited != -1) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }

    // 设置模型规则，重置游戏
    game_.setPosition(&RULES[ruleNo], stepsLimit, timeLimit);
    tempGame = game_;

    // 重置游戏
    gameReset();
}

void GameController::setEngine(int id, bool arg)
{
    isAiPlayer[id] = arg;

    if (arg) {
        ai[id]->setAi(game_);
        if (ai[id]->isRunning())
            ai[id]->resume();
        else
            ai[id]->start();
    } else {
        ai[id]->stop();
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
    if (isAiPlayer[1]) {
        ai[1]->stop();
        ai[1]->wait();
    }
    if (isAiPlayer[2]) {
        ai[2]->stop();
        ai[2]->wait();
    }

    ai[1]->setAi(game_, depth1, time1);
    ai[2]->setAi(game_, depth2, time2);

    if (isAiPlayer[1]) {
        ai[1]->start();
    }
    if (isAiPlayer[2]) {
        ai[2]->start();
    }
}

void GameController::getAiDepthTime(depth_t &depth1, int &time1, depth_t &depth2, int &time2)
{
    depth1 = ai[1]->getDepth();
    time1 = ai[1]->getTimeLimit();

    depth2 = ai[2]->getDepth();
    time2 = ai[2]->getTimeLimit();
}

void GameController::setAnimation(bool arg)
{
    hasAnimation = arg;

    // 默认动画时间500ms
    if (hasAnimation)
        durationTime = 500;
    else
        durationTime = 0;
}

void GameController::setSound(bool arg)
{
    hasSound = arg;
}

void GameController::playSound(const QString &soundPath)
{
    if (soundPath == "") {
        return;
    }

#ifndef DONOT_PLAY_SOUND
    if (hasSound) {
        QSound::play(soundPath);
    }
#endif /* ! DONOT_PLAY_SOUND */
}

void GameController::setGiveUpIfMostLose(bool enabled)
{
    options.setGiveUpIfMostLose(enabled);
}

void GameController::setAutoRestart(bool enabled)
{
    options.setAutoRestart(enabled);
}

void GameController::setRandomMove(bool enabled)
{
    options.setRandomMoveEnabled(enabled);
}

void GameController::setLearnEndgame(bool enabled)
{
    options.setLearnEndgameEnabled(enabled);  
}

// 上下翻转
void GameController::flip()
{
    if (isAiPlayer[1]) {
        ai[1]->stop();
        ai[1]->wait();
    }
    if (isAiPlayer[2]) {
        ai[2]->stop();
        ai[2]->wait();
    }

    game_.position.board.mirror(game_.cmdlist, game_.cmdline, game_.move_, game_.currentLocation);
    game_.position.board.rotate(180, game_.cmdlist, game_.cmdline, game_.move_, game_.currentLocation);
    tempGame = game_;

    // 更新棋谱
    int row = 0;
    for (const auto &str : *(game_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    ai[1]->setAi(game_);
    ai[2]->setAi(game_);

    if (isAiPlayer[1]) {
        ai[1]->start();
    }

    if (isAiPlayer[2]) {
        ai[2]->start();
    }
}

// 左右镜像
void GameController::mirror()
{
    if (isAiPlayer[1]) {
        ai[1]->stop();
        ai[1]->wait();
    }
    if (isAiPlayer[2]) {
        ai[2]->stop();
        ai[2]->wait();
    }

    game_.position.board.mirror(game_.cmdlist, game_.cmdline, game_.move_, game_.currentLocation);
    tempGame = game_;

    // 更新棋谱
    int row = 0;

    for (const auto &str : *(game_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    loggerDebug("list: %d\n", row);

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    ai[1]->setAi(game_);
    ai[2]->setAi(game_);

    if (isAiPlayer[1]) {
        ai[1]->start();
    }

    if (isAiPlayer[2]) {
        ai[2]->start();
    }
}

// 视图须时针旋转90°
void GameController::turnRight()
{
    if (isAiPlayer[1]) {
        ai[1]->stop();
        ai[1]->wait();
    }
    if (isAiPlayer[2]) {
        ai[2]->stop();
        ai[2]->wait();
    }

    game_.position.board.rotate(-90, game_.cmdlist, game_.cmdline, game_.move_, game_.currentLocation);
    tempGame = game_;

    // 更新棋谱
    int row = 0;

    for (const auto &str : *(game_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        phaseChange(currentRow, true);

    ai[1]->setAi(game_);
    ai[2]->setAi(game_);

    if (isAiPlayer[1]) {
        ai[1]->start();
    }

    if (isAiPlayer[2]) {
        ai[2]->start();
    }
}

// 视图逆时针旋转90°
void GameController::turnLeft()
{
    if (isAiPlayer[1]) {
        ai[1]->stop();
        ai[1]->wait();
    }
    if (isAiPlayer[2]) {
        ai[2]->stop();
        ai[2]->wait();
    }

    game_.position.board.rotate(90, game_.cmdlist, game_.cmdline, game_.move_, game_.currentLocation);
    tempGame = game_;

    // 更新棋谱
    int row = 0;
    for (const auto &str : *(game_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    updateScence();

    ai[1]->setAi(game_);
    ai[2]->setAi(game_);
    if (isAiPlayer[1]) {
        ai[1]->start();
    }
    if (isAiPlayer[2]) {
        ai[2]->start();
    }
}

void GameController::timerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    static QTime qt1, qt2;

    // 玩家的已用时间
    game_.update();
    remainingTime[1] = game_.getElapsedTime(1);
    remainingTime[2] = game_.getElapsedTime(2);

    // 如果规则要求计时，则time1和time2表示倒计时
    if (timeLimit > 0) {
        // 玩家的剩余时间
        remainingTime[1] = timeLimit * 60 - remainingTime[1];
        remainingTime[2] = timeLimit * 60 - remainingTime[2];
    }

    qt1 = QTime(0, 0, 0, 0).addSecs(remainingTime[1]);
    qt2 = QTime(0, 0, 0, 0).addSecs(remainingTime[2]);

    emit time1Changed(qt1.toString("hh:mm:ss"));
    emit time2Changed(qt2.toString("hh:mm:ss"));

    // 如果胜负已分
    if (game_.whoWin() != PLAYER_NOBODY) {
        // 停止计时
        killTimer(timeID);

        // 定时器ID为0
        timeID = 0;

        // 发信号更新状态栏
        message = QString::fromStdString(game_.getTips());
        emit statusBarChanged(message);

        // 弹框
        //QMessageBox::about(NULL, "游戏结果", message);

        // 播放音效
#ifndef DONOT_PLAY_WIN_SOUND
        playSound(":/sound/resources/sound/win.wav");
#endif
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
    return isAiPlayer[game_.position.sideId];
}

// 关键槽函数，根据QGraphicsScene的信号和状态来执行选子、落子或去子
bool GameController::actionPiece(QPointF pos)
{
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
            game_ = tempGame;
            manualListModel.removeRows(currentRow + 1, manualListModel.rowCount() - currentRow - 1);

            // 如果再决出胜负后悔棋，则重新启动计时
            if (game_.whoWin() == PLAYER_NOBODY) {

                // 重新启动计时
                timeID = startTimer(100);

                // 发信号更新状态栏
                message = QString::fromStdString(game_.getTips());
                emit statusBarChanged(message);
#ifndef MOBILE_APP_UI
            }
        } else {
            return false;
#endif /* !MOBILE_APP_UI */
        }
    }

    // 如果未开局则开局
    if (game_.getPhase() == PHASE_NOTSTARTED)
        gameStart();

    // 判断执行选子、落子或去子
    bool result = false;
    PieceItem *piece = nullptr;
    QGraphicsItem *item = scene.itemAt(pos, QTransform());

    switch (game_.getAction()) {
    case ACTION_PLACE:
        if (game_._place(r, s)) {
            if (game_.getAction() == ACTION_CAPTURE) {
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
        if (game_.choose(r, s)) {
            // 播放选子音效
            playSound(":/sound/resources/sound/choose.wav");
            result = true;
        } else {
            // 播放禁止音效
            playSound(":/sound/resources/sound/forbidden.wav");
        }
        break;

    case ACTION_CAPTURE:
        if (game_._capture(r, s)) {
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
        message = QString::fromStdString(game_.getTips());
        emit statusBarChanged(message);

        // 将新增的棋谱行插入到ListModel
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;

        // 输出命令行        
        for (const auto & i : *(game_.getCmdList())) {
            // 跳过已添加的，因标准list容器没有下标
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), i.c_str());
        }

        // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
        if (game_.whoWin() != PLAYER_NOBODY &&
            (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over."))
            playSound(":/sound/resources/sound/win.wav");
#endif

        // AI设置
        if (&game_ == &(this->game_)) {
            // 如果还未决出胜负
            if (game_.whoWin() == PLAYER_NOBODY) {
                if (game_.position.sideToMove == PLAYER_1) {
                    if (isAiPlayer[1]) {
                        ai[1]->resume();
                    }
                    if (isAiPlayer[2])
                        ai[2]->pause();
                } else {
                    if (isAiPlayer[1])
                        ai[1]->pause();
                    if (isAiPlayer[2]) {
                        ai[2]->resume();
                    }
                }
            }
            // 如果已经决出胜负
            else {
                ai[1]->stop();
                ai[2]->stop();

                // 弹框
                //message = QString::fromStdString(game_.getTips());
                //QMessageBox::about(NULL, "游戏结果", message);
            }
        }
    }

    updateScence();
    return result;
}

bool GameController::giveUp()
{
    bool result = game_.giveup(game_.position.sideToMove);
        
    if (!result) {
        return false;
    }

    // 将新增的棋谱行插入到ListModel
    currentRow = manualListModel.rowCount() - 1;
    int k = 0;

    // 输出命令行
    for (const auto & i : *(game_.getCmdList())) {
        // 跳过已添加的，因标准list容器没有下标
        if (k++ <= currentRow)
            continue;
        manualListModel.insertRow(++currentRow);
        manualListModel.setData(manualListModel.index(currentRow), i.c_str());
    }

    if (game_.whoWin() != PLAYER_NOBODY)
        playSound(":/sound/resources/sound/loss.wav");

    return result;
}

// 关键槽函数，棋谱的命令行执行，与actionPiece独立
bool GameController::command(const QString &cmd, bool update /* = true */)
{
    Q_UNUSED(hasSound)

    // 防止接收滞后结束的线程发送的指令
    if (sender() == ai[1] && !isAiPlayer[1])
        return false;

    if (sender() == ai[2] && !isAiPlayer[2])
        return false;

    // 声音
    QString sound;

    switch (game_.getAction()) {
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

    // 如果未开局则开局
    if (game_.getPhase() == PHASE_NOTSTARTED) {
        gameStart();
    }

    if (!game_.command(cmd.toStdString().c_str()))
        return false;

    if (sound == ":/sound/resources/sound/drog.wav" && game_.getAction() == ACTION_CAPTURE) {
        sound = ":/sound/resources/sound/capture.wav";
    }

    if (update) {
        playSound(sound);
        updateScence(game_);
    }

    // 发信号更新状态栏
    message = QString::fromStdString(game_.getTips());
    emit statusBarChanged(message);

    // 对于新开局
    if (game_.getCmdList()->size() <= 1) {
        manualListModel.removeRows(0, manualListModel.rowCount());
        manualListModel.insertRow(0);
        manualListModel.setData(manualListModel.index(0), game_.getCmdLine());
        currentRow = 0;
    }
    // 对于当前局
    else {
        currentRow = manualListModel.rowCount() - 1;
        // 跳过已添加行,迭代器不支持+运算符,只能一个个++
        auto i = (game_.getCmdList()->begin());
        for (int r = 0; i != (game_.getCmdList())->end(); i++) {
            if (r++ > currentRow)
                break;
        }
        // 将新增的棋谱行插入到ListModel
        while (i != game_.getCmdList()->end()) {
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i++).c_str());
        }
    }

    // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
    if (game_.whoWin() != PLAYER_NOBODY &&
        (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over.")) {
        playSound(":/sound/resources/sound/win.wav");
    }
#endif

    // AI设置
    if (&game_ == &(this->game_)) {
        // 如果还未决出胜负
        if (game_.whoWin() == PLAYER_NOBODY) {
            if (game_.position.sideToMove == PLAYER_1) {
                if (isAiPlayer[1]) {
                    ai[1]->resume();
                }
                if (isAiPlayer[2])
                    ai[2]->pause();
            } else {
                if (isAiPlayer[1])
                    ai[1]->pause();
                if (isAiPlayer[2]) {
                    ai[2]->resume();
                }
            }
        }
        // 如果已经决出胜负
        else {           
                ai[1]->stop();
                ai[2]->stop();

                if (options.getAutoRestart()) {
                    gameReset();
                    gameStart();

                    if (isAiPlayer[1]) {
                        setEngine(1, true);
                    }
                    if (isAiPlayer[2]) {
                        setEngine(2, true);
                    }
                }

#ifdef MESSAGEBOX_ENABLE
            // 弹框
            message = QString::fromStdString(game_.getTips());
            QMessageBox::about(NULL, "游戏结果", message);
#endif
        }
    }

    // 网络: 将着法放到服务器的发送列表中
    if (isAiPlayer[1])
    {
        ai[1]->getServer()->setAction(cmd);
    } else if (isAiPlayer[2]) {
        ai[1]->getServer()->setAction(cmd);    // 注意: 同样是AI1
    }

    return true;
}

// 浏览历史局面，通过command函数刷新局面显示
bool GameController::phaseChange(int row, bool forceUpdate)
{
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
    tempGame.setStartTime(game_.getStartTimeb());

    // 刷新棋局场景
    updateScence(tempGame);

    return true;
}

bool GameController::updateScence()
{
    return updateScence(game_);
}

bool GameController::updateScence(Game &game)
{
    const int *board = game.getBoardLocations();
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
        key = (i % 2) ? (i / 2 + 0x21) : (i / 2 + 0x11);

        int j;

        // 遍历棋盘，查找并放置棋盘上的棋子
        for (j = Board::LOCATION_BEGIN; j < Board::LOCATION_END; j++) {
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
            if (key & 0x10) {
                pos = (key - 0x11 < nTotalPieces / 2 - game.getPiecesInHandCount(1)) ?
                        scene.pos_p2_g : scene.pos_p1;
            } else {
                pos = (key - 0x21 < nTotalPieces / 2 - game.getPiecesInHandCount(2)) ?
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
    if (rule.hasForbiddenLocations && game.getPhase() == PHASE_PLACING) {
        for (int j = Board::LOCATION_BEGIN; j < Board::LOCATION_END; j++) {
            if (board[j] == 0x0F) {
                pos = scene.rs2pos(j / Board::N_SEATS, j % Board::N_SEATS + 1);
                if (nTotalPieces < pieceList.size()) {
                    pieceList.at(nTotalPieces++)->setPos(pos);
                } else {
                    auto *newP = new PieceItem;
                    newP->setDeleted();
                    newP->setPos(pos);
                    pieceList.append(newP);
                    nTotalPieces++;
                    scene.addItem(newP);
                }
            }
        }
    }

    // 走棋阶段清除禁子点
    if (rule.hasForbiddenLocations && game.getPhase() != PHASE_PLACING) {
        while (nTotalPieces < pieceList.size()) {
            delete pieceList.at(nTotalPieces);
            pieceList.removeAt(nTotalPieces);
        }
    }

    // 选中当前棋子
    int ipos = game.getCurrentLocation();
    if (ipos) {
        key = board[game.getCurrentLocation()];
        ipos = key & 0x10 ? (key - 0x11) * 2 : (key - 0x21) * 2 + 1;
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
    emit score1Changed(QString::number(game.score[1], 10));
    emit score2Changed(QString::number(game.score[2], 10));
    emit scoreDrawChanged(QString::number(game.score_draw, 10));

    return true;
}

void GameController::showNetworkWindow()
{
    ai[1]->getServer()->show();
    ai[1]->getClient()->show();
}
