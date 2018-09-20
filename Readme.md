# 九联棋 NineChess

#### 项目介绍：
本游戏根据作者儿时游戏——“九联棋”编制，加上“成三棋”、“打三棋”和“莫里斯九子棋”，共三种规则玩法。  
三种规则略有差异，鼠标放在相应菜单项有会有详细的规则提示。

#### 软件构架：
+ GUI框架：Qt5.11，Qt5大版本下均可通用。
+ 编译器：MSVC2017，MSVC2013及以上版本可用。
+ 源文件编码：所有头文件(*.h)和源文件(*.cpp)采用UTF-8+BOM编码格式。pro文件等采用UTF-8无BOM编码。
+ 本程序采用MVC（模型——视图——控制器）设计规范，对应类如下：  
```
 MVC
 ├─Model
 │  └─NineChess：用标准C++写的棋类模型，处理下棋过程
 ├─View
 │  ├─NineChessWindow：从QMainWindow派生的主窗口类，由Qt自动生成
 │  ├─SizeHintListView：从QListView派生的列表框，用于显示棋谱
 │  ├─GameView：从QGraphicsView派生的视图框，用于显示棋局
 │  ├─GameScene：从QGraphicsScene派生的场景类
 │  ├─BoardItem：从QGraphicsItem派生的棋盘图形类
 │  └─PiecedItem：从QGraphicsItem派生的棋子图形类
 └─Controller
    └─GameController：从QObject派生的控制类
```
+ 这个程序用到了很多Qt特性，其模式后期可以扩展到各种棋类游戏，适合初学者一看。

#### 许可协议
参见Licence.txt

#### 更新历史
参见History.txt

#### 作者声明：
多年前上大学那会儿，笔者就打算做这么个程序出来。然而，条件比较艰苦：  
一来没有老师教，课上只学了C语言和VB，C++是笔者自学的，一个人啃晦涩过时的MFC;  
二来我穷到连个电脑都没有……  三嘛，就是贪玩……  
工作之后有条件了，我又自学了C#和Qt，但都很肤浅，没深入学，只用来做几个小工具而已。  
如果你发现本程序有什么问题或好的建议，请与本人联系。我的邮箱是：liuweilhy@163.com  
>　　　　　　　　　　——by liuweilhy 2015年11月6日
