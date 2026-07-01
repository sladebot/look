# Look — AGENTS.md

## Project Overview

A lightweight, self-hosted photo library designed to run on a private network (Tailscale). Provides fast browsing, search, albums, tags, smart collections, deduplication, and GPS/geo-queries for local photo collections — without moving the archive into a cloud service.

The project has two parts:
- **FastAPI server** (`api/`) that indexes a local photo folder and exposes a REST API + web UI.
- **Native iOS/iPad app** (`ios/`, SwiftUI) that is a *client* for a self-hosted Look server. It does not scan the phone's photo library and does not host photos in the cloud.

**Primary entry point:** `api/server.py` (FastAPI app)  
**Required env:** project-local conda env at `.conda/` (Python 3.13)  
**Run:** `./.conda/bin/python -m uvicorn api.server:app --host 0.0.0.0 --port 5678`  
**UI:** `http://studio.taila3f2b.ts.net:5678`

> **Note:** `CLAUDE.md` is the sibling copy of this file (identical content) for Claude tooling. If you change one, update the other to keep them in sync.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Web framework | FastAPI 0.115.0 + Uvicorn 0.32.0 |
| Database | SQLite (WAL mode, foreign keys enabled) |
| Image processing | Pillow 10.4.0, rawpy 0.27.0, piexif 1.1.3 |
| File watching | watchdog 6.0.0 |
| Web frontend | React (JSX), served without a build step from `web/` |
| iOS client | SwiftUI (Xcode project in `ios/Look.xcodeproj`) |
| Tests | pytest + httpx (ASGI transport) |

---

## File Map

```
main.py                Legacy thin launcher; prefer the uvicorn command below
api/                   Backend Python package
  __init__.py
  server.py            FastAPI app — all route handlers, lifespan, auth middleware (~55 routes)
  config.py            Configuration from env vars and DB settings table
  database.py          SQLite layer — schema, table creation, all DB queries, geo_query
  migrations.py        Versioned schema migrations w/ rollback (schema_version in server_settings)
  processor.py         Image processing pipeline — EXIF extraction, GPS parse, thumbnail path
  scanner.py           Filesystem scanner — recursive walk, case-insensitive sidecar JPEG detection
  decoder.py           RAW file conversion (ARW/CR2/NEF → JPEG via rawpy)
  filewatcher.py       watchdog-based daemon — auto-import on file creation/change
  preview_queue.py     Background RAW→JPEG preview generation queue
  task_queue.py        Generic async background task queue (dedup scans, etc.)
  rate_limiter.py      FastAPI rate-limiting middleware
  smart_collection.py  Rule-based dynamic album evaluation
  dedup_engine.py      Perceptual hashing (pHash/DCT) and duplicate detection
  tags_manager.py      Tag CRUD, auto-tagging from EXIF, atomic tag merging
web/                   Web frontend assets (React, no build step)
  templates/
    index.html         Single-page app shell
  static/              *.jsx (shell, app, admin, detail, grid, tweaks-panel), look-data.js, CSS, SVG
ios/                   Native SwiftUI client
  Look/                App sources — APIClient, PhotoStore, Models, ~20 Views
  Look.xcodeproj       Xcode project
  LookTests/           iOS tests
  scripts/             iOS build/screenshot helpers
tests/                 pytest suite (root-level; conftest.py + 13 test modules)
scripts/               Utility scripts (backfill_dimensions, regen_thumbnails, scan_secrets, smoke)
demo/                  App Store screenshots + contact sheets (generated mock data)
docs/                  Additional docs
requirements.txt       Python dependencies (incl. test deps)
```

---

## Architecture

