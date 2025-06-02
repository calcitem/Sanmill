// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// game_interaction.cpp

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

// Check if AI tasks are active.
// Implementation detail: if you manage the counter in your code,
// you would increment g_activeAiTasks when you submit an AI task,
// and decrement it when the AI task finishes.
bool Game::hasActiveAiTasks()
{
    return (g_activeAiTasks.load(std::memory_order_relaxed) > 0);
}

bool Game::isValidBoardClick(QPointF p, File &f, Rank &r)
{
    // Convert the clicked point to board coordinates
    if (!scene.convertToPolarCoordinate(p, f, r)) {
        return false;
    }

    // In the old code, you blocked clicks when the computer was "playing" or
    // "searching" via aiThread[WHITE]->searching || aiThread[BLACK]->searching.
    // Now, block clicks only when it's AI's turn OR the search task is still
    // running *and* that search belongs to the current (AI) side-to-move.
    // If the side-to-move is human, we allow the click even if
    // g_activeAiTasks > 0 (this covers the short time gap before
    // handleAiSearchCompleted() resets the counter).
    if (isAiSideToMove()) {
        // It's AI's turn – human shouldn't click.
        return false;
    }

    // If it's human's turn but AI task counter hasn't been cleared yet,
    // ignore the residual counter.
    // Therefore, we no longer check hasActiveAiTasks() here.

    return true;
}

bool Game::applyBoardAction(File f, Rank r, QPointF p)
{
    bool result = false;
    PieceItem *piece = nullptr;
    QGraphicsItem *item = scene.itemAt(p, QTransform());

    // Decide the next action based on the current game phase
    switch (position.get_action()) {
    case Action::place:
        if (position.put_piece(f, r)) {
            // If we successfully placed a piece and the next action is remove,
            // that indicates a mill was formed
            if (position.get_action() == Action::remove) {
                playGameSound(GameSound::mill);
            } else {
                playGameSound(GameSound::drag);
            }
            result = true;

            // Check for threefold repetition if your game rules allow it
            if (rule.threefoldRepetitionRule && position.has_game_cycle()) {
                position.set_gameover(DRAW,
                                      GameOverReason::drawThreefoldRepetition);
            }
            break;
        }
        // If placing failed, fall through to possibly select or move
        [[fallthrough]];

    case Action::select:
        piece = qgraphicsitem_cast<PieceItem *>(item);
        if (!piece) {
            break;
        }
        if (position.select_piece(f, r)) {
            playGameSound(GameSound::select);
            result = true;
        } else {
            playGameSound(GameSound::banned);
        }
        break;

    case Action::remove:
        if (position.remove_piece(f, r)) {
            playGameSound(GameSound::remove);
            result = true;
        } else {
            playGameSound(GameSound::banned);
        }
        break;

    case Action::none:
        // If the game is over or there's no valid action, do nothing
        break;
    }

    return result;
}

void Game::resignHumanPlayer()
{
    // If there's no winner yet, allow a human to resign
    if (position.get_winner() == NOBODY) {
        resignGame();
    }
}
