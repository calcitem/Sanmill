// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// gamewindow.cpp

#include <QActionGroup>
#include <QButtonGroup>
#include <QComboBox>
#include <QDesktopServices>
#include <QDialog>
#include <QDialogButtonBox>
#include <QFileDialog>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QHelpEvent>
#include <QLabel>
#include <QMessageBox>
#include <QPicture>
#include <QProcess>
#include <QPushButton>
#include <QScreen>
#include <QSpinBox>
#include <QTimer>
#include <QToolTip>
#include <QVBoxLayout>

#include "client.h"
#include "game.h"
#include "gamescene.h"
#include "gamewindow.h"
#include "graphicsconst.h"
#include "option.h"
#include "server.h"
#include "version.h"
#include "translations/languagemanager.h"
#include "time_settings_dialog.h"

MillGameWindow::MillGameWindow(QWidget *parent)
    : QMainWindow(parent)
    , autoRunTimer(this)
{
    ui.setupUi(this);

    // Remove the title bar
    // setWindowFlags(Qt::FramelessWindowHint);

    // Set transparency
    // (the title bar of the form is opaque and the background is transparent.
    // If the title bar is not removed, the background will turn black)
    // setAttribute(Qt::WA_TranslucentBackground);

    // Set the overall transparency factor
    // setWindowOpacity(0.7);

    // Set up the scene
    scene = new GameScene(this);

    // Set the scene size to 1.08 times the board size
    scene->setSceneRect(-BOARD_SIDE_LENGTH * 0.54, -BOARD_SIDE_LENGTH * 0.54,
                        BOARD_SIDE_LENGTH * 1.08, BOARD_SIDE_LENGTH * 1.08);

    // Initialize the controls

    // Associate views and scenes
    ui.gameView->setScene(scene);

    // View anti aliasing
    ui.gameView->setRenderHint(QPainter::Antialiasing, true);

    // View anti aliasing
    ui.gameView->setRenderHint(QPainter::Antialiasing);

    // Due to function limitation, some functions are not available and will be
    // added in the future
    ui.actionInternet_I->setDisabled(false);
    ui.actionSetting_O->setDisabled(true);

    // Initialize game rules menu
    ui.menu_R->installEventFilter(this);

    // Associated auto run timer
    connect(&autoRunTimer, SIGNAL(timeout()), this, SLOT(onAutoRunTimeOut()));

    // Game initialization
    initialize();

    // Centering will be done in showEvent
}

MillGameWindow::~MillGameWindow()
{
    if (game) {
        game->disconnect();
        game->deleteLater();
    }

    qDeleteAll(ruleActionList);
}

void MillGameWindow::closeEvent(QCloseEvent *event)
{
    if (file.isOpen())
        file.close();

    // Cancel auto run
    ui.actionAutoRun_A->setChecked(false);

    debugPrintf("closed\n");

    QMainWindow::closeEvent(event);
}

bool MillGameWindow::eventFilter(QObject *watched, QEvent *event)
{
    // This function is overridden just to make the rules menu (dynamic) display
    // prompts
    if (watched == ui.menu_R && event->type() == QEvent::ToolTip) {
        const auto *he = dynamic_cast<QHelpEvent *>(event);
        QAction *action = ui.menu_R->actionAt(he->pos());
        if (action) {
            QToolTip::showText(he->globalPos(), action->toolTip(), this);
            return true;
        }
    }

    return QMainWindow::eventFilter(watched, event);
}

