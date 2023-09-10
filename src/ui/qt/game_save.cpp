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

void Game::saveScore()
{
    const QString strDate = QDateTime::currentDateTime().toString("yyyy-MM-dd");
    const qint64 pid = QCoreApplication::applicationPid();

    const QString path = QDir::currentPath() + "/" + tr("Score-MillPro_") +
                         strDate + "_" + QString::number(pid) + ".txt";

    QFile file;

    file.setFileName(path);

    if (file.isOpen()) {
        file.close();
    }

    if (!file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
        return;
    }

    QTextStream textStream(&file);

    textStream << QCoreApplication::applicationFilePath() << "\n"
               << "\n";

    textStream << gameTest->getKey() << "\n"
               << "\n";

    if (isAiPlayer[WHITE]) {
        textStream << "White:\tAI Player"
                   << "\n";
    } else {
        textStream << "White:\tHuman Player"
                   << "\n";
    }

    if (isAiPlayer[BLACK]) {
        textStream << "Black:\tAI Player"
                   << "\n";
    } else {
        textStream << "Black:\tHuman Player"
                   << "\n";
    }

    textStream << ""
               << "\n";

    position.gamesPlayedCount = position.score[WHITE] + position.score[BLACK] +
                                position.score_draw;

    if (position.gamesPlayedCount == 0) {
        goto out;
    }

    textStream << "Sum\t" + QString::number(position.gamesPlayedCount) << "\n";
    textStream << "White\t" + QString::number(position.score[WHITE]) + "\t" +
                      QString::number(position.score[WHITE] * 10000 /
                                      position.gamesPlayedCount)
               << "\n";
    textStream << "Black\t" + QString::number(position.score[BLACK]) + "\t" +
                      QString::number(position.score[BLACK] * 10000 /
                                      position.gamesPlayedCount)
               << "\n";
    textStream << "Draw\t" + QString::number(position.score_draw) + "\t" +
                      QString::number(position.score_draw * 10000 /
                                      position.gamesPlayedCount)
               << "\n";

out:
    file.flush();
    file.close();
}

void Game::finalizeEndgameLearning()
{
#ifdef ENDGAME_LEARNING
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::saveEndgameHashMapToFile();
    }
#endif
}
