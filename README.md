# scout

A web-research plugin for [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview). You give scout a fully-specified research question; it runs multi-source web research with inline cross-source verification and writes **one cited report file** per run. It returns to you only a compact cited summary plus the path to that report.

The plugin is named **scout**; its single AI agent is also named **scout** (dispatch with `claude --agent scout:scout`).

scout was carved out of [flight](https://github.com/tenzoki/flight) so that research's context-firehose traffic — dozens of search results and fetched pages — stays out of a working conversation. You run scout in its own session, get one report file, and hand that file to flight's `pilot` for synthesis. Same family.

## The two-layer model

scout has two layers, and you can stop after the first:

- **Breadth (works immediately).** No setup beyond installing the plugin. scout fires parallel web searches and page fetches, reads the results together, and cross-verifies each claim across sources over plain HTTP. This is the whole product for most questions.
- **Depth (optional, registered separately).** An add-on for pages that genuinely need an interactive browser (JavaScript-rendered content, owned-account logins). It is a separate MCP server you register yourself; until you do, scout runs breadth-only and flags any depth-needing page as a gap in the report rather than silently dropping it. See **Optional depth layer (browser-use)** below.

A user who never registers the depth layer keeps a fully working breadth research plugin.

## What scout produces

scout writes one cited report per run to `scout-workbench/research/<prefix>-<topic>.md` and returns a compact summary plus that path. The report is structured so every claim is auditable: **claim → sources → method → confidence → verification**, followed by a blocked-sources table and the full list of sources consulted.

scout returns only the compact summary inline — never the full report — so your calling session does not get re-flooded with the research traffic. That session-isolation is scout's whole reason to exist.

### Hand the report to flight's pilot

The intended flow is a bring-a-document handoff:

1. Run scout on a fully-specified question. It writes the report and prints the path.
2. Open that report file in [flight](https://github.com/tenzoki/flight)'s `pilot` agent (`claude --agent flight:pilot`) and discuss, summarize, or draft from it.

scout does the research; pilot does the synthesis.

## Specify the question fully before you run

**scout cannot ask you clarifying questions mid-run.** It runs autonomously from the moment you dispatch it. So state the full question up front: scope, constraints, language, any source preferences or exclusions, and how deep to go. If the question is under-specified, scout does its best and records the ambiguity in the report rather than stalling — but a tighter question gets a tighter report.

## Quick start (recommended — one line, no git)

In your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/tenzoki/scout/main/install.sh | bash
```

This downloads scout over plain HTTPS into `~/.scout` and installs a `scout`
launcher. No git, no SSH, no Claude Code marketplace. Then, in any project folder:

```bash
scout          # starts Claude Code with the scout agent loaded
```

- **Update:** `scout --update` (or re-run the one-liner above).
- **Uninstall:** `scout --uninstall`.
- **Where it lives:** `scout --where` (prints the install dir).

### Where scout installs

The one-line installer writes to exactly two places — both in your home folder, nothing system-wide and nothing inside Claude Code's plugin cache:

```
~/.local/bin/scout      the `scout` command (a thin launcher script)
~/.scout/               the plugin files: .claude-plugin/, agents/,
                        stilwerk/, README, LICENSE
```

The launcher is one line — `claude --plugin-dir ~/.scout --agent scout:scout "$@"` — so every run loads the plugin straight from `~/.scout`. That is why update and uninstall are reliable: there is no cache to get out of sync. `scout --where` prints the plugin path any time.

Both locations are overridable with environment variables before installing:

- `SCOUT_HOME` — where the plugin files go (default `~/.scout`)
- `SCOUT_BIN` — where the `scout` launcher goes (default `~/.local/bin`)

To remove scout completely: `scout --uninstall` (which is just `rm -rf ~/.scout` plus removing the launcher). Claude Code's own `~/.claude/` directory is never touched.

### Alternative: Claude Code marketplace

If you prefer the built-in plugin system (note: it uses git, which can fail when your git is configured for SSH):

```bash
/plugin marketplace add tenzoki/claude-plugins
/plugin install scout@tenzoki-plugins
```

(Registering scout in that marketplace is out of scope for this build; the one-line installer above is the supported path today.)

## Where the report lands

Every run writes exactly one report to:

```
scout-workbench/research/<prefix>-<topic>.md
```

`scout-workbench/` is scout's runtime workbench, created in your project on the first run (scout runs `mkdir -p scout-workbench/research/` itself). It is gitignored by the plugin source tree but lives in *your* project — keep it or commit it as you see fit.

The `<prefix>` is a date-time stamp. The default renders as `YYYY-MM-DD_HH-MM` (e.g. `2026-06-14_13-45`). You can override it by setting the environment variable `SCOUT_FILE_PREFIX` to a `date(1)` strftime string — e.g. `export SCOUT_FILE_PREFIX='%Y%m%d-%H%M%S'` for full-year + seconds precision. Default keeps existing reports sorting consistently; change it only on a clean project.

## Optional depth layer (browser-use)

The depth layer lets scout drive a **real local Chromium browser** for pages the breadth layer cannot reach over plain HTTP: JavaScript-rendered content, owned-account logins, interactive interfaces. It is the [browser-use](https://github.com/browser-use/browser-use) stack, run locally and exposed to scout as an MCP server.

It is **entirely optional**. If you never register it, scout runs breadth-only and records any page that genuinely needs an interactive browser as a "needs depth tools" gap in the report's blocked-sources table — never silently dropped. Register it only if you actually hit such pages.

### Register the MCP server

**Easiest path:** run the `/scout:setup` skill. It registers the server for you with the `0.11.9` pin and both no-cloud env vars baked in, checks `uvx`, and prompts for your OpenAI key (it never writes the key into the repo). The manual JSON block below is the alternative if you would rather edit your MCP settings yourself.

Add this to your Claude Code MCP settings. It runs browser-use locally via `uvx`, pinned to the version scout is tested against:

```json
{
  "mcpServers": {
    "browser-use": {
      "command": "uvx",
      "args": ["browser-use[cli]@0.11.9", "--mcp"],
      "env": {
        "OPENAI_API_KEY": "<your own OpenAI API key>",
        "ANONYMIZED_TELEMETRY": "False",
        "BROWSER_USE_VERSION_CHECK": "false"
      }
    }
  }
}
```

The pin is `0.11.9` — the version scout's depth layer is built and verified against. A version bump is a deliberate, tested change, not an automatic track.

### Both no-cloud environment variables are mandatory

`ANONYMIZED_TELEMETRY=False` and `BROWSER_USE_VERSION_CHECK=false` **must appear in every documented snippet**, here and anywhere else you register the server. They disable browser-use's two on-by-default outbound pings — the PostHog telemetry call and the version-check call. Without them, registering the server quietly phones home on startup. Do not omit either one.

### You need your own OpenAI API key

The depth layer's two LLM-using tools — `browser_extract_content` (turn a page into structured text) and `retry_with_browser_use_agent` (the last-resort internal loop) — call an LLM, and you supply the key via `OPENAI_API_KEY`. `browser_extract_content` is **hardwired to OpenAI** at the MCP layer in this version, so an OpenAI mini model is the default.

This is not a "no cloud" violation. scout's no-cloud rule bans browser-use's **hosted service** (browser-use Cloud) — the browser runs entirely on your machine. The LLM call for content extraction is an ordinary external LLM call, the same kind scout makes for everything else. (Routing extraction through Anthropic instead of OpenAI needs an upstream browser-use patch and is out of scope here.)

### Server name and tool prefix must match

The server key `browser-use` in the snippet above must equal the `mcp__browser-use__` prefix in scout's tool allow-list (`agents/scout.md`). They are coupled: scout's allow-list names the tools as `mcp__browser-use__browser_navigate`, `mcp__browser-use__browser_get_state`, and so on. **If you register the server under a different name, the allow-list prefix must track it** — otherwise scout cannot see the depth tools and silently falls back to breadth-only. Keep the name `browser-use` unless you have a reason to change both sides.

### No captcha-solving — the foreground-handoff two-step

Be clear-eyed about this: **nothing in this local, no-cloud configuration reliably defeats a modern captcha.** That capability was given up when scout chose local browser-use over browser-use Cloud. scout will not pretend otherwise — it caps captcha effort at a few steps and moves on.

When scout hits a wall on a source it judges essential — a captcha, a login, a hard 403, an interstitial — it does **not** silently drop it. It returns a **blocked-sources block** in the report: the URL, the wall type, and what a human must do to clear it. The handoff back to you is two steps:

1. scout returns the blocked-sources block. You see exactly which sources are walled and why.
2. You clear the wall **live, in a foreground browser-use session** — log in, solve the captcha, whatever it takes. The persistent local Chromium profile (`~/.config/browseruse/profiles/default`) captures the authenticated state. Then you **re-run scout**, and it reaches the now-unlocked source on the next pass.

The wall becomes structured information you act on out-of-band, not a silent gap and not a budget-burning captcha loop.

## Language

Default is English. scout ships professional-voice style profiles (for the report prose) and chat-voice profiles (for the compact summary it returns) in English and German. For other languages, it reads the English profile and applies the same intent in the target language.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) v2.0.12 or higher.
- That's it for the breadth layer — no git, no Node, no Python.
- The optional depth layer adds its own requirements: `uvx` (from [uv](https://github.com/astral-sh/uv)) to run browser-use locally, an `OPENAI_API_KEY`, and a local Chromium that browser-use manages. See **Optional depth layer (browser-use)** above. None of this is needed for breadth.

## License

MIT. See [LICENSE](LICENSE).
