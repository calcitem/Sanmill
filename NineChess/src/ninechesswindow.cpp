#if _MSC_VER >= 1600
#pragma execution_character_set("utf-8")
#endif
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
#include <QLabel>
#include <QHelpEvent>
#include <QToolTip>
#include <QDebug>
#include "ninechesswindow.h"
#include "gamecontroller.h"
#include "gamescene.h"
#include "graphicsconst.h"

NineChessWindow::NineChessWindow(QWidget *parent)
    : QMainWindow(parent),
    scene(NULL),
    game(NULL),
    ruleNo(0)
{
    ui.setupUi(this);
    //去掉标题栏
    //setWindowFlags(Qt::FramelessWindowHint);
    //设置透明(窗体标题栏不透明,背景透明，如果不去掉标题栏，背景就变为黑色)
    //setAttribute(Qt::WA_TranslucentBackground);
    //设置全体透明度系数
    //setWindowOpacity(0.7);

    // 设置场景
    scene = new GameScene(this);
    // 设置场景尺寸大小为棋盘大小的1.08倍
    scene->setSceneRect(-BOARD_SIZE * 0.54, -BOARD_SIZE * 0.54, BOARD_SIZE*1.08, BOARD_SIZE*1.08);

    // 初始化各个控件

    // 关联视图和场景
    ui.gameView->setScene(scene);
    // 视图反走样
    ui.gameView->setRenderHint(QPainter::Antialiasing, true);
    // 视图反锯齿
    ui.gameView->setRenderHint(QPainter::Antialiasing);

    // 因功能限制，使部分功能不可用
    ui.actionViewText_V->setDisabled(true);
    ui.actionAutoRun_A->setDisabled(true);
    ui.actionEngine_E->setDisabled(true);
    ui.actionInternet_I->setDisabled(true);
    ui.actionEngine1_T->setDisabled(true);
    ui.actionEngine2_R->setDisabled(true);
    ui.actionSetting_O->setDisabled(true);
    ui.actionAnimation_A->setDisabled(true);

    // 关联既有动作信号和主窗口槽
    // 视图上下翻转
    connect(ui.actionFlip_F, &QAction::triggered,
        ui.gameView, &GameView::flip);
    // 视图左右镜像
    connect(ui.actionMirror_M, &QAction::triggered,
        ui.gameView, &GameView::mirror);
    // 视图须时针旋转90°
    connect(ui.actionTurnRight_R, &QAction::triggered,
        ui.gameView, &GameView::turnRight);
    // 视图逆时针旋转90°
    connect(ui.actionTurnLeftt_L, &QAction::triggered,
        ui.gameView, &GameView::turnLeft);

    // 初始化游戏规则菜单
    ui.menu_R->installEventFilter(this);

    // 安装一次性定时器，执行初始化
    QTimer::singleShot(0, this, SLOT(initialize()));
}

NineChessWindow::~NineChessWindow()
{
    if (game != NULL)
        delete game;
    qDeleteAll(ruleActionList);
}

bool NineChessWindow::eventFilter(QObject *watched, QEvent *event)
{
    // 重载这个函数只是为了让规则菜单（动态）显示提示
    if (watched == ui.menu_R)
    {
        switch (event->type())
        {
        case QEvent::ToolTip:
            QHelpEvent * he = dynamic_cast <QHelpEvent *> (event);
            QAction *action = ui.menu_R->actionAt(he->pos());
            if (action)
            {
                QToolTip::showText(he->globalPos(), action->toolTip(), this);
                return true;
            }
            break;
        }
    }
    return QMainWindow::eventFilter(watched, event);
}

