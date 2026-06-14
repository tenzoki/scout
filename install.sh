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
for item in .claude-plugin agents skills stilwerk README.md LICENSE; do
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
case "\${1:-}" in
  --update)
    curl -fsSL "https://raw.githubusercontent.com/$REPO/main/install.sh" -o /tmp/scout-install.sh \
      && bash /tmp/scout-install.sh
    exit \$?
    ;;
  --uninstall)
    rm -rf "\$SCOUT_DIR" "$LAUNCHER"
    echo "scout removed."
    exit 0
    ;;
  --where)
    echo "\$SCOUT_DIR"
    exit 0
    ;;
esac
exec claude --plugin-dir "\$SCOUT_DIR" --agent scout:scout "\$@"
EOF
chmod +x "$LAUNCHER"

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
