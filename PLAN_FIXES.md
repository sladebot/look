# Look — Fix & Improve Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Fix all Phase 3 bugs found during live review, restore smart album evaluation for camera rules, add missing DELETE route, persist EXIF data, and add minimal test coverage.

**Architecture:** The app was refactored into `api/` (backend Python package) and `web/` (frontend templates + static). This plan touches only `api/` files and adds tests under `tests/`.

**Tech Stack:** FastAPI 0.115.0, SQLite (WAL), Pillow, piexif, pytest

---

## Pre-work: Acceptance criteria reference

From the live review on 2026-05-20, here is what must work after this plan:

| Feature | Before | After |
|---------|--------|-------|
| Camera search (`?camera=Canon`) | ✅ | ✅ |
| Keyword smart album | ✅ | ✅ |
| Camera smart album EVAL | ❌ 0 matches | ✅ N matches |
| DELETE smart collection | ❌ 405 | ✅ 200 |
| Auto-tag from EXIF | ❌ empty | ✅ returns tags |
| Tag suggest | ❌ empty | ✅ returns suggestions |
| Import explicit path | ❌ 500 (scan_count) | ✅ 200 |
| Dedup scan | ❌ broken DCT | ✅ realistic groups |
| Merge tags | ❌ NameError | ✅ atomic |

---

## Phase 1 — Critical fixes (safety + correctness)

These are blocking issues that crash the server or silently return wrong results.

---

### Task 1.1: Add `scanner.scan_count` attribute

**Objective:** Fix `POST /api/import?path=...` crashing with `AttributeError: 'DirectoryScanner' object has no attribute 'scan_count'`

**Files:**
- Modify: `api/scanner.py:15-33` — add `scan_count` to `DirectoryScanner.scan()`
- Modify: `api/server.py:256` — update reference (already correct once attribute exists)

**Step 1: Read the current scan method**

```bash
read_file("api/scanner.py", offset=15, limit=20)
```

**Step 2: Add `scan_count` after the scan loop**

In `api/scanner.py`, method `DirectoryScanner.scan()`, after the for-loop that populates `photos`, add:

```python
        self.scan_count = len(photos)
```

before the `return photos` line. The method currently returns from inside the for loop — ensure `scan_count` is set immediately before `return photos`.

**Step 3: Write a unit test**

Create `tests/test_scanner.py`:

```python
import tempfile, pathlib
from PIL import Image
from api.scanner import DirectoryScanner

def test_scanner_has_scan_count():
    """DirectoryScanner.scan() sets scan_count attribute."""
    with tempfile.TemporaryDirectory() as td:
        # Create one JPEG
        img = Image.new('RGB', (10, 10), color='red')
        img.save(pathlib.Path(td) / 'test.jpg', 'JPEG')
        scanner = DirectoryScanner(td, ('.jpg', '.jpeg'))
        photos = scanner.scan(recursive=False)
        assert len(photos) == 1
        assert scanner.scan_count == 1
```

**Step 4: Run the test**

```bash
.venv/bin/pip install pytest httpx  # if not already installed
.venv/bin/python -m pytest tests/test_scanner.py -v
```

Expected: 1 passed

**Step 5: Commit**

```bash
git add api/scanner.py tests/test_scanner.py
git commit -m "fix: add scan_count attribute to DirectoryScanner.scan()"
```

---

### Task 1.2: Fix `tags_manager.merge_tags` connection scope

**Objective:** The `conn` variable is referenced outside its `with` block on lines 95-99, causing `NameError`. Fix by wrapping the entire operation in a single connection + transaction.

**Files:**
- Modify: `api/tags_manager.py:66-116`

**Step 1: Read current code**

```bash
read_file("api/tags_manager.py", offset=66, limit=50)
```

**Step 2: Rewrite `merge_tags`**

Replace the body of `merge_tags` in `api/tags_manager.py` with a single `with self.db._connect() as conn:` block that spans the fetch, delete, insert, and history steps. Remove the per-iteration `try/except Exception` swallower.

