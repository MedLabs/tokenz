/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Compact indicator drawn in the panel for one agent/account.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../lib/usage.js" as Usage

RowLayout {
    id: indicator

    property var model
    property string providerId: ""
    property string providerName: ""
    property string brandColor: "#888888"
    property string shortText: "?"
    property bool vertical: false
    property bool showIcon: true
    property bool showLabel: false
    property string panelStyle: "percent"
    property bool hasBrandIcon: false

    spacing: Kirigami.Units.smallSpacing

    readonly property var primary: Usage.primaryWindow(model)
    readonly property bool isOk: !!model && model.state === Usage.STATE.ok
    readonly property bool isPending: !model || model.state === Usage.STATE.loading
    readonly property bool isCircle: indicator.panelStyle === "circle"
    readonly property bool isBrandIcon: indicator.panelStyle === "brandicon"
    readonly property bool showBrandIcon: indicator.isBrandIcon && indicator.hasBrandIcon
    readonly property real percent: primary ? primary.percent : 0
    readonly property color stateColor: {
        if (!isOk) return Kirigami.Theme.disabledTextColor;
        var name = Usage.usageColor(percent);
        return Kirigami.Theme[name] !== undefined ? Kirigami.Theme[name] : Kirigami.Theme.textColor;
    }
    readonly property string stateText: {
        if (indicator.isPending) return "…"
        if (indicator.isOk) return Math.round(indicator.percent) + "%"
        if (indicator.model && indicator.model.state === Usage.STATE.notLoggedIn) return "—"
        return "!"
    }

    ProviderIcon {
        visible: indicator.showBrandIcon
        providerId: indicator.providerId
        size: Kirigami.Units.iconSizes.smallMedium
        opacity: indicator.isOk ? 1.0 : 0.5
        Layout.alignment: Qt.AlignVCenter
    }

    Text {
        visible: indicator.showIcon && !indicator.isCircle
            && indicator.panelStyle !== "text"
            && (!indicator.isBrandIcon || !indicator.hasBrandIcon)
        text: indicator.shortText
        color: indicator.brandColor
        opacity: indicator.isOk ? 1.0 : 0.5
        font.bold: true
        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
        Layout.alignment: Qt.AlignVCenter
    }

    ProgressCircle {
        visible: indicator.isCircle
        Layout.alignment: Qt.AlignVCenter
        size: Math.max(Kirigami.Units.iconSizes.smallMedium, Math.round(Kirigami.Units.gridUnit * 1.6))
        value: indicator.isOk ? indicator.percent : 0
        tint: indicator.isOk ? indicator.brandColor : indicator.stateColor
        trackColor: indicator.stateColor
        textColor: indicator.stateColor
        displayText: indicator.stateText
    }

    Text {
        visible: indicator.showLabel && indicator.providerName.length > 0
        text: indicator.providerName
        color: Kirigami.Theme.textColor
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        Layout.alignment: Qt.AlignVCenter
    }

    Text {
        visible: !indicator.isCircle && indicator.panelStyle !== "icon"
        text: indicator.stateText
        color: indicator.stateColor
        font.bold: true
        font.pixelSize: Kirigami.Theme.defaultFont.pixelSize
        Layout.alignment: Qt.AlignVCenter
    }
}
