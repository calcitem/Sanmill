/*
  This file is part of Sanmill.
  Copyright (C) 2019-2021 The Sanmill developers (see AUTHORS file)

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "gamewindow.h"
#include "misc.h"
#include "bitboard.h"
#include "position.h"

QString APP_FILENAME_DEFAULT = "MillGame";

#ifdef  QT_GUI_LIB
#include <QtWidgets/QApplication>
#include <QDesktopWidget>
#include <QCoreApplication>
#include <QResource>
#include <QTranslator>

#ifndef UCT_DEMO

QString getAppFileName()
{
    QString filename;
    filename = QCoreApplication::applicationFilePath().mid(QCoreApplication::applicationDirPath().size() + 1);
    filename = filename.mid(0, filename.size() - QString(".exe").size());

    return filename;
}

#ifndef MADWEASEL_MUEHLE_PERFECT_AI_TEST
int main(int argc, char *argv[])
{
    Bitboards::init();
    Position::init();

    QResource::registerResource("gamewindow.rcc");

    QApplication a(argc, argv);
    QTranslator translator;
    translator.load("millgame-qt_zh_CN");
    a.installTranslator(&translator);
    MillGameWindow w;   
    w.show();

    w.setWindowTitle(getAppFileName() +  " (" + QString::number(QCoreApplication::applicationPid()) + ")");

#ifndef _DEBUG
    w.move((QApplication::desktop()->width() - w.width()) / 4, (QApplication::desktop()->height() - w.height()) / 2);
#endif

    return QApplication::exec();
}
#endif // !MADWEASEL_MUEHLE_PERFECT_AI_TEST

#endif // !UCT_DEMO
#endif // QT_GUI_LIB
