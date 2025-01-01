// This file is part of Sanmill.
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)
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

bool Game::validateClick(QPointF p, File &f, Rank &r)
{
    if (!scene.pointToPolarCoordinate(p, f, r)) {
        return false;
    }

    // When the computer is playing or searching, the click is invalid
    if (isAiToMove() || aiThread[WHITE]->searching ||
        aiThread[BLACK]->searching) {
        return false;
    }

    return true;
}

bool Game::performAction(File f, Rank r, QPointF p)
{
    // Judge whether to select, place, move, or remove the piece
    bool result = false;
    PieceItem *piece;
    QGraphicsItem *item = scene.itemAt(p, QTransform());

    switch (position.get_action()) {
    case Action::place:
        if (position.put_piece(f, r)) {
            if (position.get_action() == Action::remove) {
                // Play form mill sound effects
                playSound(GameSound::mill);
            } else {
                // Playing the sound effect of moving pieces
                playSound(GameSound::drag);
            }
            result = true;

            if (rule.threefoldRepetitionRule && position.has_game_cycle()) {
                position.set_gameover(DRAW,
                                      GameOverReason::drawThreefoldRepetition);
            }

            break;
        }

        // If placing is not successful, try to reselect or move. There is no
        // break here
        [[fallthrough]];

    case Action::select:
        piece = qgraphicsitem_cast<PieceItem *>(item);
        if (!piece)
            break;
        if (position.select_piece(f, r)) {
            playSound(GameSound::select);
            result = true;
        } else {
            playSound(GameSound::banned);
        }
        break;

    case Action::remove:
        if (position.remove_piece(f, r)) {
            playSound(GameSound::remove);
            result = true;
        } else {
            playSound(GameSound::banned);
        }
        break;

    case Action::none:
        // If it is game over state, no response will be made
        break;
    }

    return result;
}

void Game::humanResign()
{
    if (position.get_winner() == NOBODY) {
        resign();
    }
}