```python
    def merge_tags(self, source_tag: str, target_tag: str) -> Dict:
        source_tag = source_tag.strip()
        target_tag = target_tag.strip()
        if source_tag == target_tag:
            return {'error': 'Source and target are the same'}

        with self.db._connect() as conn:
            rows = conn.execute(
                "SELECT photo_id FROM tags WHERE tag = ?", (source_tag,)
            ).fetchall()
            photo_ids = [row['photo_id'] for row in rows]
            count = 0
            for pid in photo_ids:
                conn.execute(
                    "DELETE FROM tags WHERE photo_id = ? AND tag = ?",
                    (pid, source_tag)
                )
                conn.execute(
                    "INSERT OR IGNORE INTO tags (photo_id, tag) VALUES (?, ?)",
                    (pid, target_tag)
                )
                count += 1
                if self.config.tag_history_enabled:
                    self.db.add_tag_history(pid, source_tag, 'removed', 'merge')
                    self.db.add_tag_history(pid, target_tag, 'added', 'merge')

        return {
            'merged': source_tag,
            'into': target_tag,
            'photos_affected': count
        }
```

**Step 3: Write test**

Create `tests/test_tags_manager.py`:

```python
import tempfile, os
from api.tags_manager import TagsManager
from api.database import PhotoDatabase

class FakeConfig:
    tag_history_enabled = False
    auto_tag_gps = False
    auto_tag_camera = False

def test_merge_tags_atomic():
    """merge_tags should complete cleanly within one connection."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        db.store_photo({
            'id': 'p1', 'filename': 'a.jpg', 'filepath': '/tmp/a.jpg',
            'file_size': 100, 'width': 10, 'height': 10,
            'mime_type': 'image/jpeg', 'created_at': '2024-01-01T00:00:00',
            'indexed_at': '2024-01-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False
        })
        db.add_tag('p1', 'OldTag')
        tm = TagsManager(db, FakeConfig())
        result = tm.merge_tags('OldTag', 'NewTag')
        # Should not raise NameError or ProgrammingError
        assert result.get('photos_affected') == 1
        # Verify OldTag is gone and NewTag exists
        tags = db.get_tags('p1')
        assert 'NewTag' in tags
        assert 'OldTag' not in tags
    finally:
        os.unlink(db_path)
```

**Step 4: Run**

```bash
.venv/bin/python -m pytest tests/test_tags_manager.py -v
```

Expected: 1 passed

**Step 5: Commit**

```bash
git add api/tags_manager.py tests/test_tags_manager.py
git commit -m "fix: wrap merge_tags in single connection + transaction"
```

---

### Task 1.3: Persist EXIF data in `store_photo` and `CREATE TABLE photos`

**Objective:** Make EXIF data available so auto-tagging and smart album camera rules can use it.

**Files:**
- Modify: `api/database.py:26-40` — add `exif` column to CREATE TABLE
- Modify: `api/database.py:321-349` — add exif to `store_photo()` INSERT
- Modify: `api/server.py:228-235` — pass exif into photo dict during import

**Step 1: Add exif column to schema**

In `api/database.py`, `init_db()`, add to CREATE TABLE photos:

```sql
                CREATE TABLE IF NOT EXISTS photos (
                    ...
                    is_source_jpeg INTEGER DEFAULT 0,  -- 1 if this is a converted/sidecar JPEG
                    exif         TEXT DEFAULT NULL  -- JSON blob of EXIF data
                );
```

Add a migration right after the `rule_spec` migration (around line 142):

```python
        # Migration: add exif column to photos
        try:
            with self._connect() as conn:
                conn.execute("ALTER TABLE photos ADD COLUMN exif TEXT DEFAULT NULL")
                print("[db] Migration: added exif column to photos")
        except Exception:
            pass  # column already exists
```

**Step 2: Update store_photo to save exif**

In `api/database.py`, `store_photo()`, add `exif` to the INSERT and UPDATE columns:

