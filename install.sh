#!/usr/bin/env bash
#
# scout installer — macOS / Linux
#
# Installs scout as a Claude Code plugin WITHOUT git, without SSH, and without
# Claude Code's plugin marketplace cache. It downloads the plugin over plain
# HTTPS, drops it in ~/.scout, and installs a `scout` launcher that loads the
# plugin straight from that directory on every run.
#
#   Install / update:  curl -fsSL https://raw.githubusercontent.com/tenzoki/scout/main/install.sh | bash
#   Run:               scout
#   Update later:      scout --update
#   Remove:            scout --uninstall
#
# Depth-layer key (browser-use):
#   Update + pin key:  scout --update --key sk-ant-...
#   Reset key only:    scout --key sk-ant-...        (re-registers depth layer, no re-download)
#   (The equals form scout --key=sk-ant-... works too. The key is exported as
#   BROWSERUSE_ANTHROPIC_KEY and never printed. On a shared machine prefer the
#   env-prefix form  BROWSERUSE_ANTHROPIC_KEY=sk-ant-... scout  — an argv key can
#   appear in shell history and in `ps aux` while the command runs.)
#
# Why this exists: the marketplace path clones over git (breaks when a user's
# git is configured for SSH or has no key) and its cache is not reliably
# replaced on update/uninstall. This path avoids all of that — it is just a
# download into a folder plus a one-line launcher.
#
# Overrides (optional env vars):
#   SCOUT_REF   git ref to fetch (default: heads/main; pin a release with
#               SCOUT_REF=tags/v0.1.0)
#   SCOUT_HOME  install dir (default: ~/.scout)
#   SCOUT_BIN   launcher dir (default: ~/.local/bin)

set -euo pipefail

REPO="tenzoki/scout"
REF="${SCOUT_REF:-heads/main}"
INSTALL_DIR="${SCOUT_HOME:-$HOME/.scout}"
BIN_DIR="${SCOUT_BIN:-$HOME/.local/bin}"
LAUNCHER="$BIN_DIR/scout"
TARBALL_URL="https://github.com/$REPO/archive/refs/$REF.tar.gz"