void NineChessWindow::initialize()
{
    // 如果游戏已经初始化，则退出
    if (game != NULL)
        return;

    // 开辟一个新的游戏控制器
    game = new GameController(*scene, this);

    // 添加新菜单栏动作
    QMap <int, QStringList> actions = game->getActions();
    QMap <int, QStringList>::const_iterator i;
    for (i = actions.constBegin(); i != actions.constEnd(); i++) {
        // qDebug() << i.key() << i.value();
        // QMap的key存放int索引值，value存放规则名称和规则提示
        QAction *ruleAction = new QAction(i.value().at(0), this);
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
    connect(ui.actionEngine1_T, SIGNAL(toggled(bool)),
        game, SLOT(setEngine1(bool)));
    connect(ui.actionEngine2_R, SIGNAL(toggled(bool)),
        game, SLOT(setEngine2(bool)));
    connect(ui.actionSound_S, SIGNAL(toggled(bool)),
        game, SLOT(setSound(bool)));
    connect(ui.actionAnimation_A, SIGNAL(toggled(bool)),
        game, SLOT(setAnimation(bool)));

    /* 关联控制器的信号和主窗口控件的槽
       注意，采用信号和槽而非采用在GameController中直接控制NineChessWindow
       是MVC模型中控制器与视图相分离的方式，有利于程序梳理 */

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
    QLabel *statusBarlabel = new QLabel(this);
    ui.statusBar->addWidget(statusBarlabel);
    // 更新状态栏
    connect(game, SIGNAL(statusBarChanged(QString)),
        statusBarlabel, SLOT(setText(QString)));

    // 默认第2号规则
    ruleNo = 2;
    // 设置选中当前规则的菜单项
    ruleActionList.at(ruleNo)->setChecked(true);
    // 重置游戏规则
    game->setRule(ruleNo);
    // 更新规则显示
    ruleInfo();

    // 关联列表视图和字符串列表模型
    ui.listView->setModel(& game->manualListModel);
    // 因为QListView的rowsInserted在setModel之后才能启动，
    // 第一次需手动初始化选中listView第一项
    qDebug() << ui.listView->model();
    ui.listView->setCurrentIndex(ui.listView->model()->index(0, 0));
    // 初始局面、前一步、后一步、最终局面的槽
    connect(ui.actionBegin_S, &QAction::triggered,
        this, &NineChessWindow::on_actionRowChange);
    connect(ui.actionPrevious_B, &QAction::triggered,
        this, &NineChessWindow::on_actionRowChange);
    connect(ui.actionNext_F, &QAction::triggered,
        this, &NineChessWindow::on_actionRowChange);
    connect(ui.actionEnd_E, &QAction::triggered,
        this, &NineChessWindow::on_actionRowChange);
    // 手动在listView里选择招法后更新的槽
    connect(ui.listView, &SizeHintListView::currentChangedSignal,
        this, &NineChessWindow::on_actionRowChange);
    // 更新四个键的状态
    on_actionRowChange();
}

void NineChessWindow::ruleInfo()
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
    ui.labelInfo->setToolTip(QString(NineChess::RULES[ruleNo].name) + "\n" + 
        NineChess::RULES[ruleNo].info);
    ui.labelRule->setToolTip(ui.labelInfo->toolTip());

    //QString tip_Rule = QString("%1\n%2").arg(tr(NineChess::RULES[ruleNo].name))
    //    .arg(tr(NineChess::RULES[ruleNo].info));
}

void NineChessWindow::actionRules_triggered()
{
    // setChecked函数会发出toggled信号，在这里响应toggled信号会陷入死循环
    // 取消其它规则的选择
    for(QAction *action: ruleActionList)
        action->setChecked(false);
    // 选择当前规则
    QAction *action = dynamic_cast<QAction *>(sender());
    action->setChecked(true);
    ruleNo = action->data().toInt();
    // 重置游戏规则
    game->setRule(ruleNo);
    // 更新规则显示
    ruleInfo();
}


void NineChessWindow::on_actionNew_N_triggered()
{

}

void NineChessWindow::on_actionOpen_O_triggered()
{
    QString path = QFileDialog::getOpenFileName(this, "open", "../", "TXT(*.txt)");
    if (path.isEmpty() == false)
    {
        //文件对象  
        QFile file(path);
        //打开文件,只读方式打开  
        bool isok = file.open(QIODevice::ReadOnly);
        if (isok = true)
        {

            //读文件  
            QByteArray array = file.readAll();  
            qDebug() << array;  

        }
        //文件关闭  
        file.close();
    }
}

void NineChessWindow::on_actionSave_S_triggered()
{

}

void NineChessWindow::on_actionSaveAs_A_triggered()
{

}

void NineChessWindow::on_actionViewText_V_triggered()
{

}

void NineChessWindow::on_actionEdit_E_toggled(bool arg1)
{

}

