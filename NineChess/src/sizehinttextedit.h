/* QPlainTextEdit派生类
 * 之所以要派生这个类，重载sizeHint函数
 * 只是为了让停靠栏（父窗口）在初始时不至于过宽难看
 * QDockWidget没有很好的控制初始大小的方法，resize函数没效果
 * 如果不用派生类，使用固定宽度也可以，如下所示
 * this->setFixedWidth(108);
 * 但调节停靠栏宽度后就不好看了
 */

#ifndef SIZEHINTTEXTEDIT
#define SIZEHINTTEXTEDIT

#include <QPlainTextEdit>

class SizeHintTextEdit : public QPlainTextEdit
{
public:
    SizeHintTextEdit(QWidget * parent = 0) {}
    QSize sizeHint() const{
        QSize size = QPlainTextEdit::sizeHint();
        // 缺省宽度设为128，这样就不太宽了
        size.setWidth(128);
        return size;
    }
};

#endif // SIZEHINTTEXTEDIT

