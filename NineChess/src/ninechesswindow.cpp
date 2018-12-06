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
#include <QDesktopWidget>
#include "ninechesswindow.h"
#include "gamecontroller.h"
#include "gamescene.h"
#include "graphicsconst.h"

NineChessWindow::NineChessWindow(QWidget *parent)
    : QMainWindow(parent),
    scene(nullptr),
    game(nullptr),
    ruleNo(-1)
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

    // 因功能限制，使部分功能不可用，将来再添加
    ui.actionEngine_E->setDisabled(true);
    ui.actionInternet_I->setDisabled(true);
    ui.actionSetting_O->setDisabled(true);

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

    // 主窗口居中显示
    QRect deskTopRect = qApp->desktop()->availableGeometry();
    int unitw=(deskTopRect.width() - width())/2;
    int unith=(deskTopRect.height() - height())/2;
    this->move(unitw,unith);

    // 游戏初始化
    initialize();
}

NineChessWindow::~NineChessWindow()
{
    if (game) {
        game->disconnect();
        game->deleteLater();
    }
    qDeleteAll(ruleActionList);
}

void NineChessWindow::closeEvent(QCloseEvent *event)
{
    if (file.isOpen())
        file.close();
    //qDebug() << "closed";
    QMainWindow::closeEvent(event);
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
    // 初始化函数，仅执行一次
    if (game)
        return;

    // 开辟一个新的游戏控制器
	game = new GameController(*scene, this);

	// 添加新菜单栏动作
    QMap <int, QStringList> actions = game->getActions();
    for (auto i = actions.constBegin(); i != actions.constEnd(); i++) {
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
	connect(ui.actionGiveUp_G, SIGNAL(triggered()),
		game, SLOT(giveUp()));
	connect(ui.actionEngine1_T, SIGNAL(toggled(bool)),
        game, SLOT(setEngine1(bool)));
    connect(ui.actionEngine2_R, SIGNAL(toggled(bool)),
        game, SLOT(setEngine2(bool)));
    connect(ui.actionSound_S, SIGNAL(toggled(bool)),
        game, SLOT(setSound(bool)));
    connect(ui.actionAnimation_A, SIGNAL(toggled(bool)),
        game, SLOT(setAnimation(bool)));

    // 关联控制器的信号和主窗口控件的槽
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
    ruleActionList.at(ruleNo)->setChecked(true);
    // 重置游戏规则
    game->setRule(ruleNo);
    // 更新规则显示
    ruleInfo();

    // 关联列表视图和字符串列表模型
    ui.listView->setModel(&(game->manualListModel));
    // 因为QListView的rowsInserted在setModel之后才能启动，
    // 第一次需手动初始化选中listView第一项
    //qDebug() << ui.listView->model();
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
    connect(ui.listView, &ManualListView::currentChangedSignal,
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

void NineChessWindow::on_actionLimited_T_triggered()
{
    /* 其实本来可以用设计器做个ui，然后从QDialog派生个自己的对话框
    * 但我不想再派生新类了，又要多出一个类和两个文件
    * 还要写与主窗口的接口，费劲
    * 于是手写QDialog界面
    */
    int gStep = game->getStepsLimit();
    int gTime = game->getTimeLimit();

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
            game->setRule(ruleNo, dStep, dTime);
        }
    }

    // 删除对话框，子控件会一并删除
    dialog->disconnect();
    delete dialog;

    // 更新规则显示
    ruleInfo();
}

void NineChessWindow::actionRules_triggered()
{
    // 取消其它规则的选择
    for(QAction *action: ruleActionList)
        action->setChecked(false);
    // 选择当前规则
    QAction *action = dynamic_cast<QAction *>(sender());
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

void NineChessWindow::on_actionNew_N_triggered()
{
    if (file.isOpen())
        file.close();
    // 取消AI设定
    ui.actionEngine1_T->setChecked(false);
    ui.actionEngine2_R->setChecked(false);
    // 重置游戏规则
    game->gameReset();
}

void NineChessWindow::on_actionOpen_O_triggered()
{
    QString path = QFileDialog::getOpenFileName(this, tr("打开棋谱文件"), QDir::currentPath(), "TXT(*.txt)");
    if (path.isEmpty() == false)
    {
        if (file.isOpen())
            file.close();
        //文件对象
        file.setFileName(path);
        // 不支持1MB以上的文件
        if (file.size() > 0x100000 )
        {
            // 定义新对话框
            QMessageBox msgBox(QMessageBox::Warning, tr("文件过大"), tr("不支持1MB以上文件"), QMessageBox::Ok);
            msgBox.exec();
            return;
        }

        //打开文件,只读方式打开
        bool isok = file.open(QFileDevice::ReadOnly | QFileDevice::Text);
        if (isok)
        {
            // 取消AI设定
            ui.actionEngine1_T->setChecked(false);
            ui.actionEngine2_R->setChecked(false);
            // 读文件
            QTextStream textStream(&file);
            QString cmd;
            cmd = textStream.readLine();
            // 读取并显示棋谱时，不必刷新棋局场景
            if(!(game->command(cmd,false))) {
                // 定义新对话框
                QMessageBox msgBox(QMessageBox::Warning, tr("文件错误"), tr("不是正确的棋谱文件"), QMessageBox::Ok);
                msgBox.exec();
                return;
            }
            while (!textStream.atEnd())
            {
                cmd = textStream.readLine();
                game->command(cmd, false);
			}
            // 最后刷新棋局场景
            game->updateScence();
        }
    }
}

void NineChessWindow::on_actionSave_S_triggered()
{
    if (file.isOpen())
    {
        file.close();
        //打开文件,只写方式打开
        bool isok = file.open(QFileDevice::WriteOnly | QFileDevice::Text);
        if (isok)
        {
            //写文件
            QTextStream textStream(&file);
            QStringListModel *strlist = qobject_cast<QStringListModel *>(ui.listView->model());
            for (QString cmd : strlist->stringList())
                textStream << cmd << endl;
            file.flush();
        }
    }
    else
        on_actionSaveAs_A_triggered();
}

void NineChessWindow::on_actionSaveAs_A_triggered()
{
    QString path = QFileDialog::getSaveFileName(this, tr("打开棋谱文件"), QDir::currentPath()+tr("棋谱.txt"), "TXT(*.txt)");
    if (path.isEmpty() == false)
    {
        if (file.isOpen())
            file.close();
        //文件对象  
        file.setFileName(path);
        //打开文件,只写方式打开
        bool isok = file.open(QFileDevice::WriteOnly | QFileDevice::Text);
        if (isok)
        {
            //写文件
            QTextStream textStream(&file);
            QStringListModel *strlist = qobject_cast<QStringListModel *>(ui.listView->model());
            for (QString cmd : strlist->stringList())
                textStream << cmd << endl;
            file.flush();
        }
    }

}

void NineChessWindow::on_actionEdit_E_toggled(bool arg1)
{
	Q_UNUSED(arg1)
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
    if (obsender != nullptr) {
        if (obsender == ui.actionBegin_S) {
            ui.listView->setCurrentIndex(model->index(0, 0));
        }
        else if (obsender == ui.actionPrevious_B) {
            if (currentRow > 0) {
                ui.listView->setCurrentIndex(model->index(currentRow - 1, 0));
            }
        }
        else if (obsender == ui.actionNext_F) {
            if (currentRow < rows - 1) {
                ui.listView->setCurrentIndex(model->index(currentRow + 1, 0));
            }
        }
        else if (obsender == ui.actionEnd_E) {
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
    }
    else {
        if (currentRow <= 0) {
            ui.actionBegin_S->setEnabled(false);
            ui.actionPrevious_B->setEnabled(false);
            ui.actionNext_F->setEnabled(true);
            ui.actionEnd_E->setEnabled(true);
			ui.actionAutoRun_A->setEnabled(true);
		}
        else if (currentRow >= rows - 1)
        {
            ui.actionBegin_S->setEnabled(true);
            ui.actionPrevious_B->setEnabled(true);
            ui.actionNext_F->setEnabled(false);
            ui.actionEnd_E->setEnabled(false);
			ui.actionAutoRun_A->setEnabled(false);
		}
		else
		{
			ui.actionBegin_S->setEnabled(true);
			ui.actionPrevious_B->setEnabled(true);
			ui.actionNext_F->setEnabled(true);
			ui.actionEnd_E->setEnabled(true);
			ui.actionAutoRun_A->setEnabled(true);
		}
    }

    // 更新局面
    bool changed = game->phaseChange(currentRow);
    // 处理自动播放时的动画
    if (changed && game->isAnimation()) {
        // 不使用processEvents函数进行非阻塞延时，频繁调用占用CPU较多
        //QElapsedTimer et;
        //et.start();
        //while (et.elapsed() < waitTime) {
        //	qApp->processEvents(QEventLoop::ExcludeUserInputEvents);
        //}

        int waitTime = game->getDurationTime() + 50;
        // 使用QEventLoop进行非阻塞延时，CPU占用低
        QEventLoop loop;
        QTimer::singleShot(waitTime, &loop, SLOT(quit()));
        loop.exec();
	}
}

// 自动运行
void NineChessWindow::on_actionAutoRun_A_toggled(bool arg1)
{
	if (!arg1)
		return;
    
    int rows = ui.listView->model()->rowCount();
	int currentRow = ui.listView->currentIndex().row();

	if (rows <= 1)
		return;

	// 自动运行前禁用所有控件
	ui.menuBar->setEnabled(false);
	ui.mainToolBar->setEnabled(false);
	ui.dockWidget->setEnabled(false);
	ui.gameView->setEnabled(false);

	// 反复执行“下一招”
	while (currentRow < rows - 1)
	{
		if (currentRow < rows - 1)
		{
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
		}
		else if (currentRow >= rows - 1)
		{
			ui.actionBegin_S->setEnabled(true);
			ui.actionPrevious_B->setEnabled(true);
			ui.actionNext_F->setEnabled(false);
			ui.actionEnd_E->setEnabled(false);
			ui.actionAutoRun_A->setEnabled(false);
		}
		else
		{
			ui.actionBegin_S->setEnabled(true);
			ui.actionPrevious_B->setEnabled(true);
			ui.actionNext_F->setEnabled(true);
			ui.actionEnd_E->setEnabled(true);
			ui.actionAutoRun_A->setEnabled(true);
		}

		// 更新局面
		game->phaseChange(currentRow);
	}

	// 自动运行结束后启用所有控件
	ui.menuBar->setEnabled(true);
	ui.mainToolBar->setEnabled(true);
	ui.dockWidget->setEnabled(true);
	ui.gameView->setEnabled(true);
	// 取消自动运行按钮的选中状态
	ui.actionAutoRun_A->setChecked(false);
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
    // 空着，有时间再做
}

void NineChessWindow::on_actionViewHelp_V_triggered()
{
	QDesktopServices::openUrl(QUrl("https://blog.csdn.net/liuweilhy/article/details/83832180"));
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
