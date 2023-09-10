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

// Browse the historical situation and refresh the situation display through the
// command function
bool Game::phaseChange(int row, bool forceUpdate)
{
    // If row is the currently viewed score line, there is no need to refresh it
    if (currentRow == row && !forceUpdate)
        return false;

    // Need to refresh
    currentRow = row;
    const int rows = moveListModel.rowCount();
    const QStringList mlist = moveListModel.stringList();

    debugPrintf("rows: %d current: %d\n", rows, row);

    for (int i = 0; i <= row; i++) {
        debugPrintf("%s\n", mlist.at(i).toStdString().c_str());
        position.command(mlist.at(i).toStdString().c_str());
    }

    // The key step is to let the penitent bear the loss of time
    set_start_time(static_cast<int>(start_timeb()));

    // Refresh the scene
    updateScene(position);

    return true;
}

void Game::handleDeletedPiece(const Position &p, PieceItem *piece, int key,
                              QParallelAnimationGroup *animationGroup,
                              PieceItem *&deletedPiece)
{
    QPointF pos;

    // Judge whether it is a removing seed or an unplaced one
    if (key & W_PIECE) {
        pos = (key - 0x11 < rule.pieceCount - p.count<IN_HAND>(WHITE)) ?
                  scene.pos_p2_g :
                  scene.pos_p1;
    } else {
        pos = (key - 0x21 < rule.pieceCount - p.count<IN_HAND>(BLACK)) ?
                  scene.pos_p1_g :
                  scene.pos_p2;
    }

    if (piece->pos() != pos) {
        // In order to prepare for the selection of the recently removed
        // pieces
        deletedPiece = piece;

#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
        if (position.get_phase() == Phase::moving) {
#endif
            auto *animation = new QPropertyAnimation(piece, "pos");
            animation->setDuration(durationTime);
            animation->setStartValue(piece->pos());
            animation->setEndValue(pos);
            animation->setEasingCurve(QEasingCurve::InOutQuad);
            animationGroup->addAnimation(animation);
#ifdef GAME_PLACING_SHOW_REMOVED_PIECES
        }
#endif
    }
}

void Game::handleBannedLocations(const Position &p, const Piece *board,
                                 int &nTotalPieces)
{
    QPointF pos;

    // Add banned points in placing phase
    if (rule.hasBannedLocations && p.get_phase() == Phase::placing) {
        for (int sq = SQ_BEGIN; sq < SQ_END; sq++) {
            if (board[sq] == BAN_PIECE) {
                pos = scene.polar2pos(static_cast<File>(sq / RANK_NB),
                                      static_cast<Rank>(sq % RANK_NB + 1));
                if (nTotalPieces < static_cast<int>(pieceList.size())) {
                    pieceList.at(static_cast<size_t>(nTotalPieces++))
                        ->setPos(pos);
                } else {
                    auto *newP = new PieceItem;
                    newP->setDeleted();
                    newP->setPos(pos);
                    pieceList.push_back(newP);
                    nTotalPieces++;
                    scene.addItem(newP);
                }
            }
        }
    }

    // Clear banned points in moving phase
    if (rule.hasBannedLocations && p.get_phase() != Phase::placing) {
        while (nTotalPieces < static_cast<int>(pieceList.size())) {
            delete pieceList.at(pieceList.size() - 1);
            pieceList.pop_back();
        }
    }
}

void Game::selectCurrentAndDeletedPieces(const Piece *board, const Position &p,
                                         int nTotalPieces,
                                         PieceItem *deletedPiece)
{
    // Select the current piece
    int ipos = p.current_square();
    int key;
    if (ipos) {
        key = board[p.current_square()];
        ipos = key & W_PIECE ? (key - W_PIECE_1) * 2 :
                               (key - B_PIECE_1) * 2 + 1;
        if (ipos >= 0 && ipos < nTotalPieces) {
            currentPiece = pieceList.at(static_cast<size_t>(ipos));
            currentPiece->setSelected(true);
        }
    }

    // Set the most recently removed pieces to select action
    if (deletedPiece) {
        deletedPiece->setSelected(true);
    }
}

bool Game::resign()
{
    const bool result = position.resign(position.sideToMove);

    if (!result) {
        return false;
    }

    // Insert the new record line into list model
    currentRow = moveListModel.rowCount() - 1;
    int k = 0;

    // Output command line
    for (const auto &i : *move_history()) {
        // Skip added because the standard list container has no index
        if (k++ <= currentRow)
            continue;
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow), i.c_str());
    }

    if (position.get_winner() != NOBODY) {
        playSound(GameSound::resign, position.side_to_move());
    }

    return result;
}


