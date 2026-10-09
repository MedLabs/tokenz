#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Tokenz contributors
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Tokenz data engine.
#
# Reads usage/limits for AI coding agents and prints a single normalized JSON
# object on stdout. It never raises to the caller: every failure is reported as
# a JSON object with {"ok": false, ...} so the QML side can render it.
#
# Two engines:
#   * "codexbar" - delegates to the local `codexbar` CLI (recommended, supports
#     60+ providers and handles OAuth refresh/cookies itself).
#   * "native"   - reads the agent's own credential files and calls the provider
#     API directly (works without codexbar for Codex, OpenCode and best-effort
#     for Kimi Code and Google Antigravity).
#
# Usage:
#   tokenz_fetch.py --detect
#   tokenz_fetch.py --provider <id> [--engine auto|codexbar|native]
#                   [--account LABEL] [--source auto|web|cli|oauth|api]
#                   [--budget USD] [--label TEXT]

import argparse
import datetime as _dt
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import urllib.error
import urllib.request

STATE_OK = "ok"
STATE_NOT_LOGGED_IN = "notLoggedIn"
STATE_TOKEN_ERROR = "tokenError"
STATE_RATE_LIMITED = "rateLimited"
STATE_ERROR = "error"
STATE_DISABLED = "disabled"

HOME = os.path.expanduser("~")
UA = "tokenz/0.1"


# --------------------------------------------------------------------------- #
# Binary resolution
# --------------------------------------------------------------------------- #
# plasmashell runs as a systemd --user service whose PATH omits per-user bin
# dirs (~/.local/bin, ~/.kimi-code/bin, ...). Resolve helpers against these too
# so the applet works no matter how it was launched.
def _candidate_bin_dirs():
    import glob as _glob
    dirs = [
        os.path.join(HOME, ".local", "bin"),
        os.path.join(HOME, ".kimi-code", "bin"),
        os.path.join(HOME, ".opencode", "bin"),
        os.path.join(HOME, ".bun", "bin"),
        os.path.join(HOME, ".cargo", "bin"),
        os.path.join(HOME, "go", "bin"),
        "/usr/local/bin",
    ]
    dirs += sorted(_glob.glob(os.path.join(HOME, ".nvm", "versions", "node", "*", "bin")))
    return dirs


def which_bin(name):
    found = shutil.which(name)
    if found:
        return found
    for directory in _candidate_bin_dirs():
        candidate = os.path.join(directory, name)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    return ""


def augmented_path():
    parts = [p for p in os.environ.get("PATH", "").split(os.pathsep) if p]
    for directory in _candidate_bin_dirs():
        if directory not in parts:
            parts.append(directory)
    return os.pathsep.join(parts)


