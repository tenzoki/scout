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
#   2. Invoked by /scout:setup, which never handles the key itself: it runs this
#      script only when BROWSERUSE_ANTHROPIC_KEY is already in the session's
#      environment, so the key is read from env and never appears on a command
#      line or in the conversation.
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
# for an instant). The inherit path avoids that, but it costs more than it
# saves: ANTHROPIC_API_KEY in the environment that launches Claude Code switches
# Claude Code itself to API-key auth and API billing, off the user's
# subscription. Pinning keeps the key in the browser-use server only.
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
# This script never writes the key to a file and never echoes it: the output of
# `claude mcp add` and `claude mcp get` is redacted before it is printed, because
# /scout:setup runs this script inside a conversation that must never see the key.
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
# The copy and the registered command are refreshed only when this script runs.
# A scout release that changes the registered command (the shim, the pin, or any
# other argument) therefore needs /scout:setup re-run.
#
# Exit codes: 0 the entry is registered and names the shim copy; 1 anything
# else, with the reason on stderr. Callers (the installer, the launcher's --key,
# /scout:setup) report success only on 0.

set -u
set -o pipefail

PIN="browser-use[cli]@0.11.9"
# The pin alone does not reproduce the tested environment; three more uvx
# arguments do, and each is part of the pin discipline (a bump is a tested change):
#   PYTHON  browser-use 0.11.9 requires Python >=3.11,<4.0. uvx otherwise takes
#           the first interpreter it finds, which on macOS is the system 3.9.6.
#           An exact minor makes uv use an installed 3.12 or download a managed
#           one; 3.12 is the version this stack is tested on (a >=3.11 range
#           would float to whatever is newest and re-open the question).
#   MCP_PIN browser-use declares `mcp>=1.10.1` with no upper bound. mcp 2.x
#           removed the low-level `Server.list_tools()` decorator that
#           browser_use/mcp/server.py uses, so the server dies at start.
#   PS_PIN  browser_use/config.py imports pydantic_settings without declaring
#           it; mcp 1.x pulled it in, mcp 2.x does not. Pinned explicitly so
#           the import does not depend on another package's dependency list.
PYTHON="3.12"
MCP_PIN="mcp==1.30.0"
PS_PIN="pydantic-settings==2.16.1"

# Browser start timeouts, in seconds. browser-use 0.11.9 gives BrowserStartEvent
# and BrowserLaunchEvent 30 s each (browser_use/browser/events.py). A first start
# that has to download Chrome takes longer, times out, and the depth layer looks
# broken. browser-use reads TIMEOUT_<EventName> from the server's environment each
# time it creates the event, so passing these in the registration's env is enough.
START_TIMEOUT=120
LAUNCH_TIMEOUT=120

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
      echo "ANTHROPIC_API_KEY found in environment."
      echo "Note: ANTHROPIC_API_KEY in the environment that launches Claude Code switches Claude Code itself to API billing, off your subscription. Pinning keeps the key in the browser-use server only."
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
    echo "WARNING: ANTHROPIC_API_KEY in the shell that launches Claude Code also switches Claude Code"
    echo "WARNING: itself to API billing, off your subscription. Prefer pinning: set BROWSERUSE_ANTHROPIC_KEY"
    echo "WARNING: in your shell and re-run this script without BROWSERUSE_INHERIT."
    echo
  } >&2
fi

# Print stdin with the key masked: the literal key this run pins, then any value
# after ANTHROPIC_API_KEY= / ANTHROPIC_API_KEY: (a key left from an older entry).
redact() {
  local s
  s="$(cat)"
  if [ -n "$KEY" ]; then s="${s//"$KEY"/<redacted>}"; fi
  printf '%s\n' "$s" | sed -E 's/(ANTHROPIC_API_KEY[=:][[:space:]]*)[^[:space:]",]+/\1<redacted>/g'
}

# Optional extraction overrides, forwarded into the registration only when set.
# They are spliced into a JSON string in inherit mode, so the characters that
# would break that string are refused. The temperature is checked here against
# the same rule the shim applies (a decimal number in [0, 1]), because the
# shim's refusal note goes to the MCP server's stderr, which nobody reads: a
# value it would drop must fail this registration instead.
MODEL="${SCOUT_DEPTH_EXTRACT_MODEL:-}"
case "$MODEL" in
  *'"'*|*'\'*) echo "Stopping: SCOUT_DEPTH_EXTRACT_MODEL contains a \" or \\; a model name never does." >&2; exit 1 ;;
esac
TEMPERATURE="${SCOUT_DEPTH_EXTRACT_TEMPERATURE:-}"
# Held in a variable: bash 3.2 and 5 then read the pattern the same way.
TEMPERATURE_RE='^(0(\.[0-9]+)?|1(\.0+)?|\.[0-9]+)$'
if [ -n "$TEMPERATURE" ] && ! [[ "$TEMPERATURE" =~ $TEMPERATURE_RE ]]; then
  echo "Stopping: SCOUT_DEPTH_EXTRACT_TEMPERATURE must be a number in [0, 1], got '$TEMPERATURE'." >&2; exit 1
