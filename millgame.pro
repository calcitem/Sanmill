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
INCLUDEPATH += src
INCLUDEPATH += src/test
INCLUDEPATH += src/ui/qt

SOURCES += \
    src/endgame.cpp \
    src/evaluate.cpp \
    src/movegen.cpp \
    src/movepick.cpp \
    src/thread.cpp \
    src/tt.cpp \
    src/misc.cpp \
    src/uci.cpp \
    src/ucioption.cpp \
    src/bitboard.cpp \
    src/option.cpp \
    src/position.cpp \
    src/rule.cpp \
    src/main.cpp \
    src/search.cpp \
    src/mills.cpp \
    src/test/test.cpp \
    src/ui/qt/gamewindow.cpp \
    src/ui/qt/pieceitem.cpp \
    src/ui/qt/server.cpp \
    src/ui/qt/boarditem.cpp \
    src/ui/qt/game.cpp \
    src/ui/qt/gamescene.cpp \
    src/ui/qt/gameview.cpp \
    src/ui/qt/client.cpp \
    src/ui/qt/winmain.cpp \

HEADERS  += \
    include/config.h \
    include/version.h \
    include/version.h.template \
    src/endgame.h \
    src/evaluate.h \
    src/movegen.h \
    src/movepick.h \
    src/thread.h \
    src/tt.h \
    src/hashnode.h \
    src/debug.h \
    src/hashMap.h \
    src/misc.h \
    src/stack.h \
    src/stopwatch.h \
    src/search.h \
    src/uci.h \
    src/bitboard.h \
    src/option.h \
    src/position.h \
    src/rule.h \
    src/types.h \
    src/mills.h \
    src/test/test.h \
    src/ui/qt/client.h \
    src/ui/qt/game.h \
    src/ui/qt/gamescene.h \
    src/ui/qt/gameview.h \
    src/ui/qt/gamewindow.h \
    src/ui/qt/graphicsconst.h \
    src/ui/qt/pieceitem.h \
    src/ui/qt/movelistview.h \
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

TRANSLATIONS += millgame-qt_zh_CN.ts

DEFINES += DISABLE_PERFECT_AI

# Mobile App support
#DEFINES += QT_MOBILE_APP_UI

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
