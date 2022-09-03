// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

#ifndef TEST_H_INCLUDED
#define TEST_H_INCLUDED

#include <QBuffer>
#include <QComboBox>
#include <QDialog>
#include <QLabel>
#include <QObject>
#include <QSharedMemory>
#include <QString>
#include <string>

#include "config.h"

using std::string;

class Test : public QDialog
{
    Q_OBJECT

public:
    explicit Test(QWidget *parent = nullptr, QString k = "Key0");
    ~Test() override;

    void setKey(const QString &k) noexcept { key = k; }

    QString getKey() noexcept { return key; }

    void stop();

signals:
    void command(const string &cmd, bool update = true);

public slots:
    void writeToMemory(const QString &record);
    void readFromMemory();
    void startAction();
    void stopAction();
    void onTimeOut();

private:
    void attach();
    void detach();
    static QString createUuidString();

    static constexpr int SHARED_MEMORY_SIZE = 4096;
    QSharedMemory sharedMemory;
    QString uuid;
    int uuidSize;
    char *to {nullptr};
    QString readStr;

    QString key;

    QComboBox *keyCombo = nullptr;
    QLabel *statusLabel = nullptr;
    QPushButton *startButton = nullptr;
    QPushButton *stopButton = nullptr;

    bool isTestMode {false};
    QTimer *readMemoryTimer;
};

#endif // TEST_H_INCLUDED
