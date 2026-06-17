# scout installer — Windows / PowerShell
#
# Installs scout as a Claude Code plugin over plain HTTPS — no SSH, no version
# control client, and no Claude Code plugin marketplace cache. It downloads the
# plugin zip, drops it in %USERPROFILE%\.scout, and installs a `scout` launcher
# that loads the plugin straight from that directory on every run.
#
#   Install / update:  powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tenzoki/scout/main/install.ps1 | iex"
#   Run:               scout
#   Update later:      scout --update
#   Remove:            scout --uninstall
#
# Why this exists: the marketplace path clones over a version-control client
# (breaks when a user's client is configured for SSH or has no key) and its
# cache is not reliably replaced on update/uninstall. This path avoids all of
# that — it is just a download into a folder plus a one-line launcher. The
# `irm | iex` form runs in memory, so it is not blocked by the default
# PowerShell ExecutionPolicy that gates .ps1 files on disk.
#
# Overrides (optional env vars):
#   SCOUT_REF   ref to fetch (default: heads/main; pin a release with
#               SCOUT_REF=tags/v0.2.0)
#   SCOUT_HOME  install dir (default: %USERPROFILE%\.scout)
#   SCOUT_BIN   launcher dir (default: %USERPROFILE%\.local\bin)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # makes Invoke-WebRequest fast

# --- 0. Settings / overrides --------------------------------------------------
$Repo = "tenzoki/scout"
$Ref  = $env:SCOUT_REF;  if (-not $Ref)  { $Ref  = "heads/main" }
$InstallDir = $env:SCOUT_HOME; if (-not $InstallDir) { $InstallDir = Join-Path $HOME ".scout" }
$BinDir     = $env:SCOUT_BIN;  if (-not $BinDir)     { $BinDir     = Join-Path $HOME ".local\bin" }
$Launcher   = Join-Path $BinDir "scout.cmd"
$MetaHelper = Join-Path $BinDir "scout-meta.ps1"
$ZipUrl     = "https://github.com/$Repo/archive/refs/$Ref.zip"

function Say  { param([string]$m) Write-Host $m -ForegroundColor White }
function Warn { param([string]$m) Write-Host $m -ForegroundColor Yellow }
function Die  { param([string]$m) Write-Host $m -ForegroundColor Red; exit 1 }

# --- 1. Preconditions ---------------------------------------------------------
# Only Claude Code is required. scout installs over an HTTPS zip download (see
# below), so there is intentionally no version-control precondition — this
# mirrors install.sh, which checks only for the `claude` CLI.
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Die @"
The Claude Code CLI ('claude') was not found on your PATH.
Install Claude Code first, then re-run this installer:
  https://docs.claude.com/en/docs/claude-code
"@
}

