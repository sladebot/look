# Look — CLAUDE.md

## Project Overview

A lightweight, self-hosted photo library server designed to run on a private network (Tailscale). Provides fast browsing, smart organization, deduplication, and tag management for local photo collections.

**Primary entry point:** `main.py` (thin launcher) → `api/server.py` (FastAPI app)  
**Run:** `python main.py`  
**Alt run:** `uvicorn api.server:app`  
**UI:** `http://localhost:8080`

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Web framework | FastAPI 0.115.0 + Uvicorn 0.32.0 |
| Database | SQLite (WAL mode, foreign keys enabled) |
| Image processing | Pillow 10.4.0, rawpy 0.27.0, piexif 1.1.3 |
| File watching | watchdog 6.0.0 |
| Frontend | Vanilla JS/HTML/CSS (no build step) |

---

## File Map

```
main.py                Top-level launcher — `python main.py` starts the server
api/                   Backend Python package
  __init__.py
  server.py            FastAPI app — all route handlers, lifespan, auth middleware
  config.py            Configuration from env vars and DB settings table
  database.py          SQLite ORM-like layer — schema, migrations, all DB queries
  processor.py         Image processing pipeline — EXIF extraction, thumbnail path
  scanner.py           Filesystem scanner — recursive walk, sidecar JPEG detection
  decoder.py           RAW file conversion (ARW/CR2/NEF → JPEG via rawpy)
  filewatcher.py       watchdog-based daemon — auto-import on file creation/change
  smart_collection.py  Rule-based dynamic album evaluation
  dedup_engine.py      Perceptual hashing (pHash/DCT) and duplicate detection
  tags_manager.py      Tag CRUD, auto-tagging from EXIF, tag merging
web/                   Frontend assets
  templates/
    index.html         Single-page gallery UI
  static/              CSS, JSX, JS, SVG assets
tests/                 Test suite (root-level)
scripts/               Utility scripts (root-level)
requirements.txt       Python dependencies
```

---

## Architecture

### Data Model
- **Photo ID:** `SHA-256(absolute_filepath)[:16]` — deterministic, path-based
- **Database:** 11 tables — `photos`, `albums`, `album_photos`, `tags`, `watch_list`, `import_log`, `server_settings`, `content_hashes`, `tag_history`, `duplicates`; smart rules stored in `albums.rule_spec` column
- **Indexes:** `created_at`, `filename`, `mime_type`, `content_hashes.phash`, `tag_history.photo_id`

### Import Pipeline
1. `scanner.py` walks directory, yields file metadata (path, size, mtime)
2. `processor.py` opens image, extracts EXIF, determines thumbnail path
3. `server.py` stores photo record in DB
4. Thumbnails generated on-demand via `/api/thumbnails/{photo_id}?size=N`

### Caching
- Thumbnails → `.thumbnails/` (sibling to photo directory)
- RAW conversions → `.converted/` (sibling to photo directory)
- Duplicates archived to `.trash/`

### Authentication
- Optional; enabled by setting `API_KEY` env var
- Protects all write endpoints via `Depends(_require_api_key)` in `server.py`
- Read endpoints are open (network isolation via Tailscale is assumed)

### Async / Threading
- `FileWatcherManager` starts/stops in FastAPI lifespan
- File watcher spawns daemon threads per filesystem event
- Smart album evaluation can run in background thread (optional)

---

## Configuration (Environment Variables)

```bash
PHOTO_DIR=/path/to/photos          # default watch directory
HOST=0.0.0.0
PORT=8080
DB_PATH=~/.local/local-photos/library.db
API_KEY=                           # leave empty to disable auth
THUMBNAIL_QUALITY=85
MAX_THUMBNAIL_WIDTH=1024
LOG_LEVEL=info
SMART_ALBUMS_ENABLED=false
DEDUP_ENABLED=false
TAG_HISTORY_ENABLED=true
AUTO_TAG_GPS=false
AUTO_TAG_CAMERA=false
FILEWATCHER_COOLDOWN=3             # seconds debounce on file events
```

---

