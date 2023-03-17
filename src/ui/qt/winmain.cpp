// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#include "bitboard.h"
#include "gamewindow.h"
#include "misc.h"
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

void initializeResources()
{
    Bitboards::init();
    Position::init();
    QResource::registerResource("gamewindow.rcc");
}

void setupTranslator(QApplication &app)
{
    QTranslator translator;
    translator.load("mill-pro-qt_zh_CN");
    app.installTranslator(&translator);
}

void centerWindowOnScreen(MillGameWindow &window)
{
    const QRect desktopRect = QGuiApplication::primaryScreen()->geometry();
    window.move((desktopRect.width() - window.width()) / 4,
                (desktopRect.height() - window.height()) / 2);
}

#ifndef MADWEASEL_MUEHLE_PERFECT_AI_TEST
int main(int argc, char *argv[])
{
    initializeResources();

    QApplication app(argc, argv);
    setupTranslator(app);

    MillGameWindow window;
    window.setWindowTitle(getAppFileName() + " (" +
                          QString::number(QCoreApplication::applicationPid()) +
                          ")");
    window.show();

#ifndef _DEBUG
    centerWindowOnScreen(window);
#endif

    return QApplication::exec();
}
#endif // !MADWEASEL_MUEHLE_PERFECT_AI_TEST

#endif // !UCT_DEMO
#endif // QT_GUI_LIB
