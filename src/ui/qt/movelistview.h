// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2019-2025 The Sanmill developers (see AUTHORS file)

// movelistview.h

#ifndef MOVE_LIST_VIEW_H_INCLUDED
#define MOVE_LIST_VIEW_H_INCLUDED

#include <QListView>
#include <QMouseEvent>

#include "config.h"

/*
 * QListView derived class
 * The reason for deriving this class is to overload the sizeHint function
 * Just to make the docking bar(parent window) not too wide and ugly at the
 * beginning QDockWidget does not have a good way to control the initial size,
 * and the reset function has no effect If you don't use derived classes, you
 * can use a fixed width, as shown below ui.listView->setFixedWidth(108); But it
 * doesn't look good after adjusting the width of the dock
 */

class MoveListView final : public QListView
{
    Q_OBJECT

public:
    explicit MoveListView(QWidget *parent = nullptr) noexcept
        : QListView(parent)
    {
        Q_UNUSED(parent)
    }

    QSize sizeHint() const override
    {
        QSize size = QListView::sizeHint();

        // The default width is 128, so it's not too wide
        size.setWidth(128);

        return size;
    }

signals:
    // A currentChanged signal is required, but not by default.
    // This slot needs to be transformed into a signal
    void currentChangedSignal(const QModelIndex &current,
                              const QModelIndex &previous);

protected slots:
    // Block double-click editing feature
    void mouseDoubleClickEvent(QMouseEvent *mouseEvent) override
    {
        // Block double click events
        mouseEvent->accept();
    }

    void rowsInserted(const QModelIndex &parent, int start, int end) override
    {
        Q_UNUSED(parent)
        Q_UNUSED(start)
        Q_UNUSED(end)
        newEmptyRow = true;
    }

    // Select by judging whether the last element has changed
    void dataChanged(const QModelIndex &topLeft, const QModelIndex &bottomRight,
                     const QVector<int> &roles = QVector<int>()) override
    {
        QListView::dataChanged(topLeft, bottomRight, roles);

        if (model()) {
            const QModelIndex square = model()->index(model()->rowCount() - 1,
                                                      0);
            if (square == bottomRight && newEmptyRow) {
                setCurrentIndex(square);
                scrollToBottom();
                newEmptyRow = false;
            }
        }
    }

    // A currentChanged signal is required, but not by default.
    // This slot needs to be transformed into a signal
    // The activated signal needs to press enter to send out,
    // and the selectedChanged and clicked signals are not appropriate
    void currentChanged(const QModelIndex &current,
                        const QModelIndex &previous) override
    {
        QListView::currentChanged(current, previous);
        emit currentChangedSignal(current, previous);
    }

private:
    // The identity of the new blank line is added
    bool newEmptyRow {false};
};

#endif // MOVE_LIST_VIEW_H_INCLUDED
