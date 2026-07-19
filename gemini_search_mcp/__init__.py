"""Gemini Search MCP Server — free web search for AI agents.

Exposes Google Search AI Mode as MCP tools. Any MCP-compatible client
(Claude Desktop, Claude Code, Cursor, etc.) can call these tools to get
real-time web-grounded answers powered by Gemini — zero API key, unlimited.
"""
import asyncio
import os
from typing import Optional
from mcp.server.fastmcp import FastMCP
from mcp.types import ToolAnnotations

from gemini_search.engine import AIModeEngine


def _transport_security():
    """Build TransportSecuritySettings from the environment.

    The streamable-HTTP server rejects requests whose Host header is not
    localhost (DNS-rebinding protection, HTTP 421). Behind a reverse proxy
    the public Host differs, so it must be configured:

    - ``MCP_ALLOWED_HOSTS``: comma-separated ``host[:port]`` entries to allow
      (e.g. ``example.com:300,127.0.0.1:300``). Protection stays ON.
    - ``MCP_DNS_REBINDING_PROTECTION=0``: disable the check entirely.
      Reasonable when every request already requires a valid bearer token —
      rebinding cannot get an attacker past token auth.

    Unset: SDK default (protection on, localhost only).
    """
    from mcp.server.transport_security import TransportSecuritySettings

    if os.environ.get("MCP_DNS_REBINDING_PROTECTION") == "0":
        return TransportSecuritySettings(enable_dns_rebinding_protection=False)
    allowed = os.environ.get("MCP_ALLOWED_HOSTS")
    if allowed:
        hosts = [h.strip() for h in allowed.split(",") if h.strip()]
        return TransportSecuritySettings(allowed_hosts=hosts)
    return None


def _build_mcp() -> FastMCP:
    """Build the FastMCP server, enabling bearer-token auth when configured.

    Auth is provided by the optional ``mcp_auth`` package and is active only
    when ``MCP_AUTH_DB`` points at that service's SQLite token store. When
    unset, the server runs unauthenticated (e.g. local stdio use).
    """
    if not os.environ.get("MCP_AUTH_DB"):
        return FastMCP(name="Gemini Search", transport_security=_transport_security())

    from mcp.server.auth.settings import AuthSettings
    from pydantic import AnyHttpUrl

    from mcp_auth.adapters import mcp_sdk1
    from mcp_auth.store import open_store

    service = os.environ.get("MCP_AUTH_SERVICE", "gemini")
    store = open_store()  # path from MCP_AUTH_DB
    issuer = os.environ.get("MCP_AUTH_ISSUER", "http://localhost:8080")
    return FastMCP(
        name="Gemini Search",
        token_verifier=mcp_sdk1.build(store, service=service),
        auth=AuthSettings(
            issuer_url=AnyHttpUrl(issuer),
            resource_server_url=AnyHttpUrl(issuer.rstrip("/") + "/mcp"),
        ),
        transport_security=_transport_security(),
    )


mcp = _build_mcp()
READONLY = ToolAnnotations(readOnlyHint=True)

_engine: Optional[AIModeEngine] = None
_lock = asyncio.Lock()


async def _get_engine() -> AIModeEngine:
    global _engine
    if _engine is None:
        async with _lock:
            if _engine is None:
                import os
                _engine = AIModeEngine()
                cdp = os.environ.get("CDP_URL")
                channel = os.environ.get("BROWSER_CHANNEL", "chrome")
                headless = os.environ.get("HEADLESS", "1") != "0"
                user_data_dir = os.environ.get("GEMINI_SEARCH_USER_DATA_DIR")
                browser_backend = os.environ.get("GEMINI_SEARCH_BROWSER_BACKEND")
                proxy_server = os.environ.get("GEMINI_SEARCH_PROXY_SERVER")
                chromedriver_path = os.environ.get("GEMINI_SEARCH_CHROMEDRIVER") or os.environ.get("UC_CHROMEDRIVER")
                await _engine.start(
                    cdp_url=cdp,
                    headless=headless,
                    channel=channel,
                    user_data_dir=user_data_dir,
                    browser_backend=browser_backend,
                    proxy_server=proxy_server,
                    chromedriver_path=chromedriver_path,
                )
    return _engine


@mcp.tool(annotations=READONLY)
async def web_search(
    query: str,
) -> str:
    """Search the web using Google AI Mode and get a synthesized answer with sources.

    Uses Google Search's AI Mode (powered by Gemini) to search the web in
    real-time and return a comprehensive, grounded answer. Results include
    information from current web pages, news, and data.

    This is equivalent to using Google Search's "AI Mode" tab — the AI reads
    multiple web sources and synthesizes an answer, similar to Perplexity or
    Grok's web search, but powered by Google's search index.

    Args:
        query: Search query or question. Can be anything you'd type into Google.
               Examples: "latest news about AI regulation", "Bitcoin price today",
               "how does mRNA vaccine work", "Python asyncio best practices 2026"

    Returns:
        A synthesized answer based on real-time web search results.
        The answer is grounded in actual web content found by Google.
    """
    engine = await _get_engine()
    return await engine.ask(query)


@mcp.tool(annotations=READONLY)
async def ask(
    prompt: str,
) -> str:
    """Ask Google AI Mode any question and get an AI-generated answer.

    Similar to web_search but intended for general questions that may or may
    not require web search. Google AI Mode will automatically decide whether
    to search the web or answer from its training data.

    Args:
        prompt: Any question or instruction. Google AI Mode will search the web
                if needed and synthesize an answer.

    Returns:
        AI-generated answer, potentially grounded in web search results.
    """
    engine = await _get_engine()
    return await engine.ask(prompt)


def main():
    mcp.run(transport='stdio')


def main_http():
    """Serve the MCP over streamable-HTTP (network) instead of stdio.

    Listens on HOST:PORT (default 0.0.0.0:8080) at path ``/mcp``. When
    ``MCP_AUTH_DB`` is set, every request must carry a valid
    ``Authorization: Bearer`` token (see ``_build_mcp``).
    """
    mcp.settings.host = os.environ.get("HOST", "0.0.0.0")
    mcp.settings.port = int(os.environ.get("PORT", "8080"))
    mcp.run(transport="streamable-http")


if __name__ == "__main__":
    main()
