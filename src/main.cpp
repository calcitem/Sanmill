/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019 Calcitem <calcitem@outlook.com>

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

#include <QtWidgets/QApplication>
#include <QDesktopWidget>

#include "gamewindow.h"
#include "misc.h"

QString APP_FILENAME_DEFAULT = "MillGame";

#ifndef TRAINING_MODE
#ifndef UCT_DEMO
int main(int argc, char *argv[])
{
    QApplication a(argc, argv);
    MillGameWindow w;   
    w.show();

    w.setWindowTitle(getAppFileName() +  " (" + QString::number(QCoreApplication::applicationPid()) + ")");

#ifndef _DEBUG
    w.move((QApplication::desktop()->width() - w.width()) / 4, (QApplication::desktop()->height() - w.height()) / 2);
#endif

    return QApplication::exec();
}
#endif // !UCT_DEMO
#endif // !TRAINING_MODE
