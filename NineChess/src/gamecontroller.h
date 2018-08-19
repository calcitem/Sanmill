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
//#include "sizehintlistview.h"

class PieceItem;

class GameController : public QObject
{
    Q_OBJECT

public:
    GameController(GameScene &scene, QObject *parent = 0);
    ~GameController();
    //主窗口菜单栏明细
    const QMap <int, QStringList> getActions();
    int getRuleNo() { return ruleNo; }
    int getTimeLimit() { return timeLimit; }
    int getStepsLimit() { return stepsLimit; }
    // 文本流
    QTextStream textStream;
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
    void playSound(QString &soundPath);
    // 根据QGraphicsScene的信号和状态来执行选子、落子或去子
    bool actionPiece(QPointF p);
    // 历史局面及局面改变
    void phaseChange(int row, bool change = false);

protected:
    bool eventFilter(QObject * watched, QEvent * event);
    // 定时器
    void timerEvent(QTimerEvent * event);
    // 选子
    PieceItem *choosePiece(QPointF pos);
    // 落下新子
    PieceItem *placePiece(QPointF pos);
    // 移动旧子
    bool movePiece(QPointF pos);
    // 去子
    bool removePiece(QPointF pos);
    // 删除禁止点子
    bool cleanForbidden();
    // 更新棋局显示
    bool updateScence(NineChess &chess);

private:
    // 棋对象的数据模型
    NineChess chess;
    // 棋对象的数据模型（临时）
    NineChess chessTemp;
    // 棋局的场景类
    GameScene &scene;
    // 棋谱列表
    //SizeHintListView &listView;
    // 所有棋子
    QList<PieceItem *> pieceList;
    // 当前棋子
    PieceItem *piece;
    // 玩家1手棋数、玩家2手棋数、待去棋数
    int player1_InHand, player2_InHand, num_NeedRemove;
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
    // 是否有落子音效
    bool hasSound;
    // 定时器ID
    int timeID;
    // 规则变化
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

    // 各个音效文件路径
    QString soundNewgame;
    QString soundChoose;
    QString soundMove;
    QString soundDrog;
    QString soundForbidden;
    QString soundRemove;
    QString soundWin;
    QString soundLoss;
};

#endif // GAMECONTROLLER_H
