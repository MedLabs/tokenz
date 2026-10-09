# Tokenz

Track your **AI coding-agent usage limits** right in the KDE Plasma panel.

Tokenz shows how much of each agent's rate window you have consumed
(session / daily / weekly / monthly), when it resets, and warns you before
you hit the wall. It supports multiple accounts per agent and auto-detects
the agents installed on your machine.

```
Codex 20%  ·  Antigravity 64%  ·  OpenCode 12%
```

## Supported agents

| Agent | Detection | Data source |
|-------|-----------|-------------|
| **Codex** (ChatGPT coding plan) | `~/.codex/auth.json`, `codex` CLI | codexbar (oauth) / native |
| **Kimi Code** | `~/.kimi-code/credentials`, `kimi` CLI | native / codexbar |
| **Antigravity** | `~/.gemini/antigravity-cli`, CLI | codexbar / native |
| **OpenCode** | `~/.local/share/opencode/opencode.db` | native (local SQLite) |
| **Claude** | `~/.claude` | codexbar |
| **Gemini CLI** | `~/.gemini` | codexbar |
| **Cursor** | `cursor-agent` | codexbar |
| **GitHub Copilot** | `gh` auth | codexbar |
| **Moonshot / OpenRouter / Z.ai / MiniMax** | API key | codexbar |

Anything not covered natively goes through the local
[`codexbar`](https://github.com/) CLI when it is installed; providers that have
a built-in reader (Codex, Kimi, Antigravity, OpenCode) work without it.

## Requirements

- KDE Plasma 6
- `python3`
- *Optional:* the `codexbar` CLI for the widest provider coverage
- *Optional:* the agents' own CLIs to sign in

## Install

```sh
./install.sh
```

Then right-click the panel → **Add Widgets…** → search for **Tokenz**.

To remove it:

```sh
kpackagetool6 --type Plasma/Applet --remove org.tokenz.plasma
```

## Configure

Open the widget settings. The **AI agents** page auto-detects installed agents
and lets you:

- enable/disable each agent,
- add more agents from the catalog,
- choose the **engine** (`Auto` / `codexbar` / `Native`) and **source**
  (`auto`, `web`, `cli`, `oauth`, `api`),
- pick a specific **account** when an agent exposes several,
- set a display **label**, and
- **Sign in** (opens the agent's login in a terminal) or store an **API key**.

The **General** page controls the refresh interval, panel style, layout,
desktop background opacity and the warning threshold.

## How it works

```
QML (panel/popup)  ──►  contents/code/tokenz_fetch.py  ──►  codexbar / native readers
        ▲                        │
        └──── normalized JSON ◄──┘
```

All provider knowledge lives in the Python engine, which prints a single
normalized JSON object:

```json
{
  "ok": true,
  "provider": "codex",
  "account": "you@example.com",
  "plan": "pro",
  "engine": "codexbar",
  "source": "oauth",
  "state": "ok",
  "windows": [
    { "key": "primary", "label": "Session", "percent": 20.0,
      "resetAt": "2026-11-07T09:36:48Z", "detail": "Nov 7, 10:36" }
  ],
  "models": []
}
```

Useful manual calls:

```sh
python3 contents/code/tokenz_fetch.py --detect
python3 contents/code/tokenz_fetch.py --provider codex
python3 contents/code/tokenz_fetch.py --provider antigravity --engine codexbar
```

## Troubleshooting

- **“Not detected”** – make sure the agent's CLI is on `PATH` (including in
  `~/.local/bin`) and that you have logged in at least once.
- **“Token expired” / “Not logged in”** – use **Sign in** in the settings, or
  run the agent's own login command (e.g. `codex login`, `kimi`).
- **Nothing shows for a provider** – it may have no usage endpoint; try the
  `codexbar` engine.

## License

GPL-3.0-or-later.
