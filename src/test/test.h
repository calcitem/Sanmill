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

#include <QObject>
#include <QComboBox>
#include <QLabel>
#include <QSharedMemory>
#include <QString>
#include <QBuffer>
#include <QDialog>

class Test : public QDialog
{
    Q_OBJECT

public:
    explicit Test(QWidget *parent = nullptr, QString key = "MillGame-Key-0");
    ~Test();

    void setKey(QString k)
    {
        key = k;
    }

    QString getKey()
    {
        return key;
    }

    void stop();

signals:
    void command(const QString &cmd, bool update = true);

public slots:
    void writeToMemory(const QString &str);
    void readFromMemory();
    void startAction();
    void stopAction();
    void onTimeOut();

private:
    void attach();
    void detach();
    QString createUuidString();

private:
    static const int SHARED_MEMORY_SIZE = 4096;
    QSharedMemory sharedMemory;
    QString uuid;
    int uuidSize;
    char *to { nullptr };
    QString readStr;

    QString key;

    QComboBox *keyCombo = nullptr;
    QLabel *statusLabel = nullptr;
    QPushButton *startButton = nullptr;
    QPushButton *stopButton = nullptr;

    bool isTestMode { false };
    QTimer *readMemoryTimer;
};

#endif // TEST_H
