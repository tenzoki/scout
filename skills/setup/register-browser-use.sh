#!/usr/bin/env bash
# scout depth-layer registration — single source of truth for the browser-use
# MCP registration mechanics (pin, shim, no-cloud env vars, remove-then-add, verify).
#
# Extraction runs on Anthropic. Stock browser-use 0.11.9 hardwires its
# browser_extract_content LLM to OpenAI; scout ships a runtime shim
# (services/browser-use-anthropic/scout_browseruse_anthropic.py) that rebinds it
# to ChatAnthropic. So the registered command launches the shim inside the exact
# pinned browser-use environment, and the credential is an ANTHROPIC_API_KEY.
#
# Used two ways:
#   1. Standalone (technical user):   bash register-browser-use.sh
#   2. Invoked by /scout:setup, which collects the key conversationally and
#      passes it via env so it never lands in shell history typed by a human.
#
# Key handling (in precedence order):
#   - BROWSERUSE_INHERIT=1          -> register with NO key in the config; the
#                                      running session inherits ANTHROPIC_API_KEY
#                                      from the environment. Nothing key-shaped
#                                      is written.
#   - BROWSERUSE_ANTHROPIC_KEY=...  -> pin that key into the user-scope MCP config.
#   - else, interactive tty         -> offer inherit (if ANTHROPIC_API_KEY is set)
#                                      or prompt for a key with hidden input.
#   - else (non-interactive)        -> stop, rather than guess.
#
# Note: pinning a key via the CLI necessarily passes it in argv (visible to `ps`
# for an instant). The inherit path avoids that entirely and is the default when
# ANTHROPIC_API_KEY is already in the environment.
#
# Inherit timing: the inherit path reads ANTHROPIC_API_KEY at MCP server-launch
# time from the environment of whatever shell launches Claude Code — NOT at
# registration time, and NOT from a file. So the key must be exported before
# Claude Code starts, in the launching shell. Registering inherit-mode in a shell
# that has the key, then launching Claude Code from a different shell that does
# not, leaves registration green but the first browser_extract_content failing
# with an opaque auth error. This script warns loudly (below) when inherit is
# selected with no key in the registering environment.
#
# This script never writes the key to a file and never echoes the full key.
#
# Shim location (state-dir rule): the registration is user-scope and outlives
# every copy of the plugin, so it must not name a file inside one. The plugin
# tree (~/.scout, or ~/.claude/plugins/cache/<marketplace>/scout/<version>/) is
# replaced by an update. So this script copies the shim into one user-scoped
# state directory, the same for every caller (launcher, /scout:setup, a
# standalone run), and registers that copy:
#   STATE_DIR = ${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}
#   shim copy = $STATE_DIR/browser-use-anthropic/scout_browseruse_anthropic.py
# A STATE_DIR that is not absolute, that lies under a plugin cache
# (/plugins/cache/), or whose path holds a `"` or `\` (it is spliced into a JSON
# string below) is refused. The shim folder carries a `.scout-owned` marker, which
# `scout --uninstall` requires before it removes the folder. Decision record:
# 261016-2323-where-does-scout-keep-state-that-must-survive-a-plugin-update.md
#
# The copy is refreshed only when this script runs. A scout release that changes
# the shim or the browser-use pin therefore needs /scout:setup re-run.
#
# Exit codes: 0 the entry is registered and names the shim copy; 1 anything
# else, with the reason on stderr. Callers (the installer, the launcher's --key,
# /scout:setup) report success only on 0.

set -u
set -o pipefail

PIN="browser-use[cli]@0.11.9"

# The source shim is resolved from this script's own location, so it is correct
# in any plugin copy (launcher, marketplace cache, source tree). It is only ever
# read; the registration names the copy in STATE_DIR (see header).
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_SHIM="$(cd "$SCRIPT_DIR/../../" && pwd)/services/browser-use-anthropic/scout_browseruse_anthropic.py"

