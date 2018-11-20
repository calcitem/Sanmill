#-------------------------------------------------
#
# Project created by QtCreator 2015-11-03T22:30:34
#
#-------------------------------------------------
#QMAKE_LFLAGS_WINDOWS = /SUBSYSTEM:WINDOWS,5.01

QT       += core gui \
            multimedia

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

TARGET = NineChess
TEMPLATE = app

CONFIG += C++11 \
    warn_off

SOURCES += \
    src/main.cpp \
    src/boarditem.cpp \
    src/gamecontroller.cpp \
    src/gamescene.cpp \
    src/gameview.cpp \
    src/ninechess.cpp \
    src/ninechesswindow.cpp \
    src/pieceitem.cpp \
    src/aithread.cpp

HEADERS  += \
    src/boarditem.h \
    src/gamecontroller.h \
    src/gamescene.h \
    src/gameview.h \
    src/graphicsconst.h \
    src/ninechess.h \
    src/ninechesswindow.h \
    src/pieceitem.h \
    src/sizehintlistview.h \
    src/aithread.h

FORMS    += \
    ninechesswindow.ui

RESOURCES += \
    ninechesswindow.qrc

DISTFILES += \
    ../Readme.md \
    ../范例棋谱.txt \
    ../History.txt \
    ../Licence.txt \
    NineChess.rc

RC_FILE += NineChess.rc
