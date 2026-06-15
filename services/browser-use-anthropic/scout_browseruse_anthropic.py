#!/usr/bin/env python3
"""scout depth-layer Anthropic shim.

Stock browser-use 0.11.9 hardwires its `browser_extract_content` extraction LLM
to OpenAI in `browser_use/mcp/server.py:561` (`_init_browser_session` builds a
`ChatOpenAI`, no provider branch). This shim runs the *unmodified* pinned
browser-use MCP server but rebinds that one extraction LLM to `ChatAnthropic`,
so a user with an `ANTHROPIC_API_KEY` (and no OpenAI key) gets server-side,
query-shaped page extraction on Anthropic.

It is NOT a fork. It imports stock `browser_use.mcp.server`, wraps the
`_init_browser_session` method on `BrowserUseServer`, then hands control to the
stock `server.main()`. `ChatAnthropic` ships inside browser-use
(`browser_use/llm/__init__.py`) and `anthropic` is a hard browser-use
dependency, so the shim needs zero extra packages — it runs inside the same
`uvx --from "browser-use[cli]@0.11.9"` environment.

Launch:
    uvx --from "browser-use[cli]@0.11.9" python scout_browseruse_anthropic.py --mcp

Environment:
    SCOUT_DEPTH_PROVIDER       anthropic (default) selects the patch; any other
                               value (e.g. openai) = pass-through to stock
                               OpenAI behaviour, no patch installed.
    SCOUT_DEPTH_EXTRACT_MODEL  extraction model id (default claude-3-5-haiku-latest).
    ANTHROPIC_API_KEY          read by the Anthropic SDK / passed explicitly.

Pin discipline: a browser-use bump is a deliberate, tested change. The shim
depends on three named browser-use internals — `server.ChatOpenAI` (the symbol
it supplants), `BrowserUseServer._init_browser_session` (the wrap target), and
`ChatAnthropic` (the replacement). The import-time guard below fails loudly if
any of them is renamed upstream, instead of silently falling back to OpenAI.
"""

import functools
import os
import sys

# The browser-use pin scout registers. Named in diagnostics so a loud failure
# tells the operator exactly which version's internals drifted.
PIN = "browser-use[cli]@0.11.9"


def _fail(symbol: str, detail: str) -> None:
    """Emit a clear stderr diagnostic and exit non-zero. No silent fallback."""
    print(
        f"scout-browseruse-anthropic: missing required browser-use symbol "
        f"'{symbol}' ({detail}).\n"
        f"  Pinned browser-use: {PIN}\n"
        f"  An upstream rename likely broke this shim. Re-confirm the patched "
        f"symbols (server.ChatOpenAI, BrowserUseServer._init_browser_session, "
        f"ChatAnthropic) against the new version and re-run the smoke test.\n"
        f"  Refusing to fall back to OpenAI silently.",
        file=sys.stderr,
    )
    sys.exit(1)


def _resolve():
    """Import stock browser-use and verify the symbols the shim depends on.

    Returns (server_module, ChatAnthropic). Exits non-zero with a named
    diagnostic on any missing symbol.
    """
    try:
        import browser_use.mcp.server as server
    except Exception as exc:  # noqa: BLE001 - surface the real import failure
        _fail("browser_use.mcp.server", f"import failed: {exc!r}")

    try:
        from browser_use.llm import ChatAnthropic
    except Exception as exc:  # noqa: BLE001
        _fail("browser_use.llm.ChatAnthropic", f"import failed: {exc!r}")

    if not hasattr(server, "BrowserUseServer"):
        _fail("server.BrowserUseServer", "class not found on browser_use.mcp.server")

    if not hasattr(server.BrowserUseServer, "_init_browser_session"):
        _fail(
            "BrowserUseServer._init_browser_session",
            "method not found on BrowserUseServer",
        )

    # The symbol the shim supplants. Its absence means the OpenAI hardwiring
    # moved; the wrap below would silently no-op, so fail loudly instead.
    if not hasattr(server, "ChatOpenAI"):
        _fail("server.ChatOpenAI", "name not found at module scope")

    return server, ChatAnthropic


def _install_anthropic_patch(server, ChatAnthropic) -> None:
    """Wrap _init_browser_session so self.llm is an Anthropic extraction model.

    The stock method builds self.llm = ChatOpenAI(...) ONLY when an OpenAI key
    is present in config; with an Anthropic-only setup that branch never runs
    and self.llm stays None. So this wrapper sets self.llm UNCONDITIONALLY after
    the stock method, never "replace if present" — otherwise extraction would
    hit the 'LLM not initialized' guard.
    """
    model = os.getenv("SCOUT_DEPTH_EXTRACT_MODEL", "claude-3-5-haiku-latest")
    stock_init = server.BrowserUseServer._init_browser_session

    @functools.wraps(stock_init)
    async def _patched_init(self, *args, **kwargs):
        await stock_init(self, *args, **kwargs)
        # Unconditional: replace whatever the stock OpenAI branch did (or did
        # not) build with an Anthropic extraction model. api_key may be None;
        # the Anthropic SDK then reads ANTHROPIC_API_KEY from the environment.
        self.llm = ChatAnthropic(
            model=model,
            api_key=os.getenv("ANTHROPIC_API_KEY"),
            temperature=0.7,
        )

    server.BrowserUseServer._init_browser_session = _patched_init


def main() -> None:
    import asyncio

    provider = os.getenv("SCOUT_DEPTH_PROVIDER", "anthropic").strip().lower()

    server, ChatAnthropic = _resolve()

    if provider == "anthropic":
        _install_anthropic_patch(server, ChatAnthropic)
    # Any other provider (e.g. "openai"): no patch — pass through to stock
    # browser-use OpenAI behaviour. The shim is a no-op transport in that case.

    asyncio.run(server.main())


if __name__ == "__main__":
    main()
