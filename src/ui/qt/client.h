// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// client.h

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
