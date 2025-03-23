// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_save.cpp

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

// Helper function to create the save path
QString Game::buildSaveFilePath() const
{
    const QString strDate = QDateTime::currentDateTime().toString("yyyy-MM-dd");
    const qint64 pid = QCoreApplication::applicationPid();
    return QDir::currentPath() + "/" + tr("Score-MillPro_") + strDate + "_" +
           QString::number(pid) + ".txt";
}

// Helper function to write player type
void Game::outputPlayerType(QTextStream &textStream, const QString &color,
                            bool isAi) const
{
    textStream << color << ":\t" << (isAi ? "AI Player" : "Human Player")
               << "\n";
}

// Helper function to write game statistics
void Game::outputGameStatistics(QTextStream &textStream) const
{
    qint64 nGamesPlayed = score[WHITE] + score[BLACK] + score[DRAW];

    if (nGamesPlayed == 0) {
        return;
    }

    textStream << "Sum\t" + QString::number(nGamesPlayed) << "\n";
    textStream << "White\t" + QString::number(score[WHITE]) + "\t" +
                      QString::number(score[WHITE] * 10000 / nGamesPlayed)
               << "\n";
    textStream << "Black\t" + QString::number(score[BLACK]) + "\t" +
                      QString::number(score[BLACK] * 10000 / nGamesPlayed)
               << "\n";
    textStream << "Draw\t" + QString::number(score[DRAW]) + "\t" +
                      QString::number(score[DRAW] * 10000 / nGamesPlayed)
               << "\n";
}

void Game::saveGameScore()
{
    QFile file(buildSaveFilePath());

    if (file.isOpen()) {
        file.close();
    }

    if (!file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
        return;
    }

    QTextStream textStream(&file);
    textStream << QCoreApplication::applicationFilePath() << "\n\n";
    textStream << gameTest->getKey() << "\n\n";

    outputPlayerType(textStream, "White", isAiPlayer[WHITE]);
    outputPlayerType(textStream, "Black", isAiPlayer[BLACK]);

    textStream << "\n";

    outputGameStatistics(textStream);

    file.flush();
    file.close();
}

void Game::finishEndgameLearning()
{
#ifdef ENDGAME_LEARNING
    if (gameOptions.isEndgameLearningEnabled()) {
        Thread::saveEndgameHashMapToFile();
    }
#endif
}
