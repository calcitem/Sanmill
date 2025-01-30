// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// ai_shared_memory_dialog.cpp

#include <QThread>
#include <QtWidgets>
#include <random>

#include <QtCore>

#include "config.h"
#include "misc.h"
#include "option.h"
#include "ai_shared_memory_dialog.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

#ifdef QT_UI_TEST_MODE
#ifdef QT_GUI_LIB
QString getAppFileName();
#endif
#endif /* QT_UI_TEST_MODE */

extern QString APP_FILENAME_DEFAULT;

AiSharedMemoryDialog::AiSharedMemoryDialog(QWidget *parent, QString k)
    : QDialog(parent)
    , keyCombo(new QComboBox)
    , startButton(new QPushButton(tr("Start")))
    , stopButton(new QPushButton(tr("Stop")))
{
    const auto instructionLabel = new QLabel(tr("This feature is generally "
                                                "used to test the AI's "
                                                "performance locally. "
                                                "\n"
                                                "Open two instances of the "
                                                "application. \n"
                                                "To have them duel, set the "
                                                "same Key on both sides and "
                                                "click Start. \n"
                                                "In one instance, set White "
                                                "to be the AI and Black to be "
                                                "non-AI; \n"
                                                "do the opposite in the other "
                                                "instance. \n"
                                                "The two programs "
                                                "can then duel using shared "
                                                "memory."));

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

    connect(startButton, &QAbstractButton::clicked, this,
            &AiSharedMemoryDialog::startAction);
    connect(stopButton, &QAbstractButton::clicked, this,
            &AiSharedMemoryDialog::stopAction);
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

    mainLayout->setRowStretch(0, 1);
    mainLayout->setRowStretch(1, 0);
    mainLayout->setRowStretch(2, 0);

    auto scrollArea = new QScrollArea;
    scrollArea->setWidget(instructionLabel);
    mainLayout->addWidget(scrollArea, 0, 0, 1, 2);

    mainLayout->addWidget(keyLabel, 1, 0, 1, 1);
    mainLayout->addWidget(keyCombo, 1, 1, 1, 1);
    mainLayout->addWidget(buttonBox, 2, 0, 1, 2);

    setWindowTitle(tr("AI Shared Memory Configuration"));
}

AiSharedMemoryDialog::~AiSharedMemoryDialog()
{
    detach();
    readMemoryTimer->stop();
}

void AiSharedMemoryDialog::stop()
{
    detach();
    isTestMode = false;
    readMemoryTimer->stop();
}

void AiSharedMemoryDialog::attach()
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

void AiSharedMemoryDialog::detach()
{
    if (sharedMemory.isAttached()) {
        if (sharedMemory.detach()) {
            debugPrintf("Detached shared memory segment.\n");
        }
    }
}

void AiSharedMemoryDialog::writeToMemory(const QString &record)
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
    strncpy(from, record.toStdString().c_str(), BUFSIZ - 1);
    from[BUFSIZ - 1] = '\0';
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

void AiSharedMemoryDialog::readFromMemory()
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
            emit command(str.toStdString());
        }
    }
}

QString AiSharedMemoryDialog::createUuidString()
{
    return QUuid::createUuid().toString();
}

void AiSharedMemoryDialog::startAction()
{
    key = keyCombo->currentText();

    detach();
    attach();

    isTestMode = true;
    readMemoryTimer->start(100);

    startButton->setEnabled(false);
    stopButton->setEnabled(true);
}

void AiSharedMemoryDialog::stopAction()
{
    stop();

    startButton->setEnabled(true);
    stopButton->setEnabled(false);
}

void AiSharedMemoryDialog::onTimeOut()
{
    readFromMemory();
}
