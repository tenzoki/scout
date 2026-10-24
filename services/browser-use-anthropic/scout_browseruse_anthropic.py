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
    uvx --python 3.12 --from "browser-use[cli]@0.11.9" --with "mcp==1.30.0" --with "pydantic-settings==2.16.1" python scout_browseruse_anthropic.py --mcp

Environment:
    SCOUT_DEPTH_PROVIDER       anthropic (default) selects the patch; any other
                               value (e.g. openai) = pass-through to stock
                               OpenAI behaviour, no patch installed.
    SCOUT_DEPTH_EXTRACT_MODEL  extraction model id (default claude-haiku-4-5).
    SCOUT_DEPTH_EXTRACT_TEMPERATURE
                               extraction temperature, a number in [0, 1].
                               A valid value is always sent. Unset or empty:
                               with the default model, 0 is sent (extraction
                               is a near-deterministic read-back, per
                               7006b63); with SCOUT_DEPTH_EXTRACT_MODEL set,
                               no temperature is sent, so the API default
                               applies (some models reject non-default
                               sampling values). An override must be a model
                               whose reply starts with a text block (e.g.
                               claude-haiku-4-5): browser-use 0.11.9's
                               extraction reads only the first content
                               block, so a model that thinks by default
                               returns its thinking block instead. Current
                               models that think by default (e.g. the
                               Sonnet 5 family) are unsuitable, because
                               browser-use 0.11.9's ChatAnthropic has no
                               way to turn thinking off.
                               An unparseable or out-of-range value is treated
                               as unset, with a note on stderr.
    ANTHROPIC_API_KEY          read by the Anthropic SDK / passed explicitly.

Failed start: stock `_init_browser_session` assigns `self.browser_session`
before awaiting its `start()`, and stock only initialises when that attribute
is None. A start that times out would therefore leave the server stuck for
good ('LLM not initialized', 'Root CDP client not initialized'). The wrap
discards the half-started session and re-raises, so the next tool call retries.

