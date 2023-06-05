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

#include <QThread>
#include <QtWidgets>
#include <random>

#include <QtCore>

#include "config.h"
#include "misc.h"
#include "option.h"
#include "test.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

#ifdef QT_UI_TEST_MODE
#ifdef QT_GUI_LIB
QString getAppFileName();
#endif
#endif /* QT_UI_TEST_MODE */

extern QString APP_FILENAME_DEFAULT;

Test::Test(QWidget *parent, QString k)
    : QDialog(parent)
    , keyCombo(new QComboBox)
    , startButton(new QPushButton(tr("Start")))
    , stopButton(new QPushButton(tr("Stop")))
{
    setWindowFlags(windowFlags() & ~Qt::WindowContextHelpButtonHint);

    this->key = k;

    readMemoryTimer = new QTimer(this);
    connect(readMemoryTimer, SIGNAL(timeout()), this, SLOT(onTimeOut()));
    readMemoryTimer->stop();

    keyCombo->setEditable(true);

    const QString keyPrefix = "Key";

    for (char i = '0'; i <= '9'; i++) {
        keyCombo->addItem(keyPrefix + i);
    }

#ifdef QT_UI_TEST_MODE
#ifdef QT_GUI_LIB
    QString appFileName = getAppFileName();
    if (appFileName != APP_FILENAME_DEFAULT) {
        keyCombo->addItem(QString(appFileName));
    }
#endif // QT_GUI_LIB

#endif // QT_UI_TEST_MODE

    const auto keyLabel = new QLabel(tr("&Key:"));
    keyLabel->setBuddy(keyCombo);

    startButton->setDefault(true);
    startButton->setEnabled(true);
    stopButton->setEnabled(false);

    const auto closeButton = new QPushButton(tr("Close"));
    const auto buttonBox = new QDialogButtonBox;
    buttonBox->addButton(startButton, QDialogButtonBox::ActionRole);
    buttonBox->addButton(stopButton, QDialogButtonBox::ActionRole);
    buttonBox->addButton(closeButton, QDialogButtonBox::RejectRole);

    connect(startButton, &QAbstractButton::clicked, this, &Test::startAction);
    connect(stopButton, &QAbstractButton::clicked, this, &Test::stopAction);
    connect(closeButton, &QAbstractButton::clicked, this, &QWidget::close);

    QGridLayout *mainLayout;
    if (QGuiApplication::styleHints()->showIsFullScreen() ||
        QGuiApplication::styleHints()->showIsMaximized()) {
        const auto outerVerticalLayout = new QVBoxLayout(this);
        outerVerticalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::Ignored, QSizePolicy::MinimumExpanding));

        const auto outerHorizontalLayout = new QHBoxLayout;
        outerHorizontalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::MinimumExpanding, QSizePolicy::Ignored));

        const auto groupBox = new QGroupBox(
            QGuiApplication::applicationDisplayName());
        mainLayout = new QGridLayout(groupBox);
        outerHorizontalLayout->addWidget(groupBox);

        outerHorizontalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::MinimumExpanding, QSizePolicy::Ignored));
        outerVerticalLayout->addLayout(outerHorizontalLayout);
        outerVerticalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::Ignored, QSizePolicy::MinimumExpanding));
    } else {
        mainLayout = new QGridLayout(this);
    }

    mainLayout->addWidget(keyLabel, 0, 0);
    mainLayout->addWidget(keyCombo, 0, 1);
    mainLayout->addWidget(buttonBox, 3, 0, 1, 2);

    setWindowTitle(QGuiApplication::applicationDisplayName());
}

Test::~Test()
{
    detach();
    readMemoryTimer->stop();
}

void Test::stop()
{
    detach();
    isTestMode = false;
    readMemoryTimer->stop();
}

void Test::attach()
{
    sharedMemory.setKey(key);

    if (sharedMemory.attach()) {
        debugPrintf("Attached shared memory segment.\n");
    } else {
        if (sharedMemory.create(SHARED_MEMORY_SIZE)) {
            debugPrintf("Created shared memory segment.\n");
        } else {
            debugPrintf("Unable to create shared memory segment.\n");
        }
    }

    to = static_cast<char *>(sharedMemory.data());

    uuid = createUuidString();
    uuidSize = uuid.size();

    assert(uuidSize == 38);
}

void Test::detach()
{
    if (sharedMemory.isAttached()) {
        if (sharedMemory.detach()) {
            debugPrintf("Detached shared memory segment.\n");
        }
    }
}

void Test::writeToMemory(const QString &record)
{
    if (!isTestMode) {
        return;
    }

    if (record == readStr) {
        return;
    }

    char from[BUFSIZ] = {0};
#ifdef _MSC_VER
    strncpy_s(from, BUFSIZ, record.toStdString().c_str(), BUFSIZ);
#else
    strncpy(from, record.toStdString().c_str(), BUFSIZ);
#endif // _MSC_VER

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
    if (!isTestMode) {
        return;
    }

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

#if defined(MADWEASEL_MUEHLE_PERFECT_AI)
            if (gameOptions.getPerfectAiEnabled()) {
                perfect_command(str.toStdString().c_str());
            }
#endif

            emit command(str.toStdString());
        }
    }
}

QString Test::createUuidString()
{
    return QUuid::createUuid().toString();
}

void Test::startAction()
{
    key = keyCombo->currentText();

    detach();
    attach();

    isTestMode = true;
    readMemoryTimer->start(100);

    startButton->setEnabled(false);
    stopButton->setEnabled(true);
}

void Test::stopAction()
{
    stop();

    startButton->setEnabled(true);
    stopButton->setEnabled(false);
}

void Test::onTimeOut()
{
    readFromMemory();
}