# --- 2. Download + extract over HTTPS (no SSH, no version-control client) -----
Say "Downloading scout ($Ref) over HTTPS..."
$Tmp = Join-Path $env:TEMP ("scout-" + [System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $Tmp -Force | Out-Null
try {
  $Zip = Join-Path $Tmp "scout.zip"
  try {
    Invoke-WebRequest -Uri $ZipUrl -OutFile $Zip -UseBasicParsing
  } catch {
    Die @"
Download failed: $ZipUrl
Check your internet connection and that the ref exists.
"@
  }

  try {
    Expand-Archive -Path $Zip -DestinationPath $Tmp -Force
  } catch {
    Die "Could not extract the archive."
  }

  $Src = Get-ChildItem $Tmp -Directory | Where-Object Name -like 'scout-*' | Select-Object -First 1
  if (-not $Src) {
    Die "Downloaded archive does not look like the scout plugin (no scout-* directory)."
  }
  $Src = $Src.FullName

  $PluginJson = Join-Path $Src ".claude-plugin\plugin.json"
  if (-not (Test-Path $PluginJson)) {
    Die "Downloaded archive does not look like the scout plugin (no .claude-plugin/plugin.json)."
  }

  $Version = (Get-Content $PluginJson -Raw | ConvertFrom-Json).version

  # --- 3. Install into %USERPROFILE%\.scout (atomic-ish replace) --------------
  Say "Installing to $InstallDir ..."
  if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
  New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

  # Copy only the plugin assets — never any dev cruft.
  # Asset list MUST match install.sh:68 exactly:
  #   .claude-plugin agents skills services stilwerk README.md LICENSE
  foreach ($item in @('.claude-plugin', 'agents', 'skills', 'services', 'stilwerk', 'README.md', 'LICENSE')) {
    $srcItem = Join-Path $Src $item
    if (Test-Path $srcItem) {
      Copy-Item -Recurse -Force -Path $srcItem -Destination $InstallDir
    }
  }

  if (-not (Test-Path (Join-Path $InstallDir ".claude-plugin\plugin.json"))) {
    Die "Install copy failed."
  }

  # --- 4. Launcher -----------------------------------------------------------
  if (-not (Test-Path $BinDir)) { New-Item -ItemType Directory -Path $BinDir -Force | Out-Null }

  # scout.cmd launcher body. Mirrors install.sh's bash launcher arms
  # (--update/--uninstall/--where/meta + default dispatch). The `meta` arm
  # delegates to scout-meta.ps1 (written below) then falls through to launch
  # scout — same "start container, then launch scout" flow as install.sh:95-126.
  $launcherBody = @"
@echo off
setlocal
set "SCOUT_DIR=$InstallDir"
set "SCOUT_BIN=$BinDir"
if /i "%~1"=="--update"    ( powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/$Repo/main/install.ps1 | iex" & exit /b )
if /i "%~1"=="--uninstall" ( del /q "%SCOUT_BIN%\scout-meta.ps1" 2>nul & rmdir /s /q "%SCOUT_DIR%" & echo scout removed. & (goto) 2>nul & del /q "%~f0" )
if /i "%~1"=="--where"     ( echo %SCOUT_DIR% & exit /b 0 )
if /i "%~1"=="meta" (
  rem Opt-in metasearch backend: best-effort start the local SearXNG container,
  rem then launch scout with the `meta` token dropped. The helper never
  rem hard-fails (WebSearch fallback on any error); we ignore its exit code by
  rem design. cmd.exe's %* ignores `shift`, so to forward the unbounded verbatim
  rem argument tail (matching install.sh's `shift` + "$@") we split the command
  rem line on the first token: %%a captures `meta`, %%b is the rest verbatim.
  powershell -NoProfile -ExecutionPolicy Bypass -File "%SCOUT_BIN%\scout-meta.ps1"
  for /f "tokens=1*" %%a in ("%*") do claude --plugin-dir "%SCOUT_DIR%" --agent scout:scout %%b
  exit /b
)
claude --plugin-dir "%SCOUT_DIR%" --agent scout:scout %*
"@
  # Write as UTF-8 without BOM — a BOM breaks `@echo off` parsing in cmd.exe.
  [System.IO.File]::WriteAllText($Launcher, $launcherBody, (New-Object System.Text.UTF8Encoding $false))

  # scout-meta.ps1 helper body — the Windows `meta` port of install.sh:95-124.
  # Generates the SearXNG secret_key with PowerShell-native crypto (no external
  # crypto tool), injects it into the INSTALLED settings only, starts the
  # container with `docker compose` (v2), health-waits, and always falls back to
  # WebSearch on any failure. Never hard-fails: it always exits 0 so the launcher
  # proceeds to plain scout. The installed copy's services\searxng paths are
  # absolute here because the helper runs detached from the launcher's %SCOUT_DIR%.
  $metaBody = @"
# scout-meta.ps1 — start the local SearXNG container for the `scout meta`
# discovery backend, then return so the launcher can start scout. Mirrors the
# bash `meta)` arm in install.sh (container scout-searxng, port 8911, compose
# under services\searxng, 30x1s health-wait against http://localhost:8911/).
# Never hard-fails — any problem prints a one-line cause and exits 0, and the
# launcher falls back to WebSearch.
`$ErrorActionPreference = 'Continue'
`$ProgressPreference    = 'SilentlyContinue'

`$ScoutHome = '$InstallDir'
`$Compose   = Join-Path `$ScoutHome 'services\searxng\docker-compose.yml'
`$Settings  = Join-Path `$ScoutHome 'services\searxng\config\settings.yml'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Write-Host 'scout meta: Docker not found — SearXNG cannot start. Falling back to WebSearch.' -ForegroundColor Yellow
  exit 0
}

# Generate a real secret_key into the INSTALLED settings on first start if it is
# still empty/placeholder. Never touches the repo file. Placeholder set matches
# the bash grep -E at install.sh:106 — empty, "", or CHANGE_ME.
if (Test-Path `$Settings) {
  `$lines = Get-Content -Path `$Settings
  `$idx = -1
  for (`$i = 0; `$i -lt `$lines.Count; `$i++) {
    if (`$lines[`$i] -match '^(\s*)secret_key:\s*(""|CHANGE_ME)?\s*`$') { `$idx = `$i; break }
  }
  if (`$idx -ge 0) {
    `$indent = `$Matches[1]
    `$bytes = New-Object byte[] 32
    `$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { `$rng.GetBytes(`$bytes) } finally { `$rng.Dispose() }
    `$hex = -join (`$bytes | ForEach-Object { `$_.ToString('x2') })
    `$lines[`$idx] = "`${indent}secret_key: ""`$hex"""
    # Write BOM-free with LF endings, matching the committed file and the
    # scout.cmd/scout-meta.ps1 writes. Windows PowerShell 5.1's -Encoding UTF8
    # would emit a UTF-8 BOM, diverging byte-for-byte from the bash/sed path.
    [System.IO.File]::WriteAllText(`$Settings, ((`$lines -join "``n") + "``n"), (New-Object System.Text.UTF8Encoding `$false))
  }
}

try {
  docker compose -f `$Compose up -d *> `$null
  if (`$LASTEXITCODE -ne 0) { throw "'docker compose up' failed" }
} catch {
  Write-Host "scout meta: 'docker compose up' failed — falling back to WebSearch." -ForegroundColor Yellow
  exit 0
}

`$ready = `$false
for (`$i = 1; `$i -le 30; `$i++) {
  try {
    Invoke-WebRequest -Uri 'http://localhost:8911/' -UseBasicParsing -TimeoutSec 2 *> `$null
    `$ready = `$true
    break
  } catch {
    Start-Sleep -Seconds 1
  }
}
if (-not `$ready) {
  Write-Host 'scout meta: SearXNG health-wait timed out — falling back to WebSearch.' -ForegroundColor Yellow
}
exit 0
"@
  [System.IO.File]::WriteAllText($MetaHelper, $metaBody, (New-Object System.Text.UTF8Encoding $false))

  # --- 4b. Optional depth-layer key wiring -----------------------------------
  # When $env:BROWSERUSE_ANTHROPIC_KEY is set, pin it into the browser-use MCP
  # server's env block so the depth layer works WITHOUT the user exporting
  # ANTHROPIC_API_KEY in their shell (which would flip the scout session to
  # API-key auth and break claude.ai-subscription auth + Remote Control). The
  # bash register-browser-use.sh does not run on Windows, so we register inline
  # with the `claude` CLI here — mirroring register-browser-use.sh's pinned-mode
  # path exactly (remove-then-add at user scope; the four -e env vars; the
  # --from/python/shim/--mcp args). The key goes via the `claude` CLI into the
  # user-scope MCP config (%USERPROFILE%\.claude.json), never into a repo file;
  # it is briefly visible in the process args (same caveat as the bash pinned
  # path). With the var unset we do NOT touch any existing registration.
  #
  # Best-effort: wrapped in try/catch so a failure (uvx/claude missing, etc.)
  # warns and continues — it never fails the install.
  if ($env:BROWSERUSE_ANTHROPIC_KEY) {
    Say "Wiring the optional depth layer with a pinned Anthropic key..."
    $Shim = Join-Path $InstallDir "services\browser-use-anthropic\scout_browseruse_anthropic.py"
    try {
      # Idempotency: drop any prior user-scope entry first (add refuses to
      # overwrite). Suppress its output/error — a first run has nothing to remove.
      claude mcp remove browser-use -s user 2>$null | Out-Null
      claude mcp add browser-use uvx -s user `
        -e ANTHROPIC_API_KEY=$env:BROWSERUSE_ANTHROPIC_KEY `
        -e SCOUT_DEPTH_PROVIDER=anthropic `
        -e ANONYMIZED_TELEMETRY=False `
        -e BROWSER_USE_VERSION_CHECK=false `
        -- --from "browser-use[cli]@0.11.9" python "$Shim" --mcp
      if ($LASTEXITCODE -ne 0) { throw "claude mcp add exited $LASTEXITCODE" }
      Say "Depth layer registered: browser-use MCP pinned to your Anthropic key (your session stays on subscription auth)."
    } catch {
      Warn "Depth-layer registration did not complete (e.g. uvx/claude missing) — scout's breadth core is installed and works regardless."
      Warn "Re-run with `$env:BROWSERUSE_ANTHROPIC_KEY set, or use /scout:setup, once the prerequisite is in place."
    }
  } else {
    Write-Host "Tip: wire the optional depth layer by setting `$env:BROWSERUSE_ANTHROPIC_KEY before install/update,"
    Write-Host "     e.g.  `$env:BROWSERUSE_ANTHROPIC_KEY='sk-ant-...'; scout --update  (keeps your session on subscription auth)."
  }

  # --- 5. PATH check + add (user scope, no admin) ----------------------------
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $onPath = $false
  if ($userPath) {
    foreach ($seg in $userPath.Split(';')) {
      if ($seg.TrimEnd('\') -ieq $BinDir.TrimEnd('\')) { $onPath = $true; break }
    }
  }

  $verLabel = if ($Version) { "scout $Version installed." } else { "scout installed." }
  Write-Host ""
  Write-Host $verLabel -ForegroundColor White

  if ($onPath) {
    Write-Host "Start it any time with:  scout"
  } else {
    if ($userPath) { $newPath = "$userPath;$BinDir" } else { $newPath = $BinDir }
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    $env:PATH = "$env:PATH;$BinDir"   # update current session immediately
    Warn "$BinDir was added to your user PATH."
    Write-Host "This terminal is already updated — but open a NEW terminal for it to stick everywhere."
    Write-Host "Then start scout with:  scout"
  }
}
finally {
  if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue }
}
