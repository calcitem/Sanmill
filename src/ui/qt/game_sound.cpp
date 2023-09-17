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
static std::string buildFilename(GameSound soundType,
                                 const std::string &sideStr,
                                 const std::string &opponentStr)
{
    std::string filename;

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
        {GameSound::win, (sideStr == "DRAW" ? "Draw" : "Win_" + sideStr)},
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
void Game::playSound(GameSound soundType, Color c)
{
    std::string sideStr = (c == WHITE) ? "W" : "B";
    std::string opponentStr = (c == BLACK) ? "W" : "B";

    std::string filename = buildFilename(soundType, sideStr, opponentStr);
    performSoundPlay(filename);
}

// Function to actually perform the sound play operation
void Game::performSoundPlay(const std::string &filename)
{
#ifndef DO_NOT_PLAY_SOUND
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
#endif
}
