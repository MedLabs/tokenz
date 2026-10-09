.pragma library
/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    UI catalog of known AI agents. Keep the `id` values in sync with the
    PROVIDERS dict in contents/code/tokenz_fetch.py (detection lives there).
*/

var CATALOG = [
    { id: "codex", name: "Codex", short: "Cx", color: "#10a37f",
      hint: "OpenAI Codex CLI / ChatGPT coding plan", apikey: false, auth: "codex login" },
    { id: "kimi", name: "Kimi Code", short: "Ki", color: "#7c5cff",
      hint: "Moonshot Kimi Code (kimi CLI)", apikey: false, auth: "kimi" },
    { id: "antigravity", name: "Antigravity", short: "Ag", color: "#4285f4",
      hint: "Google Antigravity (Gemini / Claude / GPT quota)", apikey: false, auth: "agy" },
    { id: "opencode", name: "OpenCode", short: "Oc", color: "#ff6a00",
      hint: "OpenCode local token/cost usage", apikey: false, auth: "opencode auth login" },
    { id: "claude", name: "Claude", short: "Cl", color: "#d97757",
      hint: "Claude Code session & weekly limits", apikey: false, auth: "claude" },
    { id: "gemini", name: "Gemini CLI", short: "Ge", color: "#4285f4",
      hint: "Google Gemini CLI quota", apikey: false, auth: "gemini" },
    { id: "cursor", name: "Cursor", short: "Cu", color: "#6c7bff",
      hint: "Cursor subscription usage", apikey: false, auth: "cursor-agent login" },
    { id: "copilot", name: "GitHub Copilot", short: "Co", color: "#6cc644",
      hint: "GitHub Copilot premium requests", apikey: false, auth: "gh auth login" },
    { id: "moonshot", name: "Moonshot", short: "Ms", color: "#5a4bff",
      hint: "Moonshot Open Platform balance", apikey: true },
    { id: "openrouter", name: "OpenRouter", short: "Or", color: "#6467f2",
      hint: "OpenRouter credit balance", apikey: true },
    { id: "zai", name: "Z.ai", short: "Za", color: "#1f6feb",
      hint: "Z.ai GLM coding plan", apikey: true },
    { id: "minimax", name: "MiniMax", short: "Mm", color: "#e2165b",
      hint: "MiniMax coding plan", apikey: true }
];

var DEFAULT_AGENTS = [
    { id: "codex", enabled: true, engine: "auto", account: "", source: "auto", label: "" },
    { id: "kimi", enabled: true, engine: "auto", account: "", source: "auto", label: "" },
    { id: "antigravity", enabled: true, engine: "auto", account: "", source: "auto", label: "" },
    { id: "opencode", enabled: true, engine: "auto", account: "", source: "auto", label: "" }
];

function list() {
    return CATALOG;
}

function byId(id) {
    for (var i = 0; i < CATALOG.length; i++) {
        if (CATALOG[i].id === id) return CATALOG[i];
    }
    return null;
}

function entry(id) {
    var e = byId(id);
    if (e) return e;
    return { id: id, name: id, short: id.substring(0, 2), color: "#888888",
             hint: "", apikey: false };
}

function name(id) { return entry(id).name; }
function short(id) { return entry(id).short; }
function color(id) { return entry(id).color; }
function isApiKey(id) { return entry(id).apikey === true; }
function auth(id) { var e = entry(id); return e.auth || ""; }
function hint(id) { return entry(id).hint || ""; }

function defaults() {
    var copy = [];
    for (var i = 0; i < DEFAULT_AGENTS.length; i++) {
        var a = DEFAULT_AGENTS[i];
        copy.push({ id: a.id, enabled: a.enabled, engine: a.engine,
                    account: a.account, source: a.source, label: a.label });
    }
    return copy;
}

// Parse the JSON string stored in the applet config; tolerate bad input.
function parse(raw) {
    if (!raw || raw.length === 0) return defaults();
    try {
        var arr = JSON.parse(raw);
        if (!Array.isArray(arr)) return defaults();
        var out = [];
        for (var i = 0; i < arr.length; i++) {
            var a = arr[i] || {};
            if (typeof a.id !== "string" || a.id.length === 0) continue;
            out.push({
                id: a.id,
                enabled: a.enabled !== false,
                engine: a.engine || "auto",
                account: a.account || "",
                source: a.source || "auto",
                label: a.label || ""
            });
        }
        return out;
    } catch (e) {
        return defaults();
    }
}

function serialize(agents) {
    return JSON.stringify(agents);
}

function enabled(agents) {
    var out = [];
    for (var i = 0; i < agents.length; i++) {
        if (agents[i].enabled) out.push(agents[i]);
    }
    return out;
}
