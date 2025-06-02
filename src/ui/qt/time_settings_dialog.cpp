// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// time_settings_dialog.cpp

#include "time_settings_dialog.h"
#include <QSettings>
#include <QGroupBox>

// Available time options in seconds: 0 (no limit), 1s, 5s, 10s, 15s, 20s, 30s,
// 45s, 60s, 100s
const QList<int> TimeSettingsDialog::timeOptions = {0,  1,  5,  10, 15,
                                                    20, 30, 45, 60, 100};
// Available move limit options: 10, 30, 50, 60, 100, 200 moves
const QList<int> TimeSettingsDialog::moveOptions = {10, 30, 50, 60, 100, 200};

TimeSettingsDialog::TimeSettingsDialog(QWidget *parent)
    : QDialog(parent)
    , mainLayout(nullptr)
    , whiteLayout(nullptr)
    , blackLayout(nullptr)
    , moveLayout(nullptr)
    , buttonLayout(nullptr)
    , titleLabel(nullptr)
    , whiteLabel(nullptr)
    , blackLabel(nullptr)
    , moveLabel(nullptr)
    , whiteTimeCombo(nullptr)
    , blackTimeCombo(nullptr)
    , moveLimitCombo(nullptr)
    , buttonBox(nullptr)
{
    setupUI();
    setupConnections();
    populateTimeOptions();
    populateMoveOptions();
}