## Key API Endpoints

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/health` | Health check |
| GET | `/api/photos` | Query params: `album`, `tag`, `q`, `camera`, `start_date`, `end_date`, `limit`, `offset` |
| GET | `/api/thumbnails/{photo_id}` | Query param: `size` (128–1024) |
| POST | `/api/import` | Param: `path`; requires API key |
| GET/POST/DELETE | `/api/photos/{id}/tags` | Tag management |
| GET | `/api/tags` | All tags with counts |
| GET/POST/DELETE | `/api/albums` | Album CRUD |
| GET/POST | `/api/smart-collections` | Smart album rules |
| GET | `/api/dedup/scan` | Blocks server; no async |
| POST | `/api/dedup/merge` | Archive duplicates to `.trash/` |
| GET/POST/DELETE | `/api/watch-list` | Manage watched directories |

---

## Known Issues & Technical Debt

### Critical
- **Broad exception handling** — many `except Exception:` blocks swallow errors silently; add specific exception types and structured logging
- **Dedup scan is synchronous** — `GET /api/dedup/scan` blocks the server thread for large libraries; needs async task queue
- **RAW cache collision** — two RAW files with the same basename in different directories both write to `.converted/<basename>.jpg`, overwriting each other; fix by mirroring directory structure or using filepath hash

### High Priority
- **Tag merge not atomic** (`tags_manager.py:66`) — loop runs outside a transaction; partial failure leaves inconsistent state; wrap in `with self.db._connect()`
- **File watcher pending map is unbounded** (`filewatcher.py:22`) — `_pending` dict grows forever; add TTL or LRU eviction
- **Watch list hot-reload missing** — adding a directory via UI doesn't update the running watcher; requires server restart
- **EXIF date skipped on single-path import** — `POST /api/import?path=` uses file mtime only; multi-dir import uses `_best_created_at()`; unify them

### Medium Priority
- **No input validation on file paths** — watch list and import paths not checked for path traversal; validate with `Path.resolve().relative_to(base)`
- **Sidecar JPEG detection is case-sensitive** — only checks `.jpg`/`.jpeg`; use `Path.suffix.lower()` for `.JPG` on case-sensitive filesystems
- **GPS not queryable** — stored in JSON blob in `photos.exif`; normalize to `lat`/`lon` columns for geo-queries
- **No rate limiting** — thumbnail endpoint and dedup scan can be hammered; add FastAPI middleware
- **Photo ID uses truncated hash** — `SHA-256[:16]` = 2^64 keyspace; collision probability is negligible but non-zero; use full hash if uniqueness is critical

### Low Priority
- **No pagination on `/api/tags`** — returns all tags; add `limit`/`offset`
- **DB migrations are manual** — `ALTER TABLE` with try/except in `database.py`; doesn't scale; use Alembic or versioned migration files
- **THUMBNAIL_QUALITY hardcoded** — reads env var at startup (`server.py:28`) but ignores `config.thumbnail_quality` DB setting
- **EXIF dates display raw in UI** — `"2024:02:14 14:30:00"` format may not parse in `new Date()`; normalize to ISO-8601 before serving

---

## No Tests

There is **no automated test suite**. `test-photos/` has sample images but no pytest files. All testing has been manual.

Before adding features, consider covering:
- `processor.py` — EXIF edge cases (malformed, missing)
- `tags_manager.py` — merge atomicity
- `dedup_engine.py` — pHash reproducibility
- `server.py` — import flow, auth enforcement, album CRUD

---

## Feature Status

| Feature | Status |
|---------|--------|
| Multi-directory watch list | Complete |
| JPEG/PNG/HEIC/RAW support | Complete |
| EXIF extraction | Complete |
| Thumbnail generation (on-demand) | Complete |
| Album management (manual) | Complete |
| REST API | Complete |
| Web UI (gallery, modals, search) | Complete |
| Automatic file watching (daemon) | Complete |
| Tags API | Complete |
| Optional API key auth | Complete |
| Smart collections (rule-based) | Complete (Phase 3) |
| Deduplication (pHash) | Complete (Phase 3) |
| Tag history / audit trail | Complete (Phase 3) |
| Auto-tagging from EXIF | Complete (Phase 3) |
| Tag merging | Complete (Phase 3) |
| Async task queue | **Missing** |
| Automated tests | **Missing** |
| Proper DB migrations (Alembic) | **Missing** |
| Rate limiting | **Missing** |
| GPS geocoding / geo-queries | **Missing** |

---

## Development Notes

- Python 3.10+ required (uses `match`-style type hints in places)
- No build step; frontend is plain HTML/JS in `templates/index.html`
- FastAPI auto-generates OpenAPI docs at `/docs`
- SQLite WAL mode means reads don't block writes; safe for concurrent thumbnail requests
- The `.env` file in repo root is for local dev only — do not commit secrets
- `PLAN.md` has detailed Phase 2 delivery notes and design rationale
