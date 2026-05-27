"""Tests for DirectoryScanner.scan() including scan_count attribute."""
import tempfile
from pathlib import Path

import pytest

from api.scanner import DirectoryScanner


def test_scan_count_populated_with_one_jpeg(tmp_path):
    """Verify that scan_count reflects the number of photos found."""
    # Create a minimal JPEG file
    jpeg = tmp_path / "photo.jpg"
    minimal_jpeg = (
        b'\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00'
        b'\xff\xd9'
    )
    jpeg.write_bytes(minimal_jpeg)

    scanner = DirectoryScanner(str(tmp_path), image_extensions=('.jpg', '.jpeg', '.png', '.heic'))
    photos = scanner.scan(recursive=False)

    assert scanner.scan_count == 1
    assert len(photos) == 1


def test_scan_count_empty_when_no_photos(tmp_path):
    """Verify scan_count is 0 when the directory contains no images."""
    (tmp_path / "readme.txt").write_text("hello")

    scanner = DirectoryScanner(str(tmp_path), image_extensions=('.jpg', '.jpeg', '.png', '.heic'))
    photos = scanner.scan(recursive=False)

    assert scanner.scan_count == 0
    assert len(photos) == 0
