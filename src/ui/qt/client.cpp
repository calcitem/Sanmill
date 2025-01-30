// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// client.cpp

#include "config.h"

#ifdef NET_FIGHT_SUPPORT

#include <QtNetwork>
#include <QtWidgets>

#include "client.h"
#include "thread.h"

Client::Client(QWidget *parent, uint16_t port)
    : QDialog(parent)
    , hostCombo(new QComboBox)
    , portLineEdit(new QLineEdit)
    , getActionButton(new QPushButton(tr("Connect")))
    , tcpSocket(new QTcpSocket(this))
{
    setWindowFlags(windowFlags() & ~Qt::WindowContextHelpButtonHint);

    hostCombo->setEditable(true);
    hostCombo->addItem(QString("localhost"));
    portLineEdit->setValidator(new QIntValidator(1, 65535, this));

    auto hostLabel = new QLabel(tr("&Server name:"));
    hostLabel->setBuddy(hostCombo);
    auto portLabel = new QLabel(tr("S&erver port:"));
    portLabel->setBuddy(portLineEdit);

    statusLabel = new QLabel(tr("This Client requires that you run the "
                                "Server as well."));

    getActionButton->setDefault(true);
    getActionButton->setEnabled(false);

    auto quitButton = new QPushButton(tr("Close"));

    auto buttonBox = new QDialogButtonBox;
    buttonBox->addButton(getActionButton, QDialogButtonBox::ActionRole);
    buttonBox->addButton(quitButton, QDialogButtonBox::RejectRole);

    in.setDevice(tcpSocket);
    in.setVersion(QDataStream::Qt_4_0);

    connect(hostCombo, &QComboBox::editTextChanged, this,
            &Client::enableGetActionButton);
    connect(portLineEdit, &QLineEdit::textChanged, this,
            &Client::enableGetActionButton);
    connect(getActionButton, &QAbstractButton::clicked, this,
            &Client::requestNewAction);
    connect(quitButton, &QAbstractButton::clicked, this, &QWidget::close);
    connect(tcpSocket, &QIODevice::readyRead, this, &Client::readAction);
    connect(
        tcpSocket,
        QOverload<QAbstractSocket::SocketError>::of(&QAbstractSocket::error),
        this, &Client::displayError);

    QGridLayout *mainLayout = nullptr;
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
        mainLayout = new QGridLayout(groupBox);
        outerHorizontalLayout->addWidget(groupBox);
        outerHorizontalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::MinimumExpanding, QSizePolicy::Ignored));
        outerVerticalLayout->addLayout(outerHorizontalLayout);
        outerVerticalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::Ignored, QSizePolicy::MinimumExpanding));
    } else {
        mainLayout = new QGridLayout(this);
    }

    mainLayout->addWidget(hostLabel, 0, 0);
    mainLayout->addWidget(hostCombo, 0, 1);
    mainLayout->addWidget(portLabel, 1, 0);
    mainLayout->addWidget(portLineEdit, 1, 1);
    mainLayout->addWidget(statusLabel, 2, 0, 1, 2);
    mainLayout->addWidget(buttonBox, 3, 0, 1, 2);

    setWindowTitle(QGuiApplication::applicationDisplayName());
    portLineEdit->setFocus();
    portLineEdit->setText(QString::number(port));

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
                &Client::sessionOpened);

        getActionButton->setEnabled(false);
        statusLabel->setText(tr("Opening network session."));
        networkSession->open();
    }
}

void Client::requestNewAction()
{
    getActionButton->setEnabled(false);
    tcpSocket->abort();
    tcpSocket->connectToHost(hostCombo->currentText(),
                             portLineEdit->text().toUShort());
}

void Client::readAction()
{
    QString nextAction;
    in >> nextAction;

    if (nextAction == currentAction) {
        QTimer::singleShot(0, this, &Client::requestNewAction);
        return;
    }

    currentAction = nextAction;
    statusLabel->setText(currentAction);
    emit command(currentAction.toStdString());
    getActionButton->setEnabled(true);

    QTimer::singleShot(10, this, &Client::requestNewAction);
}

void Client::displayError(QAbstractSocket::SocketError socketError)
{
    switch (socketError) {
    case QAbstractSocket::RemoteHostClosedError:
        break;
    case QAbstractSocket::HostNotFoundError:
        QMessageBox::information(this, tr("Client"),
                                 tr("The host was not found. Please check the "
                                    "host name and port settings."));
        break;
    case QAbstractSocket::ConnectionRefusedError:
        QMessageBox::information(this, tr("Client"),
                                 tr("The connection was refused by the peer. "
                                    "Make sure the server is running, "
                                    "and check that the host name and port "
                                    "settings are correct."));
        break;
    default:
        QMessageBox::information(this, tr("Client"),
                                 tr("The following error occurred: %1.")
                                     .arg(tcpSocket->errorString()));
    }

    getActionButton->setEnabled(true);
}

void Client::enableGetActionButton()
{
    getActionButton->setEnabled((!networkSession || networkSession->isOpen()) &&
                                !hostCombo->currentText().isEmpty() &&
                                !portLineEdit->text().isEmpty());
}

void Client::sessionOpened()
{
    // Save the used configuration
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

    statusLabel->setText(tr("This Client requires that you run the "
                            "Server as well."));

    enableGetActionButton();
}

#endif // NET_FIGHT_SUPPORT
