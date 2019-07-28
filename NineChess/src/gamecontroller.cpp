/*****************************************************************************
 * Copyright (C) 2018-2019 NineChess authors
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

#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

#include <QGraphicsView>
#include <QGraphicsSceneMouseEvent>
#include <QKeyEvent>
#include <QApplication>
#include <QTimer>
#include <QSound>
#include <QDebug>
#include <QMessageBox>
#include <QAbstractButton>
#include <QPropertyAnimation>
#include <QParallelAnimationGroup>
#include "gamecontroller.h"
#include "graphicsconst.h"
#include "boarditem.h"
#include "server.h"
#include "client.h"

GameController::GameController(GameScene & scene, QObject * parent) :
    QObject(parent),
    scene(scene),
    currentPiece(nullptr),
    currentRow(-1),
    isEditing(false),
    isInverted(false),
    isEngine1(false),
    isEngine2(false),
    hasAnimation(true),
    durationTime(500),
    hasSound(true),
    timeID(0),
    ruleNo_(-1),
    timeLimit(0),
    stepsLimit(50),
    ai1(1),
    ai2(2),
    score1(-2),
    score2(-2)
{
    // 已在view的样式表中添加背景，scene中不用添加背景
    // 区别在于，view中的背景不随视图变换而变换，scene中的背景随视图变换而变换
    //scene.setBackgroundBrush(QPixmap(":/image/resources/image/background.png"));

    gameReset();

    // 关联AI和控制器的着法命令行
    connect(&ai1, SIGNAL(command(const QString &, bool)),
            this, SLOT(command(const QString &, bool)));
    connect(&ai2, SIGNAL(command(const QString &, bool)),
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
    ai1.stop();
    ai2.stop();
    ai1.wait();
    ai2.wait();

#ifdef BOOK_LEARNING
    NineChessAi_ab::recordOpeningBookHashMapToFile();
#endif /* BOOK_LEARNING */
}

const QMap<int, QStringList> GameController::getActions()
{
    // 主窗口更新菜单栏
    // 之所以不用信号和槽的模式，是因为发信号的时候槽还来不及关联
    QMap<int, QStringList> actions;

    for (int i = 0; i < NineChess::N_RULES; i++) {
        // QMap的key存放int索引值，value存放规则名称和规则提示
        QStringList strlist;
        strlist.append(tr(NineChess::RULES[i].name));
        strlist.append(tr(NineChess::RULES[i].description));
        actions.insert(i, strlist);
    }

    return actions;
}