# --------------------------------------------------------------------------- #
# Provider catalog
# --------------------------------------------------------------------------- #
# native: whether a direct (codexbar-free) fetcher exists
# codexbar: the provider id understood by the codexbar CLI
# paths: credential/config locations used for detection and native reads
# bins: CLI binaries used for detection
# env: environment variables that can carry an API key
# auth: command to (re)authenticate the agent interactively
PROVIDERS = {
    "codex": {
        "name": "Codex",
        "codexbar": "codex",
        "native": True,
        "paths": ["~/.codex/auth.json"],
        "bins": ["codex", "codex-cli"],
        "auth": "codex login",
    },
    "kimi": {
        "name": "Kimi Code",
        "codexbar": "kimi",
        "native": True,
        "paths": [
            "~/.kimi-code/credentials/kimi-code.json",
            "~/.kimi/credentials/kimi-code.json",
        ],
        "bins": ["kimi"],
        "auth": "kimi",
    },
    "antigravity": {
        "name": "Antigravity",
        "codexbar": "antigravity",
        "native": True,
        "paths": ["~/.gemini/antigravity-cli/antigravity-oauth-token"],
        "bins": ["agy", "antigravity"],
        "auth": "agy",
    },
    "opencode": {
        "name": "OpenCode",
        "codexbar": "opencode",
        "native": True,
        "paths": ["~/.local/share/opencode/opencode.db", "~/.opencode"],
        "bins": ["opencode"],
        "auth": "opencode auth login",
    },
    "claude": {
        "name": "Claude",
        "codexbar": "claude",
        "native": False,
        "paths": ["~/.claude/.credentials.json"],
        "bins": ["claude"],
        "auth": "claude",
    },
    "gemini": {
        "name": "Gemini CLI",
        "codexbar": "gemini",
        "native": False,
        "paths": ["~/.gemini/oauth_creds.json"],
        "bins": ["gemini"],
        "auth": "gemini",
    },
    "cursor": {
        "name": "Cursor",
        "codexbar": "cursor",
        "native": False,
        "paths": ["~/.config/Cursor", "~/.cursor"],
        "bins": ["cursor", "cursor-agent"],
        "auth": "cursor-agent login",
    },
    "copilot": {
        "name": "GitHub Copilot",
        "codexbar": "copilot",
        "native": False,
        "paths": ["~/.config/github-copilot"],
        "bins": ["gh"],
        "auth": "gh auth login",
    },
    "moonshot": {
        "name": "Moonshot",
        "codexbar": "moonshot",
        "native": False,
        "paths": [],
        "bins": [],
        "env": ["MOONSHOT_API_KEY"],
        "apikey": True,
    },
    "openrouter": {
        "name": "OpenRouter",
        "codexbar": "openrouter",
        "native": False,
        "paths": [],
        "bins": [],
        "env": ["OPENROUTER_API_KEY"],
        "apikey": True,
    },
    "zai": {
        "name": "Z.ai",
        "codexbar": "zai",
        "native": False,
        "paths": [],
        "bins": [],
        "env": ["ZAI_API_KEY", "Z_AI_API_KEY"],
        "apikey": True,
    },
    "minimax": {
        "name": "MiniMax",
        "codexbar": "minimax",
        "native": False,
        "paths": [],
        "bins": [],
        "env": ["MINIMAX_API_KEY"],
        "apikey": True,
    },
}