void MillGameWindow::initialize()
{
    // Initialize the function and execute it only once
    if (game)
        return;

    // New a new game controller
    game = new Game(*scene, this);

    // Add a new menu bar action
    map<int, QStringList> actions = game->getRuleActions();

    for (auto i = actions.begin(); i != actions.end(); ++i) {
        // The key of map stores int index value, and value stores rule name and
        // rule prompt
        auto *ruleAction = new QAction(i->second.at(0), this);
        ruleAction->setToolTip(i->second.at(1));
        ruleAction->setCheckable(true);

        // The index value is put in the data of QAction
        ruleAction->setData(i->first);

        // Add to action list
        ruleActionList.push_back(ruleAction);

        // Add to rules menu
        ui.menu_R->addAction(ruleAction);

        connect(ruleAction, SIGNAL(triggered()), this,
                SLOT(actionRules_triggered()));
    }

    // The main window controller is associated with the action of the signal
    // slot

    // connect(ui.actionResign_G, SIGNAL(triggered()), game, SLOT(resign()));

#ifdef QT_MOBILE_APP_UI
    connect(ui.pushButton_resign, SIGNAL(released()), game, SLOT(resign()));
#endif

    connect(ui.actionEngine1_T, SIGNAL(toggled(bool)), game,
            SLOT(setWhiteIsAiPlayer(bool)));

    connect(ui.actionEngine2_R, SIGNAL(toggled(bool)), game,
            SLOT(setBlackIsAiPlayer(bool)));

    connect(ui.actionFixWindowSize, SIGNAL(toggled(bool)), game,
            SLOT(setFixWindowSize(bool)));

    connect(ui.actionSound_S, SIGNAL(toggled(bool)), game,
            SLOT(setSound(bool)));

    connect(ui.actionAnimation_A, SIGNAL(toggled(bool)), game,
            SLOT(setAnimation(bool)));

    connect(ui.actionAlphaBetaAlgorithm, SIGNAL(toggled(bool)), game,
            SLOT(setAlphaBetaAlgorithm(bool)));

    connect(ui.actionPvsAlgorithm, SIGNAL(toggled(bool)), game,
            SLOT(setPvsAlgorithm(bool)));

    connect(ui.actionMtdfAlgorithm, SIGNAL(toggled(bool)), game,
            SLOT(setMtdfAlgorithm(bool)));

    connect(ui.actionMctsAlgorithm, SIGNAL(toggled(bool)), game,
            SLOT(setMctsAlgorithm(bool)));

    connect(ui.actionUsePerfectDatabase, SIGNAL(toggled(bool)), game,
            SLOT(setUsePerfectDatabase(bool)));

    connect(ui.actionDrawOnHumanExperience, SIGNAL(toggled(bool)), game,
            SLOT(setDrawOnHumanExperience(bool)));

    connect(ui.actionConsiderMobility, SIGNAL(toggled(bool)), game,
            SLOT(setConsiderMobility(bool)));

    connect(ui.actionFocusOnBlockingPaths, SIGNAL(toggled(bool)), game,
            SLOT(setFocusOnBlockingPaths(bool)));

    connect(ui.actionAiIsLazy, SIGNAL(toggled(bool)), game,
            SLOT(setAiIsLazy(bool)));

    connect(ui.actionResignIfMostLose_G, SIGNAL(toggled(bool)), game,
            SLOT(setResignIfMostLose(bool)));

    connect(ui.actionAutoRestart_A, SIGNAL(toggled(bool)), game,
            SLOT(setAutoRestart(bool)));

    connect(ui.actionOpen_Settings_File, &QAction::triggered, this,
            &MillGameWindow::on_actionOpen_Settings_File_triggered);

    connect(ui.actionAutoChangeFirstMove_C, SIGNAL(toggled(bool)), game,
            SLOT(setAutoChangeFirstMove(bool)));

    connect(ui.actionShuffling_R, SIGNAL(toggled(bool)), game,
            SLOT(setShuffling(bool)));

    connect(ui.actionLearnEndgame_E, SIGNAL(toggled(bool)), game,
            SLOT(setLearnEndgame(bool)));

    connect(ui.actionIDS_I, SIGNAL(toggled(bool)), game, SLOT(setIDS(bool)));

    // DepthExtension
    connect(ui.actionDepthExtension_D, SIGNAL(toggled(bool)), game,
            SLOT(setDepthExtension(bool)));

    //  OpeningBook
    connect(ui.actionOpeningBook_O, SIGNAL(toggled(bool)), game,
            SLOT(setOpeningBook(bool)));

    connect(ui.actionDeveloperMode, SIGNAL(toggled(bool)), game,
            SLOT(setDeveloperMode(bool)));

    connect(ui.actionFlip_F, &QAction::triggered, game,
            &Game::flipBoardVertically);

    connect(ui.actionMirror_M, &QAction::triggered, game,
            &Game::flipBoardHorizontally);

    connect(ui.actionTurnRight_R, &QAction::triggered, game,
            &Game::rotateBoardClockwise);

    connect(ui.actionTurnLeft_L, &QAction::triggered, game,
            &Game::rotateBoardCounterclockwise);

    connect(game, SIGNAL(nGamesPlayedChanged(QString)),
            ui.scoreLcdNumber_GamesPlayed, SLOT(display(QString)));

    connect(game, SIGNAL(score1Changed(QString)), ui.scoreLcdNumber_1,
            SLOT(display(QString)));

    connect(game, SIGNAL(score2Changed(QString)), ui.scoreLcdNumber_2,
            SLOT(display(QString)));

    connect(game, SIGNAL(scoreDrawChanged(QString)), ui.scoreLcdNumber_draw,
            SLOT(display(QString)));

    connect(game, SIGNAL(winningRate1Changed(QString)),
            ui.winningRateLcdNumber_1, SLOT(display(QString)));

    connect(game, SIGNAL(winningRate2Changed(QString)),
            ui.winningRateLcdNumber_2, SLOT(display(QString)));

    connect(game, SIGNAL(winningRateDrawChanged(QString)),
            ui.winningRateLcdNumber_draw, SLOT(display(QString)));

    connect(game, SIGNAL(time1Changed(QString)), ui.lcdNumber_1,
            SLOT(display(QString)));

    connect(game, SIGNAL(time2Changed(QString)), ui.lcdNumber_2,
            SLOT(display(QString)));

    connect(scene, SIGNAL(mouseReleased(QPointF)), game,
            SLOT(handleBoardClick(QPointF)));

    // Add a normal display label to the status bar
    auto *statusBarLabel = new QLabel(this);
    QFont statusBarFont;
    statusBarFont.setPointSize(12);
    statusBarLabel->setFont(statusBarFont);
    ui.statusBar->addWidget(statusBarLabel);

    connect(game, SIGNAL(statusBarChanged(QString)), statusBarLabel,
            SLOT(setText(QString)));

    connect(game, &Game::advantageChanged, this,
            &MillGameWindow::handleAdvantageChanged);

    ruleActionList[game->getRuleIndex()]->setChecked(true);
    game->applyRule(game->getRuleIndex());

    // List of associated models and string views
    ui.listView->setModel(game->getMoveListModel());

    // Because QListView's rowsInserted can only be started after setModel,
    // The first time you need to manually initialize, select the first item of
    // listView
    ui.listView->setCurrentIndex(ui.listView->model()->index(0, 0));

    // //The slot of the initial situation, the previous step, the next step and
    // the final situation

    connect(ui.actionBegin_S, &QAction::triggered, this,
            &MillGameWindow::on_actionRowChange);

    connect(ui.actionPrevious_B, &QAction::triggered, this,
            &MillGameWindow::on_actionRowChange);

#ifdef QT_MOBILE_APP_UI
    connect(ui.pushButton_retractMove, &QPushButton::released, this,
            &MillGameWindow::on_actionRowChange);

    connect(ui.pushButton_newGame, &QPushButton::released, this,
            &MillGameWindow::on_actionNew_N_triggered);
#endif /* QT_MOBILE_APP_UI */

    connect(ui.actionNext_F, &QAction::triggered, this,
            &MillGameWindow::on_actionRowChange);

    connect(ui.actionEnd_E, &QAction::triggered, this,
            &MillGameWindow::on_actionRowChange);

    // Manually select the updated slot in listView
    connect(ui.listView, &MoveListView::currentChangedSignal, this,
            &MillGameWindow::on_actionRowChange);

    // Update the status of the four keys
    on_actionRowChange();

    // Set form size
#ifdef QT_MOBILE_APP_UI
#if 0
    const int screen_iPhone_XS_Max[] = {1242, 2688};
    const int screen_iPhone_XS[] = {1125, 2436};
    const int screen_iPhone_XR[] = {828, 1792};
    const int screen_iPhone_X[] = {1125, 2436};
    const int screen_iPhone_8_Plus[] = {1242, 2208};
    const int screen_iPhone_8[] = {750, 1334};
    const int screen_iPhone_7_Plus[] = {1242, 2208};
    const int screen_iPhone_7[] = {750, 1334};
    const int screen_iPhone_6s_Plus[] = {1242, 2208};
    const int screen_iPhone_6s[] = {750, 1334};
#endif
    const int screen_iPhone_SE[] = {640, 1136};
    this->resize(QSize(screen_iPhone_SE[0], screen_iPhone_SE[1]));
#else  /* QT_MOBILE_APP_UI */

    // Fix window size
    if (game->fixWindowSizeEnabled()) {
        setFixedWidth(width());
        setFixedHeight(height());
    } else {
        const int h = QGuiApplication::primaryScreen()->geometry().height();
        this->resize(QSize(h * 3 / 4, h * 3 / 4));
    }

    ui.pushButton_back->setVisible(false);
    ui.pushButton_option->setVisible(false);
    ui.label_2->setVisible(false);
    ui.label->setVisible(false);
    ui.pushButton_newGame->setVisible(false);
    ui.pushButton_resign->setVisible(false);
    ui.pushButton_retractMove->setVisible(false);
    ui.pushButton_hint->setVisible(false);
#endif /* QT_MOBILE_APP_UI */

#ifdef SHOW_MAXIMIZED_ON_LOAD
    showMaximized();
    QWidget::setWindowFlags(Qt::WindowMaximizeButtonHint |
                            Qt::WindowCloseButtonHint |
                            Qt::WindowMinimizeButtonHint);
#endif // SHOW_MAXIMIZED_ON_LOAD

#ifdef QT_MOBILE_APP_UI
    ui.pushButton_option->setContextMenuPolicy(Qt::ActionsContextMenu);
    connect(ui.pushButton_option,
            SIGNAL(customContextMenuRequested(const QPoint &)), this,
            SLOT(ctxMenu(const QPoint &)));
#endif /* QT_MOBILE_APP_UI */

    ui.actionEngine1_T->setChecked(game->isAiPlayer[WHITE]);
    ui.actionEngine2_R->setChecked(game->isAiPlayer[BLACK]);

    ui.actionFixWindowSize->setChecked(game->fixWindowSizeEnabled());
    ui.actionSound_S->setChecked(game->soundEnabled());
    ui.actionAnimation_A->setChecked(game->animationEnabled());

    const auto alignmentGroup = new QActionGroup(this);
    alignmentGroup->addAction(ui.actionAlphaBetaAlgorithm);
    alignmentGroup->addAction(ui.actionPvsAlgorithm);
    alignmentGroup->addAction(ui.actionMtdfAlgorithm);
    alignmentGroup->addAction(ui.actionMctsAlgorithm);
    alignmentGroup->addAction(ui.actionRandomAlgorithm);

    switch (gameOptions.getAlgorithm()) {
    case 0:
        ui.actionAlphaBetaAlgorithm->setChecked(true);
        ui.actionPvsAlgorithm->setChecked(false);
        ui.actionMtdfAlgorithm->setChecked(false);
        ui.actionMctsAlgorithm->setChecked(false);
        ui.actionRandomAlgorithm->setChecked(false);
        debugPrintf("Algorithm is Alpha-Beta.\n");
        break;
    case 1:
        ui.actionAlphaBetaAlgorithm->setChecked(false);
        ui.actionPvsAlgorithm->setChecked(true);
        ui.actionMtdfAlgorithm->setChecked(false);
        ui.actionMctsAlgorithm->setChecked(false);
        ui.actionRandomAlgorithm->setChecked(false);
        debugPrintf("Algorithm is PVS.\n");
        break;
    case 2:
        ui.actionAlphaBetaAlgorithm->setChecked(false);
        ui.actionPvsAlgorithm->setChecked(false);
        ui.actionMtdfAlgorithm->setChecked(true);
        ui.actionMctsAlgorithm->setChecked(false);
        ui.actionRandomAlgorithm->setChecked(false);
        debugPrintf("Algorithm is MTD(f).\n");
        break;
    case 3:
        ui.actionAlphaBetaAlgorithm->setChecked(false);
        ui.actionPvsAlgorithm->setChecked(false);
        ui.actionMtdfAlgorithm->setChecked(false);
        ui.actionMctsAlgorithm->setChecked(true);
        ui.actionRandomAlgorithm->setChecked(false);
        debugPrintf("Algorithm is MCTS.\n");
        break;
    case 4:
        ui.actionAlphaBetaAlgorithm->setChecked(false);
        ui.actionPvsAlgorithm->setChecked(false);
        ui.actionMtdfAlgorithm->setChecked(false);
        ui.actionMctsAlgorithm->setChecked(false);
        ui.actionRandomAlgorithm->setChecked(true);
        debugPrintf("Algorithm is Random.\n");
        break;
    default:
        assert(false);
        break;
    }

    ui.actionDrawOnHumanExperience->setChecked(
        gameOptions.getDrawOnHumanExperience());
    ui.actionConsiderMobility->setChecked(gameOptions.getConsiderMobility());
    ui.actionFocusOnBlockingPaths->setChecked(
        gameOptions.getFocusOnBlockingPaths());
    ui.actionAiIsLazy->setChecked(gameOptions.getAiIsLazy());
    ui.actionShuffling_R->setChecked(gameOptions.getShufflingEnabled());
    ui.actionUsePerfectDatabase->setChecked(
        gameOptions.getUsePerfectDatabase());
    ui.actionIDS_I->setChecked(gameOptions.getIDSEnabled());
    ui.actionDepthExtension_D->setChecked(gameOptions.getDepthExtension());
    ui.actionResignIfMostLose_G->setChecked(gameOptions.getResignIfMostLose());
    ui.actionAutoRestart_A->setChecked(gameOptions.getAutoRestart());
    ui.actionOpeningBook_O->setChecked(gameOptions.getOpeningBook());
    ui.actionLearnEndgame_E->setChecked(gameOptions.getLearnEndgameEnabled());
    ui.actionDeveloperMode->setChecked(gameOptions.getDeveloperMode());

    // Initialize language manager and setup language menu
    languageManager = LanguageManager::getInstance();

    // Get settings file path from game and initialize language manager with it
    QString settingsFilePath = game->getSettingsFilePath();
    if (!settingsFilePath.isEmpty()) {
        languageManager->initializeWithSettingsFile(settingsFilePath);
    }

    setupLanguageMenu();

    // Connect language changed signal
    connect(languageManager, &LanguageManager::languageChanged, this,
            &MillGameWindow::onLanguageChanged);

    // Set a minimum width for the details dock widget to prevent it from
    // becoming too narrow
    if (ui.dockWidget) {
        ui.dockWidget->setMinimumWidth(128);
    }

    connect(ui.actionGameSettings, &QAction::triggered, this,
            &MillGameWindow::openGameSettingsDialog);
}

