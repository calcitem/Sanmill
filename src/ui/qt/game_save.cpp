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
QString Game::createSavePath() const
{
    const QString strDate = QDateTime::currentDateTime().toString("yyyy-MM-dd");
    const qint64 pid = QCoreApplication::applicationPid();
    return QDir::currentPath() + "/" + tr("Score-MillPro_") + strDate + "_" +
           QString::number(pid) + ".txt";
}

// Helper function to write player type
void Game::writePlayerType(QTextStream &textStream, const QString &color,
                           bool isAi) const
{
    textStream << color << ":\t" << (isAi ? "AI Player" : "Human Player")
               << "\n";
}

// Helper function to write game statistics
void Game::writeGameStats(QTextStream &textStream) const
{
    qint64 gamesPlayedCount = position.score[WHITE] + position.score[BLACK] +
                              position.score_draw;

    if (gamesPlayedCount == 0) {
        return;
    }

    textStream << "Sum\t" + QString::number(gamesPlayedCount) << "\n";
    textStream << "White\t" + QString::number(position.score[WHITE]) + "\t" +
                      QString::number(position.score[WHITE] * 10000 /
                                      gamesPlayedCount)
               << "\n";
    textStream << "Black\t" + QString::number(position.score[BLACK]) + "\t" +
                      QString::number(position.score[BLACK] * 10000 /
                                      gamesPlayedCount)
               << "\n";
    textStream << "Draw\t" + QString::number(position.score_draw) + "\t" +
                      QString::number(position.score_draw * 10000 /
                                      gamesPlayedCount)
               << "\n";
}

void Game::saveScore()
{
    QFile file(createSavePath());

    if (file.isOpen()) {
        file.close();
    }

    if (!file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
        return;
    }

    QTextStream textStream(&file);
    textStream << QCoreApplication::applicationFilePath() << "\n\n";
    textStream << gameTest->getKey() << "\n\n";

    writePlayerType(textStream, "White", isAiPlayer[WHITE]);
    writePlayerType(textStream, "Black", isAiPlayer[BLACK]);

    textStream << "\n";

    writeGameStats(textStream);

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