def now_iso():
    return _dt.datetime.now(_dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def epoch_to_iso(value):
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if n <= 0:
        return None
    # Heuristic: values < 1e12 are epoch seconds, else milliseconds.
    if n > 1e12:
        n = n / 1000.0
    try:
        return _dt.datetime.fromtimestamp(n, _dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    except (OverflowError, OSError, ValueError):
        return None


def label_for_minutes(minutes):
    try:
        m = int(minutes)
    except (TypeError, ValueError):
        return ""
    if m <= 0:
        return ""
    if m % 1440 == 0:
        return "%dd" % (m // 1440)
    if m % 60 == 0:
        return "%dh" % (m // 60)
    return "%dm" % m


def clamp_percent(value):
    try:
        p = float(value)
    except (TypeError, ValueError):
        return 0.0
    return max(0.0, min(100.0, p))


def make_window(key, label, percent, reset_at=None, detail=""):
    return {
        "key": key or "",
        "label": label or "",
        "percent": clamp_percent(percent),
        "resetAt": reset_at or None,
        "detail": detail or "",
    }


def make_result(provider_id, **kw):
    result = {
        "ok": kw.get("state", STATE_ERROR) == STATE_OK,
        "provider": provider_id,
        "account": "",
        "plan": "",
        "engine": "",
        "source": "",
        "state": STATE_ERROR,
        "error": "",
        "windows": [],
        "models": [],
        "updatedAt": now_iso(),
    }
    result.update(kw)
    return result


def find_binary(names):
    if not names:
        return ""
    for name in names:
        path = which_bin(name)
        if path:
            return path
    return ""


def expand(path):
    return os.path.expanduser(path)


def detect_provider(pid, spec):
    present = False
    binpath = find_binary(spec.get("bins"))
    if binpath:
        present = True
    has_creds = False
    for p in spec.get("paths", []) or []:
        if os.path.exists(expand(p)):
            present = True
            has_creds = True
    return {
        "id": pid,
        "name": spec.get("name", pid),
        "present": present,
        "hasCreds": has_creds,
        "bin": binpath,
        "native": bool(spec.get("native")),
        "codexbar": spec.get("codexbar", pid),
        "apikey": bool(spec.get("apikey")),
        "auth": spec.get("auth", ""),
        "env": spec.get("env", []),
    }


def run_detect():
    codexbar = which_bin("codexbar") or ""
    providers = [detect_provider(pid, spec) for pid, spec in PROVIDERS.items()]
    providers.sort(key=lambda p: (not p["present"], p["name"].lower()))
    return {
        "ok": True,
        "codexbar": codexbar,
        "python": sys.executable,
        "home": HOME,
        "providers": providers,
    }


# --------------------------------------------------------------------------- #
# HTTP helper
# --------------------------------------------------------------------------- #
def http_request(url, method="GET", headers=None, body=None, timeout=25):
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("User-Agent", UA)
    req.add_header("Accept", "application/json")
    for key, value in (headers or {}).items():
        if value is not None:
            req.add_header(key, str(value))
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8", "replace")
            return resp.status, raw
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        return exc.code, raw
    except Exception as exc:  # noqa: BLE001 - reported to the UI
        return 0, str(exc)


def read_json_file(path):
    try:
        with open(expand(path), "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:  # noqa: BLE001
        return None


# --------------------------------------------------------------------------- #
# codexbar engine
# --------------------------------------------------------------------------- #
def normalize_codexbar(pid, spec, entries):
    cb_id = spec.get("codexbar", pid)
    matching = [e for e in entries if isinstance(e, dict) and e.get("provider") == cb_id]
    entry = matching[0] if matching else (entries[0] if entries else None)
    if not isinstance(entry, dict):
        return make_result(pid, engine="codexbar", state=STATE_ERROR, error="Empty codexbar response")

    if "error" in entry and entry["error"]:
        err = entry["error"] or {}
        kind = str(err.get("kind", "error"))
        message = str(err.get("message", "codexbar error"))
        state = STATE_ERROR
        if kind in ("authentication-expired", "missing-credential"):
            state = STATE_NOT_LOGGED_IN
        elif kind == "permission-denied":
            state = STATE_TOKEN_ERROR
        elif kind == "rate-limited":
            state = STATE_RATE_LIMITED
        return make_result(pid, engine="codexbar", source=str(entry.get("source", "")),
                           state=state, error=message)

    usage = entry.get("usage") or {}
    labels = entry.get("rateWindowLabels") or {}
    identity = usage.get("identity") or {}
    windows = []
    for key in ("primary", "secondary", "tertiary"):
        window = usage.get(key)
        if not isinstance(window, dict):
            continue
        windows.append(make_window(
            key,
            labels.get(key) or label_for_minutes(window.get("windowMinutes")),
            window.get("usedPercent", 0),
            window.get("resetsAt"),
            window.get("resetDescription", ""),
        ))
    for extra in usage.get("extraRateWindows") or []:
        if not isinstance(extra, dict):
            continue
        window = extra.get("window") or {}
        windows.append(make_window(
            extra.get("id", ""),
            extra.get("title") or label_for_minutes(window.get("windowMinutes")),
            window.get("usedPercent", 0),
            window.get("resetsAt"),
        ))

    account = (identity.get("accountEmail") or identity.get("email")
               or identity.get("accountID") or "")
    plan = usage.get("loginMethod") or identity.get("planType") or ""
    version = entry.get("version") or ""

    if not windows:
        # A provider can legitimately report only a balance/identity (e.g.
        # Moonshot reports remaining balance); surface it as a detail window.
        detail = usage.get("providerCost") or {}
        note = identity.get("loginMethod") or ""
        if note:
            return make_result(pid, engine="codexbar", source=str(entry.get("source", "")),
                               state=STATE_OK, account=account, plan=note,
                               windows=[make_window("balance", "Balance", 0, None, note)])
        return make_result(pid, engine="codexbar", state=STATE_ERROR,
                           error="No usage windows returned")

    return make_result(pid, engine="codexbar", source=str(entry.get("source", "")),
                       state=STATE_OK, account=account, plan=plan,
                       windows=windows, version=version)


def fetch_codexbar(pid, spec, account="", source="auto"):
    cb = which_bin("codexbar")
    if not cb:
        return None
    cmd = [cb, "usage", "--provider", spec.get("codexbar", pid),
           "--format", "json", "--no-color"]
    if account:
        cmd += ["--account", account]
    if source and source not in ("", "auto"):
        cmd += ["--source", source]
    env = dict(os.environ)
    # codexbar shells out to the agents' own CLIs (kimi, agy, ...) to refresh
    # credentials, so give it the full per-user PATH.
    env["PATH"] = augmented_path()
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60, env=env)
    except Exception as exc:  # noqa: BLE001
        return make_result(pid, engine="codexbar", state=STATE_ERROR, error="codexbar failed: %s" % exc)
    stdout = (proc.stdout or "").strip()
    if not stdout:
        err = (proc.stderr or "").strip().splitlines()
        return make_result(pid, engine="codexbar", state=STATE_ERROR,
                           error=err[-1] if err else "codexbar returned no output")
    try:
        entries = json.loads(stdout)
    except json.JSONDecodeError:
        return make_result(pid, engine="codexbar", state=STATE_ERROR,
                           error="Invalid codexbar JSON")
    if not isinstance(entries, list):
        entries = [entries]
    return normalize_codexbar(pid, spec, entries)


# --------------------------------------------------------------------------- #
# native engine: Codex
# --------------------------------------------------------------------------- #
def fetch_codex_native(pid, spec):
    auth_paths = ["~/.codex/auth.json", os.path.join(HOME, ".config", "codex", "auth.json")]
    creds = None
    for path in auth_paths:
        creds = read_json_file(path)
        if creds:
            break
    if not creds:
        return make_result(pid, engine="native", state=STATE_NOT_LOGGED_IN,
                           error="Run `codex login` first")

    if creds.get("auth_mode") != "chatgpt":
        return make_result(pid, engine="native", state=STATE_DISABLED,
                           error="Codex API-key mode has no usage endpoint")

    tokens = creds.get("tokens") or {}
    token = tokens.get("access_token") or ""
    account_id = tokens.get("account_id") or ""
    if not token:
        return make_result(pid, engine="native", state=STATE_NOT_LOGGED_IN,
                           error="Run `codex login` first")

    status, text = http_request(
        "https://chatgpt.com/backend-api/wham/usage",
        headers={
            "Authorization": "Bearer " + token,
            "ChatGPT-Account-Id": account_id,
            "User-Agent": "codex-cli",
        },
    )
    if status == 401:
        return make_result(pid, engine="native", state=STATE_TOKEN_ERROR,
                           error="Token expired - run `codex login`")
    if status == 429:
        return make_result(pid, engine="native", state=STATE_RATE_LIMITED,
                           error="Rate limited")
    if status != 200:
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="API error (%s)" % status)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return make_result(pid, engine="native", state=STATE_ERROR, error="Parse error")

    rate_limit = data.get("rate_limit") or {}
    windows = []
    for key in ("primary_window", "secondary_window"):
        raw = rate_limit.get(key)
        if not isinstance(raw, dict):
            continue
        seconds = raw.get("limit_window_seconds")
        label = "Session (5h)" if seconds == 18000 else (
            "Weekly (7d)" if seconds == 604800 else label_for_minutes((seconds or 0) / 60.0))
        windows.append(make_window(key, label, raw.get("used_percent", 0),
                                   epoch_to_iso(raw.get("reset_at"))))
    if not windows:
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="No usage windows")
    plan = str(data.get("plan_type") or "")
    return make_result(pid, engine="native", state=STATE_OK, plan=plan, windows=windows)


# --------------------------------------------------------------------------- #
# native engine: OpenCode (local usage from its SQLite database)
# --------------------------------------------------------------------------- #
def fetch_opencode_native(pid, spec, budget_usd=0.0):
    db_paths = [
        "~/.local/share/opencode/opencode.db",
        os.path.join(HOME, ".local", "share", "opencode", "opencode.db"),
    ]
    db_path = next((p for p in db_paths if os.path.exists(expand(p))), "")
    if not db_path:
        return make_result(pid, engine="native", state=STATE_NOT_LOGGED_IN,
                           error="OpenCode database not found")
    db_path = expand(db_path)
    try:
        # Read-only, no locking surprises: copy is unnecessary for a quick read.
        conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
        cur = conn.cursor()
        cur.execute(
            "SELECT COALESCE(SUM(tokens_input + tokens_output + tokens_reasoning"
            " + tokens_cache_read + tokens_cache_write),0), COALESCE(SUM(cost),0)"
            " FROM session WHERE time_updated >= ?",
            (int((_dt.datetime.now().timestamp() - 24 * 3600) * 1000),),
        )
        tokens_today, cost_today = cur.fetchone()
        cur.execute(
            "SELECT COALESCE(SUM(tokens_input + tokens_output + tokens_reasoning"
            " + tokens_cache_read + tokens_cache_write),0), COALESCE(SUM(cost),0)"
            " FROM session WHERE time_updated >= ?",
            (int((_dt.datetime.now().timestamp() - 30 * 24 * 3600) * 1000),),
        )
        tokens_month, cost_month = cur.fetchone()
        conn.close()
    except Exception as exc:  # noqa: BLE001
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="OpenCode DB read failed: %s" % exc)

    budget = float(budget_usd or 0)
    cost_percent = (cost_month / budget * 100.0) if budget > 0 else 0.0
    windows = [
        make_window("tokens_today", "Tokens (24h)", 0, None, "{:,} tokens".format(int(tokens_today))),
        make_window("cost_month", "Cost (30d)",
                    cost_percent, None,
                    ("$%.2f" % cost_month) + ((" / $%.2f" % budget) if budget > 0 else "")),
        make_window("tokens_month", "Tokens (30d)", 0, None, "{:,} tokens".format(int(tokens_month))),
    ]
    return make_result(pid, engine="native", state=STATE_OK,
                       windows=windows, plan="local")


# --------------------------------------------------------------------------- #
# native engine: Kimi Code (best effort)
# --------------------------------------------------------------------------- #
def fetch_kimi_native(pid, spec):
    creds = None
    for path in ("~/.kimi-code/credentials/kimi-code.json",
                 "~/.kimi/credentials/kimi-code.json"):
        creds = read_json_file(path)
        if creds:
            break
    if not creds:
        return make_result(pid, engine="native", state=STATE_NOT_LOGGED_IN,
                           error="Run `kimi` to sign in")
    token = creds.get("access_token") or ""
    expires_at = creds.get("expires_at") or 0
    if token and expires_at and _dt.datetime.now().timestamp() >= float(expires_at):
        return make_result(pid, engine="native", state=STATE_TOKEN_ERROR,
                           error="Kimi Code session expired - run `kimi` to renew it")
    if not token:
        return make_result(pid, engine="native", state=STATE_NOT_LOGGED_IN,
                           error="Run `kimi` to sign in")

    status, text = http_request(
        "https://api.kimi.com/coding/v1/usages",
        headers={"Authorization": "Bearer " + token},
    )
    if status == 401:
        return make_result(pid, engine="native", state=STATE_TOKEN_ERROR,
                           error="Kimi Code session expired - run `kimi` to renew it")
    if status != 200:
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="Kimi API error (%s)" % status)
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return make_result(pid, engine="native", state=STATE_ERROR, error="Parse error")

    windows = []
    for item in (data.get("data") or data.get("usages") or []):
        if not isinstance(item, dict):
            continue
        windows.append(make_window(
            str(item.get("id") or item.get("name") or ""),
            str(item.get("title") or item.get("name") or ""),
            item.get("used_percent", item.get("usedPercent", 0)),
            epoch_to_iso(item.get("reset_at") or item.get("resetAt")),
        ))
    if not windows:
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="No usage windows returned")
    return make_result(pid, engine="native", state=STATE_OK, windows=windows)