void TimeSettingsDialog::setupUI()
{
    setWindowTitle(tr("Game Settings"));
    setModal(true);
    setFixedSize(350, 280);

    // Main layout
    mainLayout = new QVBoxLayout(this);

    // Title
    titleLabel = new QLabel(tr("Configure game settings:"), this);
    titleLabel->setStyleSheet("font-weight: bold; margin-bottom: 10px;");
    mainLayout->addWidget(titleLabel);

    // White player section
    QGroupBox *whiteGroup = new QGroupBox(tr("White Player Time Limit"), this);
    whiteLayout = new QHBoxLayout(whiteGroup);
    whiteLabel = new QLabel(tr("Time:"), whiteGroup);
    whiteTimeCombo = new QComboBox(whiteGroup);
    whiteTimeCombo->setMinimumWidth(100);
    whiteLayout->addWidget(whiteLabel);
    whiteLayout->addWidget(whiteTimeCombo);
    whiteLayout->addStretch();
    mainLayout->addWidget(whiteGroup);

    // Black player section
    QGroupBox *blackGroup = new QGroupBox(tr("Black Player Time Limit"), this);
    blackLayout = new QHBoxLayout(blackGroup);
    blackLabel = new QLabel(tr("Time:"), blackGroup);
    blackTimeCombo = new QComboBox(blackGroup);
    blackTimeCombo->setMinimumWidth(100);
    blackLayout->addWidget(blackLabel);
    blackLayout->addWidget(blackTimeCombo);
    blackLayout->addStretch();
    mainLayout->addWidget(blackGroup);

    // Move limit section
    QGroupBox *moveGroup = new QGroupBox(tr("Move Limit"), this);
    moveLayout = new QHBoxLayout(moveGroup);
    moveLabel = new QLabel(tr("N-Move Rule:"), moveGroup);
    moveLimitCombo = new QComboBox(moveGroup);
    moveLimitCombo->setMinimumWidth(100);
    moveLayout->addWidget(moveLabel);
    moveLayout->addWidget(moveLimitCombo);
    moveLayout->addStretch();
    mainLayout->addWidget(moveGroup);

    // Button box
    buttonBox = new QDialogButtonBox(
        QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    mainLayout->addWidget(buttonBox);

    setLayout(mainLayout);
}

void TimeSettingsDialog::setupConnections()
{
    // Manually connect QDialogButtonBox signals to QDialog standard slots
    // This ensures the dialog buttons work correctly
    connect(buttonBox, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttonBox, &QDialogButtonBox::rejected, this, &QDialog::reject);
}

void TimeSettingsDialog::populateTimeOptions()
{
    // Clear existing items
    whiteTimeCombo->clear();
    blackTimeCombo->clear();

    // Add time options to both combo boxes
    for (int seconds : timeOptions) {
        QString timeText;
        if (seconds == 0) {
            // Special display for no time limit option
            timeText = tr("No Limit (60min countdown)");
        } else {
            timeText = QString("%1s").arg(seconds);
        }
        whiteTimeCombo->addItem(timeText, seconds);
        blackTimeCombo->addItem(timeText, seconds);
    }

    // Set default values to 0 (no limit)
    setWhiteTimeLimit(0);
    setBlackTimeLimit(0);
}

void TimeSettingsDialog::populateMoveOptions()
{
    // Clear existing items
    moveLimitCombo->clear();

    // Add move options to the combo box
    for (int moves : moveOptions) {
        QString moveText = QString("%1 moves").arg(moves);
        moveLimitCombo->addItem(moveText, moves);
    }

    // Set default value (60 moves)
    setMoveLimit(60);
}

int TimeSettingsDialog::getWhiteTimeLimit() const
{
    if (whiteTimeCombo->currentIndex() >= 0) {
        return whiteTimeCombo->currentData().toInt();
    }
    return 0; // Default value (no limit)
}

int TimeSettingsDialog::getBlackTimeLimit() const
{
    if (blackTimeCombo->currentIndex() >= 0) {
        return blackTimeCombo->currentData().toInt();
    }
    return 0; // Default value (no limit)
}

int TimeSettingsDialog::getMoveLimit() const
{
    if (moveLimitCombo->currentIndex() >= 0) {
        return moveLimitCombo->currentData().toInt();
    }
    return 60; // Default value
}

void TimeSettingsDialog::setWhiteTimeLimit(int seconds)
{
    int index = secondsToTimeIndex(seconds);
    if (index >= 0) {
        whiteTimeCombo->setCurrentIndex(index);
    }
}

void TimeSettingsDialog::setBlackTimeLimit(int seconds)
{
    int index = secondsToTimeIndex(seconds);
    if (index >= 0) {
        blackTimeCombo->setCurrentIndex(index);
    }
}

void TimeSettingsDialog::setMoveLimit(int moves)
{
    int index = moveOptions.indexOf(moves);
    if (index >= 0) {
        moveLimitCombo->setCurrentIndex(index);
    }
}

void TimeSettingsDialog::loadSettings(QSettings *settings)
{
    if (!settings) {
        return;
    }

    int whiteTime = settings->value("Options/WhiteTimeLimit", 0).toInt();
    int blackTime = settings->value("Options/BlackTimeLimit", 0).toInt();
    int moveLimit = settings->value("Options/MoveLimit", 60).toInt();

    setWhiteTimeLimit(whiteTime);
    setBlackTimeLimit(blackTime);
    setMoveLimit(moveLimit);
}

void TimeSettingsDialog::saveSettings(QSettings *settings)
{
    if (!settings) {
        return;
    }

    settings->setValue("Options/WhiteTimeLimit", getWhiteTimeLimit());
    settings->setValue("Options/BlackTimeLimit", getBlackTimeLimit());
    settings->setValue("Options/MoveLimit", getMoveLimit());
}

int TimeSettingsDialog::timeIndexToSeconds(int index) const
{
    if (index >= 0 && index < timeOptions.size()) {
        return timeOptions[index];
    }
    return 0; // Default value (no limit)
}

int TimeSettingsDialog::secondsToTimeIndex(int seconds) const
{
    return timeOptions.indexOf(seconds);
}

int TimeSettingsDialog::moveIndexToLimit(int index) const
{
    if (index >= 0 && index < moveOptions.size()) {
        return moveOptions[index];
    }
    return 60; // Default value
}

int TimeSettingsDialog::limitToMoveIndex(int limit) const
{
    return moveOptions.indexOf(limit);
}