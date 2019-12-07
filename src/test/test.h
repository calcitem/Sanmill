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

#ifndef TEST_H
#define TEST_H

#include "config.h"

#ifdef TEST_MODE

#include <QObject>
#include <QSharedMemory>
#include <QString>
#include <QBuffer>

class Test : public QObject
{
    Q_OBJECT

public:
    Test();
    ~Test();

signals:
    void command(const QString &cmd, bool update = true);

public slots:
    void writeToMemory(const QString &str);
    void readFromMemory();

private:
    void detach();
    QString createUuidString();

private:
    const int SHARED_MEMORY_SIZE = 4096;
    QSharedMemory sharedMemory;
    QString uuid;
    int uuidSize;
    char *to { nullptr };
    QString readStr;
};

#endif // TEST_MODE
#endif // TEST_H