# --------------------------------------------------------------------------- #
# native engine: Google Antigravity (best effort)
# --------------------------------------------------------------------------- #
def fetch_antigravity_native(pid, spec):
    token_path = "~/.gemini/antigravity-cli/antigravity-oauth-token"
    data = read_json_file(token_path)
    if not data:
        return make_result(pid, engine="native", state=STATE_NOT_LOGGED_IN,
                           error="Sign in to Antigravity first")
    token_block = data.get("token") or {}
    token = token_block.get("access_token") or ""
    if not token:
        return make_result(pid, engine="native", state=STATE_NOT_LOGGED_IN,
                           error="Sign in to Antigravity first")

    project = ""
    for candidate in ("~/.gemini/antigravity-cli/cache/default_project_id.txt",
                      "~/.gemini/antigravity-cli/cache/projects.json"):
        path = expand(candidate)
        if not os.path.exists(path):
            continue
        if path.endswith(".txt"):
            try:
                project = open(path, encoding="utf-8").read().strip()
            except OSError:
                project = ""
        else:
            parsed = read_json_file(path)
            if isinstance(parsed, list) and parsed:
                first = parsed[0]
                if isinstance(first, dict):
                    project = first.get("id") or first.get("projectId") or project
        if project:
            break

    status, text = http_request(
        "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",
        method="POST",
        headers={"Authorization": "Bearer " + token},
        body={"project": project} if project else {},
    )
    if status == 401:
        return make_result(pid, engine="native", state=STATE_TOKEN_ERROR,
                           error="Antigravity token expired - sign in again")
    if status != 200:
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="Antigravity quota API error (%s)" % status)
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return make_result(pid, engine="native", state=STATE_ERROR, error="Parse error")

    windows = []
    for bucket in (payload.get("buckets") or []):
        if not isinstance(bucket, dict):
            continue
        fraction = bucket.get("remainingFraction")
        percent = (1.0 - float(fraction)) * 100.0 if fraction is not None else 0
        label = bucket.get("modelId") or bucket.get("tokenType") or "Quota"
        windows.append(make_window(str(label), str(label), percent,
                                   bucket.get("resetTime")))
    if not windows:
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="No quota buckets returned")
    return make_result(pid, engine="native", state=STATE_OK, windows=windows)


