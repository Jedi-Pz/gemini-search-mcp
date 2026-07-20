# gemini-search MCP server over streamable-HTTP with in-app bearer auth.
FROM python:3.12-slim

# xvfb: the undetected backend runs Chromium headful (headless is CAPTCHA-bait)
# on a virtual display.
RUN apt-get update && apt-get install -y --no-install-recommends \
      chromium tini git ca-certificates xvfb xauth \
    && rm -rf /var/lib/apt/lists/*

# The fork (with the gemini-search-mcp-http entrypoint) + the mcp_auth library.
# GEMINI_REF lets compose pin a commit; changing it busts the build cache.
# setuptools: shim for undetected-chromedriver's `import distutils` (removed in py3.12).
ARG GEMINI_REF=main
RUN pip install --no-cache-dir setuptools \
      "gemini-search-mcp[undetected] @ git+https://github.com/Jedi-Pz/gemini-search-mcp.git@${GEMINI_REF}" \
      "mcp-auth @ git+https://github.com/Jedi-Pz/mcp-auth.git"

ENV CHROME_PATH=/usr/bin/chromium \
    BROWSER_CHANNEL=chromium \
    PYTHONUNBUFFERED=1

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["xvfb-run", "-a", "gemini-search-mcp-http"]
