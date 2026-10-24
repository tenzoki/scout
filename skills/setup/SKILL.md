---
description: Set up scout's optional add-ons by registering their MCP servers, so a non-technical user does not hand-edit Claude Code's MCP config. Covers two optional layers — the browser-use depth layer (interactive browsing) and the SearXNG meta discovery backend (self-hosted metasearch). Invoke when the user wants to "set up scout depth", "enable interactive browsing", "register browser-use", "turn on the depth layer", "let scout drive a real browser", "set up scout meta", "enable SearXNG", or "register the metasearch backend". The SearXNG container itself is started separately, with `scout meta` in a shell or `/scout:meta` in a Claude Code session. browser-use registers a local Chromium stack pinned to the tested version with both no-cloud env vars and the Anthropic key from BROWSERUSE_ANTHROPIC_KEY in the environment, never one typed into the chat (extraction runs on Anthropic via scout's shim); SearXNG registers the self-hosted metasearch MCP (no key). Idempotent and non-destructive — both layers are entirely OPTIONAL; scout works breadth-only with WebSearch without either.
allowed-tools: [Bash, Read, AskUserQuestion]
---

# /scout:setup — register scout's optional add-ons (browser-use depth layer, SearXNG meta backend)

This skill registers scout's optional MCP-backed add-ons. There are two, and they are independent — register either, both, or neither:

- **browser-use depth layer** — a real local Chromium browser for pages the breadth layer cannot reach over plain HTTP (JavaScript-rendered content, owned-account logins, interactive interfaces). Covered in the steps immediately below.
- **SearXNG meta discovery backend** — a self-hosted metasearch engine scout uses to *discover* URLs instead of the built-in `WebSearch`. Covered in **Optional: register the SearXNG meta backend** near the end.

Ask the user which they want (or offer both). The two paths share nothing except this skill's voice and the remove-then-add discipline. The browser-use path below is unchanged; the SearXNG path is opt-in, discovery-only, and needs no key.

## browser-use depth layer

This registers the **browser-use** MCP server so scout can drive a real local Chromium browser for pages the breadth layer cannot reach over plain HTTP (JavaScript-rendered content, owned-account logins, interactive interfaces).

**Depth is optional.** scout runs fine breadth-only. Without depth registered, scout records any page that genuinely needs an interactive browser as a "needs depth tools" gap in its report's blocked-sources table — it never silently drops a source. Run this skill only if you actually hit such pages.

The skill is **idempotent** and **non-destructive**: if `browser-use` is already registered, re-running removes the old user-scope entry and re-adds it with the tested pin and env vars (so a stale or broken registration is cleanly replaced); it never touches a server you registered at another scope, never deletes a project file, and never writes your Anthropic key into the repo.

The registration mechanics — the pin `browser-use[cli]@0.11.9`, both no-cloud env vars, the remove-then-add, and the verify — live in **one place**: `${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh`. This skill drives the conversation and the key decision, then invokes that script. The script is the single source of truth for the registration command, so the pin and env vars are never duplicated in prose here. A technical user can also run the script directly without this skill.

Apply scout's short-form voice for everything you say to the user: read `${CLAUDE_PLUGIN_ROOT}/stilwerk/chat-voice-en.yaml` (or the target-language variant) and follow its intent — action-first, second person, plain words, no AI stock phrases. If no variant exists for the user's language, read the `-en` file and apply its intent in that language.

## Step 1 — State what this does, plainly

Tell the user, up front:

- This registers a local browser-use server so scout can drive a real Chromium browser when a page needs it.
- Depth is optional. scout already works breadth-only; this only adds the interactive-browser path.
- The browser runs entirely on their machine. No browser-use hosted cloud service. The only outbound call the depth layer makes is an ordinary Anthropic LLM call for content extraction (Step 3), which runs on Anthropic via scout's shim.
- Nothing installs silently. If a prerequisite is missing, the skill stops and points them at the install page.

## Step 2 — Check prerequisites (stop cleanly if missing)

The script checks prerequisites itself and stops cleanly if either is missing, but check here too so you can explain the fix in scout's voice before handing off:

```bash
command -v claude >/dev/null 2>&1 && echo "claude: ok" || echo "claude: MISSING"
command -v uvx    >/dev/null 2>&1 && echo "uvx: ok"    || echo "uvx: MISSING"
```

- If `claude` is missing: stop. Tell the user the Claude Code CLI is not on their PATH and point them at https://docs.claude.com/en/docs/claude-code. Do not continue.
- If `uvx` is missing: stop. `uvx` ships with **uv**. Point them at https://github.com/astral-sh/uv to install uv (which provides `uvx`), then re-run `/scout:setup`. Do not install anything for them.

Only continue when both report `ok`.

If the server is already registered, the script removes the old user-scope entry and re-adds it with the tested config (the CLI's `add`/`add-json` refuse to overwrite an existing server, so a clean remove-then-add is what makes the re-run replace it) — say so and continue:

```bash
claude mcp get browser-use >/dev/null 2>&1 && echo "browser-use: already registered (will re-register with the tested pin)" || echo "browser-use: not yet registered"
```

## Step 3 — Find the Anthropic key (presence only; the key never enters this conversation)

The depth layer's extraction tool, `browser_extract_content` (turn a page into structured text), calls an LLM. scout's shim runs that call on Anthropic, so it needs an Anthropic API key. This is an ordinary external LLM call, the same kind scout already makes; it is not a "no cloud" violation (the no-cloud rule bans browser-use's hosted *service*, not external LLMs). The last-resort `retry_with_browser_use_agent` loop stays OpenAI/Bedrock-only upstream — the shim patches extraction, not the agent loop — so reaching for it still needs an OpenAI or Bedrock key.

**The key never passes through this conversation.** Never ask for it, never offer to take it, never read it back, never print it — not its value, not its length, not a prefix. The key comes from `BROWSERUSE_ANTHROPIC_KEY` in the environment, and the script reads it from there. If the user pastes a key into the chat anyway: tell them not to, do not use it in any command, and suggest they rotate it in the Anthropic console, because it now sits in the transcript.

Check which variables are set, **presence only** (these lines cannot print a value):

```bash
[ -n "${BROWSERUSE_ANTHROPIC_KEY:-}" ] && echo "BROWSERUSE_ANTHROPIC_KEY: set" || echo "BROWSERUSE_ANTHROPIC_KEY: unset"
[ -n "${ANTHROPIC_API_KEY:-}" ] && echo "ANTHROPIC_API_KEY: set" || echo "ANTHROPIC_API_KEY: unset"
```

This shows the environment of *this Claude Code session*, which can differ from the user's own shell (a variable set in a profile this session did not source, a shell inside a container, a session started from an app). Say so when the result surprises the user.

Decide, then carry it into Step 4:

- **`BROWSERUSE_ANTHROPIC_KEY: set` → pinned path (the default).** The script pins that key into the browser-use server's user-scope MCP config. No question to ask.
- **`BROWSERUSE_ANTHROPIC_KEY: unset` → do not register the depth layer from here.** Hand the user the command to run **themselves, in their own shell** where the variable is set (possibly inside a container). Write `${CLAUDE_PLUGIN_ROOT}` out as the real absolute path, not the variable (run `printf '%s\n' "${CLAUDE_PLUGIN_ROOT}"` if you need it):

  ```bash
  bash "<absolute plugin root>/skills/setup/register-browser-use.sh"
  ```

  With the launcher install, `scout --key "$BROWSERUSE_ANTHROPIC_KEY"` does the same. Either way the shell expands the variable, so the key is never typed out. Then they restart Claude Code. If the variable is not set anywhere yet, tell them to set `BROWSERUSE_ANTHROPIC_KEY` in that shell first — not `ANTHROPIC_API_KEY` (see below). The SearXNG path needs no key and is unaffected.
- **`ANTHROPIC_API_KEY: set`** changes none of the above. Tell the user plainly: with `ANTHROPIC_API_KEY` in its launch environment, Claude Code itself runs on API-key auth and API billing, not their subscription. scout does not use that variable unless they explicitly ask for inherit mode.

**Inherit mode — only on explicit request.** The script still supports `BROWSERUSE_INHERIT=1`: no key is written to the config, and the browser-use server reads `ANTHROPIC_API_KEY` from the environment of the Claude Code process when it starts. Offer it only when the user asks for it, and warn first: **`ANTHROPIC_API_KEY` in the environment that launches Claude Code switches Claude Code itself to API billing** (and off subscription auth and Remote Control). The key must also be in that environment *before* Claude Code launches; exporting it inside a running session is too late. Never recommend exporting `ANTHROPIC_API_KEY` in a shell profile.

Whichever path: never write the key into any file in the repo, and never put it in a commit.

## Step 4 — Register the server (invoke the script)

Invoke the single-source-of-truth script. It removes any existing user-scope `browser-use`, adds it fresh under the **exact** name `browser-use` (coupled to scout's allow-list: scout's tools are `mcp__browser-use__browser_navigate`, `mcp__browser-use__browser_get_state`, and so on — a different name means scout silently falls back to breadth-only), at **user scope** so depth works from any project directory, with the tested pin and both mandatory no-cloud env vars baked in, and then verifies.

**Pinned path** (`BROWSERUSE_ANTHROPIC_KEY: set` in Step 3). The script reads the key from the inherited environment, so the command line carries no key. `BROWSERUSE_INHERIT=` clears a stray inherit setting so the script takes the pinned branch:

```bash
BROWSERUSE_INHERIT= bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh"
```

Never write the key, or a placeholder for it, into the command. The script masks the key in everything it prints.

**Inherit path** (only when the user explicitly asked for it, after the billing warning in Step 3):

```bash
BROWSERUSE_INHERIT=1 bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-browser-use.sh"
```

Read the script's inherit notice and any WARNING to the user in scout's voice; do not bury them.

The script prints its own prerequisite, registration, and verification output.

The script copies the shim out of this plugin copy into scout's state directory, `${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}`, and registers that copy. A plugin update replaces the plugin tree, so the registration must never name a file inside it. Whenever a scout release changes the registered command — the shim, the browser-use pin, or any other argument — the user re-runs `/scout:setup` (or `scout --key "$BROWSERUSE_ANTHROPIC_KEY"`) to refresh the copy and the registration.

**Fallback — if the script cannot run in this environment** (e.g. the CLI registration forms fail in this Claude Code version): first run the ownership check (the first shell line below, the same condition `register-browser-use.sh` applies before it writes). If it prints `Stopping:`, run none of the other lines: tell the user that folder exists and was not written by scout, and that they should move it aside or set `SCOUT_STATE_DIR` to another directory. Only when it prints `ownership check: ok`, create the shim copy with the other three lines (the last writes the `.scout-owned` marker the script writes, without which `scout --uninstall` leaves the folder in a custom `SCOUT_STATE_DIR`), then print the exact JSON `mcpServers` block for the user to paste into their MCP settings by hand, and tell them plainly that you are falling back to the manual paste because the scripted registration was unavailable:

```bash
D="${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/browser-use-anthropic"; if [ -e "$D" ] && [ ! -f "$D/.scout-owned" ] && ! { [ -d "$D" ] && { [ -z "$(ls -A "$D" 2>/dev/null)" ] || [ -z "${SCOUT_STATE_DIR:-}" ] || [ -f "$D/scout_browseruse_anthropic.py" ]; }; }; then echo "Stopping: $D exists and was not written by scout (no .scout-owned marker). Move it aside or set SCOUT_STATE_DIR to another directory." >&2; false; else echo "ownership check: ok"; fi
mkdir -p "${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/browser-use-anthropic"
cp "${CLAUDE_PLUGIN_ROOT}"/services/browser-use-anthropic/scout_browseruse_anthropic.py "${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/browser-use-anthropic/"
[ -f "${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/browser-use-anthropic/.scout-owned" ] || printf '%s\n' "Written by scout (register-browser-use.sh). scout --uninstall removes this folder only while this file is here." > "${SCOUT_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/scout}/browser-use-anthropic/.scout-owned"
```

In the JSON, replace `<state dir>` with the absolute path that state directory expands to (by default `$HOME/.local/state/scout`, written out in full):

```json
{
  "mcpServers": {
    "browser-use": {
      "command": "uvx",
      "args": [
        "--python", "3.12",
        "--from", "browser-use[cli]@0.11.9",
        "--with", "mcp==1.30.0",
        "--with", "pydantic-settings==2.16.1",
        "python", "<state dir>/browser-use-anthropic/scout_browseruse_anthropic.py",
        "--mcp"
      ],
      "env": {
        "ANTHROPIC_API_KEY": "<your own Anthropic API key>",
        "SCOUT_DEPTH_PROVIDER": "anthropic",
        "ANONYMIZED_TELEMETRY": "False",
        "BROWSER_USE_VERSION_CHECK": "false"
      }
    }
  }
}
```

Do not guess a different registration command. Use the script, or the manual JSON block.

## Step 5 — Confirm the registration took

The script ends by running `claude mcp get browser-use` and printing the result. Read its output: it should show `Type: stdio`, `Command: uvx`, args including `--python 3.12`, `--from`, `browser-use[cli]@0.11.9`, `--with mcp==1.30.0`, `--with pydantic-settings==2.16.1`, the shim path `<state dir>/browser-use-anthropic/scout_browseruse_anthropic.py` (by default `~/.local/state/scout/browser-use-anthropic/scout_browseruse_anthropic.py`, never a path under `~/.claude/plugins/cache/` or inside `~/.scout`), and `--mcp`, and the env carrying `SCOUT_DEPTH_PROVIDER`, `ANONYMIZED_TELEMETRY`, and `BROWSER_USE_VERSION_CHECK`. The script masks any `ANTHROPIC_API_KEY` value as `<redacted>`; never try to recover or print it. The script exits non-zero when `claude mcp add` failed, when the verified entry is missing, does not name the shim copy or lacks one of the three pins above, or when it names a path under `/plugins/cache/` (a file a plugin update deletes). Read the exit code: on non-zero, the registration did not take — report the script's `Stopping:` line and stop so the user can retry, rather than reporting a false success. Note that the old entry is removed before the add, so a failed add leaves no browser-use registration at all.

On success, tell the user: depth is registered. Re-run scout — pages that need an interactive browser will now be driven in a real local Chromium, and depth findings will carry the `depth (browser-use, manual drive)` method tag in the report. Restart Claude Code so the new registration loads. If they registered via inherit at their explicit request, remind them once that the depth layer then only works when `ANTHROPIC_API_KEY` is live in the shell that launches Claude Code — a green registration alone does not prove the key is reachable — and that the same variable puts Claude Code itself on API billing.

## Step 6 — Set expectations honestly (no captcha; foreground handoff)

Be clear-eyed, so the user is not surprised later:

- **No captcha-solving.** Nothing in this local, no-cloud setup reliably defeats a modern captcha. That capability was given up by choosing local browser-use over the hosted cloud. scout caps captcha effort at a few steps and moves on.
- **Foreground handoff for walls.** When scout hits a captcha, login, hard 403, or interstitial on an essential source, it does not silently drop it. It returns a blocked-sources block naming the URL, the wall type, and what a human must do. You clear the wall live in a foreground browser-use session (the persistent local Chromium profile at `~/.config/browseruse/profiles/default` captures the authenticated state), then re-run scout to reach the now-unlocked source.

Point the user at the README's **Optional depth layer (browser-use)** section for the full handoff write-up. Do not re-narrate the whole thing here.

## Optional: register the SearXNG meta backend

This path is fully independent of browser-use. Run it when the user wants scout to discover URLs through a **self-hosted SearXNG metasearch engine** instead of the built-in `WebSearch`. Apply the same scout voice as above.

**State what it is, plainly.** SearXNG is scout's **opt-in discovery backend** — it finds URLs. It is **not** a fetcher: `WebFetch` and the depth layer still do all content fetching. scout works fine without it (default discovery is `WebSearch`), so this is purely additive. It is **self-hosted** and needs **no API key** — the skill collects nothing secret for SearXNG. There are two coupled pieces: this skill **registers the MCP**, and `scout meta` (in a shell) or `/scout:meta` (in a Claude Code session) **starts the local SearXNG container**. Both are needed for scout to actually use it; if the MCP is registered but the container is not running (neither `scout meta` nor `/scout:meta` run), scout's reachability probe fails and it falls back to `WebSearch` cleanly.

**Check prerequisites (stop cleanly if missing).** SearXNG registration needs `npx` (from Node) for the MCP runner, and Docker to actually run the container via `scout meta` or `/scout:meta`:

```bash
command -v claude >/dev/null 2>&1 && echo "claude: ok" || echo "claude: MISSING"
command -v npx    >/dev/null 2>&1 && echo "npx: ok"    || echo "npx: MISSING"
command -v docker >/dev/null 2>&1 && echo "docker: ok" || echo "docker: MISSING (needed for 'scout meta' or /scout:meta to start the container)"
```

- If `claude` or `npx` is missing: stop. `npx` ships with Node.js — point the user at https://nodejs.org. Do not continue registration.
- If `docker` is missing: the MCP can still be registered, but tell the user plainly that neither `scout meta` nor `/scout:meta` can start the container until Docker is installed (https://docs.docker.com/get-docker), so scout will fall back to WebSearch until then. Let the user decide whether to register now or install Docker first.

**Register the server (invoke the script).** The registration mechanics — the `mcp-searxng` pin, the `SEARXNG_URL`, the remove-then-add, the verify — live in one place: `${CLAUDE_PLUGIN_ROOT}/skills/setup/register-searxng.sh`. Drive it the same way you drive the browser-use script. It writes no secret:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/setup/register-searxng.sh"
```

The script removes any existing user-scope `searxng`, adds it fresh under the **exact** name `searxng` (coupled to the prefix `mcp__searxng__` of scout's allow-listed tool `mcp__searxng__searxng_web_search` — a different name means scout silently falls back to WebSearch), at user scope, with `SEARXNG_URL=http://localhost:8911`, then verifies with `claude mcp get searxng`.

**Confirm and set expectations.** Read the script's verify output: it should show `Type: stdio`, `Command: npx`, the pinned `mcp-searxng` arg, and `SEARXNG_URL`. The script also runs a `== scope-conflict check ==` step — if it prints a WARNING that another `searxng` registration is shadowing scout's, surface that warning to the user in scout's voice the same way you surface the browser-use script output: name the conflicting scope/endpoint the script reports and give the fix command `claude mcp remove searxng -s project` (or `-s local`), keeping scout's user-scope entry. A `searxng` that is registered but failing to connect because of a scope conflict is **not** a success — do not report it as one; relay the warning and the fix, and let the user clear the conflict before re-running. On success (no conflict), tell the user: the meta backend is registered. Start scout with `scout meta` (not plain `scout`), or run `/scout:meta` in a Claude Code session, so the SearXNG container comes up; scout then discovers URLs through SearXNG and each discovered source carries a `discovery: searxng` note in the report. If they run plain `scout` without having started the container another way, or if the container is not up, scout discovers with WebSearch — no failure either way. Once the container is up, every run uses it, plain `scout` and dispatches from other agents included; `docker stop scout-searxng` sends every run back to WebSearch. Point them at the README's **Optional metasearch backend (SearXNG)** section for the full picture.

## Optional: scope scout's shell access to the commands it runs

scout's agent definition grants the `Bash` tool, but it never needs arbitrary shell. This is everything it runs:

- **Every run:** `printenv SCOUT_FILE_PREFIX` (to read the filename-prefix override, if one is set), `date` (to stamp the report's date-time, sourced from the machine rather than guessed), `mkdir -p scout-workbench/research/` or the `REPORT DIR` folder (to create the report directory), and `pwd` (to report the report's absolute path back).
- **Briefing runs only** (`scout brief`): `date +%s` (to measure the time budget), the ledger retriever `briefing/ledger-retrieve.sh`, and `curl` (to fetch each host's `robots.txt`).

Claude Code does **not** let a plugin ship a permission allowlist that binds a dispatched agent's own `Bash` calls — permission rules are read from the `settings.json` precedence chain in the directory where you launch `scout` (enterprise → `~/.claude/settings.json` → the project's `.claude/settings.json` → `.claude/settings.local.json`), not from anything inside `~/.scout`. So the scoping is something **you** add to the project (or your home) settings, and this skill recommends it rather than installing it.

To hold scout to the commands of a normal run, add this to your project's `.claude/settings.json` (or `~/.claude/settings.json` to apply it to every project):

```json
{
  "permissions": {
    "allow": [
      "Bash(printenv SCOUT_FILE_PREFIX)",
      "Bash(date:*)",
      "Bash(mkdir:*)",
      "Bash(pwd)"
    ]
  }
}
```

With this in place, scout's `printenv SCOUT_FILE_PREFIX`, `date`, `mkdir` and `pwd` calls run without a prompt, and any other shell command (a `cat`, an `rm`) falls outside the allowlist — Claude Code prompts you before it runs, so nothing arbitrary executes silently. If briefings run under these settings, also allow `Bash(curl:*)` and the retriever. To make the boundary a hard wall, add a `deny` list as well (e.g. `"deny": ["Bash(rm:*)"]`), which Claude Code refuses outright. **Do not deny `curl` where briefings run:** scout then cannot read any host's `robots.txt`, so it fetches nothing from hosts it could not check and lists them in the report as blocked.

**Known gap, stated plainly:** without this snippet, scout still only *calls* the commands above — but Claude Code may prompt you to approve a broader `Bash` permission, and approving it grants more than scout uses. The allowlist is the way to keep scout's shell access scoped to the commands it actually runs. This is a recommendation, not an automatic install, because no plugin-level mechanism can apply it for you.

## What this skill does NOT do

- Does not install `uv`/`uvx`, `npx`/Node, Docker, Claude Code, or a browser — it only checks and points at the install page if missing.
- Does not ask for, accept, print or commit your Anthropic key, and never writes it into a repo file. It reads `BROWSERUSE_ANTHROPIC_KEY` from the environment or hands you the command to run in your own shell. The SearXNG path writes no secret at all.
- Does not start the SearXNG container — that is the job of `scout meta` (in a shell) or `/scout:meta` (in a Claude Code session). This skill only registers the MCP.
- Does not change scout's agent, plugin manifest, or style profiles.
- Does not register anything if a prerequisite is missing — it stops cleanly.