NATIVE_FETCHERS = {
    "codex": fetch_codex_native,
    "kimi": fetch_kimi_native,
    "antigravity": fetch_antigravity_native,
}


# --------------------------------------------------------------------------- #
# Dispatch
# --------------------------------------------------------------------------- #
def fetch(args):
    pid = args.provider
    spec = PROVIDERS.get(pid)
    if not spec:
        return make_result(pid, state=STATE_ERROR, error="Unknown provider: %s" % pid)

    engine = args.engine or "auto"
    result = None

    if engine in ("auto", "codexbar"):
        cb = which_bin("codexbar")
        if cb:
            result = fetch_codexbar(pid, spec, account=args.account or "",
                                    source=args.source or "auto")
        elif engine == "codexbar":
            return make_result(pid, engine="codexbar", state=STATE_ERROR,
                               error="codexbar is not installed")

    if result is not None and result.get("state") != STATE_OK:
        # codexbar ran but failed; only fall back to native if the user did not
        # explicitly ask for codexbar.
        if engine == "auto" and spec.get("native"):
            fallback = fetch_native(pid, args)
            if fallback.get("state") != STATE_ERROR or not result.get("error"):
                return fallback
        return result

    if result is not None:
        return result

    # engine == native (or no codexbar available)
    return fetch_native(pid, args)


