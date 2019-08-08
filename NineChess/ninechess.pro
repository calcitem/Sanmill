#-------------------------------------------------
#
# Project created by QtCreator 2015-11-03T22:30:34
#
#-------------------------------------------------

QT       += core gui \
            multimedia

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

TARGET = NineChess
TEMPLATE = app

CONFIG += C++11 \
    warn_off

INCLUDEPATH += src

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
    src/HashNode.h \
    src/MemoryPool.h \
    src/MemoryPool.tcc \
    src/StackAlloc.h \
    src/boarditem.h \
    src/client.h \
    src/config.h \
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
    ninechesswindow.ui

RESOURCES += \
    ninechesswindow.qrc

DISTFILES += \
    NineChess.rc \
    ../Readme.md \
    ../Sample.txt \
    ../History.txt \
    ../Licence.txt

RC_FILE += NineChess.rc

# With C++14 support
greaterThan(QT_MAJOR_VERSION, 4) {
CONFIG += c++14
} else {
QMAKE_CXXFLAGS += -std=c++0x
}