say()  { printf '\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
die()  { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# --- 1. Preconditions ---------------------------------------------------------
command -v curl >/dev/null 2>&1 || die "curl is required but not found."
command -v tar  >/dev/null 2>&1 || die "tar is required but not found."
if ! command -v claude >/dev/null 2>&1; then
  die "The Claude Code CLI ('claude') was not found on your PATH.
Install Claude Code first, then re-run this installer:
  https://docs.claude.com/en/docs/claude-code"
fi

# --- 2. Download + extract over HTTPS (no git, no SSH) ------------------------
say "Downloading scout ($REF) over HTTPS..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$TARBALL_URL" -o "$TMP/scout.tar.gz" \
  || die "Download failed: $TARBALL_URL
Check your internet connection and that the ref exists."
tar -xzf "$TMP/scout.tar.gz" -C "$TMP" || die "Could not extract the archive."

SRC="$(find "$TMP" -maxdepth 1 -type d -name 'scout-*' | head -1)"
[ -n "$SRC" ] && [ -f "$SRC/.claude-plugin/plugin.json" ] \
  || die "Downloaded archive does not look like the scout plugin (no .claude-plugin/plugin.json)."

VERSION="$(sed -n 's/.*"version" *: *"\([^"]*\)".*/\1/p' "$SRC/.claude-plugin/plugin.json" | head -1)"

# --- 3. Install into ~/.scout (atomic replace) -------------------------------
say "Installing to $INSTALL_DIR ..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
# Copy only the plugin assets — never any dev cruft.
for item in .claude-plugin agents briefing skills services stilwerk README.md LICENSE; do
  [ -e "$SRC/$item" ] && cp -R "$SRC/$item" "$INSTALL_DIR/"
done
[ -f "$INSTALL_DIR/.claude-plugin/plugin.json" ] || die "Install copy failed."

# --- 4. Launcher --------------------------------------------------------------
mkdir -p "$BIN_DIR"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# scout launcher — loads the plugin directly from a folder (no cache, no git).
set -euo pipefail
SCOUT_DIR="$INSTALL_DIR"

# --- Pre-parse: pull out --key <val> / --key=<val> before the command case. ---
# A pinned key is exported as BROWSERUSE_ANTHROPIC_KEY (the var the installer and
# register script already understand) and stripped from the positional args so
# the existing case sees only real commands. The key is NEVER printed.
SCOUT_KEY_GIVEN=0
SCOUT_REMAINING=()
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --key)
      if [ "\$#" -lt 2 ] || [ -z "\${2:-}" ]; then
        echo "scout: --key requires a value" >&2
        exit 2
      fi
      export BROWSERUSE_ANTHROPIC_KEY="\$2"
      SCOUT_KEY_GIVEN=1
      shift 2
      ;;
    --key=*)
      SCOUT_KEY_VAL="\${1#--key=}"
      if [ -z "\$SCOUT_KEY_VAL" ]; then
        echo "scout: --key requires a value" >&2
        exit 2
      fi
      export BROWSERUSE_ANTHROPIC_KEY="\$SCOUT_KEY_VAL"
      SCOUT_KEY_GIVEN=1
      shift
      ;;
    *)
      SCOUT_REMAINING+=("\$1")
      shift
      ;;
  esac
done
# Restore the surviving args (bash 3.2: expanding an empty array under set -u
# is an error, so guard the empty case explicitly).
if [ "\${#SCOUT_REMAINING[@]}" -gt 0 ]; then
  set -- "\${SCOUT_REMAINING[@]}"
else
  set --
fi

# Standalone --key with no other command: instant key reset — re-register the
# depth layer with the new key WITHOUT a full re-download, then exit.
# The call sits in an if: under set -e a bare failing call would end the
# launcher before it could say that the registration failed.
if [ "\$SCOUT_KEY_GIVEN" -eq 1 ] && [ "\$#" -eq 0 ]; then
  if BROWSERUSE_ANTHROPIC_KEY="\$BROWSERUSE_ANTHROPIC_KEY" bash "\$SCOUT_DIR/skills/setup/register-browser-use.sh"; then
    echo "scout: depth layer re-registered with the new key."
    exit 0
  else
    rc=\$?
    echo "scout: depth-layer registration FAILED (exit \$rc); the reason is above. browser-use is not registered with the new key." >&2
    exit \$rc
  fi
fi

case "\${1:-}" in
  --update)
    curl -fsSL "https://raw.githubusercontent.com/$REPO/main/install.sh" -o /tmp/scout-install.sh \
      && bash /tmp/scout-install.sh
    exit \$?
    ;;
  --uninstall)
    rm -rf "\$SCOUT_DIR" "$LAUNCHER"
    # The SearXNG container and scout's user state directory (SearXNG secret and
    # config, the browser-use shim copy) live outside the install; remove them
    # too. Same state-dir rule as the scripts that write it. Only the two
    # subfolders scout writes are removed, and only when they carry the
    # .scout-owned marker those scripts drop into them: the names are generic,
    # and a user-chosen SCOUT_STATE_DIR may hold a folder of the same name that
    # scout never wrote. Under the default directory, which only scout uses, an
    # unmarked folder from before the marker existed counts as scout's. The
    # directory itself goes only through rmdir, which succeeds only when empty.
    docker rm -f scout-searxng >/dev/null 2>&1 || true
    SCOUT_STATE="\${SCOUT_STATE_DIR:-\${XDG_STATE_HOME:-\$HOME/.local/state}/scout}"
    # Collapse repeated slashes and drop a trailing one before comparing, so
    # \$HOME// or /// cannot slip past the root and home guard.
    SCOUT_STATE="\$(printf '%s' "\$SCOUT_STATE" | sed -e 's#//*#/#g' -e 's#\(.\)/\$#\1#')"
    SCOUT_HOME_N="\$(printf '%s' "\$HOME" | sed -e 's#//*#/#g' -e 's#\(.\)/\$#\1#')"
    if [ -z "\${SCOUT_STATE_DIR:-}" ]; then SCOUT_STATE_DEFAULT=1; else SCOUT_STATE_DEFAULT=0; fi
    case "\$SCOUT_STATE" in
      /|"\$SCOUT_HOME_N") echo "scout: not touching state directory '\$SCOUT_STATE' (refusing a root or home path)." >&2 ;;
      */plugins/cache|*/plugins/cache/*) echo "scout: not touching state directory '\$SCOUT_STATE' (it lies inside the plugin cache)." >&2 ;;
      /?*)
        for SCOUT_SUB in browser-use-anthropic searxng; do
          SCOUT_P="\$SCOUT_STATE/\$SCOUT_SUB"
          [ -e "\$SCOUT_P" ] || [ -L "\$SCOUT_P" ] || continue
          if [ -f "\$SCOUT_P/.scout-owned" ] || { [ "\$SCOUT_STATE_DEFAULT" -eq 1 ] && [ -d "\$SCOUT_P" ]; }; then
            echo "scout: removing \$SCOUT_P"
            rm -rf "\$SCOUT_P"
          else
            echo "scout: leaving \$SCOUT_P in place: it has no .scout-owned marker, so scout did not write it (or wrote it before scout added the marker). Remove it yourself if it is scout's." >&2
          fi
        done
        rmdir "\$SCOUT_STATE" 2>/dev/null || true
        ;;
      *) echo "scout: not touching state directory '\$SCOUT_STATE' (not an absolute path)." >&2 ;;
    esac
    echo "scout removed. A registered browser-use MCP entry stays until you run: claude mcp remove browser-use -s user"
    echo "A marketplace copy of scout (scout@tenzoki-plugins) shares this state directory: re-run /scout:setup there to restore its depth layer."
    exit 0
    ;;
  --where)
    echo "\$SCOUT_DIR"
    exit 0
    ;;
  brief)
    # Unattended briefing run. exec, not a call: the orchestrator replaces this
    # launcher process, so its three-valued exit code (0 briefing written,
    # 1 merge produced none, 2 stopped before a briefing was possible) reaches
    # whatever started it unchanged rather than through a wrapper that could
    # remap it. The orchestrator resolves the profile path and anchors the run
    # in the profile's own directory, so nothing is resolved here.
    # SCOUT_BRIEF_MAX_USD and the rest of the environment pass through
    # untouched.
    shift
    exec bash "\$SCOUT_DIR/briefing/scout-brief.sh" "\$@"
    ;;
  meta)
    # Opt-in metasearch backend: start the local SearXNG container, then fall
    # through to launch scout. Never registers the MCP (that is /scout:setup's
    # job) and never hard-fails — any failure falls back to WebSearch. The start
    # script keeps its secret and rendered config in scout's user state
    # directory, never in this install (which --update replaces).
    bash "\$SCOUT_DIR/services/searxng/start-searxng.sh" || echo "scout meta: falling back to WebSearch." >&2
    shift
    ;;
esac
exec claude --plugin-dir "\$SCOUT_DIR" --agent scout:scout "\$@"
EOF
chmod +x "$LAUNCHER"

# --- 4b. Optional depth-layer key wiring -------------------------------------
# When BROWSERUSE_ANTHROPIC_KEY is set, pin it into the browser-use MCP server's
# env block so the depth layer works WITHOUT the user exporting ANTHROPIC_API_KEY
# in their shell (which would flip the scout session to API-key auth and break
# claude.ai-subscription auth + Remote Control). The key goes only into the
# browser-use MCP child process via the user-scope MCP config — never into a repo
# file. With the var unset, install/update behaves exactly as before and does NOT
# touch any existing browser-use registration.
#
# Best-effort + set -e guard: register-browser-use.sh can exit non-zero (uvx
# missing, etc.). We capture the exit code in an `if` condition so its failure
# can never abort this installer under `set -e`/`set -o pipefail`.
if [ -n "${BROWSERUSE_ANTHROPIC_KEY:-}" ]; then
  say "Wiring the optional depth layer with a pinned Anthropic key..."
  if BROWSERUSE_ANTHROPIC_KEY="$BROWSERUSE_ANTHROPIC_KEY" bash "$INSTALL_DIR/skills/setup/register-browser-use.sh"; then
    say "Depth layer registered: browser-use MCP pinned to your Anthropic key (your shell stays on subscription auth)."
  else
    warn "Depth-layer registration FAILED (the reason is above; e.g. uvx missing, or 'claude mcp add' failed) — browser-use is not registered. scout's breadth core is installed and works regardless."
    warn "Re-run with BROWSERUSE_ANTHROPIC_KEY set, or use /scout:setup, once the prerequisite is in place."
  fi
else
  echo "Tip: wire the optional depth layer by setting BROWSERUSE_ANTHROPIC_KEY before install/update,"
  echo "     e.g.  BROWSERUSE_ANTHROPIC_KEY=sk-ant-... scout --update  (keeps your session on subscription auth)."
fi

# --- 5. PATH check ------------------------------------------------------------
say "scout ${VERSION:-} installed."
case ":$PATH:" in
  *":$BIN_DIR:"*)
    echo "Start it any time with:  scout"
    ;;
  *)
    warn "$BIN_DIR is not on your PATH yet."
    echo "Add it once (zsh):"
    echo "  echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
    echo "Then start scout with:  scout"
    echo "(Or run it now with the full path: $LAUNCHER)"
    ;;
esac
