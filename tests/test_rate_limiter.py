"""Tests for the rate limiter."""
import time

import pytest

from api.rate_limiter import RateLimiter


# ── Basic functionality ───────────────────────────────────────────────────────

def test_default_allow_request():
    """Default limiter should allow requests up to default_rate per minute."""
    limiter = RateLimiter(default_rate=60, default_burst=120)

    # Should allow
    allowed, info = limiter.allow_request("127.0.0.1", "/api/photos")

    assert allowed is True
    assert info['remaining'] >= 0
    assert info['retry_after'] is None


def test_default_denies_after_burst_exhausted():
    """Requests should be denied once the burst bucket is exhausted."""
    limiter = RateLimiter(default_rate=10, default_burst=5)

    # Exhaust the bucket
    for _ in range(5):
        limiter.allow_request("10.0.0.1", "/api/photos")

    # Next should be denied
    allowed, info = limiter.allow_request("10.0.0.1", "/api/photos")

    assert allowed is False
    assert info['remaining'] == 0
    assert info['retry_after'] is not None
    assert info['retry_after'] > 0


def test_rate_limit_per_endpoint():
    """Different endpoints have independent rate-limited buckets per IP."""
    limiter = RateLimiter(default_rate=10, default_burst=5)

    # Use up burst on /api/photos
    for _ in range(5):
        limiter.allow_request("10.0.0.2", "/api/photos")

    # /api/albums on same IP has its own bucket, should still be allowed
    allowed, info = limiter.allow_request("10.0.0.2", "/api/albums")

    assert allowed is True  # Different endpoint = separate bucket


def test_configured_endpoint_override():
    """A configured endpoint should use its own rate/burst."""
    limiter = RateLimiter(default_rate=60, default_burst=120)
    limiter.set_limit("/api/thumbnails/*", rate=2, burst=3)

    # Use up thumbnail bucket
    for _ in range(3):
        limiter.allow_request("10.0.0.3", "/api/thumbnails/abc123")

    # Next thumbnail should be denied (only 2/min, burst 3)
    allowed, info = limiter.allow_request("10.0.0.3", "/api/thumbnails/abc123")
    assert allowed is False

    # But /api/photos should still be allowed (global default)
    allowed, info = limiter.allow_request("10.0.0.3", "/api/photos")
    assert allowed is True


def test_refill_tokens_over_time():
    """Tokens should refill over time based on the rate."""
    limiter = RateLimiter(default_rate=60, default_burst=5)  # 1 token/sec
    limiter.set_limit("/api/photos", rate=12, burst=3)  # 0.2 tokens/sec

    # Exhaust the bucket (burst=3)
    for _ in range(3):
        limiter.allow_request("10.0.0.5", "/api/photos")

    # Wait 2 seconds (rate=12 means ~0.2 tokens/sec → 0.4 tokens gained)
    time.sleep(2.05)

    allowed, info = limiter.allow_request("10.0.0.5", "/api/photos")

    assert allowed is True  # Tokens refilled enough to allow 1 request


def test_token_bucket_cap_at_burst():
    """Token count should never exceed burst capacity."""
    limiter = RateLimiter(default_rate=60, default_burst=10)

    # Wait without hitting any requests — tokens should accumulate up to burst
    time.sleep(2.0)

    # Use up the bucket (burst=10)
    for _ in range(10):
        limiter.allow_request("10.0.0.6", "/api/photos")

    allowed, info = limiter.allow_request("10.0.0.6", "/api/photos")
    assert allowed is False  # Should be denied after burst exhausted


def test_exact_endpoint_match():
    """Exact endpoint matches should override pattern matches."""
    limiter = RateLimiter(default_rate=60, default_burst=120)
    limiter.set_limit("/api/thumbnails", rate=5, burst=10)

    # This exact endpoint should match the configured limit
    rate, burst = limiter._lookup("/api/thumbnails")
    assert rate == 5
    assert burst == 10

    # Sub-path should not match (no trailing /* in pattern)
    rate2, burst2 = limiter._lookup("/api/thumbnails/abc")
    assert rate2 == 60  # falls back to default


def test_glob_pattern_match():
    """Glob patterns (ending in /*) should match prefixes."""
    limiter = RateLimiter(default_rate=60, default_burst=120)
    limiter.set_limit("/api/thumbnails/*", rate=5, burst=10)

    rate, burst = limiter._lookup("/api/thumbnails/abc123")
    assert rate == 5
    assert burst == 10

    rate2, burst2 = limiter._lookup("/api/thumbnails/xyz789")
    assert rate2 == 5


def test_reset_specific():
    """Reset should clear buckets for specific IP, endpoint, or all."""
    limiter = RateLimiter(default_rate=60, default_burst=1)

    # Create some state — different endpoints get separate buckets
    limiter.allow_request("10.0.0.1", "/api/photos")
    limiter.allow_request("10.0.0.2", "/api/photos")

    # Reset specific IP on a specific endpoint
    limiter.reset(ip="10.0.0.1", endpoint="/api/photos")

    # 10.0.0.1 on /api/photos should get a fresh bucket
    allowed, info = limiter.allow_request("10.0.0.1", "/api/photos")
    assert allowed is True  # Fresh bucket

    # 10.0.0.2 should still be exhausted
    allowed, info = limiter.allow_request("10.0.0.2", "/api/photos")
    assert allowed is False  # Still exhausted


def test_reset_all():
    """Reset with no arguments should clear all buckets."""
    limiter = RateLimiter(default_rate=60, default_burst=120)

    limiter.allow_request("10.0.0.1", "/api/photos")
    limiter.allow_request("10.0.0.2", "/api/photos")

    limiter.reset()  # Clear all

    # Both should now have fresh buckets
    allowed, _ = limiter.allow_request("10.0.0.1", "/api/photos")
    assert allowed is True
    allowed, _ = limiter.allow_request("10.0.0.2", "/api/photos")
    assert allowed is True
