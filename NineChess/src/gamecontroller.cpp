#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif

#include <QGraphicsView>
#include <QGraphicsSceneMouseEvent>
#include <QKeyEvent>
#include <QApplication>
#include <QSound>
#include <QDebug>
#include <QMessageBox>
#include <QAbstractButton>
#include <QPropertyAnimation>
#include <QParallelAnimationGroup>
#include "gamecontroller.h"
#include "graphicsconst.h"
#include "boarditem.h"

GameController::GameController(GameScene &scene, QObject *parent) : QObject(parent),
// 是否浏览过历史纪录
scene(scene),
currentPiece(NULL),
currentRow(-1),
isEditing(false),
isInverted(false),
isEngine1(false),
isEngine2(false),
hasAnimation(true),
durationTime(250),
hasSound(true),
timeID(0),
ruleNo(-1),
timeLimit(0),
stepsLimit(0)
{
    // 已在view的样式表中添加背景，scene中不用添加背景
    // 区别在于，view中的背景不随视图变换而变换，scene中的背景随视图变换而变换
    //scene.setBackgroundBrush(QPixmap(":/image/Resources/image/background.png"));

    gameReset();
    // 安装事件过滤器监视scene的各个事件，由于我重载了QGraphicsScene，相关事件在重载函数中已设定，不必安装监视器。
    //scene.installEventFilter(this);
}

GameController::~GameController()
{
	// 清除棋子
	qDeleteAll(pieceList);
	pieceList.clear();
	currentPiece = NULL;
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
    chess.start();
    chessTemp = chess;
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
    // 重置游戏
    chess.reset();
    chessTemp.reset();

    // 清除棋子
    qDeleteAll(pieceList);
    pieceList.clear();
    currentPiece = NULL;
    // 重新绘制棋盘
    scene.setDiagonal(chess.getRule()->hasObliqueLine);

	// 绘制所有棋子，放在起始位置，分成2组写，后面好区分
	for (int i = 0; i < chess.getRule()->numOfChess; i++)
	{
		PieceItem::Models md = isInverted ? PieceItem::whitePiece : PieceItem::blackPiece;
		PieceItem *newP = new PieceItem;
		newP->setModel(md);
		newP->setPos(scene.pos_p1);
		newP->setNum(i + 1);
		// 如果重复三连不可用，则显示棋子序号，九连棋专用玩法
		if (!(chess.getRule()->canRepeated))
			newP->setShowNum(true);
		pieceList.append(newP);
		scene.addItem(newP);
	}
	for (int i = 0; i < chess.getRule()->numOfChess; i++)
	{
		PieceItem::Models md = isInverted ? PieceItem::blackPiece : PieceItem::whitePiece;
		PieceItem *newP = new PieceItem;
		newP->setModel(md);
		newP->setPos(scene.pos_p2);
		newP->setNum(i + 1);
		// 如果重复三连不可用，则显示棋子序号，九连棋专用玩法
		if (!(chess.getRule()->canRepeated))
			newP->setShowNum(true);
		pieceList.append(newP);
		scene.addItem(newP);
	}


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
    // 更新棋谱
    manualListModel.removeRows(0, manualListModel.rowCount());
    currentRow = 0;
    manualListModel.insertRow(0);
    manualListModel.setData(manualListModel.index(0), chess.getCmdLine());

    // 发出信号通知主窗口更新LCD显示
    QTime qtime = QTime(0, 0, 0, 0).addMSecs(time1);
    emit time1Changed(qtime.toString("mm:ss.zzz"));
    emit time2Changed(qtime.toString("mm:ss.zzz"));
    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(":/sound/Resources/sound/newgame.wav");
}

void GameController::setEditing(bool arg)
{
    isEditing = arg;
}

