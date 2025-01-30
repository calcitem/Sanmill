// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// database.cpp

#include <QThread>
#include <QtWidgets>
#include <random>

#include <QtCore>

#include "config.h"
#include "database.h"
#include "misc.h"
#include "option.h"

#if defined(GABOR_MALOM_PERFECT_AI)
#include "perfect/perfect_adaptor.h"
#endif

extern QString APP_FILENAME_DEFAULT;

DatabaseDialog::DatabaseDialog(QWidget *parent, QString p)
    : QDialog(parent)
    , pathCombo(new QComboBox)
    , okButton(new QPushButton(tr("OK")))
{
    setWindowFlags(windowFlags() & ~Qt::WindowContextHelpButtonHint);

    this->path = p;

    pathCombo->setEditable(true);

    pathCombo->addItem(".");
    pathCombo->addItem("%USERPROFILE%\\Documents");
    pathCombo->addItem("E:\\Malom\\Malom_Standard_Ultra-strong_1.1.0\\Std_DD_"
                       "89adjusted");
    pathCombo->addItem("D:\\Repo\\malom\\MalomAPI\\bin\\Debug");

    // TODO: Use database path, not only dll
    const auto pathLabel = new QLabel(tr("&Path of MalomAPI.dll:"));
    pathLabel->setBuddy(pathCombo);

    okButton->setDefault(true);
    okButton->setEnabled(true);

    const auto closeButton = new QPushButton(tr("Close"));
    const auto buttonBox = new QDialogButtonBox;
    buttonBox->addButton(okButton, QDialogButtonBox::ActionRole);
    buttonBox->addButton(closeButton, QDialogButtonBox::RejectRole);

    connect(okButton, &QAbstractButton::clicked, this,
            &DatabaseDialog::okAction);
    connect(closeButton, &QAbstractButton::clicked, this, &QWidget::close);

    QGridLayout *mainLayout;
    if (QGuiApplication::styleHints()->showIsFullScreen() ||
        QGuiApplication::styleHints()->showIsMaximized()) {
        const auto outerVerticalLayout = new QVBoxLayout(this);
        outerVerticalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::Ignored, QSizePolicy::MinimumExpanding));

        const auto outerHorizontalLayout = new QHBoxLayout;
        outerHorizontalLayout->addItem(new QSpacerItem(
            0, 0, QSizePolicy::MinimumExpanding, QSizePolicy::Ignored));

        const auto groupBox = new QGroupBox(
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

    mainLayout->addWidget(pathLabel, 0, 0);
    mainLayout->addWidget(pathCombo, 0, 1);
    mainLayout->addWidget(buttonBox, 3, 0, 1, 2);

    setWindowTitle(QGuiApplication::applicationDisplayName());
}

DatabaseDialog::~DatabaseDialog() { }

void DatabaseDialog::okAction()
{
    path = pathCombo->currentText();
    accept(); // closes dialog and returns QDialog::Accepted
}