Pin discipline: a browser-use bump is a deliberate, tested change. The shim
depends on four named browser-use internals — `server.ChatOpenAI` (the symbol
it supplants), `BrowserUseServer._init_browser_session` (the wrap target),
`ChatAnthropic` (the replacement) and `server.BrowserSession.kill` (stops a
session whose start failed). The import-time guard below fails loudly if any
of them is renamed upstream, instead of silently falling back to OpenAI. The
failed-start recovery also relies on the instance attributes `browser_session`,
`tools`, `file_system` and `active_sessions` (keyed by session `id`), which an
import-time check cannot see; re-read them in `server.py` on a bump.
"""

import asyncio
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
        f"ChatAnthropic, BrowserSession.kill) against the new version and re-run the smoke test.\n"
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

    # What the wrap calls to stop a session whose start failed. Without it the
    # recovery path would raise AttributeError (logged, not fatal) and leave a
    # launched browser behind, so a rename must surface here instead.
    if not hasattr(getattr(server, "BrowserSession", None), "kill"):
        _fail("server.BrowserSession.kill", "method not found on BrowserSession")

    return server, ChatAnthropic


# The default extraction model. It must be a served model id: an id the API has
# retired passes the import guard and fails only at the first extraction.
DEFAULT_EXTRACT_MODEL = "claude-haiku-4-5"


# Extraction is a near-deterministic read-back of page text, not generation:
# temperature 0 keeps a long, dense filing from making the model wander or
# under-return. (Stock's fallback is 0.7; scout chose 0 on purpose in 7006b63.)
# It applies only to DEFAULT_EXTRACT_MODEL, which is known to accept it.
DEFAULT_EXTRACT_TEMPERATURE = 0.0


def _extract_temperature(model_overridden: bool) -> "float | None":
    """Decide the extraction temperature, or None for "send none".

    None means browser-use's ChatAnthropic leaves the parameter out of the
    request, so the API default applies. The rule, one branch per case:
    - SCOUT_DEPTH_EXTRACT_TEMPERATURE set to a number in [0, 1]: that number.
    - otherwise, default model: DEFAULT_EXTRACT_TEMPERATURE.
    - otherwise, model overridden: None, because some models answer 400 to
      any non-default sampling value, and scout cannot know what an
      operator-chosen model accepts. (Sending none only gets the request
      accepted; the override must still reply with a text block first, since
      browser-use 0.11.9 reads only the first content block.)
    A set value that is not a number, or lies outside [0, 1], counts as unset,
    and stderr says which value was refused, so a typo is visible in the MCP
    server log.
    """
    fallback = None if model_overridden else DEFAULT_EXTRACT_TEMPERATURE
    raw = os.getenv("SCOUT_DEPTH_EXTRACT_TEMPERATURE", "").strip()
    if not raw:
        return fallback
    try:
        value = float(raw)
    except ValueError:
        value = None
    # `value == value` rejects NaN, which float() accepts.
    if value is None or value != value or not 0.0 <= value <= 1.0:
        sent = "sending no temperature (API default)" if fallback is None else f"using {fallback:g}"
        print(
            f"scout-browseruse-anthropic: SCOUT_DEPTH_EXTRACT_TEMPERATURE={raw!r} "
            f"is not a number in [0, 1]; {sent}.",
            file=sys.stderr,
        )
        return fallback
    return value


# Upper bound on tearing down a half-started browser. kill() can wait on
# browser-use's own stop timeouts (up to 45 s); the tool call that failed should
# not hang that long on cleanup that is only best-effort anyway.
DISCARD_TIMEOUT_SECONDS = 10.0


async def _discard_half_started(self) -> None:
    """Undo what a failed stock _init_browser_session left behind.

    Stock assigns self.browser_session BEFORE awaiting its start(), and builds
    self.tools / self.llm / self.file_system only after start() returns. When
    start() raises or times out (e.g. browser-use's 30 s BrowserStartEvent
    timeout on a slow first launch), the server is left with a non-None but
    unstarted session and no tools. Stock _execute_tool only initialises
    `if not self.browser_session`, so it never retries: every later call fails
    with 'Root CDP client not initialized' or 'LLM not initialized'.

    Resetting the attributes is what makes the next tool call retry the whole
    start, so it happens first and unconditionally. Killing the dead session is
    best-effort and bounded; its failure is logged, never raised, so the
    caller's original exception is the one that propagates.
    """
    session = self.browser_session
    self.browser_session = None
    self.tools = None
    self.file_system = None
    if session is None:
        return
    # Stock tracks the session only after start() succeeds, so a start failure
    # leaves no entry; a failure later in init (Tools(), FileSystem()) would.
    # Drop it either way so browser_list_sessions does not list a dead session.
    active = getattr(self, "active_sessions", None)
    if isinstance(active, dict):
        active.pop(getattr(session, "id", None), None)
    try:
        await asyncio.wait_for(session.kill(), timeout=DISCARD_TIMEOUT_SECONDS)
    except Exception as exc:  # noqa: BLE001 - cleanup must not mask the cause
        print(
            f"scout-browseruse-anthropic: could not stop the half-started "
            f"browser session after a failed start: {exc!r}",
            file=sys.stderr,
        )


def _install_anthropic_patch(server, ChatAnthropic) -> None:
    """Wrap _init_browser_session so self.llm is an Anthropic extraction model.

    The stock method builds self.llm = ChatOpenAI(...) ONLY when an OpenAI key
    is present in config; with an Anthropic-only setup that branch never runs
    and self.llm stays None. So this wrapper sets self.llm UNCONDITIONALLY after
    the stock method, never "replace if present" — otherwise extraction would
    hit the 'LLM not initialized' guard.

    If the stock method fails, the wrapper discards the half-started session
    (see _discard_half_started) and re-raises, so the next tool call starts
    over and reaches the self.llm assignment. That is why self.llm needs no
    second assignment before the stock call: no tool runs against a session
    whose init did not complete.
    """
    model_override = os.getenv("SCOUT_DEPTH_EXTRACT_MODEL", "").strip()
    model = model_override or DEFAULT_EXTRACT_MODEL
    temperature = _extract_temperature(model_overridden=bool(model_override))
    stock_init = server.BrowserUseServer._init_browser_session

    @functools.wraps(stock_init)
    async def _patched_init(self, *args, **kwargs):
        # Stock returns early when a session already exists; only a call that
        # starts from no session may tear down what it built.
        starting_fresh = self.browser_session is None
        try:
            await stock_init(self, *args, **kwargs)
        except BaseException:
            # BaseException: a timeout can arrive as asyncio.CancelledError.
            if starting_fresh:
                await _discard_half_started(self)
            raise
        # Unconditional: replace whatever the stock OpenAI branch did (or did
        # not) build with an Anthropic extraction model. api_key may be None;
        # the Anthropic SDK then reads ANTHROPIC_API_KEY from the environment.
        # temperature may be None, which ChatAnthropic omits from the request.
        self.llm = ChatAnthropic(
            model=model,
            api_key=os.getenv("ANTHROPIC_API_KEY"),
            temperature=temperature,
        )

    server.BrowserUseServer._init_browser_session = _patched_init


def main() -> None:
    provider = os.getenv("SCOUT_DEPTH_PROVIDER", "anthropic").strip().lower()

    server, ChatAnthropic = _resolve()

    if provider == "anthropic":
        _install_anthropic_patch(server, ChatAnthropic)
    # Any other provider (e.g. "openai"): no patch — pass through to stock
    # browser-use OpenAI behaviour. The shim is a no-op transport in that case.

    asyncio.run(server.main())


if __name__ == "__main__":
    main()
