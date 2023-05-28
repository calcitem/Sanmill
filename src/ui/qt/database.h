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

#ifndef DATABASE_H_INCLUDED
#define DATABASE_H_INCLUDED

#include <QBuffer>
#include <QComboBox>
#include <QDialog>
#include <QLabel>
#include <QObject>
#include <QSharedMemory>
#include <QString>
#include <string>

#include "config.h"

using std::string;

class DatabaseDialog : public QDialog
{
    Q_OBJECT

public:
    explicit DatabaseDialog(QWidget *parent = nullptr, QString p = ".");
    ~DatabaseDialog() override;

    void setPath(const QString &p) noexcept { path = p; }

    QString getPath() noexcept { return path; }

signals:

public slots:
    void okAction();

private:
    QString path;

    QComboBox *pathCombo = nullptr;
    QPushButton *okButton = nullptr;
};

#endif // DATABASE_H_INCLUDED
