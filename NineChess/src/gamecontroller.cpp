#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif
#include <QGraphicsView>
#include <QGraphicsSceneMouseEvent>
#include <QKeyEvent>
#include <QApplication>
#include <Qsound>
#include <QDebug>
#include "gamecontroller.h"
#include "graphicsconst.h"
#include "boarditem.h"
#include "pieceitem.h"

GameController::GameController(GameScene & scene, QObject *parent) : QObject(parent),
scene(scene),
piece(NULL),
isEditing(false),
isInverted(false),
isEngine1(false),
isEngine2(false),
hasAnimation(true),
hasSound(true),
timeID(0),
timeLimit(0),
stepsLimit(0)
{
    // 设置场景尺寸大小为棋盘大小的1.08倍
    scene.setSceneRect(-BOARD_SIZE * 0.54, -BOARD_SIZE * 0.54, BOARD_SIZE*1.08, BOARD_SIZE*1.08);
    // 已在view的样式表中添加背景，scene中不用添加背景
    // 区别在于，view中的背景不随视图变换而变换，scene中的背景随视图变换而变换
    //scene.setBackgroundBrush(QPixmap(":/image/Resources/image/background.png"));
    // 初始化音效文件路径
    QString dir = QCoreApplication::applicationDirPath();
    soundNewgame = dir + "/sound/newgame.wav";
    soundChoose = dir + "/sound/choose.wav";
    soundMove = dir + "/sound/move.wav";
    soundDrog = dir + "/sound/drog.wav";
    soundForbidden = dir + "/sound/forbidden.wav";
    soundRemove = dir + "/sound/remove.wav";
    soundWin = dir + "/sound/win.wav";
    soundLoss = dir + "/sound/loss.wav";

    gameReset();
    // 安装事件过滤器监视scene的各个事件，由于我重载了QGraphicsScene，相关事件在重载函数中已设定，不必安装监视器。
    //scene.installEventFilter(this);
}

GameController::~GameController()
{
}

const QMap<int, QStringList> GameController::getActions()
{
    // 主窗口更新菜单栏
    // 之所以不用信号和槽的模式，是因为发信号的时候槽还来不及关联
    QMap<int, QStringList> actions;
    for (int i = 0; i < NineChess::RULENUM; i++)
    {
        // QMap的key存放int索引值，value存放规则名称和规则提示
        QStringList strlist;
        strlist.append(tr(NineChess::RULES[i].name));
        strlist.append(tr(NineChess::RULES[i].info));
        actions.insert(i, strlist);
    }
    return actions;
}


void GameController::gameStart()
{
    // 每隔100毫秒调用一次定时器处理函数
    timeID = startTimer(100);
}

void GameController::gameReset()
{
    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);
    // 定时器ID为0
    timeID = 0;
    // 重置游戏
    chess.reset();

    // 清除棋子
    qDeleteAll(pieceList);
    pieceList.clear();
    piece = NULL;
    // 重新绘制棋盘
    scene.setDiagonal(chess.getRule()->hasObliqueLine);

    // 读取规则限时要求
    timeLimit = chess.getRule()->maxTime;
    // 如果规则不要求计时，则time1和time2表示已用时间
    if (timeLimit <= 0) {
        // 将玩家的已用时间清零
        time1 = time2 = 0;
    }
    else
    {
        // 将玩家的剩余时间置为限定时间
        time1 = time2 = timeLimit * 60000;
    }
    // 发出信号通知主窗口更新LCD显示
    QTime qtime = QTime(0, 0, 0, 0).addMSecs(time1);
    emit time1Changed(qtime.toString("mm:ss.zzz"));
    emit time2Changed(qtime.toString("mm:ss.zzz"));
    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(soundNewgame);
}

void GameController::setEditing(bool arg)
{
    isEditing = arg;
}

