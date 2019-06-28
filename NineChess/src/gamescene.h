#ifndef GAMESCENE_H
#define GAMESCENE_H

#include <QGraphicsScene>

#include "config.h"

class BoardItem;

class GameScene : public QGraphicsScene
{
    Q_OBJECT
public:
    explicit GameScene(QObject *parent = nullptr);
    ~GameScene();

    // 将模型的圈、位转化为落子点坐标
    QPointF cp2pos(int c, int p);

    // 将落子点坐标转化为模型用的圈、位
    bool pos2cp(QPointF pos, int &c, int &p);

    // 设置棋盘斜线
    void setDiagonal(bool arg = true);

    // 玩家1的己方棋盒及对方棋盒位置
    const QPointF pos_p1, pos_p1_g;

    // 玩家2的己方棋盒及对方棋盒位置
    const QPointF pos_p2, pos_p2_g;

protected:
    //void keyPressEvent(QKeyEvent *keyEvent);
    void mouseDoubleClickEvent(QGraphicsSceneMouseEvent *mouseEvent);
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent);
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent);

signals:
    void mouseReleased(QPointF);

public slots:

private:
    // 棋盘对象
    BoardItem *board;

};

#endif // GAMESCENE_H