void MillGameWindow::handleAdvantageChanged(qreal value)
{
    scene->board->updateAdvantageValue(value);
}

#ifdef QT_MOBILE_APP_UI
void MillGameWindow::ctxMenu(const QPoint &pos)
{
    QMenu *menu = new QMenu;
    menu->addAction(tr("Test Item"), this, SLOT(on_actionNew_N_triggered()));
    menu->exec(ui.pushButton_option->mapToGlobal(pos));
}
#endif /* QT_MOBILE_APP_UI */

void MillGameWindow::saveBook(const QString &path)
{
    if (path.isEmpty()) {
        return;
    }

    if (file.isOpen()) {
        file.close();
    }

    file.setFileName(path);

    if (!file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
        return;
    }

    QTextStream textStream(&file);
    const auto *strList = qobject_cast<QStringListModel *>(
        ui.listView->model());

    for (const QString &cmd : strList->stringList()) {
        textStream << cmd << "\n";
    }

    file.flush();
}

void MillGameWindow::actionRules_triggered()
{
    ui.actionAutoRun_A->setChecked(false);

    // Cancel the selection of other rules
    for (QAction *action : ruleActionList)
        action->setChecked(false);

    // Select current rule
    auto *action = dynamic_cast<QAction *>(sender());
    action->setChecked(true);
    ruleNo = action->data().toInt();

    // If the rules of the game have not changed, return
    if (ruleNo == game->getRuleIndex())
        return;

    // Cancel AI setting
    ui.actionEngine1_T->setChecked(false);
    ui.actionEngine2_R->setChecked(false);

    game->applyRule(ruleNo);
}

