// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// winmain.cpp

#include "bitboard.h"
#include "gamewindow.h"
#include "position.h"

QString APP_FILENAME_DEFAULT = "mill-pro";

#ifdef QT_GUI_LIB
#include <QCoreApplication>
#include <QResource>
#include <QScreen>
#include <QTranslator>
#include <QtWidgets/QApplication>

#ifndef UCT_DEMO

QString getAppFileName()
{
    QString filename = QCoreApplication::applicationFilePath().mid(
        QCoreApplication::applicationDirPath().size() + 1);
    filename = filename.mid(0, filename.size() - QString(".exe").size());

    return filename;
}

int main(int argc, char *argv[])
{
    Bitboards::init();
    Position::init();

    QResource::registerResource("gamewindow.rcc");

    QApplication a(argc, argv);
    QTranslator translator;
    if (!translator.load("mill-pro-qt_zh_CN")) {
        qWarning() << "Failed to load translation file.";
    }
    a.installTranslator(&translator);
    MillGameWindow w;
    w.show();

    w.setWindowTitle(getAppFileName() + " (" +
                     QString::number(QCoreApplication::applicationPid()) + ")");

#ifndef _DEBUG
    const QRect desktopRect = QGuiApplication::primaryScreen()->geometry();
    w.move((desktopRect.width() - w.width()) / 4,
           (desktopRect.height() - w.height()) / 2);
#endif

    return QApplication::exec();
}

#endif // !UCT_DEMO
#endif // QT_GUI_LIB