void GameController::setInvert(bool arg)
{
    isInverted = arg;
    // 遍历所有棋子
    for (PieceItem * p : pieceList)
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

void GameController::setRule(int ruleNo, int stepLimited /*= -1*/, int timeLimited /*= -1*/)
{
    // 更新规则，原限时和限步不变
    if (ruleNo < 0 || ruleNo >= NineChess::RULENUM)
        return;
    this->ruleNo = ruleNo;

    if (stepLimited != -1 && timeLimited != -1) {
        stepsLimit = stepLimited;
        timeLimit = timeLimited;
    }
    // 设置模型规则，重置游戏
    chess.setData(&NineChess::RULES[ruleNo], stepsLimit, timeLimit);
    chessTemp = chess;

    // 重置游戏
    gameReset();
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
	// 默认动画时间250ms
	if (hasAnimation)
		durationTime = 250;
	else
		durationTime = 0;
}

void GameController::setSound(bool arg)
{
    hasSound = arg;
}

void GameController::playSound(const QString &soundPath)
{
	if (hasSound) {
		QSound::play(soundPath);
	}
}

bool GameController::eventFilter(QObject * watched, QEvent * event)
{
    return QObject::eventFilter(watched, event);
}

void GameController::timerEvent(QTimerEvent *event)
{
	Q_UNUSED(event)
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
        playSound(":/sound/Resources/sound/win.wav");
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

bool GameController::command(QString &cmd)
{
    if (chess.command(cmd.toStdString().c_str())) {
        if (chess.getPhase() == NineChess::GAME_NOTSTARTED) {
            gameReset();
            gameStart();
        }
        updateScence(chess);
        // 将新增的棋谱行插入到ListModel
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;
        // 输出命令行
        for (auto i = (chess.getCmdList())->begin(); i != (chess.getCmdList())->end(); ++i) {
            // 跳过已添加的，因标准list容器没有下标
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i).c_str());
        }
        return true;
    }
    else {
        return false;
    }
}

// 历史局面
void GameController::phaseChange(int row, bool change /*= false*/)
{
    // 如果row是当前浏览的棋谱行，则直接推出不刷新
    if (currentRow == row)
        return;
    else
        currentRow = row;

    int rows = manualListModel.rowCount();
    QStringList mlist = manualListModel.stringList();
    qDebug() << "rows:" << rows << " current:" << row;
    for (int i = 0; i <= row; i++)
    {
        qDebug() << mlist.at(i);
        chessTemp.command(mlist.at(i).toStdString().c_str());
    }
    // 下面这步关键，让悔棋者承担时间损失
    chessTemp.setStartTimeb(chess.getStartTimeb());

    updateScence(chessTemp);
}

// 槽函数，根据QGraphicsScene的信号和状态来执行选子、落子或去子
bool GameController::actionPiece(QPointF pos)
{
    bool result = false;

    // 是否在浏览历史记录
    if (currentRow != manualListModel.rowCount() - 1)
    {
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

        if (QMessageBox::Ok == msgBox.exec())
        {
            chess = chessTemp;
            manualListModel.removeRows(currentRow + 1, manualListModel.rowCount() - currentRow - 1);
        }
        else
        {
            return result;
        }
    }


    switch (chess.getPhase()) {
    case NineChess::GAME_NOTSTARTED:
        // 如果未开局则开局，这里还要继续判断，不可break
        gameStart();

    case NineChess::GAME_OPENING:
        // 如果是开局阶段（轮流落下新子），落子
        if (chess.getAction() == NineChess::ACTION_PLACE) {
            result = placePiece(pos);
        }// 去子
        else if (chess.getAction() == NineChess::ACTION_REMOVE) {
            result = removePiece(pos);
        }
        // 如果完成后进入中局，则删除禁点
        //if (chess.getPhase() == NineChess::GAME_MID && chess.getRule()->hasForbidden)
        //    cleanForbidden();
        break;

    case NineChess::GAME_MID:
        // 如果是中局阶段（轮流移子）
        // 选子
        if (chess.getAction() == NineChess::ACTION_CHOOSE) {
            result = choosePiece(pos);
        }// 移子
        else if (chess.getAction() == NineChess::ACTION_PLACE) {
            // 如果移子不成功，尝试重新选子
            result = movePiece(pos);
            if (!result)
                result = choosePiece(pos);
        }// 去子
        else if (chess.getAction() == NineChess::ACTION_REMOVE) {
            result = removePiece(pos);
        }
        break;

    default:
        // 如果是结局状态，不做任何响应
        break;
    }

    if (result)
    {
        // 将新增的棋谱行插入到ListModel
        currentRow = manualListModel.rowCount() - 1;
        int k = 0;
        // 输出命令行
        for (auto i = (chess.getCmdList())->begin(); i != (chess.getCmdList())->end(); ++i) {
            // 跳过已添加的，因标准list容器没有下标
            if (k++ <= currentRow)
                continue;
            manualListModel.insertRow(++currentRow);
            manualListModel.setData(manualListModel.index(currentRow), (*i).c_str());
        }
        if (chess.whoWin() != NineChess::NOBODY && 
			(manualListModel.data(manualListModel.index(currentRow-1))).toString().contains("Time over."))
            playSound(":/sound/Resources/sound/win.wav");
    }

    updateScence(this->chess);
    return result;
}