void GameController::gameStart()
{
    chess_.start();
    chessTemp = chess_;

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
    if (score1 < 0 || score2 < 0) {
        score1++;
        score2++;
    }
    else {
        if (chess_.getStage() == NineChess::GAME_MOVING &&
            chess_.whoWin() == NineChess::NOBODY)
        {
            giveUp();
        }
    }

    emit time1Changed(QString::number(score1, 10));
    emit time2Changed(QString::number(score2, 10));

    // 重置游戏
    chess_.reset();
    chessTemp = chess_;

    // 停掉线程
    ai1.stop();
    ai2.stop();
    isEngine1 = false;
    isEngine2 = false;

    // 清除棋子
    qDeleteAll(pieceList);
    pieceList.clear();
    currentPiece = nullptr;

    // 重新绘制棋盘
    scene.setDiagonal(chess_.getRule()->hasObliqueLines);

    // 绘制所有棋子，放在起始位置
    // 0: 先手第1子； 1：后手第1子
    // 2：先手嫡2子； 3：后手第2子
    // ......
    PieceItem::Models md;
    PieceItem *newP;

    for (int i = 0; i < chess_.getRule()->nTotalPiecesEachSide; i++) {
        // 先手的棋子
        md = isInverted ? PieceItem::whitePiece : PieceItem::blackPiece;
        newP = new PieceItem;
        newP->setModel(md);
        newP->setPos(scene.pos_p1);
        newP->setNum(i + 1);

        // 如果重复三连不可用，则显示棋子序号，九连棋专用玩法
        if (!(chess_.getRule()->allowRemovePiecesRepeatedly))
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
        if (!(chess_.getRule()->allowRemovePiecesRepeatedly))
            newP->setShowNum(true);

        pieceList.append(newP);
        scene.addItem(newP);
    }

    // 读取规则限时要求
    timeLimit = chess_.getRule()->maxTimeLedToLose;

    // 如果规则不要求计时，则time1和time2表示已用时间
    if (timeLimit <= 0) {
        // 将玩家的已用时间清零
        remainingTime1 = remainingTime2 = 0;
    } else {
        // 将玩家的剩余时间置为限定时间
        remainingTime1 = remainingTime2 = timeLimit * 60000;
    }

    // 更新棋谱
    manualListModel.removeRows(0, manualListModel.rowCount());
    manualListModel.insertRow(0);
    manualListModel.setData(manualListModel.index(0), chess_.getCmdLine());
    currentRow = 0;

    // 发出信号通知主窗口更新LCD显示
    //QTime qtime = QTime(0, 0, 0, 0).addMSecs(remainingTime1);
    //emit time1Changed(qtime.toString("mm:ss.zzz"));
    //emit time2Changed(qtime.toString("mm:ss.zzz"));

    // 发信号更新状态栏
    message = QString::fromStdString(chess_.getTips());
    emit statusBarChanged(message);

    // 播放音效
    playSound(":/sound/resources/sound/newgame.wav");
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

void GameController::setRule(int ruleNo, int stepLimited /*= -1*/, int timeLimited /*= -1*/)
{
    // 更新规则，原限时和限步不变
    if (ruleNo < 0 || ruleNo >= NineChess::N_RULES)
        return;
    this->ruleNo_ = ruleNo;

    if (stepLimited != -1 && timeLimited != -1) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }

    // 设置模型规则，重置游戏
    chess_.setContext(&NineChess::RULES[ruleNo], stepsLimit, timeLimit);
    chessTemp = chess_;

    // 重置游戏
    gameReset();
}

void GameController::setEngine1(bool arg)
{
    isEngine1 = arg;
    if (arg) {
        ai1.setAi(chess_);
        if (ai1.isRunning())
            ai1.resume();
        else
            ai1.start();
    } else {
        ai1.stop();
    }
}

void GameController::setEngine2(bool arg)
{
    isEngine2 = arg;
    if (arg) {
        ai2.setAi(chess_);
        if (ai2.isRunning())
            ai2.resume();
        else
            ai2.start();
    } else {
        ai2.stop();
    }
}

void GameController::setAiDepthTime(int depth1, int time1, int depth2, int time2)
{
    if (isEngine1) {
        ai1.stop();
        ai1.wait();
    }
    if (isEngine2) {
        ai2.stop();
        ai2.wait();
    }

    ai1.setAi(chess_, depth1, time1);
    ai2.setAi(chess_, depth2, time2);

    if (isEngine1) {
        ai1.start();
    }
    if (isEngine2) {
        ai2.start();
    }
}

void GameController::getAiDepthTime(int &depth1, int &time1, int &depth2, int &time2)
{
    ai1.getDepthTime(depth1, time1);
    ai2.getDepthTime(depth2, time2);
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
#ifndef DONOT_PLAY_SOUND
    if (hasSound) {
        QSound::play(soundPath);
    }
#else
    soundPath;  // 为消除变量未使用过的警告
#endif /* ! DONOT_PLAY_SOUND */
}

