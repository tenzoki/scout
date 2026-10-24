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
- **Docker** — Docker Desktop on mac and Windows; runs the SearXNG container. Needed **only** for `scout meta` / `/scout:meta`, never for the default `scout` path.
- `npx` — ships with [Node.js](https://nodejs.org); runs the SearXNG MCP.

**The launcher install needs no git** — it downloads over plain HTTPS. The marketplace install fetches through git.

## Installation

scout installs two ways. Both are supported; pick one.

**Marketplace (primary, every OS)** — inside a Claude Code session:

```
/plugin marketplace add tenzoki/claude-plugins
/plugin install scout@tenzoki-plugins
```

This loads scout in every session where the plugin is enabled: the `scout:scout` agent, `/scout:setup` and `/scout:meta`. It gives you no `scout` shell command, so `scout brief`, `scout --key` and `scout meta` need the launcher. Run scout as the main agent with `claude --agent scout:scout`.

**Launcher (mac / Linux)** — paste into your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/tenzoki/scout/main/install.sh | bash
```

Installs to `~/.scout`; launcher at `~/.local/bin/scout`. Nothing system-wide, nothing inside Claude Code's plugin cache.

**Windows** — there is no Windows launcher. Use the marketplace install, then `/scout:setup` and `/scout:meta` inside a session; they run the same bash scripts as on mac and Linux, under the Git Bash that Claude Code uses on Windows. **This Windows path has not yet been tested on a Windows machine.**

**Two copies, if you install both.** A `scout` launcher session starts Claude Code with `--plugin-dir ~/.scout`, which silently overrides an enabled marketplace copy for that session. The update commands refresh different copies: `scout --update` refreshes `~/.scout` only, `claude plugin update scout@tenzoki-plugins` the marketplace copy only. Keep one install, or update both together.

**State directory.** The depth-layer shim copy and the SearXNG secret and config live outside both copies, in `~/.local/state/scout` (override with `SCOUT_STATE_DIR`), so they survive every update. Both copies share it.

## Updating and removing

**Marketplace:** refresh the listing inside a session with `/plugin marketplace update tenzoki-plugins`, then run `claude plugin update scout@tenzoki-plugins` in your terminal and restart Claude Code. Remove with `claude plugin uninstall scout@tenzoki-plugins`.

**Launcher:**

- `scout --update` — re-downloads `main` and reinstalls into the same place (or just re-run the install one-liner).
- `scout --uninstall` — removes the install dir and the launcher, the SearXNG container, and scout's marked folders in the state directory.
- `scout --where` — prints the install dir.

Neither route removes the MCP registrations, which live in Claude Code's own config; the README's **Remove scout completely** section lists those commands.

## Starting a run

### Basic (breadth only)

```bash
cd /path/to/any/project
scout                      # launcher
claude --agent scout:scout # marketplace install
```

Then ask scout a research question. State it fully up front — scout runs autonomously and can't ask clarifying questions mid-run. It writes one cited report into a `scout-workbench/` folder it creates in the current directory (a dispatching agent can choose another folder with `REPORT DIR`, see the README), and returns a compact cited summary plus the path.

### Wire the depth layer at install time (launcher; keeps your session on subscription auth)

With the launcher, the shortest path to the depth layer is to set `BROWSERUSE_ANTHROPIC_KEY` **before** the install/update one-liner — the installer pins the key into the browser-use MCP server for you, so you skip the `/scout:setup` browser-use step:

```bash
# mac / Linux
BROWSERUSE_ANTHROPIC_KEY=sk-ant-... curl -fsSL https://raw.githubusercontent.com/tenzoki/scout/main/install.sh | bash
```

The key is pinned into the **browser-use MCP server only**, so you do **not** export `ANTHROPIC_API_KEY` in your shell — your scout session stays on claude.ai-subscription/OAuth auth and **Remote Control keeps working**. It's optional (the breadth core needs no key), best-effort (a missing `uvx`/`claude` just warns, the install still succeeds), and leaves any existing registration alone when the var is unset. Rotate by re-running update with the var set (`BROWSERUSE_ANTHROPIC_KEY=sk-ant-new scout --update`). Caveat: the pinned key is stored in plaintext in your user-scope MCP config (`~/.claude.json`). This is the **pin** side of the inherit-vs-pin tradeoff noted below; you can still do it later via `/scout:setup` instead.

### Full scope (both optional layers)

First time only, register the add-ons; after that, `scout meta` (launcher) or `/scout:meta` (any session) is all you need.

1. **Only if you choose inherit mode: export your key before launching.** Skip this step if you pin the key (step 3). Inherit mode reads `ANTHROPIC_API_KEY` from the environment of the Claude Code process *at the moment it launches* — so export it first, in the shell you'll launch from:

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

   With a marketplace install, start your session as usual and run `/scout:meta` instead. Both run the same start script. `scout meta` starts the local SearXNG Docker container, waits for it to report healthy, then launches scout. If Docker is missing or the container fails to come up, it prints the cause and falls back to `WebSearch` — it never hard-fails.

3. **Register the add-ons (first time only).** Inside the session, run:

   ```
   /scout:setup
   ```

   It offers both layers — register either, both, or neither. For browser-use, choose **pin**: only the browser-use server sees the key and your session stays on subscription auth (the trade-off is that the key is stored in plaintext in `~/.claude.json`). Choose **inherit** only if you knowingly run Claude Code with an exported `ANTHROPIC_API_KEY` already (step 1). For SearXNG, no key is needed. The skill stops cleanly and points you at an install page if a prerequisite (`uvx`, `npx`, Docker) is missing.

4. **Restart the session.** MCP servers take effect on restart, so quit and relaunch (`scout meta`, or your usual start plus `/scout:meta`) after `/scout:setup`. On the next run scout drives a real browser for pages that need it and discovers URLs through SearXNG.

SearXNG is used whenever its MCP is registered and the container answers — in plain `scout` runs too, whoever started the container; `docker stop scout-searxng` sends every run back to `WebSearch`. Without the depth layer registered scout simply records any browser-needing page as a gap in the report rather than dropping it — so every layer degrades cleanly to the one below.

### Troubleshooting: `searxng` in multiple scopes

If `/mcp` shows `searxng` failing to connect because it is **defined in multiple scopes with different endpoints**, a stray registration from another project is shadowing scout's. `/scout:setup` registers scout's SearXNG at **user scope** (`npx -y mcp-searxng`); remove the conflicting **project-scope** entry so scout's loads:

```bash
claude mcp remove searxng -s project
```

(If the stray entry were at user scope instead, use `-s user` — but scout's is the user-scope one, so the project-scope entry is normally the one to drop.)

Note: the conflicting entry may be in a **home-level `~/.mcp.json`**, not a per-project one. Claude Code walks **up** from your cwd and treats the nearest `.mcp.json` as the project config, so a `~/.mcp.json` shadows scout's user-scope `searxng` everywhere under your home. `claude mcp remove searxng -s project` targets the **cwd's** `.mcp.json`, not necessarily the loaded one — so a `No MCP server found with name: searxng in .mcp.json` error means the entry lives higher up (usually `~/.mcp.json`). Re-run from there: `cd ~ && claude mcp remove searxng -s project`. (`claude mcp get searxng` shows the scope and which file defines it.)
