"""Tests for the review auth proxy (api/review_proxy.py).

The proxy fronts a public Tailscale Funnel: it requires a review credential
(Bearer token or X-API-Key) and forwards authorized traffic to the backend.

These tests cover the proxy's value-add — the auth decision, the 401 contract,
and which headers are stripped before forwarding. End-to-end streaming fidelity
(byte-identical binary responses, header passthrough) is verified against a live
backend; see docs/release/review-funnel-access.md.
"""
import os
from types import SimpleNamespace

import httpx
from httpx import ASGITransport

# The proxy fails fast at import if REVIEW_API_KEY is unset, so set it first.
os.environ.setdefault("REVIEW_API_KEY", "test-review-key-abc123")

from api import review_proxy  # noqa: E402

# Use whatever key the module actually loaded at import.
REVIEW_KEY = review_proxy.REVIEW_API_KEY


class _FakeRequest:
    """Minimal stand-in exposing the .headers.get() the proxy relies on."""

    def __init__(self, headers: dict, host: str = "203.0.113.10"):
        self.headers = headers
        self.client = SimpleNamespace(host=host)


def _client() -> httpx.Client:
    transport = ASGITransport(app=review_proxy.app, client=("203.0.113.10", 12345))
    return httpx.Client(transport=transport, base_url="http://proxy")


# ── Auth decision (_authorized) ───────────────────────────────────────────────

def test_valid_bearer_is_authorized():
    req = _FakeRequest({"authorization": f"Bearer {REVIEW_KEY}"})
    assert review_proxy._authorized(req) is True


def test_valid_x_api_key_is_authorized():
    """The existing iOS client sends X-API-Key; the proxy accepts it too."""
    req = _FakeRequest({"x-api-key": REVIEW_KEY})
    assert review_proxy._authorized(req) is True


def test_missing_credential_is_rejected():
    assert review_proxy._authorized(_FakeRequest({})) is False


def test_wrong_bearer_is_rejected():
    req = _FakeRequest({"authorization": "Bearer nope"})
    assert review_proxy._authorized(req) is False


def test_wrong_x_api_key_is_rejected():
    assert review_proxy._authorized(_FakeRequest({"x-api-key": "nope"})) is False


def test_bare_key_without_bearer_prefix_is_rejected():
    """A raw key in the Authorization header (no 'Bearer ' prefix) must fail."""
    req = _FakeRequest({"authorization": REVIEW_KEY})
    assert review_proxy._authorized(req) is False


def test_non_ascii_credential_is_rejected_not_crash():
    """A non-ASCII value makes hmac.compare_digest raise TypeError; the guard
    must turn that into a rejection, never a 500."""
    req = _FakeRequest({"authorization": "Bearer café"})
    assert review_proxy._authorized(req) is False


def test_loopback_request_is_recognized():
    assert review_proxy._is_loopback_request(_FakeRequest({}, "127.0.0.1")) is True
    assert review_proxy._is_loopback_request(_FakeRequest({}, "::1")) is True


def test_remote_request_is_not_loopback():
    assert review_proxy._is_loopback_request(_FakeRequest({}, "100.64.0.10")) is False


# ── 401 contract (via the app) ────────────────────────────────────────────────

def test_missing_credential_returns_401_json():
    with _client() as c:
        resp = c.get("/api/health")
    assert resp.status_code == 401
    assert resp.json() == {"error": "Unauthorized"}


def test_wrong_credential_returns_401_json():
    with _client() as c:
        resp = c.get("/api/anything", headers={"Authorization": "Bearer nope"})
    assert resp.status_code == 401
    assert resp.json() == {"error": "Unauthorized"}


# ── Header hygiene ────────────────────────────────────────────────────────────

def test_credential_and_hop_headers_are_stripped_from_forward():
    """Credential headers never reach the backend; neither do hop-by-hop or
    content-length (httpx recomputes the latter from the buffered body)."""
    drop = review_proxy._DROP_FROM_REQUEST
    for name in ("authorization", "x-api-key", "host", "content-length",
                 "connection", "transfer-encoding"):
        assert name in drop
