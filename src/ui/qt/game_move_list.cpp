// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_move_list.cpp

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

// Helper function to handle snprintf and append to gameMoveList
void Game::appendMoveRecord(const char *format, ...)
{
    char record[64] = {0};
    va_list args;

    va_start(args, format);
    vsnprintf(record, Position::RECORD_LEN_MAX, format, args);
    va_end(args);

    debugPrintf("%s\n", record);

    // WAR: Prevents appending game results after the last item is
    // already a game result. Especially when browsing history.
    if (gameMoveList.empty() || gameMoveList.back() != record) {
        gameMoveList.emplace_back(record);
    }
}

void Game::resetMoveListKeepFirst()
{
    // Reset game history
    // WAR
    if (gameMoveList.size() > 1) {
        string bak = gameMoveList[0];
        gameMoveList.clear();
        gameMoveList.emplace_back(bak);
    }
}

void Game::recordGameOverReason()
{
    if (position.phase != Phase::gameOver) {
        return;
    }

    switch (position.gameOverReason) {
    case GameOverReason::loseNoLegalMoves:
        appendMoveRecord(LOSE_REASON_NO_LEGAL_MOVES, position.sideToMove,
                         position.winner);
        break;
    case GameOverReason::loseTimeout:
        appendMoveRecord(LOSE_REASON_TIMEOUT, position.winner);
        break;
    case GameOverReason::drawThreefoldRepetition:
        appendMoveRecord(DRAW_REASON_THREEFOLD_REPETITION);
        break;
    case GameOverReason::drawFiftyMove:
        appendMoveRecord(DRAW_REASON_FIFTY_MOVE);
        break;
    case GameOverReason::drawEndgameFiftyMove:
        appendMoveRecord(DRAW_REASON_ENDGAME_FIFTY_MOVE);
        break;
    case GameOverReason::loseFullBoard:
        appendMoveRecord(LOSE_REASON_FULL_BOARD);
        break;
    case GameOverReason::drawFullBoard:
        appendMoveRecord(DRAW_REASON_FULL_BOARD);
        break;
    case GameOverReason::drawStalemateCondition:
        appendMoveRecord(DRAW_REASON_STALEMATE_CONDITION);
        break;
    case GameOverReason::loseFewerThanThree:
        appendMoveRecord(LOSE_REASON_LESS_THAN_THREE, position.winner);
        break;
    case GameOverReason::loseResign:
        appendMoveRecord(LOSE_REASON_PLAYER_RESIGNS, ~position.winner);
        break;
    case GameOverReason::None:
        debugPrintf("No Game Over Reason");
        break;
    }
}

void Game::clearMoveList()
{
    gameMoveList.clear();
}
