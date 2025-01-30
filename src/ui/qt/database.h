// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// database.h

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
