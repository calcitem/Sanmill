// This file is part of Sanmill.
// Copyright (C) 2019-2023 The Sanmill developers (see AUTHORS file)
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

#include <QThread>
#include <QtWidgets>
#include <random>

#include <QtCore>

#include "config.h"
#include "misc.h"
#include "option.h"
#include "database.h"

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

DatabaseDialog::~DatabaseDialog()
{

}

void DatabaseDialog::okAction()
{
    path = pathCombo->currentText();
    accept(); // closes dialog and returns QDialog::Accepted
}
