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

CONFIG += warn_off

INCLUDEPATH += include
INCLUDEPATH += src/base
INCLUDEPATH += src/ai
INCLUDEPATH += src/game
INCLUDEPATH += src/ui/qt

SOURCES += \
    src/main.cpp \
    src/base/thread.cpp \
    src/ai/search.cpp \
    src/game/ninechess.cpp \
    src/ui/qt/ninechesswindow.cpp \
    src/ui/qt/pieceitem.cpp \
    src/ui/qt/server.cpp \
    src/ui/qt/boarditem.cpp \
    src/ui/qt/gamecontroller.cpp \
    src/ui/qt/gamescene.cpp \
    src/ui/qt/gameview.cpp \
    src/ui/qt/client.cpp

HEADERS  += \
    include/config.h \
    include/version.h \
    include/version.h.template \
    src/base/HashNode.h \
    src/base/hashMap.h \
    src/base/MemoryPool.h \
    src/base/MemoryPool.tcc \
    src/base/stackalloc.h \
    src/base/thread.h \
    src/ai/search.h \
    src/ai/zobrist.h \
    src/game/ninechess.h \
    src/ui/qt/client.h \
    src/ui/qt/gamecontroller.h \
    src/ui/qt/gamescene.h \
    src/ui/qt/gameview.h \
    src/ui/qt/graphicsconst.h \
    src/ui/qt/ninechesswindow.h \
    src/ui/qt/pieceitem.h \
    src/ui/qt/manuallistview.h \
    src/ui/qt/server.h \
    src/ui/qt/boarditem.h

FORMS    += \
    ninechesswindow.ui

RESOURCES += \
    ninechesswindow.qrc

DISTFILES += \
    NineChess.rc \
    version.sh

RC_FILE += NineChess.rc

# With C++17 support
greaterThan(QT_MAJOR_VERSION, 4) {
CONFIG += c++17
#QMAKE_CXXFLAGS += -O0 -g3 -fsanitize=leak -fno-omit-frame-pointer
#QMAKE_LFLAGS += -fsanitize=leak
} else {
QMAKE_CXXFLAGS += -std=c++0x
}
