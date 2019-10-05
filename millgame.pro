#-------------------------------------------------
#
# Project created by QtCreator 2015-11-03T22:30:34
#
#-------------------------------------------------

QT       += core gui \
            multimedia

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

TARGET = MillGame
TEMPLATE = app

CONFIG += warn_off
CONFIG += console

INCLUDEPATH += include
INCLUDEPATH += src/base
INCLUDEPATH += src/ai
INCLUDEPATH += src/game
INCLUDEPATH += src/ui/qt

SOURCES += \
    src/ai/endgame.cpp \
    src/ai/evaluate.cpp \
    src/ai/movegen.cpp \
    src/ai/tt.cpp \
    src/base/memmgr.cpp \
    src/base/misc.cpp \
    src/base/zobrist.cpp \
    src/game/board.cpp \
    src/game/location.cpp \
    src/game/option.cpp \
    src/game/player.cpp \
    src/game/position.cpp \
    src/game/rule.cpp \
    src/main.cpp \
    src/base/thread.cpp \
    src/ai/search.cpp \
    src/ui/qt/gamewindow.cpp \
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
    src/ai/endgame.h \
    src/ai/evaluate.h \
    src/ai/movegen.h \
    src/ai/tt.h \
    src/base/HashNode.h \
    src/base/debug.h \
    src/base/hashMap.h \
    src/base/memmgr.h \
    src/base/misc.h \
    src/base/sort.h \
    src/base/stack.h \
    src/base/thread.h \
    src/ai/search.h \
    src/base/zobrist.h \
    src/game/board.h \
    src/game/location.h \
    src/game/option.h \
    src/game/player.h \
    src/game/position.h \
    src/game/rule.h \
    src/game/types.h \
    src/ui/qt/client.h \
    src/ui/qt/gamecontroller.h \
    src/ui/qt/gamescene.h \
    src/ui/qt/gameview.h \
    src/ui/qt/gamewindow.h \
    src/ui/qt/graphicsconst.h \
    src/ui/qt/pieceitem.h \
    src/ui/qt/manuallistview.h \
    src/ui/qt/server.h \
    src/ui/qt/boarditem.h

FORMS    += \
    gamewindow.ui

RESOURCES += \
    gamewindow.qrc

DISTFILES += \
    MillGame.rc \
    version.sh

RC_FILE += millgame.rc

# Mobile App support
#DEFINES += MOBILE_APP_UI

# With C++17 support
greaterThan(QT_MAJOR_VERSION, 4) {
CONFIG += c++17
#QMAKE_CXXFLAGS += -O0 -g3 -fsanitize=address -fno-omit-frame-pointer
#QMAKE_LFLAGS += -fsanitize=address
} else {
QMAKE_CXXFLAGS += -std=c++0x
}

*msvc* {
    QMAKE_CXXFLAGS += /MP
}

android {
    QMAKE_LFLAGS += -nostdlib++
}