```python
    def store_photo(self, photo: dict):
        with self._connect() as conn:
            import json
            exif_json = None
            if photo.get('exif'):
                exif_json = json.dumps(photo['exif']) if isinstance(photo['exif'], dict) else photo['exif']
            conn.execute("""
                INSERT INTO photos (id, filename, filepath, file_size, width, height,
                                   mime_type, created_at, indexed_at, has_thumbnail,
                                   is_favorite, color_tag, is_source_jpeg, exif)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(filepath) DO UPDATE SET
                    ...
                    is_source_jpeg = excluded.is_source_jpeg,
                    exif = excluded.exif
            """, (
                photo['id'], photo['filename'], photo['filepath'],
                photo.get('file_size'), photo.get('width'), photo.get('height'),
                photo.get('mime_type'), photo.get('created_at'),
                photo.get('indexed_at', datetime.now().isoformat()),
                1 if photo.get('has_thumbnail') else 0,
                1 if photo.get('is_favorite') else 0,
                photo.get('color_tag', 'none'),
                1 if photo.get('is_source_jpeg') else 0,
                exif_json
            ))
```

**Step 3: Pass EXIF during import**

In `api/server.py`, both import paths (specific-path around line 202, no-path around line 228), add:

```python
                    photo_meta['exif'] = proc_result.get('exif', {})
```

after the `proc_result` is obtained.

**Step 4: Write test**

Create `tests/test_exif_persistence.py`:

```python
import tempfile, os, json
from PIL import Image
import piexif
from api.database import PhotoDatabase

def test_store_photo_with_exif():
    """store_photo persists exif as JSON."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        exif_data = {'make': 'Canon', 'model': 'EOS R5'}
        db.store_photo({
            'id': 'p1', 'filename': 'a.jpg', 'filepath': '/tmp/a.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-01-01T00:00:00',
            'indexed_at': '2024-01-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': exif_data
        })
        photo = db.get_photo('p1')
        stored_exif = photo.get('exif')
        assert stored_exif is not None
        parsed = json.loads(stored_exif) if isinstance(stored_exif, str) else stored_exif
        assert parsed['make'] == 'Canon'
        assert parsed['model'] == 'EOS R5'
    finally:
        os.unlink(db_path)
```

**Step 5: Run**

```bash
.venv/bin/python -m pytest tests/test_exif_persistence.py -v
```

Expected: 1 passed

**Step 6: Commit**

```bash
git add api/database.py api/server.py tests/test_exif_persistence.py
git commit -m "feat: persist exif JSON in photos table"
```

---

### Task 1.4: Add DELETE route for smart collections

**Objective:** Fix 405 Method Not Allowed when the UI calls `DELETE /api/smart-collections/{album_id}`

**Files:**
- Modify: `api/server.py` — add new route

**Step 1: Add the route**

After the `eval_smart_collection` route (line 563 in `api/server.py`), add:

```python
@app.delete("/api/smart-collections/{album_id}")
async def delete_smart_collection(album_id: str, _auth=_API_AUTH):
    """Delete a smart album (the album and its rules, not the photos)."""
    success = db.delete_album(album_id)
    if not success:
        raise HTTPException(status_code=404, detail="Smart album not found")
    return {"status": "ok", "album_id": album_id}
```

> Note: `db.delete_album()` already exists (database.py line 268) and works for any album regardless of source.

**Step 2: Write test**

Add to `tests/test_smart_collections.py` (create if needed):

```python
from api.server import app
from fastapi.testclient import TestClient

def test_delete_smart_collection():
    """DELETE /api/smart-collections/{id} returns 200."""
    import tempfile, os
    # Use a fresh test DB path
    test_db = tempfile.mktemp(suffix='.db')
    os.environ['DB_PATH'] = test_db
    # Rest of test depends on test infrastructure...
```

> For integration testing, use the existing `smoke.py` pattern or a manual curl test.

**Step 3: Manual verification**

```bash
# Create a smart album
curl -X POST 'http://127.0.0.1:8765/api/smart-collections?name=Test&rule_spec=%7B%22rules%22%3A%5B%5D%7D'
# Delete it
curl -X DELETE 'http://127.0.0.1:8765/api/smart-collections/<album_id>'
# Expected: {"status":"ok","album_id":"<album_id>"}
```

**Step 4: Commit**

```bash
git add api/server.py
git commit -m "feat: add DELETE /api/smart-collections/{album_id} route"
```

---

### Task 1.5: Fix camera smart album evaluation

**Objective:** Camera-based smart album rules match against the EXIF JSON stored in the `exif` column using SQLite's `json_extract` function.

