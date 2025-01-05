// gameview.h

#ifndef GAME_VIEW_H_INCLUDED
#define GAME_VIEW_H_INCLUDED

#include "config.h"

#include <QGraphicsView>

enum class TransformType {
    FlipVertically,
    FlipHorizontally,
    RotateClockwise,
    RotateCounterclockwise
};

// This class is mainly derived to make the view adapt to the scene size and
// image rotation flipHorizontally operation
class GameView : public QGraphicsView
{
    Q_OBJECT

public:
    explicit GameView(QWidget *parent);
    ~GameView() override;

public slots:
    void flipVertically();
    void flipHorizontally();
    void rotateClockwise();
    void RotateCounterclockwise();

protected:
    void resizeEvent(QResizeEvent *event) override;

private:
    void applyTransform(TransformType type);
};

#endif // GAME_VIEW_H_INCLUDED