STATE_DIR="${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}"
case "$STATE_DIR" in
  /*) ;;
  *) echo "Stopping: the scout state directory must be an absolute path, got '$STATE_DIR' (set SCOUT_STATE_DIR or XDG_STATE_HOME to an absolute path)." >&2; exit 1 ;;
esac
case "$STATE_DIR" in
  */plugins/cache|*/plugins/cache/*) echo "Stopping: the scout state directory '$STATE_DIR' lies inside a plugin cache, which a plugin update deletes. Point SCOUT_STATE_DIR somewhere outside it." >&2; exit 1 ;;
esac
case "$STATE_DIR" in
  *'"'*|*'\'*) echo "Stopping: the scout state directory '$STATE_DIR' contains a \" or \\, which cannot be written into the registration. Point SCOUT_STATE_DIR at a plain path." >&2; exit 1 ;;
esac
SHIM_DIR="$STATE_DIR/browser-use-anthropic"
SHIM_PATH="$SHIM_DIR/scout_browseruse_anthropic.py"
SHIM_MARKER="$SHIM_DIR/.scout-owned"

echo "== prerequisites =="
missing=0
if command -v claude >/dev/null 2>&1; then echo "claude: ok"; else echo "claude: MISSING -> https://docs.claude.com/en/docs/claude-code"; missing=1; fi
if command -v uvx >/dev/null 2>&1; then echo "uvx: ok"; else echo "uvx: MISSING -> install uv (ships uvx): https://github.com/astral-sh/uv"; missing=1; fi
if [ ! -f "$SRC_SHIM" ]; then echo "shim: MISSING -> expected at $SRC_SHIM"; missing=1; else echo "shim: ok"; fi
if [ "$missing" -ne 0 ]; then echo "Stopping: install the missing prerequisite, then re-run."; exit 1; fi

# Decide key mode.
KEY=""
INHERIT=0
case "${BROWSERUSE_INHERIT:-}" in 1|true|True|TRUE|yes|Yes) INHERIT=1 ;; esac

if [ "$INHERIT" -ne 1 ] && [ -n "${BROWSERUSE_ANTHROPIC_KEY:-}" ]; then
  KEY="$BROWSERUSE_ANTHROPIC_KEY"
elif [ "$INHERIT" -ne 1 ]; then
  if [ -t 0 ]; then
    if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
      echo "ANTHROPIC_API_KEY found in environment (length ${#ANTHROPIC_API_KEY})."
      read -r -p "Inherit it instead of pinning it into the config? [Y/n] " ans
      case "${ans:-Y}" in [Nn]*) INHERIT=0 ;; *) INHERIT=1 ;; esac
    fi
    if [ "$INHERIT" -ne 1 ]; then
      read -r -s -p "Paste your Anthropic API key (input hidden): " KEY; echo
    fi
  fi
fi

if [ "$INHERIT" -ne 1 ] && [ -z "$KEY" ]; then
  echo "No Anthropic key available and not running interactively."
  echo "Set BROWSERUSE_ANTHROPIC_KEY=... to pin a key, or BROWSERUSE_INHERIT=1 to inherit one from the environment."
  exit 1
fi

# Early warning: inherit mode chosen but no key in THIS environment. Registration
# will still succeed (and look green), but depth will not work until the key is
# exported into the shell that launches Claude Code. Warn loudly; do not fail —
# the inherit-at-runtime design is legitimate and the key may be exported later.
if [ "$INHERIT" -eq 1 ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  {
    echo
    echo "WARNING: inherit mode selected, but ANTHROPIC_API_KEY is NOT set in this environment."
    echo "WARNING: Registration will still succeed and 'claude mcp get browser-use' will look healthy,"
    echo "WARNING: but depth will NOT work until you export the key and (re)start Claude Code."
    echo "WARNING: The browser-use MCP server reads ANTHROPIC_API_KEY at launch time from the shell"
    echo "WARNING: that starts Claude Code — not from this registration, and not from any file."
    echo "WARNING: Fix: export ANTHROPIC_API_KEY=sk-ant-... in the shell that launches Claude Code,"
    echo "WARNING: then restart Claude Code. Or re-run with BROWSERUSE_ANTHROPIC_KEY=sk-ant-... to pin it."
    echo
  } >&2
fi

# Optional extraction overrides, forwarded into the registration only when set.
# They are spliced into a JSON string in inherit mode, so the characters that
# would break that string are refused. The shim itself range-checks the
# temperature ([0, 1]); here it only has to be number-shaped.
MODEL="${SCOUT_DEPTH_EXTRACT_MODEL:-}"
case "$MODEL" in
  *'"'*|*'\'*) echo "Stopping: SCOUT_DEPTH_EXTRACT_MODEL contains a \" or \\; a model name never does." >&2; exit 1 ;;
esac
TEMPERATURE="${SCOUT_DEPTH_EXTRACT_TEMPERATURE:-}"
case "$TEMPERATURE" in
  *[!0-9.]*) echo "Stopping: SCOUT_DEPTH_EXTRACT_TEMPERATURE must be a number in [0, 1], got '$TEMPERATURE'." >&2; exit 1 ;;
esac
# The same overrides in the two shapes the two registration forms take: a JSON
# fragment (inherit) and `-e NAME=value` flags (pinned key).
OPT_JSON=""
OPT_FLAGS=()
if [ -n "$MODEL" ]; then
  OPT_JSON="$OPT_JSON\"SCOUT_DEPTH_EXTRACT_MODEL\": \"$MODEL\", "
  OPT_FLAGS+=(-e "SCOUT_DEPTH_EXTRACT_MODEL=$MODEL")
fi
if [ -n "$TEMPERATURE" ]; then
  OPT_JSON="$OPT_JSON\"SCOUT_DEPTH_EXTRACT_TEMPERATURE\": \"$TEMPERATURE\", "
  OPT_FLAGS+=(-e "SCOUT_DEPTH_EXTRACT_TEMPERATURE=$TEMPERATURE")
fi

echo
echo "== copy shim to the state directory =="
# Write only into a folder scout owns: absent, empty, marked, under the default
# state directory (only scout uses it), or holding scout's shim as 0.6.0 left it
# before the marker existed. Anything else is someone else's folder.
if [ -e "$SHIM_DIR" ] && [ ! -f "$SHIM_MARKER" ]; then
  if [ -d "$SHIM_DIR" ] && { [ -z "$(ls -A "$SHIM_DIR" 2>/dev/null)" ] || [ -z "${SCOUT_STATE_DIR:-}" ] || [ -f "$SHIM_PATH" ]; }; then
    :
  else
    echo "Stopping: $SHIM_DIR exists and was not written by scout (no .scout-owned marker). Move it aside or set SCOUT_STATE_DIR to another directory." >&2
    exit 1
  fi
fi
if ! mkdir -p "$SHIM_DIR"; then echo "Stopping: could not create $SHIM_DIR." >&2; exit 1; fi
if [ ! -f "$SHIM_MARKER" ] && ! printf '%s\n' "Written by scout (register-browser-use.sh). scout --uninstall removes this folder only while this file is here." > "$SHIM_MARKER"; then
  echo "Stopping: could not write the ownership marker $SHIM_MARKER." >&2; exit 1
fi
if ! cp "$SRC_SHIM" "$SHIM_PATH"; then echo "Stopping: could not copy the shim to $SHIM_PATH." >&2; exit 1; fi
if ! cmp -s "$SRC_SHIM" "$SHIM_PATH"; then echo "Stopping: the shim copy at $SHIM_PATH does not match $SRC_SHIM." >&2; exit 1; fi
echo "shim copy: $SHIM_PATH"

echo
echo "== register browser-use (user scope) =="
# add/add-json refuse to overwrite an existing server, so remove first (scoped to
# user so a project/local server you set up by hand is left untouched). The
# `|| true` keeps a first run (nothing to remove) from erroring under set -o
# pipefail.
claude mcp remove browser-use -s user >/dev/null 2>&1 || true

# The old entry is gone by now, so a failed add leaves no registration at all.
# That must decide the exit code, or every caller reports success.
add_failed() {
  echo "Stopping: 'claude mcp add' failed, so browser-use is NOT registered (the previous entry was already removed). Fix the error above and re-run." >&2
  exit 1
}

if [ "$INHERIT" -eq 1 ]; then
  # No ANTHROPIC_API_KEY entry: the running session inherits it from the
  # environment. The shim still runs (SCOUT_DEPTH_PROVIDER=anthropic) and both
  # no-cloud env vars are passed.
  claude mcp add-json browser-use -s user '{ "type": "stdio", "command": "uvx", "args": ["--from", "'"$PIN"'", "python", "'"$SHIM_PATH"'", "--mcp"], "env": { "SCOUT_DEPTH_PROVIDER": "anthropic", '"$OPT_JSON"'"ANONYMIZED_TELEMETRY": "False", "BROWSER_USE_VERSION_CHECK": "false" } }' || add_failed
  # Inherit-mode runtime contract: the key is read from the launching shell's
  # environment when the MCP server starts, not from this config. Say so plainly
  # so a green registration is not mistaken for a working depth layer.
  echo
  echo "Inherit mode: no ANTHROPIC_API_KEY was written to the config."
  echo "The browser-use MCP server reads ANTHROPIC_API_KEY at launch time from the"
  echo "environment of whatever shell starts Claude Code. Export it BEFORE you start"
  echo "Claude Code (in that launching shell), or depth fails on the first extract."
  echo "Put 'export ANTHROPIC_API_KEY=sk-ant-...' in a file you source on shell start,"
  echo "kept outside any repo. To sidestep env timing entirely, re-run with"
  echo "BROWSERUSE_ANTHROPIC_KEY=sk-ant-... to pin the key into the user-scope config."
else
  # Flag form keeps the key out of a JSON blob and matches the skill's documented
  # mechanism. The shim runs inside the pinned browser-use env via `--from`.
  # `${OPT_FLAGS[@]+...}` keeps an empty array from tripping `set -u` on bash 3.2.
  claude mcp add browser-use uvx -s user -e ANTHROPIC_API_KEY="$KEY" -e SCOUT_DEPTH_PROVIDER=anthropic ${OPT_FLAGS[@]+"${OPT_FLAGS[@]}"} -e ANONYMIZED_TELEMETRY=False -e BROWSER_USE_VERSION_CHECK=false -- --from "$PIN" python "$SHIM_PATH" --mcp || add_failed
fi

echo
echo "== verify =="
VERIFY_OUT="$(claude mcp get browser-use 2>&1)"
printf '%s\n' "$VERIFY_OUT"
# A check that can fail decides the exit code: a missing entry, or one that does
# not name the shim copy, is a failed registration, not a warning.
case "$VERIFY_OUT" in
  *"$SHIM_PATH"*) echo "shim path: ok ($SHIM_PATH)" ;;
  *) echo "Stopping: the registered browser-use entry is missing or does not name the shim copy $SHIM_PATH. Re-run /scout:setup." >&2; exit 1 ;;
esac
case "$VERIFY_OUT" in
  */plugins/cache/*) echo "Stopping: the registered entry names a path under /plugins/cache/, which the next plugin update deletes. Re-run /scout:setup." >&2; exit 1 ;;
esac
echo
echo "Done. If the entry shows Type: stdio, Command: uvx, the --from pin + shim path + --mcp args, SCOUT_DEPTH_PROVIDER=anthropic, and the two no-cloud env vars, depth is registered. Re-run scout."
