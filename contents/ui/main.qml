/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Tokenz - AI agent usage limits in your panel.

    Root PlasmoidItem. It parses the configured agent list, instantiates one
    ProviderController per enabled agent/account and renders a compact panel
    indicator plus a detailed popup.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.plasma.core as PlasmaCore
import "lib/usage.js" as Usage
import "lib/providers.js" as Providers
import "adapters/GenericAdapter.js" as GenericAdapter
import "components"

PlasmoidItem {
    id: root

    // Absolute path to the data engine (no file:// prefix).
    readonly property string scriptPath:
        Qt.resolvedUrl("../code/tokenz_fetch.py").toString().replace("file://", "")

    readonly property var agents: Providers.parse(Plasmoid.configuration.agents)
    readonly property var enabledAgents: Providers.enabled(agents)

    // Bumped whenever any controller's model changes; used to refresh bindings
    // that read controller models through helper functions.
    property int modelVersion: 0

    readonly property bool isVerticalLayout: Plasmoid.configuration.panelLayout === "vertical"
    readonly property bool showAppIcon: Plasmoid.configuration.panelStyle === "appicon"

    function makeAdapter(agent) {
        var meta = Providers.entry(agent.id)
        return GenericAdapter.make({
            id: agent.id,
            displayName: meta.name,
            iconName: "widget.svg",
            scriptPath: root.scriptPath
        })
    }

    function controllerAt(index) {
        return controllers.itemAt(index)
    }

    function refreshAll() {
        for (var i = 0; i < controllers.count; i++) {
            var item = controllers.itemAt(i)
            if (item) item.refresh()
        }
    }

    readonly property string lastUpdate: {
        var _ = root.modelVersion
        var newest = 0
        for (var i = 0; i < controllers.count; i++) {
            var item = controllers.itemAt(i)
            if (item && item.model && item.model.lastSuccess > newest) newest = item.model.lastSuccess
        }
        return newest > 0 ? Qt.formatTime(new Date(newest), "hh:mm:ss") : ""
    }

    readonly property int okCount: {
        var _ = root.modelVersion
        var n = 0
        for (var i = 0; i < controllers.count; i++) {
            var item = controllers.itemAt(i)
            if (item && item.model && item.model.state === Usage.STATE.ok) n++
        }
        return n
    }

    // ---- headless controllers (one per enabled agent/account) ----
    Repeater {
        id: controllers
        model: root.enabledAgents

        delegate: ProviderController {
            required property var modelData
            required property int index

            adapter: root.makeAdapter(modelData)
            label: modelData.label || ""
            config: ({
                refreshInterval: Plasmoid.configuration.refreshInterval || 5,
                engine: modelData.engine || "auto",
                account: modelData.account || "",
                source: modelData.source || "auto",
                budget: modelData.budget || 0
            })
            onModelChanged: root.modelVersion++
        }
    }

    // ---- launching agent sign-in in a terminal ----
    Plasma5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }

    function shq(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function loginPath() {
        return "$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.opencode/bin:"
            + "$HOME/.bun/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
    }

    function launchInTerminal(command) {
        var inner = "export PATH=\"" + loginPath() + "\"; cd $HOME && " + command
            + "; echo; echo 'Press Enter to close'; read _"
        var runner = "if command -v konsole >/dev/null; then konsole --hold -e bash -c " + shq(inner)
            + "; elif command -v gnome-terminal >/dev/null; then gnome-terminal -- bash -c " + shq(inner)
            + "; elif command -v xfce4-terminal >/dev/null; then xfce4-terminal --hold -e bash -c " + shq(inner)
            + "; elif command -v xterm >/dev/null; then xterm -hold -e bash -c " + shq(inner) + "; fi"
        launcher.connectSource("bash -c " + shq(runner) + " &")
    }

    function launchAuth(providerId) {
        var cmd = ""
        if (providerId === "kimi") {
            cmd = "if command -v kimi >/dev/null 2>&1; then kimi; else \"$HOME/.kimi-code/bin/kimi\"; fi"
        } else if (providerId === "antigravity") {
            cmd = "if command -v agy >/dev/null 2>&1; then agy; else \"$HOME/.local/bin/agy\"; fi"
        } else {
            cmd = Providers.auth(providerId)
        }
        if (!cmd || cmd.length === 0) {
            cmd = providerId
        }
        root.launchInTerminal(cmd)
    }

    // ============ COMPACT (panel) ============
    compactRepresentation: Item {
        Layout.minimumWidth: root.showAppIcon
            ? Kirigami.Units.iconSizes.smallMedium + Kirigami.Units.largeSpacing * 2
            : content.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.minimumHeight: root.showAppIcon
            ? Kirigami.Units.iconSizes.medium
            : (root.isVerticalLayout
                ? content.implicitHeight + Kirigami.Units.largeSpacing * 2
                : Kirigami.Units.iconSizes.medium)

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }

        Kirigami.Icon {
            visible: root.showAppIcon
            anchors.centerIn: parent
            source: "tokenz"
            fallback: "tokenz"
            implicitWidth: Kirigami.Units.iconSizes.smallMedium
            implicitHeight: Kirigami.Units.iconSizes.smallMedium
        }

        GridLayout {
            id: content
            visible: !root.showAppIcon
            anchors.centerIn: parent
            columns: root.isVerticalLayout ? 1 : -1
            rows: root.isVerticalLayout ? -1 : 1
            flow: root.isVerticalLayout ? GridLayout.TopToBottom : GridLayout.LeftToRight
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            BrandBadge {
                visible: root.enabledAgents.length === 0
                brandColor: "#3daee9"
                text: "Tz"
                size: Kirigami.Units.iconSizes.smallMedium
                opacity: 0.7
            }

            Repeater {
                model: root.enabledAgents

                delegate: ProviderIndicator {
                    required property var modelData
                    required property int index

                    property var ctrl: { root.modelVersion; return root.controllerAt(index) }

                    model: { root.modelVersion; return ctrl ? ctrl.model : null }
                    providerId: modelData.id
                    providerName: Providers.name(modelData.id)
                    brandColor: Providers.color(modelData.id)
                    shortText: Providers.short(modelData.id)
                    vertical: root.isVerticalLayout
                    showIcon: Plasmoid.configuration.showIcon !== false
                    showLabel: Plasmoid.configuration.showLabel === true
                    panelStyle: Plasmoid.configuration.panelStyle || "percent"
                    hasBrandIcon: Providers.hasIcon(modelData.id)
                }
            }
        }
    }

    // ============ FULL (popup) ============
    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 8
        Layout.preferredWidth: Kirigami.Units.gridUnit * 15
        Layout.maximumWidth: Kirigami.Units.gridUnit * 16
        implicitWidth: Kirigami.Units.gridUnit * 15
        implicitHeight: popupColumn.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.preferredHeight: Math.min(implicitHeight, Kirigami.Units.gridUnit * 46)

        ColumnLayout {
            id: popupColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.mediumSpacing

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: i18n("Tokenz")
                    font.bold: true
                    font.pixelSize: Math.round(Kirigami.Theme.defaultFont.pixelSize * 1.3)
                    color: Kirigami.Theme.textColor
                    Layout.fillWidth: true
                }
                PlasmaComponents.ToolButton {
                    icon.name: "configure"
                    text: i18n("Settings")
                    onClicked: Plasmoid.internalAction("configure").trigger()
                }
            }

            Kirigami.Separator { Layout.fillWidth: true }

            PlasmaComponents.Label {
                visible: root.enabledAgents.length === 0
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.disabledTextColor
                font.italic: true
                text: i18n("No AI agents configured. Open settings to detect and add agents.")
            }

            Repeater {
                model: root.enabledAgents

                delegate: ColumnLayout {
                    id: sectionCell
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.mediumSpacing

                    property var ctrl: { root.modelVersion; return root.controllerAt(index) }

                    ProviderSection {
                        Layout.fillWidth: true
                        model: { root.modelVersion; return sectionCell.ctrl ? sectionCell.ctrl.model : null }
                        providerId: sectionCell.modelData.id
                        providerName: Providers.name(sectionCell.modelData.id)
                        brandColor: Providers.color(sectionCell.modelData.id)
                        shortText: Providers.short(sectionCell.modelData.id)
                        accountLabel: sectionCell.modelData.label || sectionCell.modelData.account || ""
                        hasBrandIcon: Providers.hasIcon(sectionCell.modelData.id)
                        trFn: function(t) { return i18n(t) }
                        onSignInRequested: root.launchAuth(sectionCell.modelData.id)
                    }

                    Kirigami.Separator {
                        Layout.fillWidth: true
                        visible: sectionCell.index < root.enabledAgents.length - 1
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Kirigami.Separator { Layout.fillWidth: true }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    color: Kirigami.Theme.disabledTextColor
                    text: root.lastUpdate.length > 0
                        ? i18n("Updated: %1", root.lastUpdate)
                        : i18n("Refreshing…")
                }
                PlasmaComponents.Button {
                    icon.name: "view-refresh"
                    text: i18n("Refresh")
                    onClicked: root.refreshAll()
                }
            }
        }
    }

    // ---- background / panel ----
    readonly property bool isOnPanel: Plasmoid.location === PlasmaCore.Types.TopEdge
        || Plasmoid.location === PlasmaCore.Types.BottomEdge
        || Plasmoid.location === PlasmaCore.Types.LeftEdge
        || Plasmoid.location === PlasmaCore.Types.RightEdge

    Plasmoid.backgroundHints: isOnPanel ? PlasmaCore.Types.DefaultBackground : PlasmaCore.Types.NoBackground

    Rectangle {
        visible: !root.isOnPanel
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        opacity: Plasmoid.configuration.backgroundOpacity
        radius: Kirigami.Units.cornerRadius
    }

    Plasmoid.icon: "tokenz"
    toolTipMainText: i18n("Tokenz")
    toolTipSubText: {
        var _ = root.modelVersion
        var parts = []
        for (var i = 0; i < controllers.count; i++) {
            var item = controllers.itemAt(i)
            if (!item || !item.model) continue
            var m = item.model
            if (m.state !== Usage.STATE.ok) continue
            var primary = Usage.primaryWindow(m)
            if (!primary) continue
            parts.push((m.label || m.displayName) + " " + Math.round(primary.percent) + "%")
        }
        return parts.length > 0 ? parts.join(" · ") : i18n("No usage data")
    }

    // ---- first-run helpers ----
    Plasma5Support.DataSource {
        id: iconInstaller
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
    }

    Component.onCompleted: {
        var iconSource = Qt.resolvedUrl("../icons/widget.svg").toString().replace("file://", "")
        iconInstaller.connectSource("bash -c 'ICON_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps && mkdir -p $ICON_DIR && cp \"" + iconSource + "\" $ICON_DIR/tokenz.svg 2>/dev/null'")
    }
}
