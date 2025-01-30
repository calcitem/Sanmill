// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// server.h

#ifndef SERVER_H_INCLUDED
#define SERVER_H_INCLUDED

#include "config.h"

#ifdef NET_FIGHT_SUPPORT

#include <QDialog>
#include <QString>
#include <QVector>
#include <queue>
#include <string>

using std::string;

QT_BEGIN_NAMESPACE
class QLabel;
class QTcpServer;
class QNetworkSession;
QT_END_NAMESPACE

class Server : public QDialog
{
    Q_OBJECT

public:
    explicit Server(QWidget *parent = nullptr, uint16_t port = 33333);
    ~Server();
    void setAction(const QString &a);
    void setPort(uint16_t p) noexcept { port = p; }
    uint16_t getPort() noexcept { return port; }

private slots:
    void sessionOpened();
    void sendAction();

private:
    QLabel *statusLabel = nullptr;
    QTcpServer *tcpServer = nullptr;
    QNetworkSession *networkSession = nullptr;
    uint16_t port;
    std::queue<QString> actions;
    QString action;
};

#endif // NET_FIGHT_SUPPORT

#endif // SERVER_H_INCLUDED