// Key slot function, according to the signal and state of qgraphics scene to
// select, drop or remove sub
bool Game::actionPiece(QPointF p)
{
    // Click non drop point, do not execute
    File f;
    Rank r;

    if (!validateClick(p, f, r))
        return false;

    if (!isRepentancePhase())
        return false;

    initiateGameIfReady();

    bool result = performAction(f, r, p);

    updateState(result);

    return result;
}

bool Game::validateClick(QPointF p, File &f, Rank &r)
{
    if (!scene.pos2polar(p, f, r)) {
        return false;
    }

    // When the computer is playing or searching, the click is invalid
    if (isAIsTurn() || aiThread[WHITE]->searching ||
        aiThread[BLACK]->searching) {
        return false;
    }

    return true;
}

// TODO: Function name
bool Game::isRepentancePhase()
{
    // When you click the board while browsing the history, it is considered
    // repentance
    if (currentRow != moveListModel.rowCount() - 1) {
#ifndef QT_MOBILE_APP_UI
        // Define new dialog box
        QMessageBox msgBox;
        msgBox.setIcon(QMessageBox::Question);
        msgBox.setMinimumSize(600, 400);
        msgBox.setText(tr("You are looking back at an old position."));
        msgBox.setInformativeText(tr("Do you want to retract your moves?"));
        msgBox.setStandardButtons(QMessageBox::Ok | QMessageBox::Cancel);
        msgBox.setDefaultButton(QMessageBox::Cancel);
        (msgBox.button(QMessageBox::Ok))->setText(tr("Yes"));
        (msgBox.button(QMessageBox::Cancel))->setText(tr("No"));

        if (QMessageBox::Ok == msgBox.exec()) {
#endif /* !QT_MOBILE_APP_UI */
            const int rowCount = moveListModel.rowCount();
            const int removeCount = rowCount - currentRow - 1;
            moveListModel.removeRows(currentRow + 1, rowCount - currentRow - 1);

            for (int i = 0; i < removeCount; i++) {
                moveHistory.pop_back();
            }

            // If you regret the game, restart the timing
            if (position.get_winner() == NOBODY) {
                // Restart timing
                timeID = startTimer(100);

                // Signal update status bar
                updateScene();
                message = QString::fromStdString(getTips());
                emit statusBarChanged(message);
#ifndef QT_MOBILE_APP_UI
            }
        } else {
            return false;
#endif /* !QT_MOBILE_APP_UI */
        }
    }
    return true;
}

