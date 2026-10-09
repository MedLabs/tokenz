.pragma library
/*
    SPDX-FileCopyrightText: 2026 Tokenz contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Generic adapter. Every provider is fetched by invoking the Tokenz Python
    engine, which prints one normalized JSON object. This adapter only knows how
    to assemble that command; all provider knowledge lives in the engine.
*/

function shellQuote(value) {
    var s = String(value === undefined || value === null ? "" : value);
    // single-quote, escaping embedded single quotes
    return "'" + s.replace(/'/g, "'\\''") + "'";
}

// spec: { id, displayName, iconName, scriptPath }
function make(spec) {
    return {
        id: spec.id,
        displayName: spec.displayName,
        iconName: spec.iconName || "widget.svg",

        buildCommand: function(config) {
            var c = config || {};
            var parts = ["python3", shellQuote(spec.scriptPath),
                         "--provider", shellQuote(spec.id)];
            if (c.engine && c.engine !== "auto") parts.push("--engine", shellQuote(c.engine));
            if (c.account) parts.push("--account", shellQuote(c.account));
            if (c.source && c.source !== "auto") parts.push("--source", shellQuote(c.source));
            if (c.budget) parts.push("--budget", String(Number(c.budget) || 0));
            parts.push("2>/dev/null");
            return parts.join(" ");
        }
    };
}
