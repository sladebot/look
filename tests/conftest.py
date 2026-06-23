"""Shared pytest configuration."""
import asyncio

import httpx

_AsyncASGITransport = httpx.ASGITransport


class SyncASGITransport(httpx.BaseTransport):
    """Synchronous wrapper for httpx's async-only ASGITransport.

    The test suite uses httpx.Client with ASGITransport. Newer httpx releases
    only expose async transport hooks, so this wrapper keeps those tests stable
    without changing application code.
    """

    def __init__(self, *args, **kwargs):
        self._transport = _AsyncASGITransport(*args, **kwargs)

    def handle_request(self, request):
        async_response = asyncio.run(self._transport.handle_async_request(request))
        content = asyncio.run(async_response.aread())
        return httpx.Response(
            status_code=async_response.status_code,
            headers=async_response.headers,
            content=content,
            request=request,
            extensions=async_response.extensions,
        )

    def close(self):
        asyncio.run(self._transport.aclose())


httpx.ASGITransport = SyncASGITransport