### Data Model
- **Photo ID:** `SHA-256(absolute_filepath)[:16]` — deterministic, path-based
- **Database:** 10 tables — `photos`, `albums`, `album_photos`, `tags`, `import_log`, `watch_list`, `server_settings`, `content_hashes`, `tag_history`, `duplicates`; smart rules stored in `albums.rule_spec`
- **GPS:** normalized `photos.gps_lat` / `photos.gps_lon` REAL columns (nullable), populated from EXIF; partial index `idx_photos_gps` enables radius queries via `database.geo_query()` (haversine)
- **Schema version:** tracked as `schema_version` key in `server_settings`, driven by `migrations.py`
- **Indexes:** `created_at`, `filename`, `mime_type`, `content_hashes.phash`, `tag_history.photo_id`, `photos(gps_lat, gps_lon)`

### Import Pipeline
1. `scanner.py` walks directory, yields file metadata (path, size, mtime)
2. `processor.py` opens image, extracts EXIF (incl. GPS), determines thumbnail path
3. `server.py` stores photo record in DB
4. Thumbnails generated on-demand via `/api/thumbnails/{photo_id}?size=N`

### Caching
- Thumbnails → `thumbnails/` inside each watched photo directory
- RAW JPEG previews → `converted/` inside each watched photo directory
- Duplicates archived to `.trash/`

### Authentication
- Optional; enabled by setting `API_KEY` env var
- Protects all write endpoints via `Depends(_require_api_key)` in `server.py`
- Read endpoints are open (network isolation via Tailscale is assumed)

### Async / Threading
- `FileWatcherManager` starts/stops in FastAPI lifespan; spawns daemon threads per filesystem event
- `task_queue.py` runs background jobs (e.g. dedup scan) with submit/poll/cancel via `/api/tasks`
- `preview_queue.py` generates RAW previews off the request path
- Smart album evaluation can run in a background thread (optional)

---

## Configuration (Environment Variables)

```bash
PHOTO_DIR=/path/to/photos          # default watch directory
HOST=0.0.0.0
PORT=5678
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

See `.env.example` for the current template.

---

## Key API Endpoints

(~55 routes total; see `api/server.py` or `/docs` for the full list.)

| Method | Path | Notes |
|--------|------|-------|
| GET | `/api/health` | Health check |
| GET | `/api/photos` | Query params: `album`, `tag`, `q`, `camera`, `start_date`, `end_date`, `limit`, `offset` |
| GET | `/api/photos/nearby` | Geo radius search: `lat`, `lon`, `radius_km`, `limit`, `offset` |
| GET | `/api/photos/{id}` | Single photo metadata |
| GET | `/api/thumbnails/{photo_id}` | Query param: `size` (128–1024) |
| GET | `/api/full/{photo_id}` · `/api/download/jpeg/{id}` · `/api/download/raw/{id}` | Full image / downloads |
| POST | `/api/import` | Param: `path`; requires API key |
| GET/POST/DELETE | `/api/photos/{id}/tags` | Tag management (+ `/history`, `/auto`, `/suggest`) |
| GET | `/api/tags` · POST `/api/tags/merge` | Tags with counts; atomic merge |
| GET | `/api/search` | Search across filename/path/tags/camera/date |
| CRUD | `/api/albums` (+ `/photos/{id}`) | Album CRUD and membership |
| CRUD | `/api/smart-collections` (+ `/eval`) | Rule-based smart albums |
| POST/GET | `/api/dedup/scan` | POST submits async task → `task_id`; GET polls (or legacy sync scan) |
| POST | `/api/dedup/merge` | Archive duplicates to `.trash/` |
| GET/POST | `/api/tasks` (+ `/{id}`, `/{id}/cancel`) | Background task status/control |
| GET/POST | `/api/migrate` (+ `/rollback`) | Schema migration status / run / rollback |
| CRUD | `/api/watch-list` (+ `/active`) | Manage watched directories |
| GET/PUT | `/api/settings` (+ `/{key}`) | Server settings |

---

## Runtime

Use the project-local conda environment. Do not run with the base Python.

```bash
# Create once if missing
conda create -p ./.conda python=3.13 pip -y
./.conda/bin/python -m pip install -r requirements.txt