// 选子
bool GameController::choosePiece(QPointF pos)
{
    int c, p;
    if (!scene.pos2cp(pos, c, p)) {
        return false;
    }
    PieceItem *piece = NULL;
    QGraphicsItem *item = scene.itemAt(pos, QTransform());
    piece = qgraphicsitem_cast<PieceItem *>(item);
    if (!piece) {
        return false;
    }
    if (chess.choose(c, p)) {
        // 发信号更新状态栏
        message = QString::fromStdString(chess.getTip());
        emit statusBarChanged(message);
        // 播放音效
        playSound(":/sound/Resources/sound/choose.wav");
        return true;
    }
    else {
        return false;
    }
}

// 落下新子
bool GameController::placePiece(QPointF pos)
{
    int c, p;
    if (!scene.pos2cp(pos, c, p)) {
        return false;
    }
    if (!chess.place(c, p)) {
        return false;
    }
    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(":/sound/Resources/sound/drog.wav");
    return true;
}

// 移动旧子
bool GameController::movePiece(QPointF pos)
{
    if (!currentPiece) {
        return false;
    }
    int c, p;
    if (!scene.pos2cp(pos, c, p)) {
        return false;
    }

    if (chess.place(c, p))
    {
        // 发信号更新状态栏
        message = QString::fromStdString(chess.getTip());
        emit statusBarChanged(message);
        // 播放音效
        playSound(":/sound/Resources/sound/move.wav");
        return true;
    }
    return false;
}

// 去子
bool GameController::removePiece(QPointF pos)
{
    int c, p;
    if (!scene.pos2cp(pos, c, p)) {
        return false;
    }
    if (!chess.remove(c, p)) {
        return false;
    }

    // 发信号更新状态栏
    message = QString::fromStdString(chess.getTip());
    emit statusBarChanged(message);
    // 播放音效
    playSound(":/sound/Resources/sound/remove.wav");
    return true;
}

bool GameController::giveUp()
{
	bool result = false;
	if (chess.whosTurn() == NineChess::PLAYER1)
		result = chess.giveup(NineChess::PLAYER1);
	else if (chess.whosTurn() == NineChess::PLAYER2)
		result = chess.giveup(NineChess::PLAYER2);
	if (result)
	{
		// 将新增的棋谱行插入到ListModel
		currentRow = manualListModel.rowCount() - 1;
		int k = 0;
		// 输出命令行
		for (auto i = (chess.getCmdList())->begin(); i != (chess.getCmdList())->end(); ++i) {
			// 跳过已添加的，因标准list容器没有下标
			if (k++ <= currentRow)
				continue;
			manualListModel.insertRow(++currentRow);
			manualListModel.setData(manualListModel.index(currentRow), (*i).c_str());
		}
		if (chess.whoWin() != NineChess::NOBODY)
			playSound(":/sound/Resources/sound/loss.wav");
	}
	return result;
}

