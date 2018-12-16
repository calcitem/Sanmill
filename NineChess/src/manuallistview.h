/* QListView派生类
 * 之所以要派生这个类，重载sizeHint函数
 * 只是为了让停靠栏（父窗口）在初始时不至于过宽难看
 * QDockWidget没有很好的控制初始大小的方法，resize函数没效果
 * 如果不用派生类，使用固定宽度也可以，如下所示
 * ui.listView->setFixedWidth(108);
 * 但调节停靠栏宽度后就不好看了
 */

#ifndef MANUALLISTVIEW
#define MANUALLISTVIEW

#include <QListView>
#include <QMouseEvent>
#include <QDebug>

class ManualListView : public QListView
{
    Q_OBJECT

public:
    ManualListView(QWidget * parent = nullptr) : QListView (parent), newEmptyRow(false) {
        Q_UNUSED(parent)
    }
    QSize sizeHint() const {
        QSize size = QListView::sizeHint();
        // 缺省宽度设为128，这样就不太宽了
        size.setWidth(128);
        return size;
    }

signals:
    // 需要一个currentChanged信号，但默认没有，需要把这个槽改造成信号
    void currentChangedSignal(const QModelIndex &current, const QModelIndex &previous);

protected slots:
    // 屏蔽掉双击编辑功能
    void mouseDoubleClickEvent(QMouseEvent *mouseEvent) {
        //屏蔽双击事件
        mouseEvent->accept();
    }

    void rowsInserted(const QModelIndex &parent, int start, int end) {
        Q_UNUSED(parent)
        Q_UNUSED(start)
        Q_UNUSED(end)
        newEmptyRow = true;
    }

    /* 本来重载rowsInserted函数用于在插入新行后自动选中最后一行，
    但是，在关联Model的insertRow执行后rowsInserted会被立即执行，
    此时，Model的setData还未被执行，会选中一个空行。
    所以不再采用这种方式，而是在控制模块中指定。
    void rowsInserted(const QModelIndex &parent, int start, int end) {
        // 调用父类函数，为使滚动条更新，否则scrollToBottom不能正确执行。
        QListView::rowsInserted(parent, start, end);
        QModelIndex id = model()->index(end, 0);
        setCurrentIndex(id);
        scrollToBottom();
    }
    */

    // 采用判断最后一个元素是否改变来选中之
    void dataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight,
        const QVector<int> &roles = QVector<int>()) {
        // 调用父类默认函数
        QListView::dataChanged(topLeft, bottomRight, roles);
        // 如果包含model
        if (model()) {
            // 判断
            QModelIndex index = model()->index(model()->rowCount() - 1, 0);
            if (index == bottomRight && newEmptyRow) {
                setCurrentIndex(index);
                QAbstractItemView::scrollToBottom();
                newEmptyRow = false;
            }
        }
    }

    // 需要一个currentChanged信号，但默认没有，需要把这个槽改造成信号
    // activated信号需要按下回车才发出，selectedChanged和clicked信号也不合适
    void currentChanged(const QModelIndex &current, const QModelIndex &previous) {
        QListView::currentChanged(current, previous);
        emit currentChangedSignal(current, previous);
    }

private:
    // 添加了新空行的标识
    bool newEmptyRow;
};

#endif // MANUALLISTVIEW