fi
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
  claude mcp add-json browser-use -s user '{ "type": "stdio", "command": "uvx", "args": ["--python", "'"$PYTHON"'", "--from", "'"$PIN"'", "--with", "'"$MCP_PIN"'", "--with", "'"$PS_PIN"'", "python", "'"$SHIM_PATH"'", "--mcp"], "env": { "SCOUT_DEPTH_PROVIDER": "anthropic", '"$OPT_JSON"'"TIMEOUT_BrowserStartEvent": "'"$START_TIMEOUT"'", "TIMEOUT_BrowserLaunchEvent": "'"$LAUNCH_TIMEOUT"'", "ANONYMIZED_TELEMETRY": "False", "BROWSER_USE_VERSION_CHECK": "false" } }' || add_failed
  # Inherit-mode runtime contract: the key is read from the launching shell's
  # environment when the MCP server starts, not from this config. Say so plainly
  # so a green registration is not mistaken for a working depth layer.
  echo
  echo "Inherit mode: no ANTHROPIC_API_KEY was written to the config."
  echo "The browser-use MCP server reads ANTHROPIC_API_KEY at launch time from the"
  echo "environment of whatever shell starts Claude Code. Export it BEFORE you start"
  echo "Claude Code (in that launching shell), or depth fails on the first extract."
  echo "WARNING: ANTHROPIC_API_KEY in that launching shell also switches Claude Code"
  echo "itself to API-key auth and API billing, off your subscription. To keep the"
  echo "key in the browser-use server only, set BROWSERUSE_ANTHROPIC_KEY in your shell"
  echo "and re-run this script without BROWSERUSE_INHERIT (pinned mode)."
else
  # Flag form keeps the key out of a JSON blob and matches the skill's documented
  # mechanism. The shim runs inside the pinned browser-use env via `--from`,
  # on the pinned Python and with the two pinned `--with` packages.
  # `${OPT_FLAGS[@]+...}` keeps an empty array from tripping `set -u` on bash 3.2.
  # Output goes through redact; pipefail keeps claude's exit code deciding.
  claude mcp add browser-use uvx -s user -e ANTHROPIC_API_KEY="$KEY" -e SCOUT_DEPTH_PROVIDER=anthropic ${OPT_FLAGS[@]+"${OPT_FLAGS[@]}"} -e TIMEOUT_BrowserStartEvent="$START_TIMEOUT" -e TIMEOUT_BrowserLaunchEvent="$LAUNCH_TIMEOUT" -e ANONYMIZED_TELEMETRY=False -e BROWSER_USE_VERSION_CHECK=false -- --python "$PYTHON" --from "$PIN" --with "$MCP_PIN" --with "$PS_PIN" python "$SHIM_PATH" --mcp 2>&1 | redact || add_failed
fi

echo
echo "== verify =="
VERIFY_OUT="$(claude mcp get browser-use 2>&1)"
# `claude mcp get` lists the server's env, a pinned key included. The checks
# below read VERIFY_OUT; only the redacted copy is printed.
printf '%s\n' "$VERIFY_OUT" | redact
# A check that can fail decides the exit code: a missing entry, or one that does
# not name the shim copy, is a failed registration, not a warning.
case "$VERIFY_OUT" in
  *"$SHIM_PATH"*) echo "shim path: ok ($SHIM_PATH)" ;;
  *) echo "Stopping: the registered browser-use entry is missing or does not name the shim copy $SHIM_PATH. Re-run /scout:setup." >&2; exit 1 ;;
esac
# An entry without the Python and dependency pins starts on an unsuitable
# interpreter or an incompatible mcp, so it is a failed registration too.
for want in "--python $PYTHON " "--with $MCP_PIN " "--with $PS_PIN "; do
  case "$VERIFY_OUT" in
    *"$want"*) ;;
    *) echo "Stopping: the registered browser-use entry does not carry '${want% }', so the server would not start reproducibly. Re-run /scout:setup." >&2; exit 1 ;;
  esac
done
echo "python and dependency pins: ok ($PYTHON, $MCP_PIN, $PS_PIN)"
# Without the start timeouts a first start that downloads Chrome times out.
# `claude mcp get` lists env as NAME=value, one per line; the trailing newline
# keeps 120 from matching 1200.
for want in "TIMEOUT_BrowserStartEvent=$START_TIMEOUT" "TIMEOUT_BrowserLaunchEvent=$LAUNCH_TIMEOUT"; do
  case "$VERIFY_OUT"$'\n' in
    *"$want"$'\n'*) ;;
    *) echo "Stopping: the registered browser-use entry does not carry '$want', so a first browser start that downloads Chrome would time out. Re-run /scout:setup." >&2; exit 1 ;;
  esac
done
echo "browser start timeouts: ok (${START_TIMEOUT}s start, ${LAUNCH_TIMEOUT}s launch)"
case "$VERIFY_OUT" in
  */plugins/cache/*) echo "Stopping: the registered entry names a path under /plugins/cache/, which the next plugin update deletes. Re-run /scout:setup." >&2; exit 1 ;;
esac
echo
echo "Done. If the entry shows Type: stdio, Command: uvx, the --python, --from and two --with pins + shim path + --mcp args, SCOUT_DEPTH_PROVIDER=anthropic, the two start timeouts, and the two no-cloud env vars, depth is registered. Re-run scout."