void MillGameWindow::on_actionNew_N_triggered()
{
    const auto *strList = qobject_cast<QStringListModel *>(
        ui.listView->model());

    // If you have not finished playing game and have already taken more than a
    // few steps, you will be lost
    if (strList->stringList().size() > 12) {
        game->resignHumanPlayer();
    }

    game->saveGameScore();

#ifdef SAVE_GAME_BOOK_WHEN_ACTION_NEW_TRIGGERED
    const QString strDateTime = QDateTime::currentDateTime().toString("yyyy-MM-"
                                                                      "dd_"
                                                                      "hhmmss");
    QString strDate = QDateTime::currentDateTime().toString("yyyy-MM-dd");
    QString whoWin;

    switch (game->getPosition()->get_winner()) {
    case WHITE:
        whoWin = "White-Win";
        break;
    case BLACK:
        whoWin = "Black-Win";
        break;
    case DRAW:
        whoWin = "Draw";
        break;
    case NOBODY:
    case COLOR_NB:
        whoWin = "Unknown";
        break;
    }

    const QString path = QDir::currentPath() + "/" + tr("Book_") + whoWin +
                         "_" + strDateTime + ".txt";

    // After a certain number of steps, save the score when creating a new game
    if (strList->stringList().size() > 18) {
        saveBook(path);
    }
#endif /* SAVE_GAME_BOOK_WHEN_ACTION_NEW_TRIGGERED */

    ui.actionAutoRun_A->setChecked(false);

    game->gameReset();
}

