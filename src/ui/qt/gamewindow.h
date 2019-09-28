/*****************************************************************************
 * Copyright (C) 2018-2019 MillGame authors
 *
 * Authors: liuweilhy <liuweilhy@163.com>
 *          Calcitem <calcitem@outlook.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef GAMEWINDOW_H
#define GAMEWINDOW_H

#include <QtWidgets/QMainWindow>
#include <QTextStream>
#include <QStringListModel>
#include <QFile>
#include <QTimer>

#include "config.h"

#include "ui_gamewindow.h"

#include "server.h"
#include "client.h"

class GameScene;
class GameController;

class MillGameWindow : public QMainWindow
{
    Q_OBJECT

public:
    MillGameWindow(QWidget *parent = nullptr);
    ~MillGameWindow() override;

protected:
    bool eventFilter(QObject *watched, QEvent *event) override;
    void closeEvent(QCloseEvent *event) override;
#ifdef MOBILE_APP_UI
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
#endif /* MOBILE_APP_UI */

private slots:
    // 初始化
    void initialize();

#ifdef MOBILE_APP_UI
    // 上下文菜单
    void ctxMenu(const QPoint &pos);
#endif /* MOBILE_APP_UI */

    // 动态增加的菜单栏动作的槽函数
    void actionRules_triggered();

    // 更新规则标签
    void ruleInfo();

    // 自动运行定时处理函数
    void onAutoRunTimeOut(QPrivateSignal signal);

    // 下面是各动作的槽函数
    // 注释掉的是已在UI管理器或主窗口初始化函数中连接好的
    void on_actionNew_N_triggered();
    void on_actionOpen_O_triggered();
    void on_actionSave_S_triggered();
    void on_actionSaveAs_A_triggered();
    //void on_actionExit_X_triggered();
    void on_actionEdit_E_toggled(bool arg1);
    //void on_actionFlip_F_triggered();
    //void on_actionMirror_M_triggered();
    //void on_actionTurnRight_R_triggered();
    //void on_actionTurnLeftt_L_triggered();
    void on_actionInvert_I_toggled(bool arg1);
    // 前后招的公共槽
    void on_actionRowChange();
    void on_actionAutoRun_A_toggled(bool arg1);
    //void on_actionGiveUp_G_triggered();
    void on_actionLimited_T_triggered();
    void on_actionLocal_L_triggered();
    void on_actionInternet_I_triggered();
    void on_actionEngine_E_triggered();
    //void on_actionEngine1_R_toggled(bool arg1);
    //void on_actionEngine2_T_toggled(bool arg1);
    //void on_actionSetting_O_triggered();
    //void on_actionToolBar_T_toggled(bool arg1);
    //void on_actionDockBar_D_toggled(bool arg1);
    //void on_actionSound_S_toggled(bool arg1);
    //void on_actionAnimation_A_toggled(bool arg1);
    //void on_actionAutoRestart_A_triggered();
    void on_actionViewHelp_V_triggered();
    void on_actionWeb_W_triggered();
    void on_actionAbout_A_triggered();

private:
    // 界面文件
    Ui::MillGameWindowClass ui {};

    // 视图场景
    GameScene *scene {nullptr};

    // 控制器
    GameController *gameController {nullptr};

    // 动态增加的菜单栏动作列表
    QList <QAction *> ruleActionList;

    // 游戏的规则号，涉及菜单项和对话框，所以要有
    int ruleNo {-1};

    // 文件
    QFile file;

    // 定时器
    QTimer autoRunTimer;

#ifdef MOBILE_APP_UI
    bool m_move {false};
    QPoint m_startPoint;
    QPoint m_windowPoint;
#endif
};

#endif // GAMEWINDOW_H
