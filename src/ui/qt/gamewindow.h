// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
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

#ifndef GAMEWINDOW_H_INCLUDED
#define GAMEWINDOW_H_INCLUDED

#include <QFile>
#include <QTimer>
#include <QtWidgets/QMainWindow>
#include <vector>

#include "config.h"

#include "ui_gamewindow.h"

#include "client.h"
#include "server.h"

using std::vector;

class GameScene;
class Game;

class MillGameWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MillGameWindow(QWidget *parent = nullptr);
    ~MillGameWindow() override;

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void closeEvent(QCloseEvent *event) override;
#ifdef QT_MOBILE_APP_UI
    void mousePressEvent(QMouseEvent *mouseEvent) override;
    void mouseMoveEvent(QMouseEvent *mouseEvent) override;
    void mouseReleaseEvent(QMouseEvent *mouseEvent) override;
#endif /* QT_MOBILE_APP_UI */

private slots:
    void initialize();

#ifdef QT_MOBILE_APP_UI
    void ctxMenu(const QPoint &pos);
#endif /* QT_MOBILE_APP_UI */

    void actionRules_triggered();

    void ruleInfo() const;

    void onAutoRunTimeOut(QPrivateSignal signal) const;

    // The slot function for each action
    // Remove functions have been connected in UI manager or main window
    // initialization function
    void on_actionNew_N_triggered();
    void on_actionOpen_O_triggered();
    void on_actionSave_S_triggered();
    void on_actionSaveAs_A_triggered();
#if 0
    void on_actionExit_X_triggered();
#endif
    static void on_actionEdit_E_toggled(bool arg1);
#if 0
    void on_actionFlip_F_triggered();
    void on_actionMirror_M_triggered();
    void on_actionTurnRight_R_triggered();
    void on_actionTurnLeft_L_triggered();
#endif
    void on_actionInvert_I_toggled(bool arg1) const;
    void on_actionRowChange() const;
    void on_actionAutoRun_A_toggled(bool arg1);
    // void on_actionResign_G_triggered();
    void on_actionLimited_T_triggered();
    void on_actionLocal_L_triggered() const;
    void on_actionEngineFight_E_triggered() const;
    static void on_actionInternet_I_triggered();
    void on_actionEngine_E_triggered();
#if 0
    void on_actionEngine1_R_toggled(bool arg1);
    void on_actionEngine2_T_toggled(bool arg1);
    void on_actionSetting_O_triggered();
    void on_actionToolBar_T_toggled(bool arg1);
    void on_actionDockBar_D_toggled(bool arg1);
    void on_actionSound_S_toggled(bool arg1);
    void on_actionAnimation_A_toggled(bool arg1);
    void on_actionAutoRestart_A_triggered();
#endif
    static void on_actionViewHelp_V_triggered();
    static void on_actionWeb_W_triggered();
    static void on_actionAbout_A_triggered();

protected:
    void saveBook(const QString &path);

private:
    Ui::MillGameWindowClass ui {};
    GameScene *scene {nullptr};
    Game *game {nullptr};
    vector<QAction *> ruleActionList;
    int ruleNo {-1};
    QFile file;
    QTimer autoRunTimer;

#ifdef QT_MOBILE_APP_UI
    bool m_move {false};
    QPoint m_startPoint;
    QPoint m_windowPoint;
#endif
};

#endif // GAMEWINDOW_H_INCLUDED
