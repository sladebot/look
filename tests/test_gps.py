"""Tests for GPS extraction and geospatial queries."""
import math
import os
import tempfile
from pathlib import Path

import pytest

from api.processor import ImageProcessor
from api.config import Config


# ── GPS extraction from EXIF ──────────────────────────────────────────────────

def test_gps_extraction_exif_gps_lat_lon_present():
    """Verify _parse_exif sets gps_lat/gps_lon as top-level keys."""
    from api.processor import ImageProcessor

    proc = ImageProcessor.__new__(ImageProcessor)  # skip __init__

    # piexif stores GPS as 3-tuples of (numerator, denominator) for DMS values:
    # lat (tag 2): ((deg_num, deg_den), (min_num, min_den), (sec_num, sec_den))
    # lon (tag 4): same format
    exif = {
        '0th': {
            0x010F: b'Canon',
            0x0110: b'Canon EOS R5',
        },
        'GPS': {
            1: b'N',  # latitude reference
            2: ((40, 1), (24, 1), (44, 1)),  # DMS: 40°24'44"
            3: b'W',  # longitude reference
            4: ((73, 1), (59, 1), (22, 1)),  # DMS: 73°59'22"
        },
    }

    result = proc._parse_exif(exif)

    # Top-level GPS coords should exist
    assert result['gps_lat'] == pytest.approx(40.0 + 24/60 + 44/3600)
    # West longitude is negative
    expected_lon = -(73.0 + 59/60 + 22/3600)
    assert result['gps_lon'] == pytest.approx(expected_lon)

    # Nested gps dict should also exist
    assert 'gps' in result
    assert result['gps']['lat'] == result['gps_lat']
    assert result['gps']['lon'] == result['gps_lon']


def test_gps_extraction_south_west():
    """South latitude and West longitude should both be negative."""
    from api.processor import ImageProcessor

    proc = ImageProcessor.__new__(ImageProcessor)

    exif = {
        '0th': {},
        'GPS': {
            1: b'S',  # South
            2: ((34, 1), (3, 1), (9, 1)),
            3: b'E',  # East
            4: ((151, 1), (12, 1), (12, 1)),
        },
    }

    result = proc._parse_exif(exif)

    assert result['gps_lat'] == pytest.approx(-(34.0 + 3/60 + 9/3600))  # South = negative
    assert result['gps_lon'] == pytest.approx(151.0 + 12/60 + 12/3600)  # East = positive


def test_gps_extraction_no_gps_ifd():
    """Images without GPS EXIF should not have gps_lat/gps_lon keys."""
    from api.processor import ImageProcessor

    proc = ImageProcessor.__new__(ImageProcessor)

    exif = {'0th': {0x010F: b'Sony'}, 'GPS': {}}  # GPS IFD exists but empty

    result = proc._parse_exif(exif)

    assert 'gps_lat' not in result
    assert 'gps_lon' not in result


def test_gps_extraction_malformed_dms():
    """Malformed DMS data should gracefully return None."""
    from api.processor import ImageProcessor

    proc = ImageProcessor.__new__(ImageProcessor)

    exif = {
        '0th': {},
        'GPS': {
            1: b'N',
            2: 'not_a_tuple',  # malformed
        },
    }

    result = proc._parse_exif(exif)

    assert 'gps_lat' not in result


# ── Geospatial (haversine) query ───────────────────────────────────────────────

def test_geo_query_returns_photos_within_radius():
    """Verify that geo_query returns photos sorted by distance."""
    from api.database import PhotoDatabase

    db_path = str(Path(tempfile.mkdtemp()) / "test_gps.db")
    db = PhotoDatabase(db_path)

    # Store photos at known GPS coordinates (in NYC area)
    photos = [
        {'id': 'aaa', 'filename': 'photo1.jpg', 'filepath': '/tmp/p1.jpg', 'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01'},
        {'id': 'bbb', 'filename': 'photo2.jpg', 'filepath': '/tmp/p2.jpg', 'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-02'},
        {'id': 'ccc', 'filename': 'photo3.jpg', 'filepath': '/tmp/p3.jpg', 'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-03'},
    ]
    for p in photos:
        db.store_photo({**p, 'gps_lat': 40.7128, 'gps_lon': -74.0060})  # NYC
    # Second location (Boston)
    db.store_photo({**photos[1], 'id': 'bbb', 'gps_lat': 42.3601, 'gps_lon': -71.0589})
    # Third location (far away — Denver)
    db.store_photo({**photos[2], 'gps_lat': 39.7392, 'gps_lon': -104.9903})

    result = db.geo_query(lat=40.7128, lon=-74.0060, radius_km=500)

    # Should return NYC and Boston (Denver is ~2800 km away)
    assert len(result) == 2
    # Results should be sorted by distance (closest first)
    assert result[0]['distance_km'] <= result[1]['distance_km']


def test_geo_query_filters_by_radius():
    """Photos outside the radius should not be returned."""
    from api.database import PhotoDatabase

    db_path = str(Path(tempfile.mkdtemp()) / "test_gps2.db")
    db = PhotoDatabase(db_path)

    db.store_photo({
        'id': 'xyz', 'filename': 'photo.jpg', 'filepath': '/tmp/x.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01',
        'gps_lat': 40.7128, 'gps_lon': -74.0060,
    })

    # Query a nearby-but-different point with a tiny radius; NYC should be out.
    result = db.geo_query(lat=40.7138, lon=-74.0060, radius_km=0.0001)
    assert len(result) == 0

    # Same location, 50 km radius — should include it
    result = db.geo_query(lat=40.7128, lon=-74.0060, radius_km=50)
    assert len(result) == 1
    assert result[0]['id'] == 'xyz'


def test_geo_query_excludes_photos_without_gps():
    """Photos without GPS data should be excluded from results."""
    from api.database import PhotoDatabase

    db_path = str(Path(tempfile.mkdtemp()) / "test_gps3.db")
    db = PhotoDatabase(db_path)

    # Store a photo with GPS
    db.store_photo({
        'id': 'with_gps', 'filename': 'a.jpg', 'filepath': '/tmp/a.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01',
        'gps_lat': 40.7128, 'gps_lon': -74.0060,
    })
    # Store a photo WITHOUT GPS
    db.store_photo({
        'id': 'no_gps', 'filename': 'b.jpg', 'filepath': '/tmp/b.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01',
    })

    result = db.geo_query(lat=40.7128, lon=-74.0060, radius_km=50)

    # Only the GPS photo should appear
    assert len(result) == 1
    assert result[0]['id'] == 'with_gps'


def test_geo_query_distance_is_rounded():
    """Distance values should be rounded to 2 decimal places."""
    from api.database import PhotoDatabase

    db_path = str(Path(tempfile.mkdtemp()) / "test_gps4.db")
    db = PhotoDatabase(db_path)

    db.store_photo({
        'id': 'p', 'filename': 'x.jpg', 'filepath': '/tmp/x.jpg',
        'width': 100, 'height': 100, 'mime_type': 'image/jpeg', 'indexed_at': '2024-01-01',
        'gps_lat': 40.7128, 'gps_lon': -74.0060,
    })

    result = db.geo_query(lat=40.7128, lon=-74.0060, radius_km=50)
    assert len(result) == 1
    # Distance from same point should be 0.0
    assert result[0]['distance_km'] == 0.0
    assert isinstance(result[0]['distance_km'], float)
