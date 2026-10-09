/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    A compact circular usage gauge: a full track ring plus a value arc that
    starts at 12 o'clock and sweeps clockwise. The percentage is drawn in the
    center.
*/

import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

Item {
    id: circle

    property real value: 0                 // 0..100
    property int size: Kirigami.Units.iconSizes.medium
    property color tint: Kirigami.Theme.positiveTextColor
    property color trackColor: Kirigami.Theme.disabledTextColor
    property real trackOpacity: 0.25
    property real thickness: Math.max(2, Math.round(circle.size * 0.14))
    property bool showText: true
    property string displayText: Math.round(circle.value) + "%"
    property color textColor: Kirigami.Theme.textColor

    implicitWidth: size
    implicitHeight: size

    readonly property real _r: (Math.min(width, height) - thickness) / 2
    readonly property real _arc: Math.max(0, Math.min(circle.value, 100)) * 3.6
    // Avoid a 360° sweep (some renderers drop it); a tiny gap is imperceptible.
    readonly property real _sweep: circle.value >= 100 ? 359.9 : _arc

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Qt.rgba(circle.trackColor.r, circle.trackColor.g,
                                 circle.trackColor.b, circle.trackOpacity)
            strokeWidth: circle.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: circle.width / 2
                centerY: circle.height / 2
                radiusX: circle._r
                radiusY: circle._r
                startAngle: -90
                sweepAngle: 359.9
            }
        }

        ShapePath {
            strokeColor: circle.tint
            strokeWidth: circle.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: circle.width / 2
                centerY: circle.height / 2
                radiusX: circle._r
                radiusY: circle._r
                startAngle: -90
                sweepAngle: circle._sweep
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: circle.showText
        text: circle.displayText
        color: circle.textColor
        font.bold: true
        font.pixelSize: Math.max(7, Math.round(circle.size * 0.36))
        font.family: Kirigami.Theme.defaultFont.family
    }
}
