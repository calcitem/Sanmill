/* 这个类处理场景对象QGraphicsScene
 * 它是本程序MVC模型中唯一的控制模块
 * 它不对主窗口中的控件做任何操作，只向主窗口发出信号
 * 本来可以重载QGraphicsScene实现它，还能省去写事件过滤器的麻烦
 * 但用一个场景类做那么多控制模块的操作看上去不太好
 */

#ifndef GAMECONTROLLER_H
#define GAMECONTROLLER_H

#include <QTime>
#include <QPointF>
#include <QMap>
#include <QList>
#include <QTextStream>
#include <QStringListModel>
#include <QModelIndex>
#include "ninechess.h"
#include "gamescene.h"
#include "pieceitem.h"
#include "aithread.h"

class GameController : public QObject
{
    Q_OBJECT

public:
    GameController(GameScene &scene, QObject *parent = nullptr);
    ~GameController();
    //主窗口菜单栏明细
    const QMap <int, QStringList> getActions();
    int getRuleNo() { return ruleNo; }
    int getTimeLimit() { return timeLimit; }
    int getStepsLimit() { return stepsLimit; }
	bool isAnimation() { return hasAnimation; }
	void setDurationTime(int i) { durationTime = i; }
	int getDurationTime() { return durationTime; }
    // 棋谱字符串列表模型
    QStringListModel manualListModel;

signals:
    // 玩家1(先手）用时改变的信号
    void time1Changed(const QString &time);
    // 玩家2(后手）用时改变的信号
    void time2Changed(const QString &time);
    // 通知主窗口更新状态栏的信号
    void statusBarChanged(const QString & message);

public slots:
    // 设置规则
    void setRule(int ruleNo, int stepLimited = -1, int timeLimited = -1);
    // 游戏开始
    void gameStart();
    // 游戏重置
    void gameReset();
    // 设置编辑棋局状态
    void setEditing(bool arg = true);
    // 设置黑白反转状态
    void setInvert(bool arg = true);
    // 让电脑执先手
    void setEngine1(bool arg = true);
    // 让电脑执后手
    void setEngine2(bool arg = true);
    // 是否有落子动画
    void setAnimation(bool arg = true);
    // 是否有落子音效
    void setSound(bool arg = true);
    // 播放声音
    void playSound(const QString &soundPath);
    // 根据QGraphicsScene的信号和状态来执行选子、落子或去子
    bool actionPiece(QPointF p);
	// 认输
	bool giveUp();
    // 棋谱的命令行执行
    bool command(QString &cmd, bool update = true);
    // 历史局面及局面改变
    bool phaseChange(int row);
    // 更新棋局显示，每步后必须执行
    bool updateScence();
    bool updateScence(NineChess &chess);

protected:
    bool eventFilter(QObject * watched, QEvent * event);
    // 定时器
    void timerEvent(QTimerEvent * event);
    // 选子
    bool choosePiece(QPointF pos);
    // 落下新子
    bool placePiece(QPointF pos);
    // 移动旧子
    bool movePiece(QPointF pos);
    // 去子
    bool removePiece(QPointF pos);

private:
    // 棋对象的数据模型
    NineChess chess;
    // 棋对象的数据模型（临时）
    NineChess chessTemp;
    // 2个AI的线程
    AiThread ai1, ai2;
    // 棋局的场景类
    GameScene &scene;
    // 所有棋子
    QList<PieceItem *> pieceList;
    // 当前棋子
    PieceItem *currentPiece;
    // 当前浏览的棋谱行
    int currentRow;
    // 玩家1手棋数、玩家2手棋数、待去棋数，没有用到，注释掉
    //int player1_InHand, player2_InHand, num_NeedRemove;
    // 是否处于“编辑棋局”状态
    bool isEditing;
    // 是否黑白反转
    bool isInverted;
    // 是否电脑执先手
    bool isEngine1;
    // 是否电脑执后手
    bool isEngine2;
    // 是否有落子动画
    bool hasAnimation;
	// 动画持续时间
	int durationTime;
	// 是否有落子音效
    bool hasSound;
    // 定时器ID
    int timeID;
    // 规则号
    int ruleNo;
    // 规则限时（分钟）
    int timeLimit;
    // 规则限步数
    int stepsLimit;
    // 玩家1剩余时间（毫秒）
    int time1;
    // 玩家2剩余时间（毫秒）
    int time2;
    // 用于主窗口状态栏显示的字符串
    QString message;

};

#endif // GAMECONTROLLER_H
