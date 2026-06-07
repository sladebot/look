"""Rate Limiter — token bucket middleware for FastAPI endpoints."""
import time
import threading
from collections import defaultdict
from typing import Dict, Optional, Tuple


class RateLimiter:
    """Token bucket rate limiter supporting per-endpoint and per-IP limits.

    Usage:
        limiter = RateLimiter()
        limiter.set_limit("/api/thumbnails/*", rate=10, burst=20)
        # In middleware:
        allowed, info = limiter.allow_request(client_ip, endpoint)
        if not allowed:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")

    Default: 60 requests/minute per IP (global).
    """

    def __init__(self, default_rate: int = 60, default_burst: int = 120):
        """
        Args:
            default_rate: requests per minute for unknown endpoints.
            default_burst: max burst size (bucket capacity) for unknown endpoints.
        """
        self.default_rate = default_rate  # tokens added per second (rate/min / 60)
        self.default_burst = default_burst
        self._buckets: Dict[str, dict] = {}  # endpoint → bucket state
        self._ip_buckets: Dict[str, dict] = {}  # "endpoint:ip" → bucket state
        self._lock = threading.Lock()
        self._endpoint_patterns: Dict[str, Tuple[int, int]] = {}  # pattern → (rate, burst)

    def set_limit(self, endpoint_pattern: str, rate: int, burst: int):
        """Configure rate and burst for an endpoint pattern.

        Args:
            endpoint_pattern: Exact path (e.g. "/api/thumbnails") or glob with "*" (e.g. "/api/thumbnails/*").
            rate: Max requests per minute (tokens per second = rate / 60).
            burst: Max bucket capacity (allows short bursts).
        """
        with self._lock:
            self._endpoint_patterns[endpoint_pattern] = (rate, burst)

    def allow_request(self, ip: str, endpoint: str) -> Tuple[bool, dict]:
        """Check if a request from ip to endpoint is allowed.

        Returns:
            (allowed, info) where info contains:
              - retry_after: seconds until next token (if denied)
              - remaining: tokens left (if allowed)
              - endpoint: the matched endpoint config
        """
        with self._lock:
            rate, burst = self._lookup(endpoint)
            bucket_key = f"{endpoint}:{ip}"
            now = time.monotonic()

            # Get or create bucket
            bucket = self._ip_buckets.get(bucket_key)
            if bucket is None:
                bucket = {
                    "tokens": float(burst),
                    "last_refill": now,
                    "rate": rate,
                    "burst": burst,
                }
                self._ip_buckets[bucket_key] = bucket

            # Refill tokens
            elapsed = now - bucket["last_refill"]
            bucket["tokens"] = min(
                bucket["burst"],
                bucket["tokens"] + (elapsed * bucket["rate"])
            )
            bucket["last_refill"] = now

            if bucket["tokens"] >= 1:
                bucket["tokens"] -= 1
                return True, {
                    "remaining": int(bucket["tokens"]),
                    "retry_after": None,
                }
            else:
                # Calculate time until 1 token is available
                retry_after = (1 - bucket["tokens"]) / max(bucket["rate"], 0.01)
                return False, {
                    "remaining": 0,
                    "retry_after": round(retry_after, 1),
                }

    def _lookup(self, endpoint: str) -> Tuple[int, int]:
        """Find the best-matching (rate, burst) for an endpoint."""
        # Exact match first
        if endpoint in self._endpoint_patterns:
            return self._endpoint_patterns[endpoint]

        # Glob pattern match (e.g. "/api/thumbnails/*")
        for pattern, (rate, burst) in self._endpoint_patterns.items():
            if pattern.endswith("/*"):
                prefix = pattern[:-2]
                if endpoint.startswith(prefix):
                    return rate, burst

        # Global default
        return self.default_rate, self.default_burst

    def reset(self, ip: Optional[str] = None, endpoint: Optional[str] = None):
        """Reset buckets for a specific IP, endpoint, or all."""
        with self._lock:
            if ip and endpoint:
                key = f"{endpoint}:{ip}"
                self._ip_buckets.pop(key, None)
            elif ip:
                keys_to_remove = [k for k in self._ip_buckets if k.endswith(f":{ip}")]
                for k in keys_to_remove:
                    del self._ip_buckets[k]
            elif endpoint:
                keys_to_remove = [k for k in self._ip_buckets if k.startswith(f"{endpoint}:")]
                for k in keys_to_remove:
                    del self._ip_buckets[k]
            else:
                self._ip_buckets.clear()