void MillGameWindow::on_actionOpen_O_triggered()
{
    const QString path = QFileDialog::getOpenFileName(
        this, tr("Open Move List File"), QDir::currentPath(), "TXT(*.txt)");

    if (path.isEmpty()) {
        return;
    }

    if (file.isOpen()) {
        file.close();
    }

    file.setFileName(path);

    // Files larger than 1MB are not supported.
    if (file.size() > 0x100000) {
        QMessageBox msgBox(QMessageBox::Warning, tr("File Too Large"),
                           tr("Files exceeding 1MB are not supported."),
                           QMessageBox::Ok);
        msgBox.exec();
        return;
    }

    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return;
    }

    ui.actionEngine1_T->setChecked(false);
    ui.actionEngine2_R->setChecked(false);

    QTextStream textStream(&file);
    QString cmd = textStream.readLine();

    // No need to refresh the scene when reading and displaying the move list.
    if (!game->command(cmd.toStdString(), false)) {
        QMessageBox msgBox(QMessageBox::Warning, tr("File Error"),
                           tr("Invalid move list file."), QMessageBox::Ok);
        msgBox.exec();
        return;
    }

    // Reset the game.
    game->gameReset();

    while (!textStream.atEnd()) {
        cmd = textStream.readLine();
        game->command(cmd.toStdString(), false);
    }

    // Refresh the scene after reading the file.
    game->refreshScene();
}

void MillGameWindow::on_actionSave_S_triggered()
{
    if (file.isOpen()) {
        file.close();

        if (file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
            QTextStream textStream(&file);
            const auto *strList = qobject_cast<QStringListModel *>(
                ui.listView->model());
            for (const QString &cmd : strList->stringList())
                textStream << cmd << "\n";
            file.flush();
        }

        return;
    }

    on_actionSaveAs_A_triggered();
}

void MillGameWindow::on_actionSaveAs_A_triggered()
{
    QString dateTimeString = QDateTime::currentDateTime().toString("ddd_MMM_d_"
                                                                   "hh_mm_ss_"
                                                                   "yyyy");
    const QString path = QFileDialog::getSaveFileName(
        this, tr("Open the move list file"),
        QDir::currentPath() + tr("/MoveList_") + dateTimeString + ".txt",
        "TXT(*.txt)");

    saveBook(path);
}

void MillGameWindow::on_actionEdit_E_toggled(bool arg1)
{
    Q_UNUSED(arg1)
}

void MillGameWindow::on_actionInvert_I_toggled(bool arg1) const
{
    // If white and black are reversed
    if (arg1) {
        ui.actionEngine1_T->setIcon(QIcon(":/icon/Resources/icon/Black.png"));
        ui.actionEngine2_R->setIcon(QIcon(":/icon/Resources/icon/White.png"));
        ui.picLabel1->setPixmap(QPixmap(":/icon/Resources/icon/Black.png"));
        ui.picLabel2->setPixmap(QPixmap(":/icon/Resources/icon/White.png"));
    } else {
        ui.actionEngine1_T->setIcon(QIcon(":/icon/Resources/icon/White.png"));
        ui.actionEngine2_R->setIcon(QIcon(":/icon/Resources/icon/Black.png"));
        ui.picLabel1->setPixmap(QPixmap(":/icon/Resources/icon/White.png"));
        ui.picLabel2->setPixmap(QPixmap(":/icon/Resources/icon/Black.png"));
    }

    // Let the controller change the color of the pieces
    // game->invertPieceColor(arg1);
    game->togglePieceColors(); // TODO: Right?
}

void MillGameWindow::on_actionRowChange() const
{
    const QAbstractItemModel *model = ui.listView->model();
    const int rows = model->rowCount();
    int currentRow = ui.listView->currentIndex().row();

    QObject *const s = sender();

    if (s != nullptr) {
        if (s == ui.actionBegin_S) {
            ui.listView->setCurrentIndex(model->index(0, 0));
        } else if (s == ui.actionPrevious_B
#ifdef QT_MOBILE_APP_UI
                   || s == ui.pushButton_retractMove
#endif /* QT_MOBILE_APP_UI */
        ) {
            if (currentRow > 0) {
                ui.listView->setCurrentIndex(model->index(currentRow - 1, 0));
            }
        } else if (s == ui.actionNext_F) {
            if (currentRow < rows - 1) {
                ui.listView->setCurrentIndex(model->index(currentRow + 1, 0));
            }
        } else if (s == ui.actionEnd_E) {
            ui.listView->setCurrentIndex(model->index(rows - 1, 0));
        }

        currentRow = ui.listView->currentIndex().row();
    }

    // Update action status
    if (rows <= 1) {
        ui.actionBegin_S->setEnabled(false);
        ui.actionPrevious_B->setEnabled(false);
        ui.actionNext_F->setEnabled(false);
        ui.actionEnd_E->setEnabled(false);
        ui.actionAutoRun_A->setEnabled(false);
    } else {
        if (currentRow <= 0) {
            ui.actionBegin_S->setEnabled(false);
            ui.actionPrevious_B->setEnabled(false);
            ui.actionNext_F->setEnabled(true);
            ui.actionEnd_E->setEnabled(true);
            ui.actionAutoRun_A->setEnabled(true);
        } else if (currentRow >= rows - 1) {
            ui.actionBegin_S->setEnabled(true);
            ui.actionPrevious_B->setEnabled(true);
            ui.actionNext_F->setEnabled(false);
            ui.actionEnd_E->setEnabled(false);
            ui.actionAutoRun_A->setEnabled(false);
        } else {
            ui.actionBegin_S->setEnabled(true);
            ui.actionPrevious_B->setEnabled(true);
            ui.actionNext_F->setEnabled(true);
            ui.actionEnd_E->setEnabled(true);
            ui.actionAutoRun_A->setEnabled(true);
        }
    }

    // Update phrase
    game->refreshBoardState(currentRow, true);
}

