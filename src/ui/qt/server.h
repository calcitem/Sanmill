/*
  Sanmill, a mill game playing engine derived from NineChess 1.5
  Copyright (C) 2015-2018 liuweilhy (NineChess author)
  Copyright (C) 2019-2020 Calcitem <calcitem@outlook.com>

  Sanmill is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Sanmill is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef SERVER_H
#define SERVER_H

#include <QDialog>
#include <QString>
#include <QVector>
#include <queue>

#include "config.h"

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
    void setAction(const QString &action);
    void setPort(uint16_t p)
    {
        port = p;
    }
    uint16_t getPort()
    {
        return port;
    }

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

#endif // SERVER_H