bool GameController::updateScence(NineChess &chess)
{
	const char *board = chess.getBoard();
	QPointF pos;
	// chess类中的棋子代码
	int key;
	// 棋子总数
	int n = chess.getRule()->numOfChess * 2;

    // 动画组
    QParallelAnimationGroup *animationGroup = new QParallelAnimationGroup;

    // 棋子就位
	PieceItem *piece = NULL;
    for (int i = 0; i < n; i++)
	{
		piece = pieceList.at(i);
		// 将pieceList的下标转换为chess的棋子代号
		key = (i >= n/2) ? (i + 0x21 -n/2) : (i + 0x11);
		int j;
		// 放置棋盘上的棋子
		for (j = NineChess::SEAT; j < (NineChess::SEAT)*(NineChess::RING + 1); j++)
		{
			if (board[j] == key)
			{
				pos = scene.cp2pos(j / NineChess::SEAT, j % NineChess::SEAT + 1);
				if (piece->pos() != pos) {
                    QPropertyAnimation *animation = new QPropertyAnimation(piece, "pos");
					animation->setDuration(durationTime);
					animation->setStartValue(piece->pos());
					animation->setEndValue(pos);
					animation->setEasingCurve(QEasingCurve::InOutQuad);
					animationGroup->addAnimation(animation);
				}
				break;
			}
		}

		// 放置棋盘外的棋子
		if (j == (NineChess::SEAT)*(NineChess::RING + 1))
		{
			// 判断是被吃掉的子，还是未安放的子
			if (key & 0x10) {
				pos = (key - 0x11 < n / 2 - chess.getPlayer1_InHand()) ? scene.pos_p2_g : scene.pos_p1;
			}
			else
				pos = (key - 0x21 < n / 2 - chess.getPlayer2_InHand()) ? scene.pos_p1_g : scene.pos_p2;

			if (piece->pos() != pos) {
                QPropertyAnimation *animation = new QPropertyAnimation(piece, "pos");
                animation->setDuration(durationTime);
                animation->setStartValue(piece->pos());
                animation->setEndValue(pos);
				animation->setEasingCurve(QEasingCurve::InOutQuad);
				animationGroup->addAnimation(animation);
            }
        }
		piece->setSelected(false);
	}

	// 添加开局禁子点
	if (chess.getRule()->hasForbidden && chess.getPhase() == NineChess::GAME_OPENING)
	{
		for (int j = NineChess::SEAT; j < (NineChess::SEAT)*(NineChess::RING + 1); j++)
		{
			if (board[j] == 0x0F)
			{
				pos = scene.cp2pos(j / NineChess::SEAT, j % NineChess::SEAT + 1);
				if (n < pieceList.size())
				{
					pieceList.at(n++)->setPos(pos);
				}
				else
				{
					PieceItem *newP = new PieceItem;
					newP->setDeleted();
					newP->setPos(pos);
					pieceList.append(newP);
					n++;
					scene.addItem(newP);
				}
			}
		}
	}

	// 中局清除禁子点
	if (chess.getRule()->hasForbidden && chess.getPhase() != NineChess::GAME_OPENING)
	{
		while (n < pieceList.size())
		{
			delete pieceList.at(n);
			pieceList.removeAt(n);
		}
	}

	// 选中当前棋子
    int ipos = chess.getCurrentPos();
    if (ipos) {
		key = board[chess.getCurrentPos()];
		currentPiece = pieceList.at(key & 0x10 ? key - 0x11 : key - 0x21 + n/2);
		currentPiece->setSelected(true);
    }

    animationGroup->start(QAbstractAnimation::DeleteWhenStopped);

    return true;
}
