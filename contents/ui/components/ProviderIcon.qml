/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Renders a provider's brand glyph. The bundled SVGs use Plasma's
    ColorScheme-Text convention, so KSvg tints them for the current theme while
    leaving intentional accent colors untouched.
*/

import QtQuick
import org.kde.ksvg as KSvg
import org.kde.kirigami as Kirigami
import "../lib/providers.js" as Providers

Item {
    id: root

    // Provider id; matches contents/icons/brands/<providerId>.svg
    property string providerId: ""
    property int size: Kirigami.Units.iconSizes.smallMedium

    implicitWidth: size
    implicitHeight: size

    readonly property string imagePath: root.providerId.length > 0
        ? Qt.resolvedUrl("../../icons/brands/" + root.providerId + ".svg")
        : ""
    // Shrink solid silhouettes so they match the weight of line-art glyphs.
    readonly property real glyphSize: Math.round(root.size * Providers.glyphScale(root.providerId))

    KSvg.SvgItem {
        anchors.centerIn: parent
        visible: root.imagePath.length > 0
        width: root.glyphSize
        height: root.glyphSize
        svg: KSvg.Svg {
            imagePath: root.imagePath
            colorSet: KSvg.Svg.Window
            status: KSvg.Svg.Normal
        }
    }
}
