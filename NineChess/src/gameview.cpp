#include "gameview.h"
#include <QMatrix>
#include <QDebug>

GameView::GameView(QWidget * parent) :
    QGraphicsView(parent)
{
    Q_UNUSED(parent)
    /* 不使用下面的方法
    // 初始化缩放因子为1.0
    sx = 1.0;
    sy = 1.0;
    */
}

GameView::~GameView()
{
}

void GameView::flip()
{
    // 视图上下翻转
    /* 以下用到了很多图形变换矩阵方面的知识
     * 不要用scale方法，Qt的图形变换是针对坐标系的
     * 缩放矩阵为
     *     ┌sx  0  0┐
     * S = │ 0 sy  0│
     *     └ 0  0  1┘
     * 上下翻转应在原变换矩阵基础上乘以一个如下的矩阵：
     * ┌1  0  0┐
     * │0 -1  0│
     * └0  0  1┘
     */
     // 方法一: 直接在原变换矩阵基础上乘以上面的矩阵
     // QMatrix只对变换矩阵前两列赋值
    setMatrix(matrix() * QMatrix(1, 0, 0, -1, 0, 0));
    /* 方法二: 人工计算好新的变换矩阵后再对场景赋值
     * 这个方法的效率未必高，还需要人工计算
    QMatrix mt = matrix();
    mt.setMatrix(-mt.m11(), mt.m12(), -mt.m21(), mt.m22(), -mt.dx(), mt.dy());
    setMatrix(mt);
     */
}

void GameView::mirror()
{
    // 视图左右镜像
    /* 左右镜像应在原变换矩阵基础上乘以一个如下的矩阵：
     * ┌-1  0  0┐
     * │ 0  1  0│
     * └ 0  0  1┘
     */
    setMatrix(matrix() * QMatrix(-1, 0, 0, 1, 0, 0));
}

void GameView::turnRight()
{
    // 视图须时针旋转90°
    /* 不要用scale方法，视图镜像或翻转后它的转向会反过来
     * 旋转矩阵为
     *     ┌ cos(α)  sin(α)  0┐
     * R = │-sin(α)  cos(α)  0│
     *     └   0       0     1┘
     * 视图须时针旋转90°应在原变换矩阵基础上乘以一个如下的矩阵：
     * ┌ 0  1  0┐
     * │-1  0  0│
     * └ 0  0  1┘
     */
    setMatrix(matrix() * QMatrix(0, 1, -1, 0, 0, 0));
}

void GameView::turnLeft()
{
    // 视图逆时针旋转90°
    /* 视图逆时针旋转90°应在原变换矩阵基础上乘以一个如下的矩阵：
     * ┌0 -1  0┐
     * │1  0  0│
     * └0  0  1┘
     */
    setMatrix(matrix() * QMatrix(0, -1, 1, 0, 0, 0));
}


void GameView::resizeEvent(QResizeEvent * event)
{
    /* 不使用下面的形式了
    // 让场景适合视图
    if (sceneRect().width() <= 0 || sceneRect().height() <= 0)
        return;
    // 恢复缩放前的大小
    scale(1 / sx, 1 / sy);
    // 设置缩放因子
    sx = width() / sceneRect().width();
    sy = height() / sceneRect().height();
    sx = sx < sy ? sx : sy;
    sy = sx;
    // 缩放视图适合场景大小
    scale(sx, sy);
    //qDebug() << "scale :" << sx;
    */
    // 使用如下形式，更简洁
    QGraphicsView::resizeEvent(event);
    fitInView(sceneRect(), Qt::KeepAspectRatio);
}

