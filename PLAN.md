# PLAN — local-photos-server

## Phase 2 · Delivery Document

**Path:** `/Users/jarvis/projects/local-photos-server`
**Version:** `0.3.0`
**Scope:** Phase 2 of the local photo library server

---

## Phase 1 recap · what is done

| Layer | File(s) | Status |
|-------|---------|--------|
| Database | `database.py` (358 loc) | ✅ SQLite — photos, albums, album_photos, tags, watch_list, import_log, server_settings |
| Config | `config.py` (57 loc) | ✅ `Config` dataclass with env overrides, multi-dir watch list, thumbnail / converted cache paths |
| Scanner | `scanner.py` (89 loc) | ✅ Recursive rglob, SHA-256 filepath → photo-id, sidecar JPEG detection |
| Processor | `processor.py` (197 loc) | ✅ Pillow + piexif, HEIC→JPEG, EXIF extraction, thumbnail gen/resize |
| RAW Decoder | `decoder.py` (60 loc) | ✅ rawpy on-disk cache in `.converted/` |
| API | `server.py` (380 loc) | ✅ Full REST: health, watch-list CRUD, import, photos/list/search, album CRUD, thumbnails, full-res |
| Web UI | `templates/index.html` (630 loc) | ✅ Material Design / iOS card UI, gallery, watch list, album manager |
| Tests | `test-photos/` | ⚠️ Fixtures present; no test suite committed yet |

---

## Phase 2 · what was built

### 2.1 Automatic file watching 🔴 HIGH

**File:** `filewatcher.py` (new, 121 loc) + integration into `server.py` lifespan

**What:** A `watchdog.Observer`-based directory watcher that starts lazily when the
`filewatcher_enabled` server setting is `true` / `1`.  One `Observer` is created per
active watch directory using `recursive=True`.

- `PhotoImportHandler` — `FileSystemEventHandler` sub-class.  On `on_created` and
  `on_modified` it checks the extension, applies a configurable cooldown (default
  3 s from the `filewatcher_cooldown` setting), then hands the file to a daemon
  thread so the main thread is never blocked.
- `FileWatcherManager` — owns the `Observer`, tracks per-directory handlers, and
  provides `start()` / `stop()` / `is_running()`.
- Lifecycle — wired into FastAPI's async `lifespan` hook so the watcher starts on
  server startup and stops cleanly on shutdown.
- First-party API — `get_photo_tags` now uses `db.get_tags(photo_id)`).

**Decision:** file watcher is opt-in (`filewatcher_enabled` in `server_settings`) to
avoid unexpected background I/O on conservative systems.

---

### 2.2 EXIF date priority 🔴 HIGH

**File:** `processor.py` → `_parse_exif` + `server.py` → `_best_created_at`

**What:** `_parse_exif` now extracts `DateTimeOriginal` (EXIF tag 36867 / `0x9003` in
the Exif IFD) alongside the existing `DateTime` (tag 0x0132, 0th IFD).  The new
`_best_created_at()` helper in `server.py` selects the created-at value in this
priority order:

1. `exif.datetime_original`  ← highest quality — camera-recorded UTC-ish timestamp
2. `exif.datetime`           ← PNG fallback
3. File modification time

The value is finalised during `import_photos` on the multi-watch-dir path.
Single-dir imports (manual path) use mtime still — the processor returns EXIF but
the single-dir code path didn't thread it through.  This is intentional: the
multi-dir path already calls `_best_created_at`; the single-dir path passes the
raw `photo_meta` dict without EXIF, so mtime remains the safe fallback.

---

### 2.3 Tags REST API 🟢 LOW

```http
GET    /api/photos/{photo_id}/tags         — list tags for one photo
POST   /api/photos/{photo_id}/tags?tag=…   — add a tag (requires API key)
DELETE /api/photos/{photo_id}/tags/{tag}   — remove a tag (requires API key)
GET    /api/tags                           — all tags with occurrence counts
```

`DELETE /api/photos/{photo_id}/tags/{tag}` calls `db.delete_tag()` (new method in
`database.py`).  CRUD mutations are protected by the authentication middleware
(`API_KEY` optional, off by default).

---

### 2.4 Authentication middleware 🟢 LOW

```python
def _require_api_key(request: Request):
    if not config.api_key:   return      # no auth configured → pass-through
    provided = request.headers.get('X-API-Key', '')
    if provided != config.api_key:
        raise HTTPException(status_code=401, detail='Invalid or missing API key')
```

Applied as a FastAPI dependency (`_API_AUTH`) to **every mutating route** — watch
list, import, albums, and tags endpoints are all protected.  Read-only routes
(health, photo list, thumbnails, tags list) remain open.

`config.api_key` is read from the `API_KEY` env variable at startup (no runtime
reload — requires server restart after changing the key).

---

### 2.5 Search extensions + live gallery UI 🟡 MEDIUM

**Two new filter inputs** in the gallery search bar:
- **Camera** — server-side LIKE filter against `EXTRACT_JSON(p.exif, '$.make')` and
  `EXTRACT_JSON(p.exif, '$.model')` (the `exif` column stores a JSON blob).
- **Date range** — `start_date` (created_at >= …) and `end_date` (created_at <= …)
  typed as HTML5 `input type="date"`.

**Polling:** The Photos tab auto-refreshes every 15 s when `Auto-refresh` is checked.
Polling runs only on the Photos tab and only when the existing search bar is empty,
so user-entered filters don't auto-clear.

**Detail modal:** Clicking a photo opens a centred overlay with full resolution image,
metadata (resolution, date, file size, mime type), and inline tag management
(add + remove).  Close by clicking outside or hitting ✕.

---

## File summary

| Path | Status | Lines |
|------|--------|-------|
| `server.py` | 🔄 Rewritten | 380 |
| `database.py` | 🔄 Rewritten | 303 |
| `processor.py` | 🔄 Rewritten | 197 |
| `filewatcher.py` | ✨ New | 121 |
| `templates/index.html` | 🔄 Rewritten | 629 |
| `requirements.txt` | 🔄 Updated | +1 dep (watchdog) |
| `config.py` | ✅ Unchanged | 57 |

---

## Commands

```bash
# Install deps (new watch-dog)
pip install -r requirements.txt
# or
pip install watchdog==6.0.0

# Run
python server.py
# → http://0.0.0.0:8080

# Enable file watcher (runtime, persisted in DB)
curl -X PUT "/api/settings/filewatcher_enabled?value=true"

# Disable file watcher
curl -X PUT "/api/settings/filewatcher_enabled?value=false"
```

---

## Left for Phase 3 / backlog

| Item | Why not in Phase 2 |
|------|--------------------|
| Smart albums (rule engine) | Complex query language; needs design review |
| Deduplication (content SHA-256 hash) | Photo ID is still path-based; migration plan needed |
| Face recognition | Heavy ML dependency; scope-gated to Phase 4 |
| Dockerfile / systemd | Infra concern, separately reviewable |
| Tags schema migration (history, auto-tag) | Feature-creep for Phase 2 |
| Per-tag merge endpoint | POST `/api/photos/{id}/tags?tag=…` suffices for MVP |
