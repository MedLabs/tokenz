.pragma library
/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Shared usage layer: UsageModel factory, JSON normalizer and render helpers.

    The Python engine (contents/code/tokenz_fetch.py) prints a normalized JSON
    object. `fromPayload` turns that into a UsageModel consumed by the QML UI.
*/

var STATE = {
    ok: "ok",
    loading: "loading",
    notLoggedIn: "notLoggedIn",
    tokenError: "tokenError",
    rateLimited: "rateLimited",
    error: "error",
    disabled: "disabled"
};

// Semantic color names resolved to Kirigami.Theme.<name> by QML components.
var COLOR = {
    ok: "positiveTextColor",
    warn: "neutralTextColor",
    danger: "negativeTextColor"
};

function clampPercent(n) {
    var v = Number(n);
    if (isNaN(v)) return 0;
    if (v < 0) return 0;
    if (v > 100) return 100;
    return v;
}

// Color band: <50 green, <80 yellow, >=80 red.
function usageColor(percent) {
    var p = Number(percent);
    if (isNaN(p)) p = 0;
    if (p < 50) return COLOR.ok;
    if (p < 80) return COLOR.warn;
    return COLOR.danger;
}

function makeWindow(key, label, percent, resetAtIso, detail) {
    return {
        key: key,
        label: label,
        percent: clampPercent(percent),
        resetAt: resetAtIso || null,
        resetLabel: "",
        detail: detail || ""
    };
}

function makeModelUsage(label, percent) {
    return { label: label, percent: clampPercent(percent) };
}

function makeModel(id, fields) {
    var m = {
        id: id,
        displayName: "",
        plan: "",
        account: "",
        state: STATE.loading,
        source: "",
        engine: "",
        windows: [],
        models: [],
        error: "",
        lastSuccess: 0,
        isStale: false
    };
    if (fields) {
        for (var k in fields) {
            if (fields.hasOwnProperty(k)) m[k] = fields[k];
        }
    }
    return m;
}

// normalized JSON payload (already parsed) -> UsageModel
function fromPayload(id, payload, displayName, iconName) {
    var p = payload || {};
    var state = p.state || (p.ok ? STATE.ok : STATE.error);
    var windows = [];
    var rawWindows = p.windows || [];
    for (var i = 0; i < rawWindows.length; i++) {
        var w = rawWindows[i] || {};
        windows.push(makeWindow(w.key, w.label, w.percent, w.resetAt, w.detail));
    }
    var models = [];
    var rawModels = p.models || [];
    for (var j = 0; j < rawModels.length; j++) {
        var mm = rawModels[j] || {};
        models.push(makeModelUsage(mm.label, mm.percent));
    }
    return makeModel(id, {
        displayName: displayName || p.provider || id,
        plan: p.plan || "",
        account: p.account || "",
        state: state,
        source: p.source || "",
        engine: p.engine || "",
        windows: windows,
        models: models,
        error: p.error || "",
        lastSuccess: state === STATE.ok ? Date.now() : 0
    });
}

// The primary window used for the compact panel indicator.
function primaryWindow(model) {
    if (!model || !model.windows || model.windows.length === 0) return null;
    return model.windows[0];
}

function hasData(model) {
    if (!model) return false;
    return model.state === STATE.ok
        || model.state === STATE.rateLimited
        || model.state === STATE.tokenError;
}

// formatRemaining(resetAtIso, nowMs?) -> "2d 3h" / "3h 12m" / "12m" / ""
function formatRemaining(resetAtIso, nowMs) {
    if (!resetAtIso) return "";
    var reset = new Date(resetAtIso).getTime();
    if (isNaN(reset)) return "";
    var now = (typeof nowMs === "number") ? nowMs : Date.now();
    var diff = reset - now;
    if (diff <= 0) return "";
    var hours = Math.floor(diff / (1000 * 60 * 60));
    var minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    if (hours > 24) {
        var days = Math.floor(hours / 24);
        hours = hours % 24;
        return days + "d " + hours + "h";
    } else if (hours > 0) {
        return hours + "h " + minutes + "m";
    }
    return minutes + "m";
}