void MillGameWindow::onAutoRunTimeOut(QPrivateSignal signal) const
{
    Q_UNUSED(signal)
    const int rows = ui.listView->model()->rowCount();
    int currentRow = ui.listView->currentIndex().row();

    if (rows <= 1) {
        ui.actionAutoRun_A->setChecked(false);
        return;
    }

    // Do the "next move"
    if (currentRow >= rows - 1) {
        ui.actionAutoRun_A->setChecked(false);
        return;
    }

    if (currentRow < rows - 1) {
        ui.listView->setCurrentIndex(
            ui.listView->model()->index(currentRow + 1, 0));
    }

    currentRow = ui.listView->currentIndex().row();

    // Update action status
    if (currentRow <= 0) {
        ui.actionBegin_S->setEnabled(false);
        ui.actionPrevious_B->setEnabled(false);
        ui.actionNext_F->setEnabled(true);
        ui.actionEnd_E->setEnabled(true);
        ui.actionAutoRun_A->setEnabled(true);
    } else if (currentRow >= rows - 1) {
        ui.actionBegin_S->setEnabled(true);
        ui.actionPrevious_B->setEnabled(true);
        ui.actionNext_F->setEnabled(false);
        ui.actionEnd_E->setEnabled(false);
        ui.actionAutoRun_A->setEnabled(false);
    } else {
        ui.actionBegin_S->setEnabled(true);
        ui.actionPrevious_B->setEnabled(true);
        ui.actionNext_F->setEnabled(true);
        ui.actionEnd_E->setEnabled(true);
        ui.actionAutoRun_A->setEnabled(true);
    }

    // Renew the situation
    game->refreshBoardState(currentRow, true);
}

void MillGameWindow::on_actionAutoRun_A_toggled(bool arg1)
{
    if (arg1) {
        ui.dockWidget->setEnabled(false);
        ui.gameView->setEnabled(false);

        autoRunTimer.start(game->getDurationTime() * 10 + 50);
    } else {
        autoRunTimer.stop();

        ui.dockWidget->setEnabled(true);
        ui.gameView->setEnabled(true);
    }
}

void MillGameWindow::on_actionLocal_L_triggered() const
{
    ui.actionLocal_L->setChecked(true);
    ui.actionEngineFight_E->setChecked(false);
    ui.actionInternet_I->setChecked(false);

    game->getTest()->stop();
}

void MillGameWindow::on_actionInternet_I_triggered()
{
#ifdef NET_FIGHT_SUPPORT
    ui.actionLocal_L->setChecked(false);
    ui.actionEngineFight_E->setChecked(false);
    ui.actionInternet_I->setChecked(true);

    game->getTest()->stop();

    game->showNetworkWindow();
#endif
}

void MillGameWindow::on_actionEngineFight_E_triggered() const
{
    ui.actionLocal_L->setChecked(false);
    ui.actionEngineFight_E->setChecked(true);
    ui.actionInternet_I->setChecked(false);

    game->displayTestWindow();
}

void MillGameWindow::on_actionEngine_E_triggered()
{
    auto *dialog = new QDialog(this);
    dialog->setWindowFlags(Qt::Dialog | Qt::WindowCloseButtonHint);
    dialog->setObjectName(QStringLiteral("Dialog"));
    dialog->setWindowTitle(tr("Configure AI"));
    dialog->resize(256, 188);
    dialog->setModal(true);

    auto *vLayout = new QVBoxLayout(dialog);
    auto *groupBox1 = new QGroupBox(dialog);
    auto *groupBox2 = new QGroupBox(dialog);

    auto *hLayout1 = new QHBoxLayout;
    auto *label_time1 = new QLabel(dialog);
    auto *spinBox_time1 = new QSpinBox(dialog);

    auto *hLayout2 = new QHBoxLayout;
    auto *label_time2 = new QLabel(dialog);
    auto *spinBox_time2 = new QSpinBox(dialog);

    auto *buttonBox = new QDialogButtonBox(dialog);

    groupBox1->setTitle(tr("Player1 AI Settings"));
    label_time1->setText(tr("Time limit"));
    spinBox_time1->setMinimum(1);
    spinBox_time1->setMaximum(3600);

    groupBox2->setTitle(tr("Player2 AI Settings"));
    label_time2->setText(tr("Time limit"));
    spinBox_time2->setMinimum(1);
    spinBox_time2->setMaximum(3600);

    buttonBox->setStandardButtons(QDialogButtonBox::Cancel |
                                  QDialogButtonBox::Ok);
    buttonBox->setCenterButtons(true);
    buttonBox->button(QDialogButtonBox::Ok)->setText(tr("OK"));
    buttonBox->button(QDialogButtonBox::Cancel)->setText(tr("Cancel"));

    vLayout->addWidget(groupBox1);
    vLayout->addWidget(groupBox2);
    vLayout->addWidget(buttonBox);
    groupBox1->setLayout(hLayout1);
    groupBox2->setLayout(hLayout2);
    hLayout1->addWidget(label_time1);
    hLayout1->addWidget(spinBox_time1);
    hLayout2->addWidget(label_time2);
    hLayout2->addWidget(spinBox_time2);

    connect(buttonBox, SIGNAL(accepted()), dialog, SLOT(accept()));
    connect(buttonBox, SIGNAL(rejected()), dialog, SLOT(reject()));

    int time1, time2;
    game->getAiTimeLimits(time1, time2);
    spinBox_time1->setValue(time1);
    spinBox_time2->setValue(time2);

    if (dialog->exec() == QDialog::Accepted) {
        const int time1_new = spinBox_time1->value();
        const int time2_new = spinBox_time2->value();

        if (time1 != time1_new || time2 != time2_new) {
            game->setAiTimeLimits(time1_new, time2_new);
        }
    }

    dialog->disconnect();
    delete dialog;
}

