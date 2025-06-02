// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// time_settings_dialog.h

#ifndef TIME_SETTINGS_DIALOG_H_INCLUDED
#define TIME_SETTINGS_DIALOG_H_INCLUDED

#include <QDialog>
#include <QComboBox>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QDialogButtonBox>
#include <QPushButton>

class QSettings;

/**
 * @brief Dialog for configuring time limits and move limits for both players
 *
 * This dialog allows users to set separate time limits for white and black
 * players, and also configure move limits for the game. Time limits include
 * options: 1s, 5s, 10s, 15s, 20s, 30s, 45s, 60s, 100s Move limits include
 * options: 10, 30, 50, 60, 100, 200 moves
 */
class TimeSettingsDialog : public QDialog
{
    Q_OBJECT

public:
    explicit TimeSettingsDialog(QWidget *parent = nullptr);
    ~TimeSettingsDialog() override = default;

    // Get selected time limits in seconds
    int getWhiteTimeLimit() const;
    int getBlackTimeLimit() const;

    // Get selected move limit
    int getMoveLimit() const;

    // Set time limits in seconds
    void setWhiteTimeLimit(int seconds);
    void setBlackTimeLimit(int seconds);

    // Set move limit
    void setMoveLimit(int moves);

    // Load settings from QSettings
    void loadSettings(QSettings *settings);
    // Save settings to QSettings
    void saveSettings(QSettings *settings);

private:
    void setupUI();
    void setupConnections();
    void populateTimeOptions();
    void populateMoveOptions();
    int timeIndexToSeconds(int index) const;
    int secondsToTimeIndex(int seconds) const;
    int moveIndexToLimit(int index) const;
    int limitToMoveIndex(int limit) const;

    QVBoxLayout *mainLayout;
    QHBoxLayout *whiteLayout;
    QHBoxLayout *blackLayout;
    QHBoxLayout *moveLayout;
    QHBoxLayout *buttonLayout;

    QLabel *titleLabel;
    QLabel *whiteLabel;
    QLabel *blackLabel;
    QLabel *moveLabel;
    QComboBox *whiteTimeCombo;
    QComboBox *blackTimeCombo;
    QComboBox *moveLimitCombo;
    QDialogButtonBox *buttonBox;

    // Available time options in seconds
    static const QList<int> timeOptions;
    // Available move limit options
    static const QList<int> moveOptions;
};

#endif // TIME_SETTINGS_DIALOG_H_INCLUDED