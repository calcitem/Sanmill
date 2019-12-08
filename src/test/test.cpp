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

#include "config.h"

#include <QBuffer>
#include <QUuid>
#include <QDataStream>
#include <QString>
#include <QThread>
#include <random>

#include "test.h"

Test::Test()
{
    sharedMemory.setKey("MillGameSharedMemory");

    if (sharedMemory.attach()) {
        loggerDebug("Attached shared memory segment.\n");
    } else {
        if (sharedMemory.create(SHARED_MEMORY_SIZE)) {
            loggerDebug("Created shared memory segment.\n");
        } else {
            loggerDebug("Unable to create shared memory segment.\n");
        }
    }

    to = (char *)sharedMemory.data();

    uuid = createUuidString();
    uuidSize = uuid.size();

    assert(uuidSize == 38);
}

Test::~Test()
{
    detach();
}

void Test::writeToMemory(const QString &cmdline)
{
    if (cmdline == readStr) {
        return;
    }

    char from[128] = { 0 };
    strcpy(from, cmdline.toStdString().c_str());

    while (true) {
        sharedMemory.lock();

        if (to[0] != 0) {
            sharedMemory.unlock();
            QThread::msleep(100);
            continue;
        }

        memset(to, 0, SHARED_MEMORY_SIZE);
        memcpy(to, uuid.toStdString().c_str(), uuidSize);
        memcpy(to + uuidSize, from, strlen(from));
        sharedMemory.unlock();

        break;
    }
}

void Test::readFromMemory()
{
    sharedMemory.lock();
    QString str = to;
    sharedMemory.unlock();

    if (str.size() == 0) {
        return;
    }

    if (!(str.mid(0, uuidSize) == uuid)) {
        str = str.mid(uuidSize);
        if (str.size()) {
            sharedMemory.lock();
            memset(to, 0, SHARED_MEMORY_SIZE);
            sharedMemory.unlock();
            readStr = str;
            emit command(str);
        }
    }
}

void Test::detach()
{
    if (sharedMemory.isAttached()) {
        sharedMemory.detach();
    }
}

QString Test::createUuidString()
{
    return QUuid::createUuid().toString();
}
