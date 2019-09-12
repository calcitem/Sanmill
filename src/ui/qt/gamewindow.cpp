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

#include <QDesktopServices>
#include <QMap>
#include <QMessageBox>
#include <QTimer>
#include <QDialog>
#include <QFileDialog>
#include <QButtonGroup>
#include <QPushButton>
#include <QComboBox>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QGroupBox>
#include <QSpinBox>
#include <QLabel>
#include <QHelpEvent>
#include <QToolTip>
#include <QPicture>
#include <QScreen>
#include <QDesktopWidget>

#include "gamewindow.h"
#include "gamecontroller.h"
#include "gamescene.h"
#include "graphicsconst.h"
#include "server.h"
#include "client.h"
#include "version.h"

MillGameWindow::MillGameWindow(QWidget * parent) :
    QMainWindow(parent),
    autoRunTimer(this)
{
    ui.setupUi(this);

    // 去掉标题栏
    //setWindowFlags(Qt::FramelessWindowHint);

    // 设置透明(窗体标题栏不透明,背景透明，如果不去掉标题栏，背景就变为黑色)
    //setAttribute(Qt::WA_TranslucentBackground);

    // 设置全体透明度系数
    //setWindowOpacity(0.7);

    // 设置场景
    scene = new GameScene(this);

    // 设置场景尺寸大小为棋盘大小的1.08倍
    scene->setSceneRect(-BOARD_SIZE * 0.54, -BOARD_SIZE * 0.54,
                        BOARD_SIZE * 1.08, BOARD_SIZE * 1.08);

    // 初始化各个控件

    // 关联视图和场景
    ui.gameView->setScene(scene);

    // 视图反走样
    ui.gameView->setRenderHint(QPainter::Antialiasing, true);

    // 视图反锯齿
    ui.gameView->setRenderHint(QPainter::Antialiasing);

    // 因功能限制，使部分功能不可用，将来再添加
    ui.actionInternet_I->setDisabled(false);
    ui.actionSetting_O->setDisabled(true);

    // 初始化游戏规则菜单
    ui.menu_R->installEventFilter(this);

    // 关联自动运行定时器
    connect(&autoRunTimer, SIGNAL(timeout()),
            this, SLOT(onAutoRunTimeOut()));

    // 主窗口居中显示
    QRect deskTopRect = QGuiApplication::primaryScreen()->geometry();
    int unitw = (deskTopRect.width() - width()) / 2;
    int unith = (deskTopRect.height() - height()) / 2;
    this->move(unitw, unith);

#ifdef MOBILE_APP_UI
    // 隐藏菜单栏、工具栏、状态栏等
    ui.menuBar->setVisible(false);
    ui.mainToolBar->setVisible(false);
    ui.dockWidget->setVisible(false);
    ui.statusBar->setVisible(false);
#endif

    // 游戏初始化
    initialize();
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

    // 取消自动运行
    ui.actionAutoRun_A->setChecked(false);

    loggerDebug("closed\n");

    QMainWindow::closeEvent(event);
}