void MillGameWindow::on_actionOpen_Settings_File_triggered()
{
    QString settingsFilePath = QCoreApplication::applicationDirPath() + "/setti"
                                                                        "ngs."
                                                                        "ini";

    if (!QFileInfo::exists(settingsFilePath)) {
        QMessageBox::warning(this, tr("File Not Found"),
                             tr("The settings.ini file does not exist."));
        return;
    }

    QString editorCommand;

#if defined(Q_OS_WIN)
    editorCommand = "notepad.exe";
#elif defined(Q_OS_MAC)
    editorCommand = "open";
#elif defined(Q_OS_LINUX)
    editorCommand = "gedit";
#else
    editorCommand = QString();
#endif

    if (!editorCommand.isEmpty()) {
        QStringList arguments;
#if defined(Q_OS_MAC)
        arguments << "-a"
                  << "TextEdit" << settingsFilePath;
#else
        arguments << settingsFilePath;
#endif

        QProcess *process = new QProcess(this);
        process->start(editorCommand, arguments);

        if (!process->waitForStarted()) {
            QMessageBox::warning(this, tr("Error"),
                                 tr("Failed to open the settings file with the "
                                    "text editor."));
            delete process;
            return;
        }

        connect(process,
                QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                process, &QObject::deleteLater);
    } else {
        QDesktopServices::openUrl(QUrl::fromLocalFile(settingsFilePath));
    }
}

void MillGameWindow::on_actionViewHelp_V_triggered()
{
    QDesktopServices::openUrl(QUrl("https://github.com/calcitem/Sanmill/blob/"
                                   "master/src/perfect/README.md"));
}

void MillGameWindow::on_actionWeb_W_triggered()
{
    QDesktopServices::openUrl(QUrl("https://github.com/calcitem/Sanmill/wiki"));
}

void MillGameWindow::on_actionAbout_A_triggered()
{
    auto *dialog = new QDialog;

    dialog->setWindowFlags(Qt::Dialog | Qt::WindowCloseButtonHint);
    dialog->setObjectName(QStringLiteral("aboutDialog"));
    dialog->setWindowTitle(tr("The Mill Game"));
    dialog->setModal(true);

    auto *vLayout = new QVBoxLayout(dialog);
    auto *hLayout = new QHBoxLayout;
    // QLabel *label_icon1 = new QLabel(dialog);
    // QLabel *label_icon2 = new QLabel(dialog);
    auto *date_text = new QLabel(dialog);
    auto *version_text = new QLabel(dialog);
    auto *donate_text = new QLabel(dialog);
    auto *label_text = new QLabel(dialog);
    auto *label_image = new QLabel(dialog);

#if 0
    label_icon1->setPixmap(
        QPixmap(QString::fromUtf8(":/image/resources/image/white_piece.png")));
    label_icon2->setPixmap(
        QPixmap(QString::fromUtf8(":/image/resources/image/black_piece.png")));
    label_icon1->setAlignment(Qt::AlignCenter);
    label_icon2->setAlignment(Qt::AlignCenter);
    label_icon1->setFixedSize(32, 32);
    label_icon2->setFixedSize(32, 32);
    label_icon1->setScaledContents(true);
    label_icon2->setScaledContents(true);
#endif

    // date_text->setText(__DATE__);
    QString versionText;

    if (strcmp(versionNumber, "Unknown") > 0) {
        versionText = tr("Version: ") + versionNumber +
                      "\nBuild: " + __DATE__ " " __TIME__;
    } else {
        versionText = tr("Build: ") + __DATE__ " " __TIME__;
    }

    version_text->setText(versionText);
    version_text->setAlignment(Qt::AlignLeft);

    vLayout->addLayout(hLayout);
    // hLayout->addWidget(label_icon1);
    // hLayout->addWidget(label_icon2);
    hLayout->addWidget(version_text);
    hLayout->addWidget(label_text);
    vLayout->addWidget(date_text);
    vLayout->addWidget(donate_text);
    vLayout->addWidget(label_image);

    dialog->exec();

    dialog->disconnect();
    delete dialog;
}

