#include "ninechesswindow.h"
#include <QtWidgets/QApplication>

int main(int argc, char *argv[])
{
    QApplication a(argc, argv);
    NineChessWindow w;
    w.show();
    return a.exec();
}
