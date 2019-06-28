// 派生这个类主要是为了让视图适应场景大小及图像旋转镜像操作
#ifndef GRAPHICSVIEW_H
#define GRAPHICSVIEW_H

#include <QGraphicsView>

#include "config.h"

class GameView : public QGraphicsView
{
    Q_OBJECT

public:
    explicit GameView(QWidget *parent);
    ~GameView();

public slots:
    void flip();
    void mirror();
    void turnRight();
    void turnLeft();

protected:
    void resizeEvent(QResizeEvent *event);

private:
    // 缩放因子，代码更新后不使用了
    // qreal sx, sy;
};

#endif // GRAPHICSVIEW_H