bool MillGameWindow::eventFilter(QObject *watched, QEvent *event)
{
    // 重载这个函数只是为了让规则菜单（动态）显示提示
    if (watched == ui.menu_R &&
        event->type() == QEvent::ToolTip) {
        auto *he = dynamic_cast <QHelpEvent *> (event);
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
    // 初始化函数，仅执行一次
    if (game)
        return;

    // 开辟一个新的游戏控制器
    game = new GameController(*scene, this);

    // 添加新菜单栏动作
    QMap <int, QStringList> actions = game->getActions();

    for (auto i = actions.constBegin(); i != actions.constEnd(); i++) {
        // QMap的key存放int索引值，value存放规则名称和规则提示
        auto *ruleAction = new QAction(i.value().at(0), this);
        ruleAction->setToolTip(i.value().at(1));
        ruleAction->setCheckable(true);

        // 索引值放在QAction的Data里
        ruleAction->setData(i.key());

        // 添加到动作列表
        ruleActionList.append(ruleAction);

        // 添加到“规则”菜单
        ui.menu_R->addAction(ruleAction);

        connect(ruleAction, SIGNAL(triggered()),
                this, SLOT(actionRules_triggered()));
    }

    // 关联主窗口动作信号和控制器的槽

    connect(ui.actionGiveUp_G, SIGNAL(triggered()),
            game, SLOT(giveUp()));

#ifdef MOBILE_APP_UI
    connect(ui.pushButton_giveUp, SIGNAL(released()),
            game, SLOT(giveUp()));
#endif

    connect(ui.actionEngine1_T, SIGNAL(toggled(bool)),
            game, SLOT(setEngine1(bool)));

    connect(ui.actionEngine2_R, SIGNAL(toggled(bool)),
            game, SLOT(setEngine2(bool)));

    connect(ui.
            actionSound_S, SIGNAL(toggled(bool)),
            game, SLOT(setSound(bool)));

    connect(ui.actionAnimation_A, SIGNAL(toggled(bool)),
            game, SLOT(setAnimation(bool)));

    connect(ui.actionGiveUpIfMostLose_G, SIGNAL(toggled(bool)),
            game, SLOT(setGiveUpIfMostLose(bool)));

    connect(ui.actionAutoRestart_A, SIGNAL(toggled(bool)),
            game, SLOT(setAutoRestart(bool)));

    connect(ui.actionRandomMove_R, SIGNAL(toggled(bool)),
            game, SLOT(setRandomMove(bool)));

    // 视图上下翻转
    connect(ui.actionFlip_F, &QAction::triggered,
            game, &GameController::flip);

    // 视图左右镜像
    connect(ui.actionMirror_M, &QAction::triggered,
            game, &GameController::mirror);

    // 视图须时针旋转90°
    connect(ui.actionTurnRight_R, &QAction::triggered,
            game, &GameController::turnRight);

    // 视图逆时针旋转90°
    connect(ui.actionTurnLeftt_L, &QAction::triggered,
            game, &GameController::turnLeft);

    // 关联控制器的信号和主窗口控件的槽

    // 更新LCD，显示玩家1赢盘数
    connect(game, SIGNAL(score1Changed(QString)),
            ui.scoreLcdNumber_1, SLOT(display(QString)));

    // 更新LCD，显示玩家2赢盘数
    connect(game, SIGNAL(score2Changed(QString)),
            ui.scoreLcdNumber_2, SLOT(display(QString)));

    // 更新LCD，显示和棋数
    connect(game, SIGNAL(scoreDrawChanged(QString)),
            ui.scoreLcdNumber_draw, SLOT(display(QString)));

    // 更新LCD1，显示玩家1用时
    connect(game, SIGNAL(time1Changed(QString)),
            ui.lcdNumber_1, SLOT(display(QString)));

    // 更新LCD2，显示玩家2用时
    connect(game, SIGNAL(time2Changed(QString)),
            ui.lcdNumber_2, SLOT(display(QString)));

    // 关联场景的信号和控制器的槽
    connect(scene, SIGNAL(mouseReleased(QPointF)),
            game, SLOT(actionPiece(QPointF)));

    // 为状态栏添加一个正常显示的标签
    auto *statusBarlabel = new QLabel(this);
    QFont statusBarFont;
    statusBarFont.setPointSize(16);
    statusBarlabel->setFont(statusBarFont);
    ui.statusBar->addWidget(statusBarlabel);

    // 更新状态栏
    connect(game, SIGNAL(statusBarChanged(QString)),
            statusBarlabel, SLOT(setText(QString)));

    // 默认第2号规则
    ruleNo = 1;
    ruleActionList.at(ruleNo)->setChecked(true);

    // 重置游戏规则
    game->setRule(ruleNo);

    // 更新规则显示
    ruleInfo();

    // 关联列表视图和字符串列表模型
    ui.listView->setModel(game->getManualListModel());

    // 因为QListView的rowsInserted在setModel之后才能启动，
    // 第一次需手动初始化选中listView第一项
    ui.listView->setCurrentIndex(ui.listView->model()->index(0, 0));

    // 初始局面、前一步、后一步、最终局面的槽

    connect(ui.actionBegin_S, &QAction::triggered,
            this, &MillGameWindow::on_actionRowChange);

    connect(ui.actionPrevious_B, &QAction::triggered,
            this, &MillGameWindow::on_actionRowChange);

#ifdef MOBILE_APP_UI
    connect(ui.pushButton_retractMove, &QPushButton::released,
            this, &MillGameWindow::on_actionRowChange);

    connect(ui.pushButton_newGame, &QPushButton::released,
            this, &MillGameWindow::on_actionNew_N_triggered);
#endif /* MOBILE_APP_UI */

    connect(ui.actionNext_F, &QAction::triggered,
            this, &MillGameWindow::on_actionRowChange);

    connect(ui.actionEnd_E, &QAction::triggered,
            this, &MillGameWindow::on_actionRowChange);

    // 手动在listView里选择着法后更新的槽
    connect(ui.listView, &ManualListView::currentChangedSignal,
            this, &MillGameWindow::on_actionRowChange);

    // 更新四个键的状态
    on_actionRowChange();

    // 设置窗体大小
#ifdef MOBILE_APP_UI
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
#else /* MOBILE_APP_UI */
    int h = QApplication::desktop()->height();
    this->resize(QSize(h * 3/4, h * 3/4));

    ui.pushButton_back->setVisible(false);
    ui.pushButton_option->setVisible(false);
    ui.label_2->setVisible(false);
    ui.label->setVisible(false);
    ui.pushButton_newGame->setVisible(false);
    ui.pushButton_giveUp->setVisible(false);
    ui.pushButton_retractMove->setVisible(false);
    ui.pushButton_hint->setVisible(false);
#endif /* MOBILE_APP_UI */

    // 窗口最大化
#ifdef SHOW_MAXIMIZED_ON_LOAD
    showMaximized();
    QWidget::setWindowFlags(Qt::WindowMaximizeButtonHint |
                            Qt::WindowCloseButtonHint | Qt::WindowMinimizeButtonHint);
#endif // SHOW_MAXIMIZED_ON_LOAD

#ifdef MOBILE_APP_UI
    ui.pushButton_option->setContextMenuPolicy(Qt::ActionsContextMenu);
    connect(ui.pushButton_option, SIGNAL(customContextMenuRequested(const QPoint &)), this, SLOT(ctxMenu(const QPoint &)));
#endif /* MOBILE_APP_UI */

    ui.actionEngine2_R->setChecked(true);
}

#ifdef MOBILE_APP_UI
void MillGameWindow::ctxMenu(const QPoint &pos)
{
    QMenu *menu = new QMenu;
    menu->addAction(tr("Test Item"), this, SLOT(on_actionNew_N_triggered()));
    menu->exec(ui.pushButton_option->mapToGlobal(pos));
}
#endif /* MOBILE_APP_UI */

void MillGameWindow::ruleInfo()
{
    int s = game->getStepsLimit();
    int t = game->getTimeLimit();

    QString tl(" 不限时");
    QString sl(" 不限步");

    if (s > 0)
        sl = " 限" + QString::number(s) + "步";
    if (t > 0)
        tl = " 限时" + QString::number(s) + "分";

    // 规则显示
    ui.labelRule->setText(tl + sl);

    // 规则提示
    ui.labelInfo->setToolTip(QString(RULES[ruleNo].name) + "\n" +
                             RULES[ruleNo].description);

    ui.labelRule->setToolTip(ui.labelInfo->toolTip());

#if 0
    QString tip_Rule = QString("%1\n%2").arg(tr(RULES[ruleNo].name))
        .arg(tr(RULES[ruleNo].info));
#endif
}

void MillGameWindow::on_actionLimited_T_triggered()
{
    /* 
     * 其实本来可以用设计器做个ui，然后从QDialog派生个自己的对话框
     * 但我不想再派生新类了，又要多出一个类和两个文件
     * 还要写与主窗口的接口，费劲
     * 于是手写QDialog界面
     */
    int gStep = game->getStepsLimit();
    int gTime = game->getTimeLimit();

    // 定义新对话框
    auto *dialog = new QDialog(this);
    dialog->setWindowFlags(Qt::Dialog | Qt::WindowCloseButtonHint);
    dialog->setObjectName(QStringLiteral("Dialog"));
    dialog->setWindowTitle(tr("步数和时间限制"));
    dialog->resize(256, 108);
    dialog->setModal(true);

    // 生成各个控件
    auto *formLayout = new QFormLayout(dialog);
    auto *label_step = new QLabel(dialog);
    auto *label_time = new QLabel(dialog);
    auto *comboBox_step = new QComboBox(dialog);
    auto *comboBox_time = new QComboBox(dialog);
    auto *buttonBox = new QDialogButtonBox(dialog);
#if 0
    // 设置各个控件ObjectName，不设也没关系
    formLayout->setObjectName(QStringLiteral("formLayout"));
    label_step->setObjectName(QStringLiteral("label_step"));
    label_time->setObjectName(QStringLiteral("label_time"));
    comboBox_step->setObjectName(QStringLiteral("comboBox_step"));
    comboBox_time->setObjectName(QStringLiteral("comboBox_time"));
    buttonBox->setObjectName(QStringLiteral("buttonBox"));
#endif
    // 设置各个控件数据
    label_step->setText(tr("超出限制步数判和："));
    label_time->setText(tr("任意一方超时判负："));
    comboBox_step->addItem(tr("无限制"), 0);
    comboBox_step->addItem(tr("50步"), 50);
    comboBox_step->addItem(tr("100步"), 100);
    comboBox_step->addItem(tr("200步"), 200);
    comboBox_time->addItem(tr("无限制"), 0);
    comboBox_time->addItem(tr("5分钟"), 5);
    comboBox_time->addItem(tr("10分钟"), 10);
    comboBox_time->addItem(tr("20分钟"), 20);
    comboBox_step->setCurrentIndex(comboBox_step->findData(gStep));
    comboBox_time->setCurrentIndex(comboBox_time->findData(gTime));
    buttonBox->setStandardButtons(QDialogButtonBox::Cancel | QDialogButtonBox::Ok);
    buttonBox->setCenterButtons(true);
    buttonBox->button(QDialogButtonBox::Ok)->setText(tr("确定"));
    buttonBox->button(QDialogButtonBox::Cancel)->setText(tr("取消"));

    // 布局
    formLayout->setSpacing(6);
    formLayout->setContentsMargins(11, 11, 11, 11);
    formLayout->setWidget(0, QFormLayout::LabelRole, label_step);
    formLayout->setWidget(0, QFormLayout::FieldRole, comboBox_step);
    formLayout->setWidget(1, QFormLayout::LabelRole, label_time);
    formLayout->setWidget(1, QFormLayout::FieldRole, comboBox_time);
    formLayout->setWidget(2, QFormLayout::SpanningRole, buttonBox);

    // 关联信号和槽函数
    connect(buttonBox, SIGNAL(accepted()), dialog, SLOT(accept()));
    connect(buttonBox, SIGNAL(rejected()), dialog, SLOT(reject()));

    // 收集数据
    if (dialog->exec() == QDialog::Accepted) {
        int dStep = comboBox_step->currentData().toInt();
        int dTime = comboBox_time->currentData().toInt();
        if (gStep != dStep || gTime != dTime) {
            // 重置游戏规则
            game->setRule(ruleNo, static_cast<step_t>(dStep), dTime);
        }
    }

    // 删除对话框，子控件会一并删除
    dialog->disconnect();
    delete dialog;

    // 更新规则显示
    ruleInfo();
}

void MillGameWindow::actionRules_triggered()
{
    // 取消自动运行
    ui.actionAutoRun_A->setChecked(false);

    // 取消其它规则的选择
    for (QAction *action : ruleActionList)
        action->setChecked(false);

    // 选择当前规则
    auto *action = dynamic_cast<QAction *>(sender());
    action->setChecked(true);
    ruleNo = action->data().toInt();

    // 如果游戏规则没变化，则返回
    if (ruleNo == game->getRuleNo())
        return;

    // 取消AI设定
    ui.actionEngine1_T->setChecked(false);
    ui.actionEngine2_R->setChecked(false);

    // 重置游戏规则
    game->setRule(ruleNo);

    // 更新规则显示
    ruleInfo();
}

void MillGameWindow::on_actionNew_N_triggered()
{
    if (file.isOpen())
        file.close();

#ifdef SAVE_GAMEBOOK_WHEN_ACTION_NEW_TRIGGERED
    QString path = QDir::currentPath() + "/" + tr("book_") + QString::number(QDateTime::currentDateTimeUtc().toTime_t()) + ".txt";
    auto *strlist = qobject_cast<QStringListModel*>(ui.listView->model());

    if (!path.isEmpty() && strlist->stringList().size() > 18) {
        // 文件对象  
        file.setFileName(path);

        // 打开文件,只写方式打开
        if (file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
            // 写文件
            QTextStream textStream(&file);
            for (const QString &cmd : strlist->stringList())
                textStream << cmd << endl;
            file.flush();
        }
    }
#endif /* SAVE_GAMEBOOK_WHEN_ACTION_NEW_TRIGGERED */

    // 取消自动运行
    ui.actionAutoRun_A->setChecked(false);    

    // 重置游戏规则
    game->gameReset();

    // 重设AI设定
    if (ui.actionEngine2_R->isChecked()) {
        ui.actionEngine2_R->setChecked(false);
        ui.actionEngine2_R->setChecked(true);
    }

    if (ui.actionEngine1_T->isChecked()) {
        ui.actionEngine1_T->setChecked(false);
        ui.actionEngine1_T->setChecked(true);
    }
}

void MillGameWindow::on_actionOpen_O_triggered()
{
    QString path = QFileDialog::getOpenFileName(this, tr("打开棋谱文件"), QDir::currentPath(), "TXT(*.txt)");

    if (path.isEmpty()) {
        return;
    }

    if (file.isOpen()) {
        file.close();
    }

    // 文件对象
    file.setFileName(path);

    // 不支持 1MB 以上的文件
    if (file.size() > 0x100000) {
        // 定义新对话框
        QMessageBox msgBox(QMessageBox::Warning,
            tr("文件过大"), tr("不支持 1MB 以上文件"), QMessageBox::Ok);
        msgBox.exec();
        return;
    }

    // 打开文件,只读方式打开
    if (!(file.open(QFileDevice::ReadOnly | QFileDevice::Text))) {
        return;
    }

    // 取消AI设定
    ui.actionEngine1_T->setChecked(false);
    ui.actionEngine2_R->setChecked(false);

    // 读文件
    QTextStream textStream(&file);
    QString cmd;
    cmd = textStream.readLine();

    // 读取并显示棋谱时，不必刷新棋局场景
    if (!(game->command(cmd, false))) {
        // 定义新对话框
        QMessageBox msgBox(QMessageBox::Warning, tr("文件错误"), tr("不是正确的棋谱文件"), QMessageBox::Ok);
        msgBox.exec();
        return;
    }

    while (!textStream.atEnd()) {
        cmd = textStream.readLine();
        game->command(cmd, false);
    }

    // 最后刷新棋局场景
    game->updateScence();
}

void MillGameWindow::on_actionSave_S_triggered()
{
    if (file.isOpen()) {
        file.close();

        // 打开文件,只写方式打开
        if (file.open(QFileDevice::WriteOnly | QFileDevice::Text)) {
            // 写文件
            QTextStream textStream(&file);
            auto *strlist = qobject_cast<QStringListModel *>(ui.listView->model());
            for (const QString &cmd : strlist->stringList())
                textStream << cmd << endl;
            file.flush();
        }

        return;
    }

    on_actionSaveAs_A_triggered();
}

void MillGameWindow::on_actionSaveAs_A_triggered()
{
    QString path = QFileDialog::getSaveFileName(this,
        tr("打开棋谱文件"),
        QDir::currentPath() + tr("棋谱_") + QString::number(QDateTime::currentDateTimeUtc().toTime_t())+ ".txt", "TXT(*.txt)");

    if (path.isEmpty()) {
        return;
    }

    if (file.isOpen()) {
        file.close();
    }

    // 文件对象
    file.setFileName(path);

    // 打开文件,只写方式打开
    if (!(file.open(QFileDevice::WriteOnly | QFileDevice::Text))) {
        return;
    }

    // 写文件
    QTextStream textStream(&file);
    auto *strlist = qobject_cast<QStringListModel*>(ui.listView->model());

    for (const QString &cmd : strlist->stringList()) {
        textStream << cmd << endl;
    }

    file.flush();
}

void MillGameWindow::on_actionEdit_E_toggled(bool arg1)
{
    Q_UNUSED(arg1)
}

void MillGameWindow::on_actionInvert_I_toggled(bool arg1)
{
    // 如果黑白反转
    if (arg1) {
        // 设置玩家1和玩家2的标识图
        ui.actionEngine1_T->setIcon(QIcon(":/icon/Resources/icon/White.png"));
        ui.actionEngine2_R->setIcon(QIcon(":/icon/Resources/icon/Black.png"));
        ui.picLabel1->setPixmap(QPixmap(":/icon/Resources/icon/White.png"));
        ui.picLabel2->setPixmap(QPixmap(":/icon/Resources/icon/Black.png"));
    } else {
        // 设置玩家1和玩家2的标识图
        ui.actionEngine1_T->setIcon(QIcon(":/icon/Resources/icon/Black.png"));
        ui.actionEngine2_R->setIcon(QIcon(":/icon/Resources/icon/White.png"));
        ui.picLabel1->setPixmap(QPixmap(":/icon/Resources/icon/Black.png"));
        ui.picLabel2->setPixmap(QPixmap(":/icon/Resources/icon/White.png"));
    }

    // 让控制器改变棋子颜色
    game->setInvert(arg1);
}

// 前后招的公共槽
void MillGameWindow::on_actionRowChange()
{
    QAbstractItemModel *model = ui.listView->model();
    int rows = model->rowCount();
    int currentRow = ui.listView->currentIndex().row();

    QObject *const obsender = sender();

    if (obsender != nullptr) {
        if (obsender == ui.actionBegin_S) {
            ui.listView->setCurrentIndex(model->index(0, 0));
        } else if (obsender == ui.actionPrevious_B
#ifdef MOBILE_APP_UI
                   || obsender == ui.pushButton_retractMove
#endif /* MOBILE_APP_UI */
                   ) {
            if (currentRow > 0) {
                ui.listView->setCurrentIndex(model->index(currentRow - 1, 0));
            }
        } else if (obsender == ui.actionNext_F) {
            if (currentRow < rows - 1) {
                ui.listView->setCurrentIndex(model->index(currentRow + 1, 0));
            }
        } else if (obsender == ui.actionEnd_E) {
            ui.listView->setCurrentIndex(model->index(rows - 1, 0));
        }

        currentRow = ui.listView->currentIndex().row();
    }

    // 更新动作状态
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

    // 更新局面
    game->phaseChange(currentRow);

#if 0
    // 下面的代码全部取消，改用QTimer的方式实现
    // 更新局面
    bool changed = game->phaseChange(currentRow);
    // 处理自动播放时的动画
    if (changed && game->isAnimation()) {
        // 不使用processEvents函数进行非阻塞延时，频繁调用占用CPU较多
        //QElapsedTimer et;
        //et.start();
        //while (et.elapsed() < waitTime) {
        //    qApp->processEvents(QEventLoop::ExcludeUserInputEvents);
        //}

        int waitTime = game->getDurationTime() + 50;
        // 使用QEventLoop进行非阻塞延时，CPU占用低
        QEventLoop loop;
        QTimer::singleShot(waitTime, &loop, SLOT(quit()));
        loop.exec();
    }
#endif // 0
}

void MillGameWindow::onAutoRunTimeOut(QPrivateSignal signal)
{
    Q_UNUSED(signal)
        int rows = ui.listView->model()->rowCount();
    int currentRow = ui.listView->currentIndex().row();

    if (rows <= 1) {
        ui.actionAutoRun_A->setChecked(false);
        return;
    }

    // 执行“下一招”
    if (currentRow >= rows - 1) {
        ui.actionAutoRun_A->setChecked(false);
        return;
    }

    if (currentRow < rows - 1) {
        ui.listView->setCurrentIndex(ui.listView->model()->index(currentRow + 1, 0));
    }

    currentRow = ui.listView->currentIndex().row();

    // 更新动作状态
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

    // 更新局面
    game->phaseChange(currentRow);
}

// 自动运行
void MillGameWindow::on_actionAutoRun_A_toggled(bool arg1)
{
    if (arg1) {
        // 自动运行前禁用控件
        ui.dockWidget->setEnabled(false);
        ui.gameView->setEnabled(false);

        // 启动定时器
        autoRunTimer.start(game->getDurationTime() * 10 + 50);
    } else {
        // 关闭定时器
        autoRunTimer.stop();

        // 自动运行结束后启用控件
        ui.dockWidget->setEnabled(true);
        ui.gameView->setEnabled(true);
    }
}

void MillGameWindow::on_actionLocal_L_triggered()
{
    ui.actionLocal_L->setChecked(true);
    ui.actionInternet_I->setChecked(false);
}

void MillGameWindow::on_actionInternet_I_triggered()
{
    ui.actionLocal_L->setChecked(false);
    ui.actionInternet_I->setChecked(true);

    game->showNetworkWindow();
}

void MillGameWindow::on_actionEngine_E_triggered()
{
    // 定义新对话框
    auto *dialog = new QDialog(this);
    dialog->setWindowFlags(Qt::Dialog | Qt::WindowCloseButtonHint);
    dialog->setObjectName(QStringLiteral("Dialog"));
    dialog->setWindowTitle(tr("AI设置"));
    dialog->resize(256, 188);
    dialog->setModal(true);

    // 生成各个控件
    auto *vLayout = new QVBoxLayout(dialog);
    auto *groupBox1 = new QGroupBox(dialog);
    auto *groupBox2 = new QGroupBox(dialog);

    auto *hLayout1 = new QHBoxLayout;
    auto *label_depth1 = new QLabel(dialog);
    auto *spinBox_depth1 = new QSpinBox(dialog);
    auto *label_time1 = new QLabel(dialog);
    auto *spinBox_time1 = new QSpinBox(dialog);

    auto *hLayout2 = new QHBoxLayout;
    auto *label_depth2 = new QLabel(dialog);
    auto *spinBox_depth2 = new QSpinBox(dialog);
    auto *label_time2 = new QLabel(dialog);
    auto *spinBox_time2 = new QSpinBox(dialog);

    auto *buttonBox = new QDialogButtonBox(dialog);

    // 设置各个控件数据
    groupBox1->setTitle(tr("玩家1 AI设置"));
    label_depth1->setText(tr("深度"));
    spinBox_depth1->setMinimum(1);
    spinBox_depth1->setMaximum(99);
    label_time1->setText(tr("限时"));
    spinBox_time1->setMinimum(1);
    spinBox_time1->setMaximum(3600);

    groupBox2->setTitle(tr("玩家2 AI设置"));
    label_depth2->setText(tr("深度"));
    spinBox_depth2->setMinimum(1);
    spinBox_depth2->setMaximum(99);
    label_time2->setText(tr("限时"));
    spinBox_time2->setMinimum(1);
    spinBox_time2->setMaximum(3600);

    buttonBox->setStandardButtons(QDialogButtonBox::Cancel | QDialogButtonBox::Ok);
    buttonBox->setCenterButtons(true);
    buttonBox->button(QDialogButtonBox::Ok)->setText(tr("确定"));
    buttonBox->button(QDialogButtonBox::Cancel)->setText(tr("取消"));

    // 布局控件
    vLayout->addWidget(groupBox1);
    vLayout->addWidget(groupBox2);
    vLayout->addWidget(buttonBox);
    groupBox1->setLayout(hLayout1);
    groupBox2->setLayout(hLayout2);
    hLayout1->addWidget(label_depth1);
    hLayout1->addWidget(spinBox_depth1);
    hLayout1->addWidget(label_time1);
    hLayout1->addWidget(spinBox_time1);
    hLayout2->addWidget(label_depth2);
    hLayout2->addWidget(spinBox_depth2);
    hLayout2->addWidget(label_time2);
    hLayout2->addWidget(spinBox_time2);

    // 关联信号和槽函数
    connect(buttonBox, SIGNAL(accepted()), dialog, SLOT(accept()));
    connect(buttonBox, SIGNAL(rejected()), dialog, SLOT(reject()));

    // 目前数据
    depth_t depth1, depth2;
    int time1, time2;
    game->getAiDepthTime(depth1, time1, depth2, time2);
    spinBox_depth1->setValue(depth1);
    spinBox_depth2->setValue(depth2);
    spinBox_time1->setValue(time1);
    spinBox_time2->setValue(time2);

    // 新设数据
    if (dialog->exec() == QDialog::Accepted) {
        depth_t depth1_new, depth2_new;
        int time1_new, time2_new;

        depth1_new = static_cast<depth_t>(spinBox_depth1->value());
        depth2_new = static_cast<depth_t>(spinBox_depth2->value());

        time1_new = spinBox_time1->value();
        time2_new = spinBox_time2->value();

        if (depth1 != depth1_new ||
            depth2 != depth2_new ||
            time1 != time1_new ||
            time2 != time2_new) {
            // 重置AI
            game->setAiDepthTime(depth1_new, time1_new, depth2_new, time2_new);
        }
    }

    // 删除对话框，子控件会一并删除
    dialog->disconnect();
    delete dialog;
}

void MillGameWindow::on_actionViewHelp_V_triggered()
{
    QDesktopServices::openUrl(QUrl("https://github.com/calcitem/MillGame"));
}

void MillGameWindow::on_actionWeb_W_triggered()
{
    QDesktopServices::openUrl(QUrl("https://github.com/calcitem/MillGame/blob/master/Licence.txt"));
}

void MillGameWindow::on_actionAbout_A_triggered()
{
    auto *dialog = new QDialog;

    dialog->setWindowFlags(Qt::Dialog | Qt::WindowCloseButtonHint);
    dialog->setObjectName(QStringLiteral("aboutDialog"));
    dialog->setWindowTitle(tr("三棋"));
    dialog->setModal(true);

    // 生成各个控件
    auto *vLayout = new QVBoxLayout(dialog);
    auto *hLayout = new QHBoxLayout;
    //QLabel *label_icon1 = new QLabel(dialog);
    //QLabel *label_icon2 = new QLabel(dialog);
    auto *date_text = new QLabel(dialog);
    auto *version_text = new QLabel(dialog);
    auto *donate_text = new QLabel(dialog);
    auto *label_text = new QLabel(dialog);
    auto *label_image = new QLabel(dialog);

    // 设置各个控件数据
    //label_icon1->setPixmap(QPixmap(QString::fromUtf8(":/image/resources/image/black_piece.png")));
    //label_icon2->setPixmap(QPixmap(QString::fromUtf8(":/image/resources/image/white_piece.png")));
    //label_icon1->setAlignment(Qt::AlignCenter);
    //label_icon2->setAlignment(Qt::AlignCenter);
    //label_icon1->setFixedSize(32, 32);
    //label_icon2->setFixedSize(32, 32);
    //label_icon1->setScaledContents(true);
    //label_icon2->setScaledContents(true);

    //date_text->setText(__DATE__);
    version_text->setText(tr("Version: ") + versionNumber);
    version_text->setAlignment(Qt::AlignLeft);

    // 布局
    vLayout->addLayout(hLayout);
    //hLayout->addWidget(label_icon1);
    //hLayout->addWidget(label_icon2);
    hLayout->addWidget(version_text);
    hLayout->addWidget(label_text);
    vLayout->addWidget(date_text);
    vLayout->addWidget(donate_text);
    vLayout->addWidget(label_image);

    // 运行对话框
    dialog->exec();

    // 删除对话框
    dialog->disconnect();
    delete dialog;
}

#ifdef MOBILE_APP_UI
void MillGameWindow::mousePressEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        m_move = true;
        m_startPoint = event->globalPos();
        m_windowPoint = this->frameGeometry().topLeft();
    }
}

void MillGameWindow::mouseMoveEvent(QMouseEvent *event)
{
    if (event->buttons() & Qt::LeftButton) {
        QPoint relativePos = event->globalPos() - m_startPoint;
        this->move(m_windowPoint + relativePos );
    }
}

void MillGameWindow::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton) {
        m_move = false;
    }
}
#endif /* MOBILE_APP_UI */