// 上下翻转
void GameController::flip()
{
    if (isEngine1) {
        ai1.stop();
        ai1.wait();
    }
    if (isEngine2) {
        ai2.stop();
        ai2.wait();
    }

    chess_.mirror();
    chess_.rotate(180);
    chessTemp = chess_;

    // 更新棋谱
    int row = 0;
    for (auto str : *(chess_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        stageChange(currentRow, true);

    ai1.setAi(chess_);
    ai2.setAi(chess_);

    if (isEngine1) {
        ai1.start();
    }

    if (isEngine2) {
        ai2.start();
    }
}

// 左右镜像
void GameController::mirror()
{
    if (isEngine1) {
        ai1.stop();
        ai1.wait();
    }
    if (isEngine2) {
        ai2.stop();
        ai2.wait();
    }

    chess_.mirror();
    chessTemp = chess_;

    // 更新棋谱
    int row = 0;

    for (auto str : *(chess_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    qDebug() << "list: " << row;

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        stageChange(currentRow, true);

    ai1.setAi(chess_);
    ai2.setAi(chess_);

    if (isEngine1) {
        ai1.start();
    }

    if (isEngine2) {
        ai2.start();
    }
}

// 视图须时针旋转90°
void GameController::turnRight()
{
    if (isEngine1) {
        ai1.stop();
        ai1.wait();
    }
    if (isEngine2) {
        ai2.stop();
        ai2.wait();
    }

    chess_.rotate(-90);
    chessTemp = chess_;

    // 更新棋谱
    int row = 0;

    for (auto str : *(chess_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    if (currentRow == row - 1)
        updateScence();
    else
        stageChange(currentRow, true);

    ai1.setAi(chess_);
    ai2.setAi(chess_);

    if (isEngine1) {
        ai1.start();
    }

    if (isEngine2) {
        ai2.start();
    }
}

// 视图逆时针旋转90°
void GameController::turnLeft()
{
    if (isEngine1) {
        ai1.stop();
        ai1.wait();
    }
    if (isEngine2) {
        ai2.stop();
        ai2.wait();
    }

    chess_.rotate(90);
    chessTemp = chess_;

    // 更新棋谱
    int row = 0;
    for (auto str : *(chess_.getCmdList())) {
        manualListModel.setData(manualListModel.index(row++), str.c_str());
    }

    // 刷新显示
    updateScence();

    ai1.setAi(chess_);
    ai2.setAi(chess_);
    if (isEngine1) {
        ai1.start();
    }
    if (isEngine2) {
        ai2.start();
    }
}

void GameController::timerEvent(QTimerEvent *event)
{
    Q_UNUSED(event)
    static QTime qt1, qt2;

    // 玩家的已用时间
    chess_.getElapsedTimeMS(remainingTime1, remainingTime2);

    // 如果规则要求计时，则time1和time2表示倒计时
    if (timeLimit > 0) {
        // 玩家的剩余时间
        remainingTime1 = timeLimit * 60000 - remainingTime1;
        remainingTime2 = timeLimit * 60000 - remainingTime2;
    }

    //qt1 = QTime(0, 0, 0, 0).addMSecs(remainingTime1);
    //qt2 = QTime(0, 0, 0, 0).addMSecs(remainingTime2);

    //emit time1Changed(qt1.toString("mm:ss.zzz"));
    //emit time2Changed(qt2.toString("mm:ss.zzz"));

    // 如果胜负已分
    if (chess_.whoWin() != NineChess::NOBODY) {
        // 停止计时
        killTimer(timeID);

        // 定时器ID为0
        timeID = 0;

        // 发信号更新状态栏
        message = QString::fromStdString(chess_.getTips());
        emit statusBarChanged(message);

        // 弹框
        //QMessageBox::about(NULL, "游戏结果", message);

        if (chess_.whoWin() == NineChess::PLAYER1) {
            score1++;
        } else if (chess_.whoWin() == NineChess::PLAYER2) {
            score2++;
        }

        emit time1Changed(QString::number(score1, 10));
        emit time2Changed(QString::number(score2, 10));

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
        //qDebug() << t;
        emit time1Changed(t.toString("hh:mm:ss"));
    }
    else if (timeWhos == 2)
    {
        time2 = ti - time1;
        // 用于显示时间的临时变量，多出的50毫秒用于消除计时器误差产生的跳动
        t = QTime(0, 0, 0, 50).addMSecs(time2);
        //qDebug() << t;
        emit time2Changed(t.toString("hh:mm:ss"));
    }
#endif
}

// 关键槽函数，根据QGraphicsScene的信号和状态来执行选子、落子或去子
bool GameController::actionPiece(QPointF pos)
{
    // 点击非落子点，不执行
    int c, p;
    if (!scene.pos2cp(pos, c, p)) {
        return false;
    }

    // 电脑走棋时，点击无效
    if (chess_.whosTurn() == NineChess::PLAYER1 && isEngine1)
        return false;

    if (chess_.whosTurn() == NineChess::PLAYER2 && isEngine2)
        return false;

    // 在浏览历史记录时点击棋盘，则认为是悔棋
    if (currentRow != manualListModel.rowCount() - 1) {
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
            chess_ = chessTemp;
            manualListModel.removeRows(currentRow + 1, manualListModel.rowCount() - currentRow - 1);

            // 如果再决出胜负后悔棋，则重新启动计时
            if (chess_.whoWin() == NineChess::NOBODY) {

                // 重新启动计时
                timeID = startTimer(100);

                // 发信号更新状态栏
                message = QString::fromStdString(chess_.getTips());
                emit statusBarChanged(message);
            }
        } else
            return false;
    }

    // 如果未开局则开局
    if (chess_.getStage() == NineChess::GAME_NOTSTARTED)
        gameStart();

    // 判断执行选子、落子或去子
    bool result = false;
    PieceItem *piece = nullptr;
    QGraphicsItem *item = scene.itemAt(pos, QTransform());

    switch (chess_.getAction()) {
    case NineChess::ACTION_PLACE:
        if (chess_.place(c, p)) {
            if (chess_.getAction() == NineChess::ACTION_CAPTURE) {
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

    case NineChess::ACTION_CHOOSE:
        piece = qgraphicsitem_cast<PieceItem *>(item);
        if (!piece)
            break;
        if (chess_.choose(c, p)) {
            // 播放选子音效
            playSound(":/sound/resources/sound/choose.wav");
            result = true;
        } else {
            // 播放禁止音效
            playSound(":/sound/resources/sound/forbidden.wav");
        }
        break;

    case NineChess::ACTION_CAPTURE:
        if (chess_.capture(c, p)) {
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
        message = QString::fromStdString(chess_.getTips());
        emit statusBarChanged(message);

        // 将新增的棋谱行插入到ListModel
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;

        // 输出命令行
        for (auto i = (chess_.getCmdList())->begin(); i != (chess_.getCmdList())->end(); ++i) {
            // 跳过已添加的，因标准list容器没有下标
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i).c_str());
        }

        // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
        if (chess_.whoWin() != NineChess::NOBODY &&
            (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over."))
            playSound(":/sound/resources/sound/win.wav");
#endif

        // AI设置
        if (&chess_ == &(this->chess_)) {
            // 如果还未决出胜负
            if (chess_.whoWin() == NineChess::NOBODY) {
                if (chess_.whosTurn() == NineChess::PLAYER1) {
                    if (isEngine1) {
                        ai1.resume();
                    }
                    if (isEngine2)
                        ai2.pause();
                } else {
                    if (isEngine1)
                        ai1.pause();
                    if (isEngine2) {
                        ai2.resume();
                    }
                }
            }
            // 如果已经决出胜负
            else {
                ai1.stop();
                ai2.stop();

                // 弹框
                //message = QString::fromStdString(chess_.getTips());
                //QMessageBox::about(NULL, "游戏结果", message);
            }
        }
    }

    updateScence();
    return result;
}

bool GameController::giveUp()
{
    bool result = false;

    if (chess_.whosTurn() == NineChess::PLAYER1) {
        result = chess_.giveup(NineChess::PLAYER1);
        score2++;
        chess_.score_2++;
    }
    else if (chess_.whosTurn() == NineChess::PLAYER2) {
        result = chess_.giveup(NineChess::PLAYER2);
        score1++;
        chess_.score_2++;
    }
        
    if (result) {
        // 将新增的棋谱行插入到ListModel
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;

        // 输出命令行
        for (auto i = (chess_.getCmdList())->begin(); i != (chess_.getCmdList())->end(); ++i) {
            // 跳过已添加的，因标准list容器没有下标
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i).c_str());
        }
        if (chess_.whoWin() != NineChess::NOBODY)
            playSound(":/sound/resources/sound/loss.wav");
    }

    return result;
}

// 关键槽函数，棋谱的命令行执行，与actionPiece独立
bool GameController::command(const QString &cmd, bool update /* = true */)
{
    Q_UNUSED(hasSound)

    // 防止接收滞后结束的线程发送的指令
    if (sender() == &ai1 && !isEngine1)
        return false;

    if (sender() == &ai2 && !isEngine2)
        return false;

    // 声音
    QString sound;

    switch (chess_.getAction()) {
    case NineChess::ACTION_CHOOSE:
    case NineChess::ACTION_PLACE:
        sound = ":/sound/resources/sound/drog.wav";
        break;
    case NineChess::ACTION_CAPTURE:
        sound = ":/sound/resources/sound/remove.wav";
        break;
    default:
        break;
    }

    // 如果未开局则开局
    if (chess_.getStage() == NineChess::GAME_NOTSTARTED) {
        gameStart();
    }

    if (!chess_.command(cmd.toStdString().c_str()))
        return false;

    if (sound == ":/sound/resources/sound/drog.wav" && chess_.getAction() == NineChess::ACTION_CAPTURE) {
        sound = ":/sound/resources/sound/capture.wav";
    }

    if (update) {
        playSound(sound);
        updateScence(chess_);
    }

    // 发信号更新状态栏
    message = QString::fromStdString(chess_.getTips());
    emit statusBarChanged(message);

    // 对于新开局
    if (chess_.getCmdList()->size() <= 1) {
        manualListModel.removeRows(0, manualListModel.rowCount());
        manualListModel.insertRow(0);
        manualListModel.setData(manualListModel.index(0), chess_.getCmdLine());
        currentRow = 0;
    }
    // 对于当前局
    else {
        currentRow = manualListModel.rowCount() - 1;
        // 跳过已添加行,迭代器不支持+运算符,只能一个个++
        auto i = (chess_.getCmdList()->begin());
        for (int r = 0; i != (chess_.getCmdList())->end(); i++) {
            if (r++ > currentRow)
                break;
        }
        // 将新增的棋谱行插入到ListModel
        while (i != chess_.getCmdList()->end()) {
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i++).c_str());
        }
    }

    // 播放胜利或失败音效
#ifndef DONOT_PLAY_WIN_SOUND
    if (chess_.whoWin() != NineChess::NOBODY &&
        (manualListModel.data(manualListModel.index(currentRow - 1))).toString().contains("Time over."))
        playSound(":/sound/resources/sound/win.wav");
#endif

    // AI设置
    if (&chess_ == &(this->chess_)) {
        // 如果还未决出胜负
        if (chess_.whoWin() == NineChess::NOBODY) {
            if (chess_.whosTurn() == NineChess::PLAYER1) {
                if (isEngine1) {
                    ai1.resume();
                }
                if (isEngine2)
                    ai2.pause();
            } else {
                if (isEngine1)
                    ai1.pause();
                if (isEngine2) {
                    ai2.resume();
                }
            }
        }
        // 如果已经决出胜负
        else {
            ai1.stop();
            ai2.stop();

            // 弹框
            message = QString::fromStdString(chess_.getTips());
            QMessageBox::about(NULL, "游戏结果", message);
        }
    }

    // 网络: 将着法放到服务器的发送列表中
    if (isEngine1)
    {
        ai1.getServer()->setAction(cmd);
        qDebug() << "AI(1) set Action: " << cmd;
    } else if (isEngine2) {
        ai2.getServer()->setAction(cmd);
        qDebug() << "AI(2) set Action: " << cmd;
    }

    return true;
}

// 浏览历史局面，通过command函数刷新局面显示
bool GameController::stageChange(int row, bool forceUpdate)
{
    // 如果row是当前浏览的棋谱行，则不需要刷新
    if (currentRow == row && !forceUpdate)
        return false;

    // 需要刷新
    currentRow = row;
    int rows = manualListModel.rowCount();
    QStringList mlist = manualListModel.stringList();
    qDebug() << "rows:" << rows << " current:" << row;

    for (int i = 0; i <= row; i++) {
        qDebug() << mlist.at(i);
        chessTemp.command(mlist.at(i).toStdString().c_str());
    }

    // 下面这步关键，会让悔棋者承担时间损失
    chessTemp.setStartTimeb(chess_.getStartTimeb());

    // 刷新棋局场景
    updateScence(chessTemp);

    return true;
}

bool GameController::updateScence()
{
    return updateScence(chess_);
}

bool GameController::updateScence(NineChess &chess)
{
    const int *board = chess.getBoard();
    QPointF pos;

    // chess类中的棋子代码
    int key;

    // 棋子总数
    int nTotalPieces = chess.getRule()->nTotalPiecesEachSide * 2;

    // 动画组
    QParallelAnimationGroup *animationGroup = new QParallelAnimationGroup;

    // 棋子就位
    PieceItem *piece = nullptr;
    PieceItem *deletedPiece = nullptr;

    for (int i = 0; i < nTotalPieces; i++) {
        piece = pieceList.at(i);

        piece->setSelected(false);

        // 将pieceList的下标转换为chess的棋子代号
        key = (i % 2) ? (i / 2 + 0x21) : (i / 2 + 0x11);

        int j;

        // 遍历棋盘，查找并放置棋盘上的棋子
        for (j = NineChess::POS_BEGIN; j < NineChess::POS_END; j++) {
            if (board[j] == key) {
                pos = scene.cp2pos(j / NineChess::N_SEATS, j % NineChess::N_SEATS + 1);
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
        if (j == (NineChess::N_SEATS) * (NineChess::N_RINGS + 1)) {
            // 判断是被吃掉的子，还是未安放的子
            if (key & 0x10) {
                pos = (key - 0x11 < nTotalPieces / 2 - chess.getPiecesInHandCount_1()) ?
                        scene.pos_p2_g : scene.pos_p1;
            } else {
                pos = (key - 0x21 < nTotalPieces / 2 - chess.getPiecesInHandCount_2()) ?
                        scene.pos_p1_g : scene.pos_p2;
            }

            if (piece->pos() != pos) {
                // 为了对最近移除的棋子置为选择状态作准备
                deletedPiece = piece;

#ifdef GAME_PLACING_SHOW_CAPTURED_PIECES
                if (chess.getStage() == NineChess::GAME_MOVING) {
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
    if (chess.getRule()->hasForbiddenPoint && chess.getStage() == NineChess::GAME_PLACING) {
        for (int j = NineChess::POS_BEGIN; j < NineChess::POS_END; j++) {
            if (board[j] == 0x0F) {
                pos = scene.cp2pos(j / NineChess::N_SEATS, j % NineChess::N_SEATS + 1);
                if (nTotalPieces < pieceList.size()) {
                    pieceList.at(nTotalPieces++)->setPos(pos);
                } else {
                    PieceItem *newP = new PieceItem;
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
    if (chess.getRule()->hasForbiddenPoint && chess.getStage() != NineChess::GAME_PLACING) {
        while (nTotalPieces < pieceList.size()) {
            delete pieceList.at(nTotalPieces);
            pieceList.removeAt(nTotalPieces);
        }
    }

    // 选中当前棋子
    int ipos = chess.getCurrentPos();
    if (ipos) {
        key = board[chess.getCurrentPos()];
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

    return true;
}

void GameController::showNetworkWindow()
{
    ai1.getServer()->show();
    ai1.getClient()->show();

    ai2.getServer()->show();
    ai2.getClient()->show();
}
