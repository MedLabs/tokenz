/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Agents settings page: auto-detect installed agents, add/remove agents,
    pick the data engine, sign in and set API keys.
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasma5support as Plasma5Support
import "lib/providers.js" as Providers
import "components" as Components

KCM.SimpleKCM {
    id: page

    property string cfg_agents
    property bool initialized: false
    property int catalogVersion: 0

    readonly property string pythonPath:
        Qt.resolvedUrl("../code/tokenz_fetch.py").toString().replace("file://", "")
    readonly property string codexbarPath: detection.codexbar || ""

    property string detectionStatus: i18n("Detecting installed agents…")

    ListModel { id: agentModel }

    // ---------------------------------------------------------------- loading
    function load() {
        agentModel.clear()
        var list = Providers.parse(cfg_agents)
        for (var i = 0; i < list.length; i++) {
            appendAgent(list[i])
        }
        detect()
    }

    function appendAgent(a) {
        var meta = Providers.entry(a.id)
        agentModel.append({
            pid: a.id,
            name: meta.name,
            agentEnabled: a.enabled !== false,
            engine: a.engine || "auto",
            account: a.account || "",
            source: a.source || "auto",
            label: a.label || "",
            present: false,
            hasCreds: false,
            bin: "",
            native: meta.native !== false,
            apikey: meta.apikey === true,
            auth: meta.auth || "",
            hint: meta.hint || ""
        })
    }

    function save() {
        var out = []
        for (var i = 0; i < agentModel.count; i++) {
            var a = agentModel.get(i)
            out.push({
                id: a.pid,
                enabled: a.agentEnabled,
                engine: a.engine,
                account: a.account,
                source: a.source,
                label: a.label
            })
        }
        cfg_agents = JSON.stringify(out)
    }

    function hasAgent(id) {
        for (var i = 0; i < agentModel.count; i++) {
            if (agentModel.get(i).pid === id) return true
        }
        return false
    }

    function addAgent(id) {
        if (hasAgent(id)) return
        appendAgent({ id: id, enabled: true, engine: "auto", account: "", source: "auto", label: "" })
        catalogVersion++
        save()
        detect()
    }

    function removeAgent(index) {
        agentModel.remove(index)
        catalogVersion++
        save()
    }

    function availableCatalog() {
        var out = []
        var cat = Providers.list()
        for (var i = 0; i < cat.length; i++) {
            if (!hasAgent(cat[i].id)) out.push(cat[i])
        }
        return out
    }

    // -------------------------------------------------------------- detection
    Plasma5Support.DataSource {
        id: detection
        engine: "executable"
        connectedSources: []
        property string codexbar: ""
        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            disconnectSource(sourceName)
            page.onDetected(stdout)
        }
    }

    function shq(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'"
    }

    function detect() {
        detectionStatus = i18n("Detecting installed agents…")
        detection.connectSource("python3 " + shq(pythonPath) + " --detect 2>/dev/null")
    }

    function onDetected(stdout) {
        if (!stdout || stdout.length === 0) {
            detectionStatus = i18n("Detection failed (is python3 installed?)")
            return
        }
        var payload
        try {
            payload = JSON.parse(stdout)
        } catch (e) {
            detectionStatus = i18n("Detection failed")
            return
        }
        detection.codexbar = payload.codexbar || ""
        var map = {}
        var providers = payload.providers || []
        for (var i = 0; i < providers.length; i++) {
            map[providers[i].id] = providers[i]
        }
        var found = 0
        for (var j = 0; j < agentModel.count; j++) {
            var a = agentModel.get(j)
            var info = map[a.pid]
            var present = !!(info && info.present)
            agentModel.setProperty(j, "present", present)
            agentModel.setProperty(j, "hasCreds", !!(info && info.hasCreds))
            agentModel.setProperty(j, "bin", info ? (info.bin || "") : "")
            if (present) found++
        }
        detectionStatus = detection.codexbar.length > 0
            ? i18n("Using codexbar engine: %1", detection.codexbar)
            : i18n("codexbar not found — native engine used where possible")
    }

    // ------------------------------------------------------------------ auth
    Plasma5Support.DataSource {
        id: authRunner
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) { disconnectSource(sourceName) }
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
        authRunner.connectSource("bash -c " + shq(runner) + " &")
    }

    function signIn(id, auth) {
        var cmd = auth && auth.length > 0 ? auth : id
        if (id === "kimi") {
            cmd = "if command -v kimi >/dev/null 2>&1; then kimi; else \"$HOME/.kimi-code/bin/kimi\"; fi"
        } else if (id === "antigravity") {
            cmd = "if command -v agy >/dev/null 2>&1; then agy; else \"$HOME/.local/bin/agy\"; fi"
        }
        launchInTerminal(cmd)
    }

    function setApiKey(pid, key) {
        if (!key || key.length === 0) return
        var cb = Providers.entry(pid).codexbar || pid
        var cbBin = codexbarPath.length > 0 ? codexbarPath : "codexbar"
        var script = "printf '%s' " + shq(key)
            + " | " + shq(cbBin) + " config set-api-key --provider " + shq(cb) + " --stdin"
        authRunner.connectSource("bash -c " + shq(script))
    }

    // ------------------------------------------------------------------ init
    onCfg_agentsChanged: {
        if (!initialized) {
            initialized = true
            load()
        }
    }
    Component.onCompleted: {
        if (!initialized) {
            initialized = true
            load()
        }
    }

    // ------------------------------------------------------------------- view
    ColumnLayout {
        spacing: Kirigami.Units.mediumSpacing

        RowLayout {
            Layout.fillWidth: true
            QQC2.Label {
                Layout.fillWidth: true
                text: page.detectionStatus
                color: Kirigami.Theme.disabledTextColor
                elide: Text.ElideRight
                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            }
            QQC2.Button {
                text: i18n("Re-detect")
                icon.name: "view-refresh"
                onClicked: page.detect()
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        Repeater {
            model: agentModel

            delegate: QQC2.Frame {
                id: agentFrame
                required property int index
                required property string pid
                required property string name
                required property bool agentEnabled
                required property string engine
                required property string account
                required property string source
                required property string label
                required property bool present
                required property string bin
                required property bool apikey
                required property string auth
                required property string hint

                Layout.fillWidth: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    RowLayout {
                        Layout.fillWidth: true

                        QQC2.CheckBox {
                            checked: agentFrame.agentEnabled
                            onToggled: {
                                agentModel.setProperty(agentFrame.index, "agentEnabled", checked)
                                page.save()
                            }
                        }
                        Components.BrandBadge {
                            brandColor: Providers.color(agentFrame.pid)
                            text: Providers.short(agentFrame.pid)
                            size: Kirigami.Units.iconSizes.smallMedium
                            Layout.alignment: Qt.AlignVCenter
                        }
                        QQC2.Label {
                            text: agentFrame.name
                            font.bold: true
                        }
                        QQC2.Label {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            color: agentFrame.present ? Kirigami.Theme.positiveTextColor
                                                      : Kirigami.Theme.disabledTextColor
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            text: agentFrame.present
                                ? (agentFrame.bin.length > 0 ? agentFrame.bin : i18n("detected"))
                                : i18n("not detected")
                        }
                        QQC2.Button {
                            text: i18n("Sign in")
                            icon.name: "dialog-password"
                            visible: agentFrame.auth.length > 0
                            onClicked: page.signIn(agentFrame.pid, agentFrame.auth)
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            onClicked: page.removeAgent(agentFrame.index)
                        }
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        color: Kirigami.Theme.disabledTextColor
                        font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        text: agentFrame.hint
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 4
                        columnSpacing: Kirigami.Units.largeSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        QQC2.Label { text: i18n("Engine:"); font.pixelSize: Kirigami.Theme.smallFont.pixelSize }
                        QQC2.ComboBox {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 9
                            model: [i18n("Auto"), i18n("codexbar"), i18n("Native")]
                            currentIndex: agentFrame.engine === "codexbar" ? 1 : (agentFrame.engine === "native" ? 2 : 0)
                            onActivated: index => {
                                agentModel.setProperty(agentFrame.index, "engine",
                                    index === 1 ? "codexbar" : index === 2 ? "native" : "auto")
                                page.save()
                            }
                        }

                        QQC2.Label { text: i18n("Source:"); font.pixelSize: Kirigami.Theme.smallFont.pixelSize }
                        QQC2.ComboBox {
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 8
                            enabled: agentFrame.engine !== "native"
                            model: ["auto", "web", "cli", "oauth", "api"]
                            currentIndex: Math.max(0, model.indexOf(agentFrame.source))
                            onActivated: index => {
                                agentModel.setProperty(agentFrame.index, "source", model[index])
                                page.save()
                            }
                        }

                        QQC2.Label { text: i18n("Account:"); font.pixelSize: Kirigami.Theme.smallFont.pixelSize }
                        QQC2.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("codexbar --account label (optional)")
                            text: agentFrame.account
                            onEditingFinished: {
                                agentModel.setProperty(agentFrame.index, "account", text)
                                page.save()
                            }
                        }

                        QQC2.Label { text: i18n("Label:"); font.pixelSize: Kirigami.Theme.smallFont.pixelSize }
                        QQC2.TextField {
                            Layout.fillWidth: true
                            placeholderText: i18n("custom name shown in the panel (optional)")
                            text: agentFrame.label
                            onEditingFinished: {
                                agentModel.setProperty(agentFrame.index, "label", text)
                                page.save()
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: agentFrame.apikey
                        QQC2.TextField {
                            id: apiKeyField
                            Layout.fillWidth: true
                            echoMode: TextInput.Password
                            placeholderText: i18n("API key (stored by codexbar)")
                        }
                        QQC2.Button {
                            text: i18n("Save key")
                            enabled: apiKeyField.text.length > 0 && page.codexbarPath.length > 0
                            onClicked: {
                                page.setApiKey(agentFrame.pid, apiKeyField.text)
                                apiKeyField.text = ""
                            }
                        }
                    }
                }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        RowLayout {
            Layout.fillWidth: true
            QQC2.ComboBox {
                id: addCombo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                model: { page.catalogVersion; return page.availableCatalog() }
                textRole: "name"
                valueRole: "id"
            }
            QQC2.Button {
                text: i18n("Add agent")
                icon.name: "list-add"
                enabled: addCombo.count > 0
                onClicked: {
                    var cat = page.availableCatalog()
                    if (addCombo.currentIndex >= 0 && addCombo.currentIndex < cat.length)
                        page.addAgent(cat[addCombo.currentIndex].id)
                }
            }
            Item { Layout.fillWidth: true }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.disabledTextColor
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            text: i18n("Tip: Tokenz detects agents automatically from their CLI binaries and credential folders (~/.codex, ~/.kimi-code, ~/.gemini, ~/.local/share/opencode). “Auto” uses the codexbar engine when available and falls back to built-in readers for Codex, Kimi, Antigravity and OpenCode.")
        }
    }
}