#ifdef QT_MOBILE_APP_UI
void MillGameWindow::mousePressEvent(QMouseEvent *mouseEvent)
{
    if (mouseEvent->button() == Qt::LeftButton) {
        m_move = true;
        m_startPoint = mouseEvent->globalPos();
        m_windowPoint = this->frameGeometry().topLeft();
    }
}

void MillGameWindow::mouseMoveEvent(QMouseEvent *mouseEvent)
{
    if (mouseEvent->buttons() & Qt::LeftButton) {
        QPoint relativePos = mouseEvent->globalPos() - m_startPoint;
        this->move(m_windowPoint + relativePos);
    }
}

void MillGameWindow::mouseReleaseEvent(QMouseEvent *mouseEvent)
{
    if (mouseEvent->button() == Qt::LeftButton) {
        m_move = false;
    }
}
#endif /* QT_MOBILE_APP_UI */

void MillGameWindow::setupLanguageMenu()
{
    // Create language menu and add it to the Options menu
    languageMenu = new QMenu(tr("Language"), this);
    languageActionGroup = new QActionGroup(this);

    // Add language menu to Options menu
    ui.menu_O->addSeparator();
    ui.menu_O->addMenu(languageMenu);

    // Get available languages
    QStringList languages = languageManager->getAvailableLanguages();
    QStringList languageCodes = languageManager->getAvailableLanguageCodes();

    for (int i = 0; i < languages.size(); ++i) {
        QAction *languageAction = new QAction(languages[i], this);
        languageAction->setCheckable(true);
        languageAction->setData(languageCodes[i]);

        languageActionGroup->addAction(languageAction);
        languageMenu->addAction(languageAction);

        // Check current language
        if (languageCodes[i] == languageManager->getCurrentLanguageCode()) {
            languageAction->setChecked(true);
        }

        connect(languageAction, &QAction::triggered, this,
                &MillGameWindow::changeLanguage);
    }
}

void MillGameWindow::changeLanguage()
{
    QAction *action = qobject_cast<QAction *>(sender());
    if (!action)
        return;

    QString languageCode = action->data().toString();
    languageManager->loadLanguage(languageCode);
}

void MillGameWindow::onLanguageChanged()
{
    retranslateUi();
}

void MillGameWindow::retranslateUi()
{
    // Save current game view state to restore after retranslation
    QTransform savedTransform;
    QRect savedGeometry;
    bool hasValidView = false;

    if (ui.gameView) {
        savedTransform = ui.gameView->transform();
        savedGeometry = ui.gameView->geometry();
        hasValidView = true;
    }

    // Retranslate UI elements
    ui.retranslateUi(this);

    // Update window title
    setWindowTitle(tr("The Mill Game"));

    // Update language menu text
    if (languageMenu) {
        languageMenu->setTitle(tr("Language"));
    }

    // Restore game view state to prevent visual size changes
    if (hasValidView && ui.gameView) {
        ui.gameView->setTransform(savedTransform);
        ui.gameView->setGeometry(savedGeometry);

        // Ensure the scene rect remains unchanged
        if (scene) {
            scene->setSceneRect(-BOARD_SIDE_LENGTH * 0.54,
                                -BOARD_SIDE_LENGTH * 0.54,
                                BOARD_SIDE_LENGTH * 1.08,
                                BOARD_SIDE_LENGTH * 1.08);
        }

        // Force view to fit the scene properly without changing zoom
        ui.gameView->viewport()->update();
    }

    // Update status bar and other dynamic elements if needed
    // Note: Status bar will be updated automatically when game state changes
}

void MillGameWindow::changeEvent(QEvent *event)
{
    if (event->type() == QEvent::LanguageChange) {
        retranslateUi();
    }
    QMainWindow::changeEvent(event);
}

void MillGameWindow::showEvent(QShowEvent *event)
{
    QMainWindow::showEvent(event);
    // Center the window only on the first show event
    if (m_isFirstShow) {
        QScreen *primaryScreen = QGuiApplication::primaryScreen();
        if (primaryScreen) {
            const QRect screenGeometry = primaryScreen->geometry();
            const int windowWidth = width();
            const int windowHeight = height();

            const int x = screenGeometry.x() +
                          (screenGeometry.width() - windowWidth) / 2;
            const int y = screenGeometry.y() +
                          (screenGeometry.height() - windowHeight) / 2;
            this->move(x, y);
        }
        m_isFirstShow = false;
    }
}

void MillGameWindow::openGameSettingsDialog()
{
    auto *gameSettingsDialog = new TimeSettingsDialog(this);

    // Load current settings
    if (game && game->settings) {
        gameSettingsDialog->loadSettings(game->settings);
    }

    // Show dialog and handle user input
    if (gameSettingsDialog->exec() == QDialog::Accepted) {
        // Save settings if user clicked OK
        if (game && game->settings) {
            gameSettingsDialog->saveSettings(game->settings);

            // Apply the new time limits to the game
            int whiteTime = gameSettingsDialog->getWhiteTimeLimit();
            int blackTime = gameSettingsDialog->getBlackTimeLimit();
            int moveLimit = gameSettingsDialog->getMoveLimit();

            game->setPlayerTimeLimits(whiteTime, blackTime);
            game->setMoveLimit(moveLimit);

            // Show confirmation message
            QString message = tr("Game settings updated: White %1s, Black %2s, "
                                 "Move limit %3")
                                  .arg(whiteTime)
                                  .arg(blackTime)
                                  .arg(moveLimit);
            game->statusBarChanged(message);
        }
    }

    delete gameSettingsDialog;
}
