// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ai_shared_memory_dialog.h

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

class AiSharedMemoryDialog : public QDialog
{
    Q_OBJECT

public:
    explicit AiSharedMemoryDialog(QWidget *parent = nullptr, QString k = "Key"
                                                                         "0");
    ~AiSharedMemoryDialog() override;

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
    qsizetype uuidSize {0};
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