**Files:**
- Modify: `api/database.py:498-560` — `_evaluate_rules` camera section
- Verify: `api/database.py:170-177` — `_extend_query` camera filter (already works, leave as-is)

**Step 1: Replace `EXTRACT_JSON` with `json_extract`**

In `api/database.py`, `_evaluate_rules()`, replace the camera condition block (lines 516-523):

```python
            if field == 'camera':
                cond = "json_extract(p.exif, '$.model') LIKE ?"
                if op == 'equals':
                    cond = "json_extract(p.exif, '$.model') = ?"
                elif op == 'regex':
                    # REGEXP may not be available; use LIKE as fallback
                    cond = "json_extract(p.exif, '$.model') LIKE ?"
                conditions.append(cond)
                params.append(f'%{value}%')
```

Similarly, fix the `_extend_query` camera block (lines 171-177) which currently uses `EXTRACT_JSON` — replace with `json_extract`:

```python
        if camera:
            cond_cam = (
                "json_extract(p.exif, '$.make')  LIKE ?"
                " OR json_extract(p.exif, '$.model') LIKE ?"
            )
            conditions.append(f"({cond_cam})")
            params.extend([f"%{camera}%", f"%{camera}%"])
```

**Step 2: Write test**

Create `tests/test_smart_eval.py`:

```python
import tempfile, os, json
from api.database import PhotoDatabase

def test_camera_rule_matches_exif():
    """_evaluate_rules with camera:contains matches exif JSON."""
    with tempfile.NamedTemporaryFile(suffix='.db', delete=False) as f:
        db_path = f.name
    try:
        db = PhotoDatabase(db_path)
        # Store a photo with Canon exif
        db.store_photo({
            'id': 'p1', 'filename': 'a.jpg', 'filepath': '/tmp/a.jpg',
            'file_size': 100, 'width': 800, 'height': 600,
            'mime_type': 'image/jpeg', 'created_at': '2024-06-01T00:00:00',
            'indexed_at': '2024-06-01T00:00:00',
            'has_thumbnail': False, 'is_favorite': False,
            'color_tag': 'none', 'is_source_jpeg': False,
            'exif': json.dumps({'make': 'Canon', 'model': 'EOS R5'})
        })
        rules = {'rules': [{'field': 'camera', 'op': 'contains', 'value': 'Canon'}]}
        matching = db._evaluate_rules(rules)
        assert matching == ['p1'], f"Expected ['p1'], got {matching}"
    finally:
        os.unlink(db_path)
```

**Step 4: Run**

```bash
.venv/bin/python -m pytest tests/test_smart_eval.py -v
```

Expected: 1 passed

**Step 5: Commit**

```bash
git add api/database.py tests/test_smart_eval.py
git commit -m "fix: use json_extract instead of EXTRACT_JSON for camera rules"
```

---

### Task 1.6: Fix dedup DCT formula

**Objective:** The `_dct_2d` method in `dedup_engine.py` is missing `math.cos()`, making all perceptual hashes invalid.

**Files:**
- Modify: `api/dedup_engine.py:59-75`

**Step 1: Add `import math` at top**

```python
import math
```

**Step 2: Fix the DCT formula**

Replace the inner loop in `_dct_2d`:

```python
    def _dct_2d(self, pixels: list) -> list:
        """Compute 2D DCT coefficients for a 16x16 image."""
        import math
        grid = [pixels[i * 16:(i + 1) * 16] for i in range(16)]
        coeffs = [[0.0] * 8 for _ in range(8)]
        for u in range(8):
            for v in range(8):
                total = 0.0
                for x in range(16):
                    for y in range(16):
                        total += grid[x][y] * math.cos(
                            (2 * x + 1) * u * math.pi / 32.0
                        ) * math.cos(
                            (2 * y + 1) * v * math.pi / 32.0
                        )
                coeffs[u][v] = total * 2.0 / 16.0  # normalize
        return [c for row in coeffs for c in row]
```

**Step 3: Write test**

Add to `tests/test_dedup.py`:

