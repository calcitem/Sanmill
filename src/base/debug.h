#ifndef DEBUG_H
#define DEBUG_H

#include <cstdio>
#include <QDebug>

//#define QT_NO_DEBUG_OUTPUT

#define CSTYLE_DEBUG_OUTPUT

#ifdef CSTYLE_DEBUG_OUTPUT
#define loggerDebug printf
#else
#define loggerDebug qDebug
#endif /* CSTYLE_DEBUG_OUTPUT */

#endif /* DEBUG_H */
