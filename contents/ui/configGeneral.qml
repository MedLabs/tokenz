/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    property string cfg_language
    property int cfg_refreshInterval
    property string cfg_panelStyle
    property bool cfg_showIcon
    property bool cfg_showLabel
    property string cfg_panelLayout
    property double cfg_backgroundOpacity
    property bool cfg_notifyHigh
    property int cfg_warnThreshold

    readonly property var panelStyles: ["icon", "percent", "text", "circle", "appicon"]

    Kirigami.FormLayout {
        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Language:")
            model: ["system", "en_US"]
            currentIndex: Math.max(0, model.indexOf(cfg_language))
            onActivated: index => { cfg_language = model[index] }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Refresh interval:")
            QQC2.SpinBox {
                from: 1
                to: 999
                value: cfg_refreshInterval
                onValueChanged: cfg_refreshInterval = value
            }
            QQC2.Label { text: i18n("minutes") }
        }

        QQC2.Label {
            visible: cfg_refreshInterval < 5
            text: "⚠ " + i18n("Values under 5 minutes may trigger rate limiting.")
            color: Kirigami.Theme.neutralTextColor
            font.italic: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Panel display")
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Style:")
            model: [i18n("Icon only"), i18n("Icon + percent"), i18n("Percent only"),
                    i18n("Progress circles"), i18n("Tokenz icon only")]
            currentIndex: Math.max(0, panelStyles.indexOf(cfg_panelStyle))
            onActivated: index => { cfg_panelStyle = panelStyles[index] }
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("Provider acronym")
            checked: cfg_showIcon
            onCheckedChanged: cfg_showIcon = checked
        }
        QQC2.CheckBox {
            text: i18n("Provider name")
            checked: cfg_showLabel
            onCheckedChanged: cfg_showLabel = checked
        }

        QQC2.ComboBox {
            Kirigami.FormData.label: i18n("Layout:")
            model: [i18n("Horizontal"), i18n("Vertical")]
            currentIndex: cfg_panelLayout === "vertical" ? 1 : 0
            onActivated: index => { cfg_panelLayout = index === 1 ? "vertical" : "horizontal" }
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Desktop opacity:")
            QQC2.Slider {
                id: opacitySlider
                from: 0.0
                to: 1.0
                stepSize: 0.05
                value: cfg_backgroundOpacity
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                onMoved: cfg_backgroundOpacity = value
            }
            QQC2.Label { text: Math.round(opacitySlider.value * 100) + "%" }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: i18n("Alerts")
        }

        QQC2.CheckBox {
            Kirigami.FormData.label: i18n("Notify:")
            text: i18n("When a usage window crosses the warning threshold")
            checked: cfg_notifyHigh
            onCheckedChanged: cfg_notifyHigh = checked
        }

        RowLayout {
            Kirigami.FormData.label: i18n("Warning threshold:")
            QQC2.SpinBox {
                from: 1
                to: 100
                value: cfg_warnThreshold
                onValueChanged: cfg_warnThreshold = value
            }
            QQC2.Label { text: "%" }
        }
    }
}
