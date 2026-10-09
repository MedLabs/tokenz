/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    One runtime instance per enabled agent/account. It asks its adapter for a
    shell command, runs it through the executable DataSource, parses the
    normalized JSON payload and exposes a read-only UsageModel.
*/

import QtQuick
import org.kde.plasma.plasma5support as Plasma5Support
import "lib/usage.js" as Usage

Item {
    id: controller

    // { id, displayName, iconName, buildCommand(config) }
    property var adapter
    // { engine, account, source, budget } (camelCase keys)
    property var config: ({})
    // Optional human label from the agent config (e.g. "work account").
    property string label: ""

    readonly property alias model: d.model

    readonly property int refreshMinutes: Math.max((controller.config && controller.config.refreshInterval) || 5, 1)

    QtObject {
        id: d
        property var model: controller.adapter
            ? Usage.makeModel(controller.adapter.id, {
                  displayName: controller.adapter.displayName,
                  label: controller.label,
                  state: Usage.STATE.loading
              })
            : Usage.makeModel("unknown", { state: Usage.STATE.loading })
    }

    Plasma5Support.DataSource {
        id: runner
        engine: "executable"
        connectedSources: []
        onNewData: function(sourceName, data) {
            var stdout = (data["stdout"] || "").trim()
            var stderr = (data["stderr"] || "").trim()
            disconnectSource(sourceName)
            controller._apply(stdout, stderr)
        }
    }

    function refresh() {
        if (!controller.adapter) return
        var cmd = controller.adapter.buildCommand(controller._adapterConfig())
        if (!cmd) return
        runner.connectSource(cmd)
    }

    function _adapterConfig() {
        var c = {}
        if (controller.config) {
            for (var k in controller.config) {
                if (controller.config.hasOwnProperty(k)) c[k] = controller.config[k]
            }
        }
        if (controller.label) c.label = controller.label
        return c
    }

    function _apply(stdout, stderr) {
        if (!stdout || stdout.length === 0) {
            controller._patch({
                state: Usage.STATE.error,
                error: stderr && stderr.length > 0 ? stderr.split("\n").pop() : "No response from engine"
            })
            return
        }
        var payload
        try {
            payload = JSON.parse(stdout)
        } catch (e) {
            controller._patch({ state: Usage.STATE.error, error: "Invalid engine response" })
            return
        }
        d.model = Usage.fromPayload(controller.adapter ? controller.adapter.id : payload.provider,
                                    payload,
                                    controller.adapter ? controller.adapter.displayName : payload.provider,
                                    controller.adapter ? controller.adapter.iconName : "widget.svg")
    }

    function _patch(patch) {
        var m = d.model || {}
        var copy = {}
        for (var k in m) { if (m.hasOwnProperty(k)) copy[k] = m[k] }
        for (var j in patch) { if (patch.hasOwnProperty(j)) copy[j] = patch[j] }
        d.model = copy
    }

    Timer {
        id: refreshTimer
        interval: controller.refreshMinutes * 60000
        running: true
        repeat: true
        onTriggered: controller.refresh()
    }

    Component.onCompleted: {
        if (controller.adapter) controller.refresh()
    }
}
