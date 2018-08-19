#ifndef BOARDITEM_H
#define BOARDITEM_H

#include <QGraphicsItem>

class BoardItem : public QGraphicsItem
{
public:
    explicit BoardItem(QGraphicsItem *parent = 0);
    ~BoardItem();
    QRectF boundingRect() const;
    QPainterPath shape() const;
    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
        QWidget * widget = 0);
    // 用UserType+1表示棋子，用qgraphicsitem_cast()判断是否为BoardItem类的对象
    // 还有一个方式是把类名放在Data的0key位置setData(0, "BoardItem")，然后用data(0)来判断
    enum { Type = UserType + 1 };
    int type() const { return Type; }
    // 设置有无斜线
    void setDiagonal(bool arg = true);
    // 返回最近的落子点
    QPointF nearestPosition(QPointF const pos);
    // 将模型的圈、位转化为落子点坐标
    QPointF cp2pos(int c, int p);
    // 将落子点坐标转化为模型用的圈、位
    bool pos2cp(QPointF pos, int &c, int &p);

    // 3圈，禁止修改！
    static const int RING = 3;
    // 8位，禁止修改！
    static const int SEAT = 8;
private:
    // 棋盘尺寸
    qreal size;
    // 影子尺寸
    qreal sizeShadow;
    // 24个落子点
    QPointF position[RING * SEAT];
    // 是否有斜线
    bool hasObliqueLine;
};

#endif // BOARDITEM_H
