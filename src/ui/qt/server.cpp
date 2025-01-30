// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// server.cpp

#include "config.h"

#ifdef NET_FIGHT_SUPPORT

#include <QtCore>
#include <QtNetwork>
#include <QtWidgets>

#include "server.h"

Server::Server(QWidget *parent, uint16_t port)
    : QDialog(parent)
    , statusLabel(new QLabel)
{
    setWindowFlags(windowFlags() & ~Qt::WindowContextHelpButtonHint);
    statusLabel->setTextInteractionFlags(Qt::TextBrowserInteraction);

    this->port = port;

    QNetworkConfigurationManager manager;

    if (manager.capabilities() &
        QNetworkConfigurationManager::NetworkSessionRequired) {
        // Get saved network configuration
        QSettings settings(QSettings::UserScope, QLatin1String("QtProject"));
        settings.beginGroup(QLatin1String("QtNetwork"));
        const QString id = settings
                               .value(QLatin1String("DefaultNetworkConfiguratio"
                                                    "n"))
                               .toString();
        settings.endGroup();

        // If the saved network configuration is not currently discovered use
        // the system default
        QNetworkConfiguration config = manager.configurationFromIdentifier(id);
        if ((config.state() & QNetworkConfiguration::Discovered) !=
            QNetworkConfiguration::Discovered) {
            config = manager.defaultConfiguration();
        }

        networkSession = new QNetworkSession(config, this);
        connect(networkSession, &QNetworkSession::opened, this,
                &Server::sessionOpened);

        statusLabel->setText(tr("Opening network session."));
        networkSession->open();
    } else {
        sessionOpened();
    }

    auto quitButton = new QPushButton(tr("Close"));
    quitButton->setAutoDefault(false);
    connect(quitButton, &QAbstractButton::clicked, this, &QWidget::close);
    connect(tcpServer, &QTcpServer::newConnection, this, &Server::sendAction);

    auto buttonLayout = new QHBoxLayout;
    buttonLayout->addStretch(1);
    buttonLayout->addWidget(quitButton);
    buttonLayout->addStretch(1);

    QVBoxLayout *mainLayout = nullptr;
    if (QGuiApplication::styleHints()->showIsFullScreen() ||
        QGuiApplication::styleHints()->showIsMaximized()) {
        auto outerVerticalLayout = new QVBoxLayout(this);
        outerVerticalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::Ignored, QSizePolicy::MinimumExpanding));
        auto outerHorizontalLayout = new QHBoxLayout;
        outerHorizontalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::MinimumExpanding, QSizePolicy::Ignored));
        auto groupBox = new QGroupBox(
            QGuiApplication::applicationDisplayName());
        mainLayout = new QVBoxLayout(groupBox);
        outerHorizontalLayout->addWidget(groupBox);
        outerHorizontalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::MinimumExpanding, QSizePolicy::Ignored));
        outerVerticalLayout->addLayout(outerHorizontalLayout);
        outerVerticalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::Ignored, QSizePolicy::MinimumExpanding));
    } else {
        mainLayout = new QVBoxLayout(this);
    }

    mainLayout->addWidget(statusLabel);
    mainLayout->addLayout(buttonLayout);

    setWindowTitle(QGuiApplication::applicationDisplayName());
}

Server::~Server()
{
    while (!actions.empty()) {
        actions.pop();
    }
}

void Server::sessionOpened()
{
    // Save the used configuration
    if (networkSession) {
        QNetworkConfiguration config = networkSession->configuration();
        QString id;

        if (config.type() == QNetworkConfiguration::UserChoice)
            id = networkSession
                     ->sessionProperty(QLatin1String("UserChoiceConfiguration"))
                     .toString();
        else
            id = config.identifier();

        QSettings settings(QSettings::UserScope, QLatin1String("QtProject"));
        settings.beginGroup(QLatin1String("QtNetwork"));
        settings.setValue(QLatin1String("DefaultNetworkConfiguration"), id);
        settings.endGroup();
    }

    tcpServer = new QTcpServer(this);

    if (!tcpServer->listen(QHostAddress::LocalHost, port)) {
        port++;
        if (!tcpServer->listen(QHostAddress::LocalHost, port)) {
#ifndef QT_UI_TEST_MODE
            QMessageBox::critical(this, tr("Server"),
                                  tr("Unable to start the server: %1.")
                                      .arg(tcpServer->errorString()));
#endif // !QT_UI_TEST_MODE

            close();
            return;
        }

#ifdef MESSAGE_BOX_ENABLE
        QMessageBox::information(this, tr("Server"),
                                 tr("server Started %1.").arg(port));
#endif
    } else {
#ifdef MESSAGE_BOX_ENABLE
        QMessageBox::information(this, tr("Server"),
                                 tr("server Started %1.").arg(port));
#endif
    }

    QString ipAddress;
    QList<QHostAddress> ipAddressesList = QNetworkInterface::allAddresses();

    // use the first non-localhost IPv4 address
    for (const auto &ip : ipAddressesList) {
        if (ip != QHostAddress::LocalHost && ip.toIPv4Address()) {
            ipAddress = ip.toString();
            break;
        }
    }

    // if we did not find one, use IPv4 localhost
    if (ipAddress.isEmpty())
        ipAddress = QHostAddress(QHostAddress::LocalHost).toString();

    statusLabel->setText(tr("The server is running on\n\nIP: %1\nport: %2")
                             .arg(ipAddress)
                             .arg(tcpServer->serverPort()));
}

void Server::setAction(const QString &a)
{
    // TODO(calcitem): WAR
    if (actions.size() > 256) {
        while (!actions.empty()) {
            actions.pop();
        }
    }

    actions.push(a);
}

void Server::sendAction()
{
    QByteArray block;
    QDataStream out(&block, QIODevice::WriteOnly);
    out.setVersion(QDataStream::Qt_5_10);

    if (!actions.empty()) {
        action = actions.front();
    }

    out << action;

    QTcpSocket *clientConnection = tcpServer->nextPendingConnection();

    connect(clientConnection, &QAbstractSocket::disconnected, clientConnection,
            &QObject::deleteLater);

    clientConnection->write(block);
    clientConnection->disconnectFromHost();

    if (!actions.empty()) {
        actions.pop();
    }
}

#endif // NET_FIGHT_SUPPORT
