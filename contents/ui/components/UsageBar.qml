/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami
import "../lib/usage.js" as Usage

// Linear usage bar: green / yellow / red by threshold.
Item {
    id: bar

    property real percent: 0
    property string tint: "positiveTextColor"

    implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.5)
    implicitWidth: Kirigami.Units.gridUnit * 8

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: Kirigami.Theme.backgroundColor
        border.color: Kirigami.Theme.disabledTextColor
        border.width: 1
        opacity: 0.6
    }

    Rectangle {
        id: fill
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 1
        height: Math.max(parent.height - 2, 2)
        width: Math.max(0, Math.min(1, bar.percent / 100) * (parent.width - 2))
        radius: height / 2
        color: Kirigami.Theme[bar.tint] !== undefined
            ? Kirigami.Theme[bar.tint]
            : Kirigami.Theme.positiveTextColor
    }
}
