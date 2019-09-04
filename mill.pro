QT       += core gui \
            multimedia

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

TARGET = mill
TEMPLATE = app

CONFIG += warn_off

INCLUDEPATH += src
INCLUDEPATH += include

SOURCES += \
    src/client.cpp \
    src/main.cpp \
    src/boarditem.cpp \
    src/gamecontroller.cpp \
    src/gamescene.cpp \
    src/gameview.cpp \
    src/ninechess.cpp \
    src/ninechessai_ab.cpp \
    src/ninechesswindow.cpp \
    src/pieceitem.cpp \
    src/aithread.cpp \
    src/server.cpp

HEADERS  += \
    include/config.h \
    include/version.h \
    include/version.h.template \
    src/HashNode.h \
    src/MemoryPool.h \
    src/MemoryPool.tcc \
    src/StackAlloc.h \
    src/boarditem.h \
    src/client.h \
    src/gamecontroller.h \
    src/gamescene.h \
    src/gameview.h \
    src/graphicsconst.h \
    src/hashMap.h \
    src/ninechess.h \
    src/ninechessai_ab.h \
    src/ninechesswindow.h \
    src/pieceitem.h \
    src/manuallistview.h \
    src/aithread.h \
    src/server.h \
    src/zobrist.h

FORMS    += \
    millwindow.ui

RESOURCES += \
    ninechesswindow.qrc

DISTFILES += \
    NineChess.rc \
    ../Readme.md \
    ../Sample.txt \
    ../History.txt \
    ../Licence.txt \
    version.sh

RC_FILE += NineChess.rc

# Mobile App support
DEFINES += MOBILE_APP_UI

# With C++17 support
greaterThan(QT_MAJOR_VERSION, 4) {
CONFIG += c++17
#QMAKE_CXXFLAGS += -O0 -g3 -fsanitize=leak -fno-omit-frame-pointer
#QMAKE_LFLAGS += -fsanitize=leak
} else {
QMAKE_CXXFLAGS += -std=c++0x
}
