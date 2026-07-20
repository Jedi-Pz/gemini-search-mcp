#!/bin/sh
# Container entrypoint: drop stale Chromium singleton locks left behind when a
# previous container was killed (Chrome never shuts down cleanly), then start
# the MCP server on a virtual display.
PROFILE="${GEMINI_SEARCH_USER_DATA_DIR:-/profile}"
rm -f "$PROFILE/SingletonLock" "$PROFILE/SingletonSocket" "$PROFILE/SingletonCookie" 2>/dev/null || true
exec xvfb-run -a gemini-search-mcp-http
