// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_sound.cpp

#include <iomanip>
#include <map>
#include <unordered_map>
#include <string>

#include <QAbstractButton>
#include <QApplication>
#include <QDir>
#include <QFileInfo>
#include <QGraphicsSceneMouseEvent>
#include <QGraphicsView>
#include <QKeyEvent>
#include <QMessageBox>
#include <QParallelAnimationGroup>
#include <QPropertyAnimation>
#include <QSoundEffect>
#include <QThread>
#include <QTimer>

#include "boarditem.h"
#include "client.h"
#include "game.h"
#include "graphicsconst.h"
#include "option.h"
#include "server.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

using std::to_string;

// Helper function to build sound filename
static std::string buildSoundFilename(GameSound soundType,
                                      const std::string &sideStr,
                                      const std::string &opponentStr)
{
    std::string filename;

    std::string sideStrUpper = sideStr;
    std::transform(sideStrUpper.begin(), sideStrUpper.end(),
                   sideStrUpper.begin(), ::toupper);

    // Map for handling sound types
    std::unordered_map<GameSound, std::string> soundMap = {
        {GameSound::blockMill, "BlockMill_" + sideStr},
        {GameSound::remove, "Remove_" + opponentStr},
        {GameSound::select, "Select"},
        {GameSound::draw, "Draw"},
        {GameSound::drag, "drag"},
        {GameSound::banned, "forbidden"},
        {GameSound::gameStart, "GameStart"},
        {GameSound::resign, "Resign_" + sideStr},
        {GameSound::loss, "loss"},
        {GameSound::mill, "Mill_" + sideStr},
        {GameSound::millRepeatedly, "MillRepeatedly_" + sideStr},
        {GameSound::move, "move"},
        {GameSound::newGame, "newgame"},
        {GameSound::nextMill, "NextMill_" + sideStr},
        {GameSound::obvious, "Obvious"},
        {GameSound::repeatThreeDraw, "RepeatThreeDraw"},
        {GameSound::side, "Side_" + sideStr},
        {GameSound::star, "Star_" + sideStr},
        {GameSound::suffocated, "Suffocated_" + sideStr},
        {GameSound::vantage, "Vantage"},
        {GameSound::very, "Very"},
        {GameSound::warning, "warning"},
        {GameSound::win,
         (sideStrUpper.find("DRAW") != std::string::npos ? "Draw" :
                                                           "Win_" + sideStr)},
        {GameSound::winAndLossesAreObvious, "WinsAndLossesAreObvious"},
        {GameSound::none, ""}};

    // Try to find filename using map, if not, use a default empty string
    filename = soundMap.find(soundType) != soundMap.end() ?
                   soundMap[soundType] :
                   "";

    return filename + ".wav";
}

// Function to set sound setting
void Game::setSound(bool arg) const noexcept
{
    hasSound = arg;
    settings->setValue("Options/Sound", arg);
}

// Function to play a particular sound based on game state
void Game::playGameSound(GameSound soundType)
{
    Color c = position.side_to_move();

    if (soundType == GameSound::win) {
        c = position.get_winner();
    }

    std::string sideStr = (c == WHITE) ? "W" : "B";
    std::string opponentStr = (c == BLACK) ? "W" : "B";

    if (c == Color::DRAW) {
        sideStr = opponentStr = "DRAW";
    }

    std::string filename = buildSoundFilename(soundType, sideStr, opponentStr);
#ifndef DO_NOT_PLAY_SOUND
    doPlaySound(filename);
#endif
}

// Function to actually perform the sound play operation
void Game::doPlaySound(const std::string &filename)
{
    if (filename.empty()) {
        return;
    }

    if (hasSound) {
        auto *effect = new QSoundEffect;
        QString soundPath = QString::fromStdString(":sound/resources/sound/" +
                                                   filename);
        effect->setSource(QUrl::fromLocalFile(soundPath));
        effect->setLoopCount(1);
        effect->play();
    }
}