# Start Look
./.conda/bin/python -m uvicorn api.server:app --host 0.0.0.0 --port 5678
```

The app stores its SQLite DB at `~/.local/local-photos/library.db`, so commands that run under a filesystem sandbox may fail with `sqlite3.OperationalError: unable to open database file`. Start the server with normal filesystem access when running from agent tooling.

---

## Testing

There **is** an automated pytest suite in `tests/` (13 modules + `conftest.py`). It uses `httpx` with an ASGI transport (`conftest.py` wraps the async-only transport for sync clients) so `server.py` routes can be exercised in-process.

```bash
./.conda/bin/python -m pytest            # run all tests
./.conda/bin/python -m pytest tests/test_server.py -q
```

Coverage includes: scanner, dedup, GPS/geo, migrations, rate limiter, RAW import + preview, server routes, smart collection CRUD + eval, tags manager, task queue, watch/scan, EXIF persistence. iOS has a separate `ios/LookTests/` suite run via Xcode.

---

## Known Issues & Technical Debt

> Several items previously listed here have been resolved: dedup is now async (`task_queue`), GPS is queryable (`gps_lat/gps_lon` + `geo_query`), migrations are versioned (`migrations.py`), rate limiting exists (`rate_limiter.py`), tag merge is atomic (single transaction in `tags_manager.merge_tags`), and sidecar JPEG detection is case-insensitive. Verify against current code before acting on any item below.

### Critical
- **Broad exception handling** — many `except Exception:` blocks swallow errors silently; add specific exception types and structured logging

### High Priority
- **File watcher pending map is unbounded** (`filewatcher.py`) — `_pending` dict grows without eviction; add TTL or LRU
- **Watch list hot-reload** — verify whether adding a directory via UI updates the running watcher without a restart

### Medium Priority
- **Path traversal validation** — confirm watch-list/import paths are validated (e.g. `Path.resolve().relative_to(base)`)
- **Photo ID uses truncated hash** — `SHA-256[:16]` = 2^64 keyspace; collision probability negligible but non-zero; use full hash if uniqueness is critical
- **THUMBNAIL_QUALITY source of truth** — read at startup from env (`server.py`) and also present as a DB/config setting (`config.thumbnail_quality`); unify so the DB setting is honored

### Low Priority
- **No pagination on `/api/tags`** — returns all tags; add `limit`/`offset`
- **EXIF dates display raw in UI** — `"2024:02:14 14:30:00"` may not parse in `new Date()`; normalize to ISO-8601 before serving

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
| Web UI (React: gallery, modals, search, admin) | Complete |
| Native iOS/iPad client (SwiftUI) | Complete |
| Automatic file watching (daemon) | Complete |
| Tags API | Complete |
| Optional API key auth | Complete |
| Smart collections (rule-based) | Complete |
| Deduplication (pHash) | Complete |
| Tag history / audit trail | Complete |
| Auto-tagging from EXIF | Complete |
| Tag merging (atomic) | Complete |
| Async task queue | Complete |
| Rate limiting | Complete |
| Versioned DB migrations (+ rollback) | Complete |
| GPS geo-queries (radius search) | Complete |
| Automated tests (pytest + iOS) | Complete |
| Reverse geocoding (place names) | **Missing** |

---

## Development Notes

- Python 3.13 in `.conda/` (backend). Do not use base Python.
- Web frontend is React (JSX) served directly from `web/` with no build step.
- The iOS app is a client only; see `ios/` and the auto-memory notes on building/verifying it.
- FastAPI auto-generates OpenAPI docs at `/docs`.
- SQLite WAL mode means reads don't block writes; safe for concurrent thumbnail requests.
- `.env` in repo root is for local dev only — do not commit secrets (`scripts/scan_secrets.py` guards against this).
- `PLAN.md` / `PLAN_FIXES.md` have detailed delivery notes and design rationale.
