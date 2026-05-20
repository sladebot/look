"""Smart Album Engine — rule-based dynamic album population."""
import json
import threading
from pathlib import Path
from datetime import datetime
from typing import Optional, Callable, Dict, List


class SmartCollectionManager:
    """Manages rule-based smart albums that auto-populate based on photo properties."""

    VALID_FIELDS = ('camera', 'date_after', 'date_before', 'date_range', 'tag', 'keyword', 'is_favorite')
    VALID_OPS = ('contains', 'equals', 'regex', 'has', 'has_any')

    def __init__(self, db, processor=None):
        self.db = db
        self.processor = processor  # Optional reference to processor for validation

    def create_smart_album(self, name: str, description: str = '', rule_spec: dict = None) -> str:
        """Create a new smart album with rule specifications.

        Args:
            name: Album name
            description: Optional description
            rule_spec: Dictionary with 'rules' list. Example:
                {"rules": [{"field": "camera", "op": "contains", "value": "Canon"}]}

        Returns:
            Album ID (UUID)
        """
        if rule_spec is None:
            rule_spec = {"rules": []}

        self._validate_rules(rule_spec)

        album_id = self.db.create_album(name, description, source='smart_collection')
        self.db.update_album_rule(album_id, json.dumps(rule_spec))

        return album_id

    def evaluate(self, album_id: str) -> int:
        """Re-evaluate rules for a smart album and update its photo list.

        Returns:
            Number of photos added to the album.
        """
        with self.db._connect() as conn:
            row = conn.execute(
                "SELECT rule_spec FROM albums WHERE id = ? AND source = 'smart_collection'",
                (album_id,)
            ).fetchone()

        if not row or not row['rule_spec']:
            return 0

        try:
            rule_spec = json.loads(row['rule_spec'])
        except (json.JSONDecodeError, TypeError):
            return 0

        matching_ids = self.db._evaluate_rules(rule_spec)

        # Update album_photos with matched photos
        updated = self.db.update_album_photos_for_smart(album_id, matching_ids)

        print(f"[smart_album] Album '{album_id}': evaluated {len(matching_ids)} matches")
        return updated

    def eval_all(self) -> Dict[str, int]:
        """Re-evaluate all smart albums. Returns dict of album_id -> photo_count."""
        results = {}
        for collection in self.db.get_smart_collections():
            count = self.evaluate(collection['id'])
            results[collection['id']] = count
        return results

    def run_in_background(self):
        """Run re-evaluation in a background thread (non-blocking)."""
        t = threading.Thread(target=self.eval_all, daemon=True, name='smart-eval')
        t.start()
        return t

    def _validate_rules(self, rule_spec: dict):
        """Validate rule specifications."""
        rules = rule_spec.get('rules', [])
        for rule in rules:
            field = rule.get('field')
            op = rule.get('op', 'contains')

            if field not in self.VALID_FIELDS:
                raise ValueError(f"Invalid field '{field}'. Valid: {self.VALID_FIELDS}")
            if op not in self.VALID_OPS:
                raise ValueError(f"Invalid op '{op}'. Valid: {self.VALID_OPS}")

    @staticmethod
    def validate_rule_spec(rule_spec: dict) -> str:
        """Validate and return error message (empty if valid)."""
        try:
            SmartCollectionManager.validate_rules(rule_spec)
            return ""
        except Exception as e:
            return str(e)

    @staticmethod
    def validate_rules(rule_spec: dict):
        """Validate rule specifications (static method)."""
        rules = rule_spec.get('rules', [])
        for rule in rules:
            field = rule.get('field')
            op = rule.get('op', 'contains')

            if field not in SmartCollectionManager.VALID_FIELDS:
                raise ValueError(f"Invalid field '{field}'. Valid: {SmartCollectionManager.VALID_FIELDS}")
            if op not in SmartCollectionManager.VALID_OPS:
                raise ValueError(f"Invalid op '{op}'. Valid: {SmartCollectionManager.VALID_OPS}")
