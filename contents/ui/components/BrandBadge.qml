/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import org.kde.kirigami as Kirigami

// A small rounded badge carrying the provider's brand color and short label.
Rectangle {
    id: badge

    property string brandColor: "#888888"
    property string text: "?"
    property int size: Kirigami.Units.iconSizes.smallMedium
    property bool dimmed: false

    implicitWidth: size
    implicitHeight: size
    radius: Math.round(size * 0.28)
    color: brandColor
    opacity: dimmed ? 0.4 : 1.0

    Text {
        anchors.centerIn: parent
        text: badge.text
        color: "white"
        font.bold: true
        font.pixelSize: Math.round(badge.size * 0.42)
        font.family: Kirigami.Theme.defaultFont.family
    }
}
