"""Tags 2.0 — History, auto-tagging from EXIF, and bulk merge."""
import os
import re
import json
from pathlib import Path
from datetime import datetime
from typing import Optional, List, Dict


class TagsManager:
    """Extended tag management with history, auto-tagging, and bulk operations."""

    # ISO 3166-1 alpha-2 → country mapping (abbreviated for demo)
    # In production, load from a real geoDB or use libpostal
    COUNTRY_MAP = {
        'us': 'United States', 'ca': 'Canada', 'gb': 'United Kingdom',
        'de': 'Germany', 'fr': 'France', 'jp': 'Japan', 'au': 'Australia',
        'br': 'Brazil', 'in': 'India', 'cn': 'China', 'kr': 'South Korea',
        'mx': 'Mexico', 'it': 'Italy', 'es': 'Spain', 'nl': 'Netherlands',
        'se': 'Sweden', 'no': 'Norway', 'ch': 'Switzerland', 'sg': 'Singapore',
        'nz': 'New Zealand', 'ie': 'Ireland', 'za': 'South Africa',
    }

    def __init__(self, db, config, processor=None):
        self.db = db
        self.config = config
        self.processor = processor

    def add_tag_with_history(self, photo_id: str, tag: str):
        """Add a tag and record its history."""
        self.db.add_tag(photo_id, tag)
        if self.config.tag_history_enabled:
            self.db.add_tag_history(photo_id, tag, 'added', 'user')

    def remove_tag_with_history(self, photo_id: str, tag: str):
        """Remove a tag and record its history."""
        # Remove from database
        with self.db._connect() as conn:
            conn.execute(
                "DELETE FROM tags WHERE photo_id = ? AND tag = ?",
                (photo_id, tag)
            )
        if self.config.tag_history_enabled:
            self.db.add_tag_history(photo_id, tag, 'removed', 'user')

    def get_photo_tags(self, photo_id: str) -> List[str]:
        """Get all current tags for a photo."""
        return self.db.get_tags(photo_id)

    def get_tag_history(self, photo_id: str) -> List[Dict]:
        """Get the tag change history for a photo."""
        return self.db.get_tag_history(photo_id)

    def get_all_tags(self) -> List[Dict]:
        """Return all tags with occurrence counts."""
        with self.db._connect() as conn:
            rows = conn.execute(
                "SELECT tag, COUNT(photo_id) as count FROM tags GROUP BY tag ORDER BY tag"
            ).fetchall()
            return [{"tag": r['tag'], "count": r['count']} for r in rows]

    def get_duplicate_tag_suggestions(self) -> List[Dict]:
        """Find tags that differ only in case, spacing, or capitalization."""
        return self.db.get_duplicate_tag_suggestions()

    def merge_tags(self, source_tag: str, target_tag: str) -> Dict:
        """Merge all occurrences of source_tag into target_tag.

        Args:
            source_tag: Tag to remove (all occurrences)
            target_tag: Tag to keep

        Returns:
            Summary of the merge operation.
        """
        source_tag = source_tag.strip()
        target_tag = target_tag.strip()

        if source_tag == target_tag:
            return {'error': 'Source and target are the same'}

        # Find all photos that have the source tag
        with self.db._connect() as conn:
            rows = conn.execute(
                "SELECT photo_id FROM tags WHERE tag = ?", (source_tag,)
            ).fetchall()

        photo_ids = [row['photo_id'] for row in rows]

        # Remove source tag, add target tag for each
        count = 0
        for pid in photo_ids:
            try:
                # Remove source
                conn.execute(
                    "DELETE FROM tags WHERE photo_id = ? AND tag = ?", (pid, source_tag)
                )
                # Add target
                conn.execute(
                    "INSERT OR IGNORE INTO tags (photo_id, tag) VALUES (?, ?)", (pid, target_tag)
                )
                count += 1

                # Record history
                if self.config.tag_history_enabled:
                    self.db.add_tag_history(pid, source_tag, 'removed', 'merge')
                    self.db.add_tag_history(pid, target_tag, 'added', 'merge')

            except Exception as e:
                print(f"[tags] ERROR merging for {pid}: {e}")

        return {
            'merged': source_tag,
            'into': target_tag,
            'photos_affected': count
        }

    def auto_tag_from_exif(self, photo_id: str, exif_data: dict) -> List[str]:
        """Automatically tag a photo based on its EXIF data.

        Args:
            photo_id: The photo's database ID
            exif_data: EXIF data dict (from processor)

        Returns:
            List of tags that were added.
        """
        added = []

        # Auto-tag camera make/model
        if self.config.auto_tag_camera:
            make = exif_data.get('make')
            model = exif_data.get('model')
            if make and model:
                camera_tag = f"{make} {model}"
                # Avoid adding if already tagged
                current_tags = self.db.get_tags(photo_id)
                if camera_tag not in current_tags:
                    self.add_tag_with_history(photo_id, camera_tag)
                    added.append(camera_tag)
                elif make and make.lower() not in [t.lower() for t in current_tags]:
                    make_tag = make.strip()
                    if make_tag not in current_tags:
                        self.add_tag_with_history(photo_id, make_tag)
                        added.append(make_tag)

        # Auto-tag GPS location
        if self.config.auto_tag_gps:
            gps = exif_data.get('gps', {})
            if gps.get('lat') is not None and gps.get('lon') is not None:
                try:
                    lat = float(gps['lat'])
                    lon = float(gps['lon'])
                    tags = self._geocode_location(lat, lon)
                    current_tags = self.db.get_tags(photo_id)
                    for tag in tags:
                        if tag not in current_tags:
                            self.add_tag_with_history(photo_id, tag)
                            added.append(tag)
                except (ValueError, KeyError):
                    pass

        return added

    def _geocode_location(self, lat: float, lon: float) -> List[str]:
        """Geocode a lat/lon to tags.

        Returns location-based tags (country, region if available).
        For a production system, this would call a reverse geocoding API.
        For now, returns country from COUNTRY_MAP based on rough zone.
        """
        # For a real implementation, you'd use a reverse geocoding library
        # like geopy with a geodb. Here we return basic zone tags.
        tags = []

        # Rough region tagging based on coordinates
        if 25 <= lat <= 50 and -130 <= lon <= -60:
            tags.append('North America')
            tags.append('NorthAmerica')
        elif 35 <= lat <= 55 and -10 <= lon <= 40:
            tags.append('Europe')
            tags.append('Europe')
        elif 20 <= lat <= 55 and 60 <= lon <= 140:
            tags.append('Asia')
            tags.append('Asia')
        elif -40 <= lat <= 0 and 100 <= lon <= 160:
            tags.append('Oceania')
            tags.append('Oceania')

        return tags

    def suggest_auto_tags(self, photo_id: str) -> List[str]:
        """Suggest auto-tags for a photo based on its EXIF data.

        Returns a list of suggested tags (without adding them).
        """
        photo = self.db.get_photo(photo_id)
        if not photo:
            return []

        exif = photo.get('exif', {})
        if not exif:
            return []

        suggestions = []

        # Camera suggestion
        if self.config.auto_tag_camera:
            make = exif.get('make')
            model = exif.get('model')
            if make and model:
                suggestions.append(f"{make} {model}")
            elif make:
                suggestions.append(make)

        # GPS suggestion (read-only, won't add)
        if self.config.auto_tag_gps:
            gps = exif.get('gps', {})
            if gps.get('lat') is not None and gps.get('lon') is not None:
                lat, lon = float(gps['lat']), float(gps['lon'])
                zone_tags = self._geocode_location(lat, lon)
                suggestions.extend(zone_tags)

        return suggestions
