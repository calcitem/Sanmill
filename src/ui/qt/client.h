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

#ifndef CLIENT_H_INCLUDED
#define CLIENT_H_INCLUDED

#include "config.h"

#ifdef NET_FIGHT_SUPPORT

#include <QDataStream>
#include <QDialog>
#include <QTcpSocket>
#include <string>

using std::string;

QT_BEGIN_NAMESPACE
class QComboBox;
class QLabel;
class QLineEdit;
class QPushButton;
class QTcpSocket;
class QNetworkSession;
QT_END_NAMESPACE

class Client : public QDialog
{
    Q_OBJECT

public:
    explicit Client(QWidget *parent = nullptr, uint16_t port = 33333);

signals:
    void command(const string &cmd, bool update = true);

private slots:
    void requestNewAction();
    void readAction();
    void displayError(QAbstractSocket::SocketError socketError);
    void enableGetActionButton();
    void sessionOpened();

    void setPort(uint16_t p) noexcept { this->port = p; }

    uint16_t getPort() noexcept { return port; }

private:
    QComboBox *hostCombo = nullptr;
    QLineEdit *portLineEdit = nullptr;
    QLabel *statusLabel = nullptr;
    QPushButton *getActionButton = nullptr;

    QTcpSocket *tcpSocket = nullptr;
    QDataStream in;
    QString currentAction;

    // TODO(calcitem): 'QNetworkSession': was declared deprecated
    QNetworkSession *networkSession = nullptr;

    uint16_t port {};
};

#endif // NET_FIGHT_SUPPORT

#endif // CLIENT_H_INCLUDED
