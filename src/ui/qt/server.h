// This file is part of Sanmill.
// Copyright (C) 2019-2022 The Sanmill developers (see AUTHORS file)
//
// Sanmill is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Sanmill is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
