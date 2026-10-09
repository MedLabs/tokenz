/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Popup section: full usage detail for one agent/account.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import "../lib/usage.js" as Usage

ColumnLayout {
    id: section

    property var model
    property string providerId: ""
    property string providerName: ""
    property string brandColor: "#888888"
    property string shortText: "?"
    property string accountLabel: ""
    property bool hasBrandIcon: false
    property var trFn: function(t) { return t }

    signal signInRequested()

    spacing: Kirigami.Units.smallSpacing

    function t(text) { return section.trFn ? section.trFn(text) : text }

    readonly property bool isOk: !!model && model.state === Usage.STATE.ok
    readonly property bool needsAuth: !!model && (model.state === Usage.STATE.notLoggedIn
        || model.state === Usage.STATE.tokenError || model.state === Usage.STATE.disabled)
    readonly property bool isError: !!model && (model.state === Usage.STATE.error
        || model.state === Usage.STATE.rateLimited)
    readonly property bool isLoading: !model || model.state === Usage.STATE.loading

    // ---- header ----
    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        ProviderIcon {
            visible: section.hasBrandIcon
            providerId: section.providerId
            size: Kirigami.Units.iconSizes.smallMedium
            Layout.alignment: Qt.AlignVCenter
        }

        BrandBadge {
            visible: !section.hasBrandIcon
            brandColor: section.brandColor
            text: section.shortText
            dimmed: !section.isOk
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
                text: section.providerName + (section.accountLabel.length > 0 ? " · " + section.accountLabel : "")
                color: Kirigami.Theme.textColor
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
            Text {
                visible: !!section.model && (section.model.plan.length > 0 || section.model.account.length > 0)
                text: {
                    var parts = []
                    if (section.model && section.model.plan) parts.push(section.model.plan)
                    if (section.model && section.model.account) parts.push(section.model.account)
                    return parts.join(" · ")
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                elide: Text.ElideRight
                Layout.fillWidth: true
            }
        }
    }

    // ---- loading ----
    PlasmaComponents.Label {
        visible: section.isLoading
        text: section.t("Loading…")
        color: Kirigami.Theme.disabledTextColor
        font.italic: true
    }

    // ---- auth / error ----
    RowLayout {
        visible: section.needsAuth || section.isError
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        PlasmaComponents.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            color: section.needsAuth ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.negativeTextColor
            text: (section.model && section.model.error) ? section.model.error : section.t("Not available")
        }
        PlasmaComponents.Button {
            visible: section.needsAuth
            text: section.t("Sign in")
            icon.name: "dialog-password"
            onClicked: section.signInRequested()
        }
    }

    // ---- windows ----
    Repeater {
        model: section.isOk ? (section.model.windows || []) : []
        delegate: ColumnLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: modelData.label
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    text: modelData.detail && modelData.detail.length > 0
                        ? modelData.detail
                        : Math.round(modelData.percent) + "%"
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: {
                        var n = Usage.usageColor(modelData.percent)
                        return Kirigami.Theme[n] !== undefined ? Kirigami.Theme[n] : Kirigami.Theme.textColor
                    }
                    font.bold: true
                }
            }

            UsageBar {
                Layout.fillWidth: true
                visible: !(modelData.detail && modelData.detail.length > 0 && modelData.percent === 0)
                percent: modelData.percent
                tint: Usage.usageColor(modelData.percent)
            }

            PlasmaComponents.Label {
                visible: text.length > 0
                Layout.fillWidth: true
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: Kirigami.Theme.disabledTextColor
                text: {
                    var remaining = Usage.formatRemaining(modelData.resetAt)
                    return remaining.length > 0
                        ? section.t("Resets in") + " " + remaining
                        : ""
                }
            }
        }
    }

    // ---- per-model usage (e.g. Claude Sonnet/Opus) ----
    Repeater {
        model: section.isOk ? (section.model.models || []) : []
        delegate: RowLayout {
            required property var modelData
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: modelData.label
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
            PlasmaComponents.Label {
                text: Math.round(modelData.percent) + "%"
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                color: {
                    var n = Usage.usageColor(modelData.percent)
                    return Kirigami.Theme[n] !== undefined ? Kirigami.Theme[n] : Kirigami.Theme.textColor
                }
            }
        }
    }

    // ---- footer ----
    PlasmaComponents.Label {
        visible: section.isOk && !!section.model && section.model.engine.length > 0
        Layout.fillWidth: true
        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
        color: Kirigami.Theme.disabledTextColor
        opacity: 0.7
        text: section.model ? (section.t("via") + " " + section.model.engine
            + (section.model.source ? " · " + section.model.source : "")) : ""
    }
}
