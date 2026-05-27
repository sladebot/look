"""Tests for dedup engine DCT formula fix."""
import inspect

import pytest


def test_dct_2d_contains_math_cos():
    """Verify _dct_2d uses math.cos — the fix for broken perceptual hashing."""
    from api.dedup_engine import DedupEngine

    source = inspect.getsource(DedupEngine._dct_2d)
    assert "math.cos" in source, (
        "_dct_2d must call math.cos() to compute a real DCT. "
        "Without it, pixel values are multiplied by scalar constants, "
        "producing meaningless perceptual hashes."
    )
    # The denominator 32.0 (2 * 16) confirms correct DCT-II indexing
    assert "32.0" in source, "_dct_2d should use 32.0 (2*N) as DCT denominator"
    # No cu/cv normalization factors — simplified DCT form
    assert "cu" not in source, "_dct_2d should not define 'cu' normalization variable"
    assert "cv" not in source, "_dct_2d should not define 'cv' normalization variable"


def test_dct_2d_output_length():
    """_dct_2d returns a flat list of 64 coefficients (8x8 from 16x16 input)."""
    from api.dedup_engine import DedupEngine

    engine = DedupEngine.__new__(DedupEngine)  # no __init__ needed
    # Flat 1D list of 256 pixel values — matches how the real code passes data
    pixels = [float((x * 16 + y) % 256) for x in range(16) for y in range(16)]
    coeffs = engine._dct_2d(pixels)
    assert len(coeffs) == 64
    assert all(isinstance(c, float) for c in coeffs)


def test_dct_2d_constant_image():
    """A constant image should produce DCT where only the DC coefficient (index 0) is non-zero."""
    from api.dedup_engine import DedupEngine

    engine = DedupEngine.__new__(DedupEngine)
    # Flat 1D list of 256 constant values
    pixels = [128.0] * 256
    coeffs = engine._dct_2d(pixels)
    # DC coefficient (first element) is the sum of all pixels scaled
    assert coeffs[0] > 0
    # All AC coefficients (indices 1-63) should be zero (or extremely close)
    for i in range(1, 64):
        assert abs(coeffs[i]) < 1e-6, (
            f"AC coefficient index {i} is {coeffs[i]} for constant image, "
            "expected ~0"
        )
