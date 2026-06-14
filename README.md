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

<!-- PLACEHOLDER — filled in the depth slice (Step 10). -->

The optional depth layer (a local browser-use MCP server, for pages that need an interactive browser) is **added in the depth slice**. Registration instructions, the pinned version, the required no-cloud environment variables, and an honest note on what walls it can and cannot get past will appear here.

Until then, scout runs breadth-only: any page that genuinely needs an interactive browser is recorded as a "needs depth tools" gap in the report's blocked-sources table, never silently dropped.

## Language

Default is English. scout ships professional-voice style profiles (for the report prose) and chat-voice profiles (for the compact summary it returns) in English and German. For other languages, it reads the English profile and applies the same intent in the target language.

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code/overview) v2.0.12 or higher.
- That's it for the breadth layer — no git, no Node, no Python. (The optional depth layer has its own requirements, documented in its section above when it lands.)

## License

MIT. See [LICENSE](LICENSE).
