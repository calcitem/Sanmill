#-------------------------------------------------
#
# Project created by QtCreator 2015-11-03T22:30:34
#
#-------------------------------------------------
QMAKE_LFLAGS_WINDOWS = /SUBSYSTEM:WINDOWS,5.01

QT       += core gui \
            multimedia

greaterThan(QT_MAJOR_VERSION, 4): QT += widgets

TARGET = NineChess
TEMPLATE = app


SOURCES += src\main.cpp \
    src\ninechesswindow.cpp \
    src\pieceitem.cpp \
    src\gamecontroller.cpp \
    src\boarditem.cpp \
    src\gameview.cpp \
    src\ninechess.cpp \
    src\gamescene.cpp

HEADERS  += \
    src\ninechesswindow.h \
    src\pieceitem.h \
    src\gamecontroller.h \
    src\graphicsconst.h \
    src\boarditem.h \
    src\gameview.h \
    src\ninechess.h \
    src\sizehintlistview.h \
    src\gamescene.h

FORMS    += \
    ninechesswindow.ui

RESOURCES += \
    ninechesswindow.qrc

DISTFILES += \
    Readme.txt \
    NineChess.rc \
    History.txt

RC_FILE += NineChess.rc
