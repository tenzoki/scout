# scout — quickstart

scout is a web-research plugin for [Claude Code](https://docs.claude.com/en/docs/claude-code): it runs **discover → fetch → verify** across multiple sources and writes one cited report per run.

It has three layers, and you can stop after the first:

- **Breadth core** (default, zero-dependency) — fires parallel web searches and page fetches with built-in `WebSearch`/`WebFetch`, then cross-verifies every claim. The whole product for most questions.
- **Depth layer** (optional) — drives a real local Chromium browser ([browser-use](https://github.com/browser-use/browser-use)) for pages plain HTTP can't reach (JavaScript-rendered, owned-account logins, interactive interfaces).
- **SearXNG meta discovery** (optional) — discovers URLs through a self-hosted metasearch engine instead of `WebSearch`. A discovery backend only; fetching is unchanged.

For the full detail behind the two optional layers, see the **Optional depth layer (browser-use)** and **Optional metasearch backend (SearXNG)** sections of the [README](README.md).

## Prerequisites

**Always required**
- The [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI (`claude`) on your PATH.

**Breadth core** — nothing else. It works out of the box on built-in `WebSearch`/`WebFetch`. No git, no Node, no Python, no Docker.

**Depth layer (optional)**
- `uvx` — ships with [uv](https://github.com/astral-sh/uv); runs browser-use locally.
- An `ANTHROPIC_API_KEY` — content extraction runs on Anthropic via scout's shim.

**SearXNG meta (optional)**
- **Docker** — Docker Desktop on mac/Windows; runs the SearXNG container. Needed **only** for `scout meta`, never for the default `scout` path.
- `npx` — ships with [Node.js](https://nodejs.org); runs the SearXNG MCP.

**scout itself needs no git** — it installs over plain HTTPS.

## Installation

scout installs into your home folder and drops a `scout` launcher onto your PATH. Nothing system-wide, no plugin-marketplace cache.

**mac / Linux** — paste into your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/tenzoki/scout/main/install.sh | bash
```

Installs to `~/.scout`; launcher at `~/.local/bin/scout`.

**Windows** — paste into cmd.exe or PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/tenzoki/scout/main/install.ps1 | iex"
```

Prefer not to type? Download the repo's `install.cmd` and **double-click it** — it confirms the one prerequisite, then runs the same one-liner.

Installs to `%USERPROFILE%\.scout`; launcher at `%USERPROFILE%\.local\bin\scout.cmd`, added to your **User PATH** automatically (no admin). Open a **new** terminal afterward so the `scout` command is visible everywhere.

## Updating and removing

These work the same on every OS:

- `scout --update` — re-downloads `main` and reinstalls (or just re-run the install one-liner).
- `scout --uninstall` — removes the install dir and the launcher.
- `scout --where` — prints the install dir.

## Starting a run

### Basic (breadth only)

```bash
cd /path/to/any/project
scout
```

Then ask scout a research question. State it fully up front — scout runs autonomously and can't ask clarifying questions mid-run. It writes one cited report into a `scout-workbench/` folder it creates in the current directory, and returns a compact cited summary plus the path.

### Full scope (both optional layers)

First time only, register the add-ons; after that, `scout meta` is all you need.

1. **Export your key before launching.** Inherit mode reads `ANTHROPIC_API_KEY` from the environment of the Claude Code process *at the moment it launches* — so export it first, in the shell you'll launch from:

   ```bash
   export ANTHROPIC_API_KEY=sk-ant-...
   ```

   This is the #1 thing that bites people: if the key isn't live in the launching shell, registration still shows green but the first depth call fails with an opaque auth error. Put the `export` line in a file you source on shell start (kept outside any repo), or pin the key at registration instead.

   > **Heads-up — inherit mode changes session auth.** Exporting `ANTHROPIC_API_KEY` session-wide switches the whole Claude Code session to **API-key auth**, which disables claude.ai-subscription auth and **Remote Control** (some orgs disallow Remote Control by policy). If you rely on either *and* want the depth layer, **pin** the key into the browser-use server instead (`BROWSERUSE_ANTHROPIC_KEY=...` via `/scout:setup`) — then only that server sees the key and your session auth stays untouched. The SearXNG meta backend needs no key, so it never triggers this.

2. **Launch with the meta flag** from your project folder:

   ```bash
   cd /path/to/any/project
   scout meta
   ```

   `scout meta` starts the local SearXNG Docker container, waits for it to report healthy, then launches scout. If Docker is missing or the container fails to come up, it prints the cause and falls back to `WebSearch` — it never hard-fails.

3. **Register the add-ons (first time only).** Inside the session, run:

   ```
   /scout:setup
   ```

   It offers both layers — register either, both, or neither. For browser-use, choose **inherit** so the key never lands in a config file. For SearXNG, no key is needed. The skill stops cleanly and points you at an install page if a prerequisite (`uvx`, `npx`, Docker) is missing.

4. **Restart the session.** MCP servers take effect on restart, so quit and relaunch (`scout meta`) after `/scout:setup`. On the next run scout drives a real browser for pages that need it and discovers URLs through SearXNG.

Plain `scout` (without `meta`) never touches SearXNG, and without the depth layer registered scout simply records any browser-needing page as a gap in the report rather than dropping it — so every layer degrades cleanly to the one below.

### Troubleshooting: `searxng` in multiple scopes

If `/mcp` shows `searxng` failing to connect because it is **defined in multiple scopes with different endpoints**, a stray registration from another project is shadowing scout's. `/scout:setup` registers scout's SearXNG at **user scope** (`npx -y mcp-searxng`); remove the conflicting **project-scope** entry so scout's loads:

```bash
claude mcp remove searxng -s project
```

(If the stray entry were at user scope instead, use `-s user` — but scout's is the user-scope one, so the project-scope entry is normally the one to drop.)

Note: the conflicting entry may be in a **home-level `~/.mcp.json`**, not a per-project one. Claude Code walks **up** from your cwd and treats the nearest `.mcp.json` as the project config, so a `~/.mcp.json` shadows scout's user-scope `searxng` everywhere under your home. `claude mcp remove searxng -s project` targets the **cwd's** `.mcp.json`, not necessarily the loaded one — so a `No MCP server found with name: searxng in .mcp.json` error means the entry lives higher up (usually `~/.mcp.json`). Re-run from there: `cd ~ && claude mcp remove searxng -s project`. (`claude mcp get searxng` shows the scope and which file defines it.)
