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

void Game::resetMoveHistory()
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

    char record[64] = {0};
    switch (position.gameOverReason) {
    case GameOverReason::loseNoWay:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonNoWayStr,
                 position.sideToMove, position.winner);
        break;
    case GameOverReason::loseTimeOver:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonTimeOverStr,
                 position.winner);
        break;
    case GameOverReason::drawThreefoldRepetition:
        snprintf(record, Position::RECORD_LEN_MAX,
                 drawReasonThreefoldRepetitionStr);
        break;
    case GameOverReason::drawRule50:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonRule50Str);
        break;
    case GameOverReason::drawEndgameRule50:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonEndgameRule50Str);
        break;
    case GameOverReason::loseBoardIsFull:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonBoardIsFullStr);
        break;
    case GameOverReason::drawBoardIsFull:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonBoardIsFullStr);
        break;
    case GameOverReason::drawNoWay:
        snprintf(record, Position::RECORD_LEN_MAX, drawReasonNoWayStr);
        break;
    case GameOverReason::loseLessThanThree:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonlessThanThreeStr,
                 position.winner);
        break;
    case GameOverReason::loseResign:
        snprintf(record, Position::RECORD_LEN_MAX, loseReasonResignStr,
                 ~position.winner);
        break;
    case GameOverReason::none:
        debugPrintf("No Game Over Reason");
        break;
    }

    debugPrintf("%s\n", record);
    moveHistory.emplace_back(record);
}

void Game::clearMoveHistory()
{
    moveHistory.clear();
}