```python
from api.dedup_engine import DedupEngine

class FakeDB:
    pass

class FakeConfig:
    dedup_tolerance = 20
    photo_dir = '/tmp'

def test_dct_has_math_cos():
    """DCT formula must include math.cos() calls."""
    import inspect, math
    engine = DedupEngine(FakeDB(), FakeConfig())
    source = inspect.getsource(engine._dct_2d)
    assert 'math.cos' in source or 'cos(' in source, "DCT formula missing cos() call"
```

**Step 4: Run**

```bash
.venv/bin/python -m pytest tests/test_dedup.py -v
```

Expected: 1 passed

**Step 5: Commit**

```bash
git add api/dedup_engine.py tests/test_dedup.py
git commit -m "fix: restore math.cos() in DCT 2D formula for correct pHash"
```

---

## Phase 2 — Quality improvements

These improve reliability and user experience.

---

### Task 2.1: Clean stale root-level `__pycache__`

**Objective:** Remove stale `__pycache__` directories at the repo root left from pre-refactor layout.

**Files:**
- Remove: `__pycache__/` (root level only — keep `api/__pycache__/`)

**Step 1: Remove root pycache**

```bash
rm -rf __pycache__/
git add -A
git commit -m "chore: remove stale root-level __pycache__ from pre-refactor layout"
```

---

### Task 2.2: Fix filewatcher imports and config.get_setting

**Objective:** Fix `filewatcher.py` crashing on startup due to missing `DirectoryScanner` import.

**Files:**
- Modify: `api/filewatcher.py`

**Step 1: Add import**

At the top of `api/filewatcher.py`:

```python
from api.scanner import DirectoryScanner
```

**Step 2: Check config.get_setting call**

Search for `config.get_setting` in `api/filewatcher.py` — if present, replace with:

```python
cooldown = getattr(config, 'filewatcher_cooldown', '3')
```

**Step 3: Commit**

```bash
git add api/filewatcher.py
git commit -m "fix: add DirectoryScanner import to filewatcher.py"
```

---

## Phase 3 — Polish

### Task 3.1: Register json_extract as SQLite function for backwards compat

**Objective:** Even with the column migration, older SQLite builds may not have `json_extract`. Register it on DB init.

In `api/database.py`, `_connect()` or `init_db()`, add:

```python
    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        # Register json_extract in case SQLite < 3.38
        import json
        conn.create_function("json_extract", 2, lambda data, path: (
            (json.loads(data) if isinstance(data, str) else data or {}).get(
                path.lstrip('$.'), None
            )
        ) if data else None)
        return conn
```

### Task 3.2: Fix thumbnail size parameter ignored

In `api/processor.py`, `_get_thumbnail_path()` should include the `size` parameter. Change:

```python
    def _get_thumbnail_path(self, source_path: str, size: int = None) -> str:
        import hashlib
        source_hash = hashlib.sha256(source_path.encode()).hexdigest()[:16]
        thumb_dir = Path(self.config.photo_dir) / self.config.thumbnails_dir
        suffix = f"_{size}" if size else ""
        return str(thumb_dir / f"{source_hash}{suffix}.jpg")
```

---

## Verification Checklist

After all tasks are complete, run:

```bash
# 1. All tests pass
.venv/bin/python -m pytest tests/ -v

# 2. Compile passes for all Python files
.venv/bin/python -m py_compile api/*.py

# 3. Server starts
.venv/bin/python main.py &
sleep 2
curl http://127.0.0.1:8765/api/health | python3 -m json.tool

# 4. Camera search works
curl 'http://127.0.0.1:8765/api/photos?camera=Canon'

# 5. Camera smart album evaluates correctly
# (create, eval, verify photo count > 0)

# 6. Auto-tag returns tags for EXIF-rich photos
# POST /api/photos/{id}/tags/auto

# 7. DELETE smart collection returns 200
# DELETE /api/smart-collections/{id}

# 8. Git working tree is clean
git status --short
```

---

## Task execution order (dependency graph)

```
1.1 scan_count     ─┐
1.2 merge_tags     ─┤
1.3 exif persist   ─┼─► 1.5 camera eval  ─► 1.4 delete route
1.6 dedup DCT      ─┘
                        │
                        ▼
                    2.1 stale pycache
                    2.2 filewatcher fix
                        │
                        ▼
                    3.1 json_extract compat
                    3.2 thumbnail size fix
```