void GameController::setInvert(bool arg)
{
    isInverted = arg;
    // 遍历所有棋子
    foreach(PieceItem * p, pieceList)
    {
        if (p)
        {
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

void GameController::setRule(int ruleNo)
{
    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);
    // 定时器ID为0
    timeID = 0;

    // 更新规则，原限时和限步不变
    struct NineChess::Rule rule;
    if (ruleNo >= 0 && ruleNo < NineChess::RULENUM)
        rule = NineChess::RULES[ruleNo];
    rule.maxSteps = stepsLimit;
    rule.maxTime = timeLimit;
    // 设置模型规则，重置游戏
    chess.setRule(&rule);

    // 清除棋子
    qDeleteAll(pieceList);
    pieceList.clear();
    piece = NULL;
    // 重新绘制棋盘
    scene.setDiagonal(chess.getRule()->hasObliqueLine);

    // 如果规则不要求计时，则time1和time2表示已用时间
    if (timeLimit <= 0) {
        // 将玩家的已用时间清零
        time1 = time2 = 0;
    }
    else
    {
        // 将玩家的剩余时间置为限定时间
        time1 = time2 = timeLimit * 60000;
    }
    // 发出信号通知主窗口更新LCD显示
    QTime qtime = QTime(0, 0, 0, 0).addMSecs(time1);
    emit time1Changed(qtime.toString("mm:ss.zzz"));
    emit time2Changed(qtime.toString("mm:ss.zzz"));
    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(soundNewgame);
}

void GameController::setRule(int ruleNo, int stepLimited, int timeLimited)
{
    // 停止计时器
    if (timeID != 0)
        killTimer(timeID);
    // 定时器ID为0
    timeID = 0;

    // 更新规则，原限时和限步不变
    struct NineChess::Rule rule;
    if (ruleNo >= 0 && ruleNo < NineChess::RULENUM)
        rule = NineChess::RULES[ruleNo];
    stepsLimit = rule.maxSteps = stepLimited;
    timeLimit = rule.maxTime = timeLimited;
    // 设置模型规则，重置游戏
    chess.setRule(&rule);

    // 清除棋子
    qDeleteAll(pieceList);
    pieceList.clear();
    piece = NULL;
    // 重新绘制棋盘
    scene.setDiagonal(chess.getRule()->hasObliqueLine);

    // 如果规则不要求计时，则time1和time2表示已用时间
    if (timeLimit <= 0) {
        // 将玩家的已用时间清零
        time1 = time2 = 0;
    }
    else
    {
        // 将玩家的剩余时间置为限定时间
        time1 = time2 = timeLimit * 60000;
    }
    // 发出信号通知主窗口更新LCD显示
    QTime qtime = QTime(0, 0, 0, 0).addMSecs(time1);
    emit time1Changed(qtime.toString("mm:ss.zzz"));
    emit time2Changed(qtime.toString("mm:ss.zzz"));
    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(soundNewgame);
}

void GameController::setEngine1(bool arg)
{
    isEngine1 = arg;
    if (arg)
        qDebug() << "Player1 is computer.";
    else
        qDebug() << "Player1 is not computer.";
}

void GameController::setEngine2(bool arg)
{
    isEngine2 = arg;
    if (arg)
        qDebug() << "Player2 is computer.";
    else
        qDebug() << "Player2 is not computer.";
}

void GameController::setAnimation(bool arg)
{
    hasAnimation = arg;
}

void GameController::setSound(bool arg)
{
    hasSound = arg;
}

void GameController::playSound(QString &soundPath)
{
    if (hasSound)
        QSound::play(soundPath);
}

bool GameController::eventFilter(QObject * watched, QEvent * event)
{
    return QObject::eventFilter(watched, event);
}

void GameController::timerEvent(QTimerEvent *event)
{
    static QTime qt1, qt2;
    // 玩家的已用时间
    chess.getPlayer_TimeMS(time1, time2);
    // 如果规则要求计时，则time1和time2表示倒计时
    if (timeLimit > 0)
    {
        // 玩家的剩余时间
        time1 = timeLimit * 60000 - time1;
        time2 = timeLimit * 60000 - time2;
    }
    qt1 = QTime(0, 0, 0, 0).addMSecs(time1);
    qt2 = QTime(0, 0, 0, 0).addMSecs(time2);
    emit time1Changed(qt1.toString("mm:ss.zzz"));
    emit time2Changed(qt2.toString("mm:ss.zzz"));
    // 如果胜负已分
    if (chess.whoWin() != NineChess::NOBODY)
    {
        // 停止计时
        killTimer(timeID);
        // 定时器ID为0
        timeID = 0;
        // 发信号更新状态栏
        message = QString::fromStdString(chess.getTip());
        emit statusBarChanged(message);
        // 播放音效
        playSound(soundWin);
    }
    /*
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
    */
}

// 槽函数，根据QGraphicsScene的信号和状态来执行选子、落子或去子
bool GameController::actionPiece(QPointF pos)
{
    bool result = false;
    switch (chess.getPhase()) {
    case NineChess::GAME_NOTSTARTED:
        // 如果未开局则开局，这里还要继续判断，不可break
        gameStart();
        chess.start();
    case NineChess::GAME_OPENING:
        // 如果是开局阶段（轮流落下新子），落子
        if (chess.getAction() == NineChess::ACTION_PLACE) {
            result = placePiece(pos);
        }// 去子
        else if (chess.getAction() == NineChess::ACTION_REMOVE) {
            result = removePiece(pos);
        }
        // 如果完成后进入中局，则删除禁点
        if (chess.getPhase() == NineChess::GAME_MID && chess.getRule()->hasForbidden)
            cleanForbidden();
        break;
    case NineChess::GAME_MID:
        // 如果是中局阶段（轮流移子）
        // 选子
        if (chess.getAction() == NineChess::ACTION_CHOOSE) {
            result = choosePiece(pos);
        }// 移子
        else if (chess.getAction() == NineChess::ACTION_PLACE) {
            // 如果移子不成功，尝试重新选子
            if (!movePiece(pos))
                result = choosePiece(pos);
        }// 去子
        else if (chess.getAction() == NineChess::ACTION_REMOVE) {
            result = removePiece(pos);
        }
        break;
        // 如果是结局状态，不做任何响应
    default:
        break;
    }
    if (result)
    {
        if (chess.whoWin() != NineChess::NOBODY)
            playSound(soundWin);
    }
    return result;
}

// 选子
PieceItem *GameController::choosePiece(QPointF pos)
{
    int c, p;
    if (!scene.pos2cp(pos, c, p))
        return false;
    PieceItem *piece = NULL;
    QGraphicsItem *item = scene.itemAt(pos, QTransform());
    if (!item) {
        scene.clearSelection();
        this->piece->setSelected(true);
        return false;
    }
    piece = qgraphicsitem_cast<PieceItem *>(item);
    if (!piece)
        return false;
    if (chess.choose(c, p)) {
        scene.clearSelection();
        this->piece = piece;
        this->piece->setSelected(true);
        // 发信号更新状态栏
        message = QString::fromStdString(chess.getTip());
        emit statusBarChanged(message);
        // 播放音效
        playSound(soundChoose);
        return piece;
    }
    else
    {
        scene.clearSelection();
        if (this->piece)
            this->piece->setSelected(true);
    }
    return NULL;
}

// 落下新子
PieceItem *GameController::placePiece(QPointF pos)
{
    int c, p;
    if (!scene.pos2cp(pos, c, p))
        return NULL;
    PieceItem *newP = NULL;
    PieceItem::Models md;
    if (chess.whosTurn() == NineChess::PLAYER1)
    {
        md = isInverted ? PieceItem::whitePiece : PieceItem::blackPiece;
    }
    else {
        md = isInverted ? PieceItem::blackPiece : PieceItem::whitePiece;
    }
    if (!chess.place(c, p)) {
        scene.clearSelection();
        if (this->piece)
            this->piece->setSelected(true);
        return NULL;
    }
    newP = new PieceItem;
    newP->setModel(md);
    newP->setDeleted(false);
    newP->setPos(pos);
    newP->setNum(chess.getPieceNum(c, p));
    // 如果重复三连不可用，则显示棋子序号
    if (!(chess.getRule()->canRepeated))
        newP->setShowNum(true);
    pieceList.append(newP);
    scene.addItem(newP);
    scene.clearSelection();
    this->piece = newP;
    this->piece->setSelected(true);
    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(soundDrog);
    return newP;
}

// 移动旧子
bool GameController::movePiece(QPointF pos)
{
    if (!piece)
        return false;
    int c, p;
    if (!scene.pos2cp(pos, c, p))
        return false;
    if (chess.place(c, p))
    {
        piece->setPos(pos);
        // 发信号更新状态栏
        message = QString::fromStdString(chess.getTip());
        emit statusBarChanged(message);
        // 播放音效
        playSound(soundMove);
        return true;
    }
    scene.clearSelection();
    this->piece->setSelected(true);
    return false;
}

// 去子
bool GameController::removePiece(QPointF pos)
{
    int c, p;
    if (!scene.pos2cp(pos, c, p))
        return false;
    if (!chess.remove(c, p)) {
        scene.clearSelection();
        if (this->piece)
            this->piece->setSelected(true);
        return false;
    }

    PieceItem *piece = NULL;
    QGraphicsItem *item = scene.itemAt(pos, QTransform());
    if (!item) {
        scene.clearSelection();
        if (this->piece)
            this->piece->setSelected(true);
        return false;
    }
    piece = qgraphicsitem_cast<PieceItem *>(item);
    if (!piece) {
        scene.clearSelection();
        if (this->piece)
            this->piece->setSelected(true);
        return false;
    }
    // 如果开局阶段有禁点
    if (chess.getPhase() == NineChess::GAME_OPENING && chess.getRule()->hasForbidden)
    {
        piece->setDeleted();
    }
    else
    {
        pieceList.removeOne(piece);
        delete piece;
        this->piece = NULL;
    }
    scene.clearSelection();
    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(soundRemove);
    return true;
}

bool GameController::cleanForbidden()
{
    for each (PieceItem *p in pieceList)
    {
        if (p->isDeleted()) {
            pieceList.removeOne(p);
            delete p;
        }
    }
    return true;
}