bool Game::performAction(File f, Rank r, QPointF p)
{
    // Judge whether to select, drop or remove the seed
    bool result = false;
    PieceItem *piece;
    QGraphicsItem *item = scene.itemAt(p, QTransform());

    switch (position.get_action()) {
    case Action::place:
        if (position.put_piece(f, r)) {
            if (position.get_action() == Action::remove) {
                // Play form mill sound effects
                playSound(GameSound::mill, position.side_to_move());
            } else {
                // Playing the sound effect of moving pieces
                playSound(GameSound::drag, position.side_to_move());
            }
            result = true;
            break;
        }

        // If the moving is not successful, try to reselect. There is no break
        // here
        [[fallthrough]];

    case Action::select:
        piece = qgraphicsitem_cast<PieceItem *>(item);
        if (!piece)
            break;
        if (position.select_piece(f, r)) {
            playSound(GameSound::select, position.side_to_move());
            result = true;
        } else {
            playSound(GameSound::banned, position.side_to_move());
        }
        break;

    case Action::remove:
        if (position.remove_piece(f, r)) {
            playSound(GameSound::remove, position.side_to_move());
            result = true;
        } else {
            playSound(GameSound::banned, position.side_to_move());
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

void Game::updateState(bool result)
{
    if (!result)
        return;

    moveHistory.emplace_back(position.record);
    if (strlen(position.record) > strlen("-(1,2)")) {
        posKeyHistory.push_back(position.key());
    } else {
        posKeyHistory.clear();
    }

    // Signal update status bar
    updateScene();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // Insert the new score line into list model
    currentRow = moveListModel.rowCount() - 1;
    int k = 0;

    // Output command line
    for (const auto &i : *move_history()) {
        // Skip added because the standard list container has no subscripts
        if (k++ <= currentRow)
            continue;
        moveListModel.insertRow(++currentRow);
        moveListModel.setData(moveListModel.index(currentRow), i.c_str());
    }

    // Play win or lose sound
#ifndef DO_NOT_PLAY_WIN_SOUND
    const Color winner = position.get_winner();
    if (winner != NOBODY &&
        moveListModel.data(moveListModel.index(currentRow - 1))
            .toString()
            .contains("Time over."))
        playSound(GameSound::win, winner);
#endif

    // AI settings
    // If it's not decided yet
    if (position.get_winner() == NOBODY) {
        resumeAiThreads(position.sideToMove);
    } else {
        // If it's decided
        if (gameOptions.getAutoRestart()) {
#ifdef NNUE_GENERATE_TRAINING_DATA
            position.nnueWriteTrainingData();
#endif /* NNUE_GENERATE_TRAINING_DATA */

            saveScore();

            gameReset();
            gameStart();

            if (isAiPlayer[WHITE]) {
                setEngine(WHITE, true);
            }
            if (isAiPlayer[BLACK]) {
                setEngine(BLACK, true);
            }
        } else {
            pauseThreads();
        }
    }

    sideToMove = position.side_to_move();
    updateScene();
}

std::map<int, QStringList> Game::getActions()
{
    // Main window update menu bar
    // The reason why we don't use the mode of signal and slot is that
    // it's too late for the slot to be associated when the signal is sent
    std::map<int, QStringList> actions;

    // The key of map stores int index value, and value stores rule name and
    // rule prompt
    for (int i = 0; i < N_RULES; ++i) {
        actions.insert(createRuleEntry(i));
    }

    return actions;
}


// Key slot function, command line execution of score, independent of
// actionPiece
bool Game::command(const string &cmd, bool update /* = true */)
{
    int total;
    float blackWinRate, whiteWinRate, drawRate;

    Q_UNUSED(hasSound)

#ifdef QT_GUI_LIB
    // Prevents receiving instructions sent by threads that end late
    if (sender() == aiThread[WHITE] && !isAiPlayer[WHITE])
        return false;

    if (sender() == aiThread[BLACK] && !isAiPlayer[BLACK])
        return false;
#endif // QT_GUI_LIB

    auto soundType = GameSound::none;

    switch (position.get_action()) {
    case Action::select:
    case Action::place:
        soundType = GameSound::drag;
        break;
    case Action::remove:
        soundType = GameSound::remove;
        break;
    case Action::none:
        break;
    }

    if (position.get_phase() == Phase::ready) {
        gameStart();
    }

    debugPrintf("Computer: %s\n\n", cmd.c_str());

    // TODO: Distinguish these two cmds,
    // one starts with info and the other starts with (
    if (cmd[0] != 'i') {
        moveHistory.emplace_back(cmd);
    }

#ifdef NNUE_GENERATE_TRAINING_DATA
    nnueTrainingDataBestMove = cmd;
#endif /* NNUE_GENERATE_TRAINING_DATA */

    // TODO: Distinguish these two cmds,
    // one starts with info and the other starts with (
    if (cmd[0] != 'i' && cmd.size() > strlen("-(1,2)")) {
        posKeyHistory.push_back(position.key());
    } else {
        posKeyHistory.clear();
    }

    if (!position.command(cmd.c_str()))
        return false;

    sideToMove = position.side_to_move();

    if (soundType == GameSound::drag &&
        position.get_action() == Action::remove) {
        soundType = GameSound::mill;
    }

    if (update) {
        playSound(soundType, position.side_to_move());
        updateScene(position);
    }

    // Signal update status bar
    updateScene();
    message = QString::fromStdString(getTips());
    emit statusBarChanged(message);

    // For opening
    if (move_history()->size() <= 1) {
        moveListModel.removeRows(0, moveListModel.rowCount());
        moveListModel.insertRow(0);
        moveListModel.setData(moveListModel.index(0), position.get_record());
        currentRow = 0;
    } else {
        // For the current position
        currentRow = moveListModel.rowCount() - 1;
        // Skip the added rows. The iterator does not support the + operator and
        // can only skip one by one++
        auto i = move_history()->begin();
        for (int r = 0; i != move_history()->end(); ++i) {
            if (r++ > currentRow)
                break;
        }
        // Insert the new score line into list model
        while (i != move_history()->end()) {
            moveListModel.insertRow(++currentRow);
            moveListModel.setData(moveListModel.index(currentRow),
                                  (*i++).c_str());
        }
    }

    // Play win or lose sound
#ifndef DO_NOT_PLAY_WIN_SOUND
    const Color winner = position.get_winner();
    if (winner != NOBODY &&
        moveListModel.data(moveListModel.index(currentRow - 1))
            .toString()
            .contains("Time over.")) {
        playSound(GameSound::win, winner);
    }
#endif

    // AI Settings
    // If it's not decided yet
    if (position.get_winner() == NOBODY) {
        resumeAiThreads(position.sideToMove);
    } else {
        // If it's decided
        pauseThreads();

        gameEndTime = now();
        gameDurationTime = gameEndTime - gameStartTime;

        gameEndCycle = stopwatch::rdtscp_clock::now();

        debugPrintf("Game Duration Time: %lldms\n", gameDurationTime);

#ifdef TIME_STAT
        debugPrintf("Sort Time: %I64d + %I64d = %I64dms\n",
                    aiThread[WHITE]->sortTime, aiThread[BLACK]->sortTime,
                    (aiThread[WHITE]->sortTime + aiThread[BLACK]->sortTime));
        aiThread[WHITE]->sortTime = aiThread[BLACK]->sortTime = 0;
#endif // TIME_STAT

#ifdef CYCLE_STAT
        debugPrintf("Sort Cycle: %ld + %ld = %ld\n", aiThread[WHITE]->sortCycle,
                    aiThread[BLACK]->sortCycle,
                    (aiThread[WHITE]->sortCycle + aiThread[BLACK]->sortCycle));
        aiThread[WHITE]->sortCycle = aiThread[BLACK]->sortCycle = 0;
#endif // CYCLE_STAT

#if 0
            gameDurationCycle = gameEndCycle - gameStartCycle;
            debugPrintf("Game Start Cycle: %u\n", gameStartCycle);
            debugPrintf("Game End Cycle: %u\n", gameEndCycle);
            debugPrintf("Game Duration Cycle: %u\n", gameDurationCycle);
#endif

#ifdef TRANSPOSITION_TABLE_DEBUG
        size_t hashProbeCount_1 = aiThread[WHITE]->ttHitCount +
                                  aiThread[WHITE]->ttMissCount;
        size_t hashProbeCount_2 = aiThread[BLACK]->ttHitCount +
                                  aiThread[BLACK]->ttMissCount;

        debugPrintf("[key 1] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                    "%llu%%\n",
                    hashProbeCount_1, aiThread[WHITE]->ttHitCount,
                    aiThread[WHITE]->ttMissCount,
                    aiThread[WHITE]->ttHitCount * 100 / hashProbeCount_1);

        debugPrintf("[key 2] probe: %llu, hit: %llu, miss: %llu, hit rate: "
                    "%llu%%\n",
                    hashProbeCount_2, aiThread[BLACK]->ttHitCount,
                    aiThread[BLACK]->ttMissCount,
                    aiThread[BLACK]->ttHitCount * 100 / hashProbeCount_2);

        debugPrintf(
            "[key +] probe: %llu, hit: %llu, miss: %llu, hit rate: %llu%%\n",
            hashProbeCount_1 + hashProbeCount_2,
            aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount,
            aiThread[WHITE]->ttMissCount + aiThread[BLACK]->ttMissCount,
            (aiThread[WHITE]->ttHitCount + aiThread[BLACK]->ttHitCount) * 100 /
                (hashProbeCount_1 + hashProbeCount_2));
#endif // TRANSPOSITION_TABLE_DEBUG

        if (gameOptions.getAutoRestart()) {
#ifdef NNUE_GENERATE_TRAINING_DATA
            position.nnueWriteTrainingData();
#endif /* NNUE_GENERATE_TRAINING_DATA */

            saveScore();

            gameReset();
            gameStart();

            if (isAiPlayer[WHITE]) {
                setEngine(WHITE, true);
            }
            if (isAiPlayer[BLACK]) {
                setEngine(BLACK, true);
            }
        }

#ifdef MESSAGE_BOX_ENABLE
        message = QString::fromStdString(position.get_tips());
        QMessageBox::about(NULL, "Game Result", message);
#endif
    }

    if (cmd[0] != 'i') {
        gameTest->writeToMemory(QString::fromStdString(cmd));
    }

#ifdef NET_FIGHT_SUPPORT
    // Network: put the method in the server's send list
    getServer()->setAction(QString::fromStdString(cmd));
#endif

#ifdef ANALYZE_POSITION
    if (!gameOptions.getUsePerfectDatabase()) {
        if (isAiPlayer[WHITE]) {
            aiThread[WHITE]->analyze(WHITE);
        } else if (isAiPlayer[BLACK]) {
            aiThread[BLACK]->analyze(BLACK);
        }
    }
#endif // ANALYZE_POSITION

    total = position.score[WHITE] + position.score[BLACK] + position.score_draw;

    if (total == 0) {
        blackWinRate = 0;
        whiteWinRate = 0;
        drawRate = 0;
    } else {
        blackWinRate = static_cast<float>(position.score[WHITE]) * 100 / total;
        whiteWinRate = static_cast<float>(position.score[BLACK]) * 100 / total;
        drawRate = static_cast<float>(position.score_draw) * 100 / total;
    }

    const auto flags = cout.flags();
    cout << "Score: " << position.score[WHITE] << " : " << position.score[BLACK]
         << " : " << position.score_draw << "\ttotal: " << total << std::endl;
    cout << std::fixed << std::setprecision(2) << blackWinRate
         << "% : " << whiteWinRate << "% : " << drawRate << "%" << std::endl;
    cout.flags(flags);

#ifdef NNUE_GENERATE_TRAINING_DATA
    position.nnueGenerateTrainingFen();
#endif /* NNUE_GENERATE_TRAINING_DATA */

    return true;
}