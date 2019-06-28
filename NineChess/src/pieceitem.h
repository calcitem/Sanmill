#ifndef CHESSITEM_H
#define CHESSITEM_H

#include <QObject>
#include <QGraphicsItem>

#include "config.h"

class PieceItem : public QObject, public QGraphicsItem
{
    Q_OBJECT
        Q_INTERFACES(QGraphicsItem)

        // 位置属性
        Q_PROPERTY(QPointF pos READ pos WRITE setPos)

public:
    explicit PieceItem(QGraphicsItem *parent = nullptr);

    ~PieceItem();

    QRectF boundingRect() const;

    QPainterPath shape() const;

    void paint(QPainter *painter, const QStyleOptionGraphicsItem *option,
               QWidget *widget = nullptr);

    // 用UserType+2表示棋子，用qgraphicsitem_cast()判断是否为PieceItem类的对象
    // 还有一个方式是把类名放在Data的0key位置setData(0, "PieceItem")，然后用data(0)来判断
    enum
    {
        Type = UserType + 2
    };

    int type() const
    {
        return Type;
    }

    // 模型状态枚举，用位运算标明
    enum Models
    {
        noPiece = 0x1,      // 空棋子
        blackPiece = 0x2,   // 黑色棋子
        whitePiece = 0x4,   // 白色棋子
    };

    enum Models getModel()
    {
        return model_;
    }

    void setModel(enum Models model)
    {
        this->model_ = model;
    }

    int getNum()
    {
        return num;
    }

    void setNum(int n)
    {
        num = n;
    }

    bool isDeleted()
    {
        return deleted_;
    }

    void setDeleted(bool deleted = true)
    {
        this->deleted_ = deleted;

        if (deleted)
            this->model_ = noPiece;

        update(boundingRect());
    }

    void setShowNum(bool show = true)
    {
        this->showNum = show;
    }

protected:
    void mousePressEvent(QGraphicsSceneMouseEvent *mouseEvent);
    void mouseMoveEvent(QGraphicsSceneMouseEvent *mouseEvent);
    void mouseReleaseEvent(QGraphicsSceneMouseEvent *mouseEvent);

private:
    // 棋子本质
    enum Models model_;

    // 棋子序号，黑白都从1开始
    int num;

    // 棋子尺寸
    qreal size;

    // 有无删除线
    bool deleted_;

    // 显示序号
    bool showNum;

    // 选中子标识线宽度
    qreal chooseLineWeight;

    // 删除线宽度
    qreal removeLineWeight;

    // 选中线颜色
    QColor chooseLineColor;

    // 删除线颜色
    QColor removeLineColor;
};

#endif // CHESSITEM_H
