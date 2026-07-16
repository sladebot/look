"""Review-only auth proxy for Tailscale Funnel.

Purpose
-------
Clients reach port 5678, which is owned by this auth proxy. The raw backend runs
on loopback-only port 5680 and is never exposed directly. External reviewers
(e.g. Apple App Store Review) reach this proxy through a public HTTPS Tailscale
Funnel. The proxy enforces a bearer token and forwards authorized traffic to the
local backend.

    Tailnet/review app:   http://<mac-studio>.<tailnet>.ts.net:5678   (X-API-Key)
    External (review):    https://<mac-studio>.<tailnet>.ts.net       (Bearer key)
                              → Tailscale Funnel :443
                              → this proxy 0.0.0.0:5678
                              → backend 127.0.0.1:5680

Run
---
    export REVIEW_API_KEY="$(openssl rand -hex 32)"
    ./.conda/bin/python -m uvicorn api.server:app --host 127.0.0.1 --port 5680
    ./.conda/bin/python -m uvicorn api.review_proxy:app --host 0.0.0.0 --port 5678

See docs/release/review-funnel-access.md for full setup, testing, and the
Tailscale Funnel commands.
"""
import hmac
import ipaddress
import os
import sys
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from starlette.background import BackgroundTask

# ─── configuration ───────────────────────────────────────────────────────────
# Where the real backend listens. Loopback only — the raw backend is never the
# Funnel target.
BACKEND_URL = os.environ.get("REVIEW_BACKEND_URL", "http://127.0.0.1:5680")

# Fail fast: without a key the proxy would either reject everything or (worse)
# forward everything, so refuse to start.
REVIEW_API_KEY = os.environ.get("REVIEW_API_KEY", "").strip()
if not REVIEW_API_KEY:
    sys.stderr.write(
        "FATAL: REVIEW_API_KEY is not set.\n"
        "Generate one and export it before starting the proxy:\n"
        '  export REVIEW_API_KEY="$(openssl rand -hex 32)"\n'
    )
    raise SystemExit(1)

_EXPECTED_AUTH = f"Bearer {REVIEW_API_KEY}"

# Hop-by-hop headers must not be forwarded (RFC 7230 §6.1). `content-length` is
# stripped from forwarded *requests* because httpx recomputes it from the
# buffered body; it is preserved on *responses* (see below). The credential
# headers are stripped so the review key never lands in backend logs.
_HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "transfer-encoding", "upgrade",
}
_DROP_FROM_REQUEST = _HOP_BY_HOP | {
    "host", "content-length", "authorization", "x-api-key",
}


def _is_loopback_request(request: Request) -> bool:
    """Return true only for a direct loopback client.

    Uvicorn resolves trusted ``X-Forwarded-For`` headers before FastAPI builds
    ``request.client``. Funnel traffic therefore retains its remote client IP,
    while a browser opened directly on this Mac remains 127.0.0.1 or ::1.
    """
    host = request.client.host if request.client else ""
    try:
        return ipaddress.ip_address(host).is_loopback
    except ValueError:
        return False


def _authorized(request: Request) -> bool:
    """Accept either `Authorization: Bearer <key>` or `X-API-Key: <key>`,
    each constant-time-compared against REVIEW_API_KEY. The `X-API-Key` form
    lets the existing iOS client (which already sends that header) authenticate
    through the Funnel without a code change. A non-ASCII header value makes
    hmac.compare_digest raise TypeError — treat that as a failed match, not a 500.
    """
    candidates = (
        (request.headers.get("authorization", ""), _EXPECTED_AUTH),
        (request.headers.get("x-api-key", ""), REVIEW_API_KEY),
    )
    for provided, expected in candidates:
        if not provided:
            continue
        try:
            if hmac.compare_digest(provided, expected):
                return True
        except TypeError:
            continue
    return False


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Hold a single pooled client for the proxy's lifetime."""
    async with httpx.AsyncClient(
        base_url=BACKEND_URL,
        timeout=httpx.Timeout(60.0, connect=5.0),
    ) as client:
        _app.state.client = client
        yield


app = FastAPI(title="Look Review Proxy", version="0.1.0", lifespan=lifespan)


def _unauthorized() -> JSONResponse:
    return JSONResponse({"error": "Unauthorized"}, status_code=401)


@app.api_route(
    "/{path:path}",
    methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"],
)
async def proxy(path: str, request: Request):
    # 1. Local browsers are trusted; all remote clients require a credential.
    if not _is_loopback_request(request) and not _authorized(request):
        return _unauthorized()

    # 2. Rebuild the target URL byte-for-byte (path + query preserved as-is).
    raw_path = request.scope.get("raw_path") or request.url.path.encode("latin-1")
    query_string = request.scope.get("query_string", b"")
    raw_target = raw_path + (b"?" + query_string if query_string else b"")
    target = httpx.URL(BACKEND_URL).copy_with(raw_path=raw_target)

    # 3. Forward headers minus hop-by-hop / host / content-length / authorization.
    fwd_headers = [
        (name, value)
        for name, value in request.headers.items()
        if name.lower() not in _DROP_FROM_REQUEST
    ]

    # Buffer the request body (API payloads are small); responses are streamed.
    body = await request.body()

    client: httpx.AsyncClient = request.app.state.client
    backend_req = client.build_request(
        request.method, target, headers=fwd_headers, content=body,
    )
    try:
        backend_resp = await client.send(backend_req, stream=True)
    except httpx.RequestError:
        return JSONResponse({"error": "Bad Gateway"}, status_code=502)

    # 4. Pass the response back. Keep content-length + content-encoding (aiter_raw
    #    yields still-encoded bytes, so those headers stay accurate); drop only
    #    hop-by-hop headers such as transfer-encoding.
    resp_headers = {
        name: value
        for name, value in backend_resp.headers.items()
        if name.lower() not in _HOP_BY_HOP
    }
    return StreamingResponse(
        backend_resp.aiter_raw(),
        status_code=backend_resp.status_code,
        headers=resp_headers,
        background=BackgroundTask(backend_resp.aclose),
    )