void NineChessWindow::on_actionInvert_I_toggled(bool arg1)
{
    // 如果黑白反转
    if (arg1)
    {
        // 设置玩家1和玩家2的标识图
        ui.actionEngine1_T->setIcon(QIcon(":/icon/Resources/icon/White.png"));
        ui.actionEngine2_R->setIcon(QIcon(":/icon/Resources/icon/Black.png"));
        ui.picLabel1->setPixmap(QPixmap(":/icon/Resources/icon/White.png"));
        ui.picLabel2->setPixmap(QPixmap(":/icon/Resources/icon/Black.png"));
    }
    else
    {
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
void NineChessWindow::on_actionRowChange()
{
    QAbstractItemModel * model = ui.listView->model();
    int rows = model->rowCount();
    int currentRow = ui.listView->currentIndex().row();

    QObject * const obsender = sender();
    if (obsender != NULL) {
        if (obsender == (QObject *)ui.actionBegin_S) {
            ui.listView->setCurrentIndex(model->index(0, 0));
        }
        else if (obsender == (QObject *)ui.actionPrevious_B) {
            if (currentRow > 0) {
                ui.listView->setCurrentIndex(model->index(currentRow - 1, 0));
            }
        }
        else if (obsender == (QObject *)ui.actionNext_F) {
            if (currentRow < rows - 1) {
                ui.listView->setCurrentIndex(model->index(currentRow + 1, 0));
            }
        }
        else if (obsender == (QObject *)ui.actionEnd_E) {
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
    }
    else {
        if (currentRow <= 0) {
            ui.actionBegin_S->setEnabled(false);
            ui.actionPrevious_B->setEnabled(false);
            ui.actionNext_F->setEnabled(true);
            ui.actionEnd_E->setEnabled(true);
        }
        if (currentRow >= rows - 1)
        {
            ui.actionBegin_S->setEnabled(true);
            ui.actionPrevious_B->setEnabled(true);
            ui.actionNext_F->setEnabled(false);
            ui.actionEnd_E->setEnabled(false);
        }
    }

    // 更新局面
    game->phaseChange(currentRow);
}

void NineChessWindow::on_actionAutoRun_A_toggled(bool arg1)
{

}

void NineChessWindow::on_actionResign_R_triggered()
{

}

void NineChessWindow::on_actionLimited_T_triggered()
{
    /* 其实本来可以用设计器做个ui，然后从QDialog派生个自己的对话框
    * 但我不想再派生新类了，又要多出一个类和两个文件
    * 还要写与主窗口的接口，费劲
    * 于是手写QDialog界面
    */
    int stepLimited = game->getStepsLimit();
    int timeLimited = game->getTimeLimit();

    // 定义新对话框
    QDialog *dialog = new QDialog(this);
    dialog->setWindowFlags(Qt::Dialog | Qt::WindowCloseButtonHint);
    dialog->setObjectName(QStringLiteral("Dialog"));
    dialog->setWindowTitle(tr("步数和时间限制"));
    dialog->resize(256, 108);
    dialog->setModal(true);
    // 生成各个控件
    QFormLayout *formLayout = new QFormLayout(dialog);
    QLabel *label_step = new QLabel(dialog);
    QLabel *label_time = new QLabel(dialog);
    QComboBox *comboBox_step = new QComboBox(dialog);
    QComboBox *comboBox_time = new QComboBox(dialog);
    QDialogButtonBox *buttonBox = new QDialogButtonBox(dialog);
    // 设置各个控件ObjectName，不设也没关系
    /*formLayout->setObjectName(QStringLiteral("formLayout"));
    label_step->setObjectName(QStringLiteral("label_step"));
    label_time->setObjectName(QStringLiteral("label_time"));
    comboBox_step->setObjectName(QStringLiteral("comboBox_step"));
    comboBox_time->setObjectName(QStringLiteral("comboBox_time"));
    buttonBox->setObjectName(QStringLiteral("buttonBox"));*/
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
    comboBox_step->setCurrentIndex(comboBox_step->findData(stepLimited));
    comboBox_time->setCurrentIndex(comboBox_time->findData(timeLimited));
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
        stepLimited = comboBox_step->currentData().toInt();
        timeLimited = comboBox_time->currentData().toInt();
        // 选择当前规则
        QAction *action = dynamic_cast<QAction *>(sender());
        action->setChecked(true);
        int ruleNo = action->data().toInt();
        // 重置游戏规则
        game->setRule(ruleNo, stepLimited, timeLimited);
    }

    // 更新规则显示
    ruleInfo();

    // 删除对话框，子控件会一并删除
    delete dialog;
}

void NineChessWindow::on_actionLocal_L_triggered()
{
    ui.actionLocal_L->setChecked(true);
    ui.actionInternet_I->setChecked(false);
}

void NineChessWindow::on_actionInternet_I_triggered()
{
    ui.actionLocal_L->setChecked(false);
    ui.actionInternet_I->setChecked(true);
}

void NineChessWindow::on_actionEngine_E_triggered()
{

}

void NineChessWindow::on_actionViewHelp_V_triggered()
{

}

void NineChessWindow::on_actionWeb_W_triggered()
{
    QDesktopServices::openUrl(QUrl("http://hy-tech.top"));
}

void NineChessWindow::on_actionAbout_A_triggered()
{
    QMessageBox aboutBox;
    aboutBox.setText(tr("九连棋"));
    aboutBox.setInformativeText(tr("by liuweilhy"));
    aboutBox.setIcon(QMessageBox::Information);
    aboutBox.exec();
}

