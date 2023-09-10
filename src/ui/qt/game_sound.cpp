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

void Game::setSound(bool arg) const noexcept
{
    hasSound = arg;
    settings->setValue("Options/Sound", arg);
}

void Game::playSound(GameSound soundType, Color c)
{
    std::string filename = buildSoundFilename(soundType, c);
    performSoundPlay(filename);
}

std::string Game::buildSoundFilename(GameSound soundType, Color c)
{
    std::string sideStr = c == WHITE ? "W" : "B";
    std::string opponentStr = c == BLACK ? "W" : "B";
    std::string filename;

    switch (soundType) {
    case GameSound::blockMill:
        filename = "BlockMill_" + sideStr + ".wav";
        break;
    case GameSound::remove:
        filename = "Remove_" + opponentStr + ".wav";
        break;
    case GameSound::select:
        filename = "Select.wav";
        break;
    case GameSound::draw:
        filename = "Draw.wav";
        break;
    case GameSound::drag:
        filename = "drag.wav";
        break;
    case GameSound::banned:
        filename = "forbidden.wav";
        break;
    case GameSound::gameStart:
        filename = "GameStart.wav";
        break;
    case GameSound::resign:
        filename = "Resign_" + sideStr + ".wav";
        break;
    case GameSound::loss:
        filename = "loss.wav";
        break;
    case GameSound::mill:
        filename = "Mill_" + sideStr + ".wav";
        break;
    case GameSound::millRepeatedly:
        filename = "MillRepeatedly_" + sideStr + ".wav";
        break;
    case GameSound::move:
        filename = "move.wav";
        break;
    case GameSound::newGame:
        filename = "newgame.wav";
        break;
    case GameSound::nextMill:
        filename = "NextMill_" + sideStr + ".wav";
        break;
    case GameSound::obvious:
        filename = "Obvious.wav";
        break;
    case GameSound::repeatThreeDraw:
        filename = "RepeatThreeDraw.wav";
        break;
    case GameSound::side:
        filename = "Side_" + sideStr + ".wav";
        break;
    case GameSound::star:
        filename = "Star_" + sideStr + ".wav";
        break;
    case GameSound::suffocated:
        filename = "Suffocated_" + sideStr + ".wav";
        break;
    case GameSound::vantage:
        filename = "Vantage.wav";
        break;
    case GameSound::very:
        filename = "Very.wav";
        break;
    case GameSound::warning:
        filename = "warning.wav";
        break;
    case GameSound::win:
        filename = c == DRAW ? "Draw.wav" : "Win_" + sideStr + ".wav";
        break;
    case GameSound::winAndLossesAreObvious:
        filename = "WinsAndLossesAreObvious.wav";
        break;
    case GameSound::none:
        filename = "";
        break;
    }

    return filename;
}

void Game::performSoundPlay(const std::string &filename)
{
#ifndef DO_NOT_PLAY_SOUND
    if (filename.empty())
        return;

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