def fetch_native(pid, args):
    if pid == "opencode":
        return fetch_opencode_native(pid, PROVIDERS["opencode"], budget_usd=args.budget or 0)
    fetcher = NATIVE_FETCHERS.get(pid)
    if not fetcher:
        return make_result(pid, engine="native", state=STATE_ERROR,
                           error="No native reader for %s - install codexbar" % pid)
    return fetcher(pid, PROVIDERS[pid])


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--detect", action="store_true")
    parser.add_argument("--provider")
    parser.add_argument("--engine", default="auto")
    parser.add_argument("--account", default="")
    parser.add_argument("--source", default="auto")
    parser.add_argument("--budget", type=float, default=0.0)
    parser.add_argument("--label", default="")
    args = parser.parse_args()

    try:
        if args.detect:
            payload = run_detect()
        elif args.provider:
            payload = fetch(args)
        else:
            payload = {"ok": False, "error": "Nothing to do (use --detect or --provider)"}
    except Exception as exc:  # noqa: BLE001 - last-resort guard
        payload = {"ok": False, "state": STATE_ERROR,
                   "provider": getattr(args, "provider", "") or "",
                   "error": "tokenz_fetch internal error: %s" % exc,
                   "windows": [], "models": []}

    sys.stdout.write(json.dumps(payload))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
