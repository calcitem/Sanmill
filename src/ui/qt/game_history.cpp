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

// Helper function to handle snprintf and append to moveHistory
void Game::appendRecordToMoveHistory(const char *format, ...)
{
    char record[64] = {0};
    va_list args;

    va_start(args, format);
    vsnprintf(record, Position::RECORD_LEN_MAX, format, args);
    va_end(args);

    debugPrintf("%s\n", record);

    moveHistory.emplace_back(record);
}

void Game::resetMoveHistoryReserveFirst()
{
    // Reset game history
    // WAR
    if (moveHistory.size() > 1) {
        string bak = moveHistory[0];
        moveHistory.clear();
        moveHistory.emplace_back(bak);
    }
}

void Game::appendGameOverReasonToMoveHistory()
{
    if (position.phase != Phase::gameOver) {
        return;
    }

    switch (position.gameOverReason) {
    case GameOverReason::loseNoWay:
        appendRecordToMoveHistory(loseReasonNoWayStr, position.sideToMove,
                                  position.winner);
        break;
    case GameOverReason::loseTimeOver:
        appendRecordToMoveHistory(loseReasonTimeOverStr, position.winner);
        break;
    case GameOverReason::drawThreefoldRepetition:
        appendRecordToMoveHistory(drawReasonThreefoldRepetitionStr);
        break;
    case GameOverReason::drawRule50:
        appendRecordToMoveHistory(drawReasonRule50Str);
        break;
    case GameOverReason::drawEndgameRule50:
        appendRecordToMoveHistory(drawReasonEndgameRule50Str);
        break;
    case GameOverReason::loseBoardIsFull:
        appendRecordToMoveHistory(loseReasonBoardIsFullStr);
        break;
    case GameOverReason::drawBoardIsFull:
        appendRecordToMoveHistory(drawReasonBoardIsFullStr);
        break;
    case GameOverReason::drawNoWay:
        appendRecordToMoveHistory(drawReasonNoWayStr);
        break;
    case GameOverReason::loseLessThanThree:
        appendRecordToMoveHistory(loseReasonlessThanThreeStr, position.winner);
        break;
    case GameOverReason::loseResign:
        appendRecordToMoveHistory(loseReasonResignStr, ~position.winner);
        break;
    case GameOverReason::none:
        debugPrintf("No Game Over Reason");
        break;
    }
}

void Game::clearMoveHistory()
{
    moveHistory.clear();
}
