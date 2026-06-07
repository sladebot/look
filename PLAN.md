# Production Upgrade Plan: look

## Methodology Notes

All bug references below have been verified against the actual source. Notable findings beyond the initial review:

- `tags_manager.merge_tags` uses `conn` on lines 95–99 after the `with` block that opened it closes at line 86 — this is an active NameError or stale-connection bug, not just a missing transaction.
- `filewatcher.py` references `DirectoryScanner` on line 125 without importing it — the watcher crashes on startup when `filewatcher_enabled=true`.
- `config.get_setting()` does not exist on the `Config` dataclass — `filewatcher.py` line 27 calls it and will raise `AttributeError` at startup.
- `server.py` line 265 references `scanner_local.scan_count`, but `DirectoryScanner` has no `scan_count` attribute — silently fails.
- The `exif` column is queried via `EXTRACT_JSON` in `database.py` (lines 173–174, 524–528), but that column is never defined in `CREATE TABLE photos` — camera-filter queries always return nothing or raise errors on SQLite builds without the JSON1 extension.
- `/api/photos` returns `"total": len(photos)` which is the count of the current page, not the true total — frontend cannot implement correct pagination.
- The `list_photos` query uses `LEFT JOIN tags` without `DISTINCT`, meaning photos with multiple tags are returned as duplicate rows.

**Second-pass review additions (2026-05-22):**

- Items 1.6 and 1.9 were already fixed in the current code (see notes on those tasks below).
- `processor.py:_get_thumbnail_path` ignores the `size` parameter — all thumbnails for a photo share one filename regardless of requested size; `?size=N` on the thumbnail endpoint is silently ignored after first generation. (New: 1.10)
- GPS coordinate parsing is broken: EXIF stores lat/lon as 3-component DMS rationals but `_convert_exif_float` handles only a single `(n, d)` rational — produces a TypeError swallowed by `except:`, storing `0.0`. (New: 1.11)
- The DCT formula in `dedup_engine.py:_dct_2d` has no `math.cos()` call — hashes do not reflect perceptual similarity, making all dedup results unreliable. (New: 1.12)
- `@app.on_event("startup")` is mixed with the `lifespan` context manager in `server.py` — deprecated API can conflict with lifespan; static mount should move inside `lifespan`. (New: 1.13)
- Several route handlers bypass existing ORM/manager methods (e.g. `DELETE /api/photos/{id}/tags/{tag}` uses raw SQL despite `db.delete_tag()` existing; `GET /api/tags` duplicates `tags_manager.get_all_tags()`). (New: 1.14)

---

## Phase 1 — Critical Fixes (Safety & Correctness)

**Goal:** Eliminate crashes, data-loss risks, and silent failures. These are blocking issues in production.

---

### 1.1 Fix `merge_tags` connection scope (active NameError / data-loss bug)

**Scope:** S  
**Files:** `tags_manager.py`

**Problem:** `conn` is opened in a `with self.db._connect() as conn:` block (lines 83–86), closed when that block exits, then referenced again on lines 95–99. On CPython this will either silently use a closed connection or raise `NameError`/`ProgrammingError`. No transaction wraps the entire operation, so partial merges leave orphaned source tags.

**Fix:**
- Wrap the entire fetch-and-update loop in a single `with self.db._connect() as conn:` block.
- Execute all `DELETE` and `INSERT` statements inside that same block — they will all run atomically within one SQLite transaction.
- Remove the per-iteration `try/except Exception` swallower; let the outer transaction roll back on error and raise a typed exception the route handler can catch and return as a 500.

**Acceptance criteria:**
- Merging tag A into tag B with 1,000 photos succeeds with zero remaining A-tag rows in `tags`.
- If the DB write fails mid-loop, no rows are modified (rollback verified by inspecting `tags` table).

---

### 1.2 Fix `filewatcher.py` missing `DirectoryScanner` import and `config.get_setting` AttributeError

**Scope:** S  
**Files:** `filewatcher.py`, `config.py`

**Problem 1:** Line 125 of `filewatcher.py` instantiates `DirectoryScanner` without importing it — the watcher crashes immediately when `filewatcher_enabled=true`.

**Problem 2:** Line 27 calls `config.get_setting('filewatcher_cooldown')` but `Config` is a dataclass with no such method — raises `AttributeError` at import time when the handler is constructed.

**Fix:**
- Add `from scanner import DirectoryScanner` at the top of `filewatcher.py`.
- Replace `config.get_setting('filewatcher_cooldown')` with `getattr(config, 'filewatcher_cooldown', '3')` (the attribute already exists on `Config`).

**Acceptance criteria:**
- Server starts with `FILEWATCHER_ENABLED=true` without exception.
- A new JPEG dropped into a watched directory appears in the DB within the cooldown window.

---

### 1.3 Fix RAW cache collision in `decoder.py`

**Scope:** S  
**Files:** `decoder.py`

**Problem:** `_get_converted_path` derives the output filename from `Path(filepath).stem` only — `photo_dir_A/DSC001.ARW` and `photo_dir_B/DSC001.ARW` both map to `.converted/DSC001.jpg`, and whichever is written second silently overwrites the first.

**Fix:**
- Key the converted filename on a content-stable identifier: `hashlib.sha256(filepath.encode()).hexdigest()[:16]` (same approach used by `processor._get_thumbnail_path`).
- New pattern: `.converted/<sha256[:16]>.jpg`.

**Acceptance criteria:**
- Two RAW files with identical basenames in different directories both decode to distinct cache paths.
- Existing `.converted/` cache invalidation is not required (old files will be orphaned and can be cleaned up by a separate housekeeping task).

---

### 1.4 Fix sidecar JPEG detection case sensitivity

**Scope:** S  
**Files:** `scanner.py`

**Problem:** `find_sidecar_jpeg` checks only `['.jpg', '.jpeg']` (lowercase). On case-sensitive filesystems (Linux, external drives formatted as HFS+ with case sensitivity), `DSC001.JPG` is missed.

**Fix:**
- Replace the suffix check with a case-insensitive glob or normalize via `.lower()` — for each candidate path, check `jpg_path.exists()` for both the lowercase and original-case variant, or use `parent.glob(f"{base}.[Jj][Pp][Gg]")`.

**Acceptance criteria:**
- `DSC001.JPG`, `DSC001.jpg`, `DSC001.Jpg` are all detected as sidecars for `DSC001.ARW` on a case-sensitive filesystem.

---

### 1.5 Add path traversal validation on watch-list and import inputs

**Scope:** S  
**Files:** `server.py`, `database.py`

**Problem:** `POST /api/watch-list?path=../../etc` and `POST /api/import?path=/etc/passwd` accept arbitrary filesystem paths. An authenticated caller (or anyone if no API key is configured) can register and scan any directory on the host.

**Fix:**
- In `add_watch_dir` route: after `Path(path).resolve()`, validate that the path is an absolute path pointing to an existing directory (`is_dir()` check). Optionally, maintain an `ALLOWED_BASE_DIRS` env list; reject any path not under one of those prefixes.
- In `import_photos` route: apply the same guard before constructing the scanner.
- `db.add_watch_dir` should not resolve paths itself — resolution and validation belong at the API boundary.

**Acceptance criteria:**
- `POST /api/watch-list?path=../../etc` returns HTTP 400 with a clear error.
- `POST /api/watch-list?path=/tmp/safe_dir` succeeds (if `safe_dir` exists and is a directory).

---

### 1.6 ~~Fix EXIF date skipped on single-path import~~ ✅ FIXED

**Scope:** S  
**Files:** `server.py`

**Status:** Fixed in current code — both import branches now call `_prepare_photo_for_import()` which calls `_best_created_at()` on line 203. No further action required.

---

### 1.7 Add missing `exif` column and fix camera-filter queries

**Scope:** M  
**Files:** `database.py`, `server.py`

**Problem:** The `photos` table schema in `init_db` has no `exif` column, yet `list_photos` and `_evaluate_rules` query `EXTRACT_JSON(p.exif, '$.make')` and `EXTRACT_JSON(p.exif, '$.model')`. Camera filtering silently returns zero results. Additionally, `EXTRACT_JSON` is not a built-in SQLite function — the correct function is `json_extract`.

**Fix:**
- Add `exif TEXT DEFAULT NULL` to the `CREATE TABLE photos` DDL.
- Add a migration block (matching the existing `ALTER TABLE albums` pattern) to add the column to existing databases.
- `store_photo` must persist the `exif` dict as a JSON string: `json.dumps(photo.get('exif', {}))`.
- Replace all `EXTRACT_JSON(p.exif, '$.make')` with `json_extract(p.exif, '$.make')`.
- The import loop must pass `exif` from `proc_result` into `photo_meta` before calling `db.store_photo`.

**Acceptance criteria:**
- `/api/photos?camera=Canon` returns photos whose EXIF make or model contains "Canon".
- `SELECT json_extract(exif, '$.make') FROM photos LIMIT 5` returns non-null values after re-import.

---

### 1.8 Fix `list_photos` duplicate rows from unguarded tag JOIN

**Scope:** S  
**Files:** `database.py`

**Problem:** `list_photos` uses `LEFT JOIN tags t ON p.id = t.photo_id` without `SELECT DISTINCT p.*`. A photo with 3 tags is returned 3 times in the result set, causing incorrect pagination counts and visual duplicates in the gallery.

**Fix:**
- Add `DISTINCT` to the select: `SELECT DISTINCT p.*`.
- The `total` field in the route response is `len(photos)` (page size), not the true total across all pages. Add a separate `COUNT(DISTINCT p.id)` query that applies all the same filters but omits `LIMIT`/`OFFSET`, return it as `"total_count"` alongside `"photos"`.

**Acceptance criteria:**
- A photo tagged with 5 tags appears exactly once in `GET /api/photos`.
- `total_count` reflects the full filtered set, not the page size.

---

### 1.9 ~~Fix `scan_count` AttributeError on `DirectoryScanner`~~ ✅ FIXED

**Scope:** S  
**Files:** `scanner.py`, `server.py`

**Status:** Fixed in current code — `server.py` now uses `total_scanned = len(imported_photos)` directly. No further action required.

---

---

### 1.10 Fix thumbnail size parameter silently ignored

**Scope:** S  
**Files:** `processor.py`

**Problem:** `_get_thumbnail_path(source_path, size)` hashes only `source_path` — the `size` argument is accepted but never used. All thumbnail requests for the same photo resolve to the same file path regardless of the `?size=N` query parameter. Once a thumbnail at one size is generated, subsequent requests at different sizes return that same file without resizing.

**Fix:**
- Change the hash key to include size: `hashlib.sha256(f"{source_path}:{size}".encode()).hexdigest()[:16]`.
- Rename the `original_width` parameter to `size` throughout for clarity.

**Acceptance criteria:**
- `GET /api/thumbnails/{id}?size=128` and `GET /api/thumbnails/{id}?size=512` produce files at their respective dimensions.
- A freshly generated 128px thumbnail does not return a previously cached 512px file.

---

### 1.11 Fix GPS coordinate parsing (broken DMS→decimal conversion)

**Scope:** S  
**Files:** `processor.py`

**Problem:** EXIF stores GPS lat/lon as a 3-tuple of rationals `((deg_n, deg_d), (min_n, min_d), (sec_n, sec_d))`. `_convert_exif_float` receives this tuple-of-tuples, matches `isinstance(exif_value, tuple)`, then attempts `exif_value[0] / exif_value[1]` which is `(deg_n, deg_d) / (min_n, min_d)` — a `TypeError` silently swallowed by the bare `except:`, storing `0.0` for all GPS coordinates.

**Fix:**
- Detect the 3-tuple DMS form in `_parse_exif` and convert correctly:
  ```python
  def _dms_to_decimal(dms):
      d = dms[0][0] / dms[0][1]
      m = dms[1][0] / dms[1][1]
      s = dms[2][0] / dms[2][1]
      return d + m / 60 + s / 3600
  ```
- Apply the latitude reference (`N`/`S`) and longitude reference (`E`/`W`) to sign the result.

**Acceptance criteria:**
- A JPEG with known GPS coordinates (e.g. 48°51'30"N 2°17'40"E) produces `lat ≈ 48.858`, `lon ≈ 2.294` in the stored EXIF dict.
- No `0.0` stored for photos that have valid GPS EXIF.

---

### 1.12 Fix DCT formula in pHash (missing cosine — dedup produces meaningless hashes)

**Scope:** S  
**Files:** `dedup_engine.py`

**Problem:** `_dct_2d` uses `(2*x+1)*u/32.0 + (2*y+1)*v/32.0` as the kernel — there is no `math.cos()` call. The standard 2D DCT kernel is `cos((2x+1)*u*π/(2N)) * cos((2y+1)*v*π/(2N))`. The current formula computes an arbitrary weighted sum, not a frequency decomposition, so the resulting hashes do not reflect perceptual similarity. All dedup scan results are unreliable.

**Fix:**
- Add `import math` and replace the kernel:
  ```python
  import math
  total += grid[x][y] * (
      math.cos((2 * x + 1) * u * math.pi / 32) *
      math.cos((2 * y + 1) * v * math.pi / 32)
  )
  ```
- Invalidate existing `content_hashes` rows after deploying (they were computed with the wrong formula): `DELETE FROM content_hashes;`

**Acceptance criteria:**
- Two visually identical JPEGs (one re-saved at lower quality) produce hashes with Hamming distance ≤ 5.
- Two completely different photos produce hashes with Hamming distance > 20.

---

### 1.13 Remove deprecated `@app.on_event("startup")` mixed with lifespan

**Scope:** S  
**Files:** `server.py`

**Problem:** `server.py` uses both the `lifespan` context manager (the modern FastAPI approach) and `@app.on_event("startup")` (deprecated since FastAPI 0.93). The static directory mount happens in `startup`, which runs after `lifespan` begins — the ordering is implicit and fragile, and FastAPI may warn or break this in future versions.

**Fix:**
- Move the `static_dir.mkdir()` and `app.mount("/static", …)` calls into the `lifespan` function (before `yield`).
- Delete the `@app.on_event("startup")` handler entirely.

**Acceptance criteria:**
- Server starts cleanly with no deprecation warnings.
- `/static/` assets are served correctly.

---

### 1.14 Route handlers bypass existing ORM/manager methods

**Scope:** S  
**Files:** `server.py`

**Problem:** Several route handlers contain raw SQL or duplicate logic instead of calling the methods that already exist:
- `DELETE /api/photos/{id}/tags/{tag}` (line 447) uses `db._connect()` directly despite `db.delete_tag()` existing.
- `GET /api/tags` (line 455) duplicates the query already in `tags_manager.get_all_tags()`.

This means tag history is not recorded on deletion (the `TagsManager.remove_tag_with_history` path is bypassed), and the duplication creates two maintenance surfaces for the same logic.

**Fix:**
- Replace the raw SQL in `remove_photo_tag` with `tags_manager.remove_tag_with_history(photo_id, tag)`.
- Replace the raw SQL in `all_tags` with `tags_manager.get_all_tags()`.

**Acceptance criteria:**
- Deleting a tag via the API creates a `tag_history` row with `action='removed'` (when `tag_history_enabled=true`).
- `GET /api/tags` returns the same results as before.

---

## Phase 2 — Robustness (Data Integrity & Reliability)

**Goal:** Prevent silent failure propagation, harden the ID scheme, bound resource usage, and establish a repeatable migration path. No Phase 2 task should be started until all Phase 1 tasks are complete and verified.

---

### 2.1 Replace broad `except Exception` swallowers with typed exception handling and structured logging

**Scope:** M  
**Files:** `processor.py`, `scanner.py`, `dedup_engine.py`, `filewatcher.py`, `server.py`, `tags_manager.py`, `decoder.py`

**Problem:** 18+ bare `except:` or `except Exception:` clauses silently swallow errors with a `print()`. This makes diagnosing production failures nearly impossible.

**Fix:**
- Add Python's standard `logging` module to every file. Configure a root logger in `server.py` using `logging.basicConfig` with JSON formatter (use `python-json-logger` from PyPI) at a level controlled by `config.log_level`.
- Replace every `print(f"Error …: {e}")` with `logger.error("message", exc_info=True, extra={…})`.
- Narrow exception types where the expected failure mode is known: `OSError` for filesystem, `sqlite3.DatabaseError` for DB, `PIL.UnidentifiedImageError` for corrupt images.
- In `processor._process_standard`, the inner `except:` on EXIF parsing (line 51) is acceptable as a bare catch since EXIF is non-critical — but log it at `DEBUG`, not silently.

**Acceptance criteria:**
- Every unhandled exception in a background thread (filewatcher, dedup scan) produces a structured log line including `filepath`, `error_type`, `message`, and a stack trace.
- No bare `except:` without a logged message remains in any source file.

---

### 2.2 Move dedup scan off the request thread

**Scope:** M  
**Files:** `server.py`, `dedup_engine.py`

**Problem:** `GET /api/dedup/scan` calls `dedup.scan()` synchronously on the FastAPI async event loop thread. Since `scan()` does heavy I/O and CPU work (pHash for every photo), the server is effectively blocked for the duration of the scan.

**Fix:**
- Use FastAPI's `BackgroundTasks` or `asyncio.run_in_executor` (with `ThreadPoolExecutor`) to run `dedup.scan()` in a thread pool.
- Introduce a simple scan-state machine on `DedupEngine`: `IDLE | RUNNING | COMPLETED`. `GET /api/dedup/scan` returns `{"status": "started"}` immediately if idle, or `{"status": "running"}` if already in progress.
- Add `GET /api/dedup/status` to poll for completion and retrieve the result.
- Store `duplicate_groups` result on the engine instance so `merge_group` can still access it.

**Acceptance criteria:**
- `GET /api/dedup/scan` returns HTTP 202 within 100ms regardless of library size.
- `/api/dedup/status` eventually transitions from `running` to `completed` with groups populated.
- Triggering a second scan while one is running returns `{"status": "running"}` without starting a second thread.

---

### 2.3 Bound the filewatcher `_pending` map (memory leak)

**Scope:** S  
**Files:** `filewatcher.py`

**Problem:** `PhotoImportHandler._pending` is a plain dict that grows unboundedly. Every unique path ever seen is kept forever. On a large library with frequent filesystem events, this will eventually exhaust memory.

**Fix:**
- Replace `_pending` with `functools.lru_cache` bounded at a fixed size, or use a `collections.OrderedDict` capped at `N=10_000` entries with LRU eviction.
- Alternatively, after a file is successfully imported (in `_import_file`), remove its entry from `_pending`.
- Add an eviction pass: any entry older than `cooldown * 10` seconds is dropped on the next `_maybe_import` call.

**Acceptance criteria:**
- After processing 100,000 distinct files, `sys.getsizeof(_pending)` is bounded, not proportional to the number of distinct files seen.

---

### 2.4 Hot-reload file watcher when watch list changes

**Scope:** M  
**Files:** `filewatcher.py`, `server.py`

**Problem:** Adding or removing a watch directory via the API has no effect on the running `Observer`. The only way to apply the new list is a server restart.

**Fix:**
- Add `add_watch_directory(path)` and `remove_watch_directory(path)` methods to `FileWatcherManager` that schedule/unschedule handlers on the live `Observer` without restarting it.
- Call these methods from the `add_watch_dir` and `remove_watch_dir` route handlers when `app.state.file_watcher` is not None.
- `watchdog.Observer.schedule()` and `unschedule()` are thread-safe and can be called on a running observer.

**Acceptance criteria:**
- `POST /api/watch-list?path=/new/dir` immediately begins watching `/new/dir` without server restart (confirmed by dropping a file and seeing it appear in the DB).
- `DELETE /api/watch-list/{path}` stops watching that path (new files no longer auto-import).

---

### 2.5 Replace truncated SHA-256 photo ID with full hash

**Scope:** M  
**Files:** `scanner.py`, `database.py`, `server.py`

**Problem:** Photo IDs are `sha256(filepath)[:16]` — 64 bits. With a 10,000-photo library, birthday collision probability is ~2.7 × 10⁻¹⁰ per pair. At 1M photos it becomes material. More critically, the ID is path-derived, so moving a file changes its ID, orphaning all album memberships, tags, and history.

**Fix (minimal — keep path-based but fix truncation):**
- Change `hexdigest()[:16]` to `hexdigest()[:32]` (128 bits, collision probability negligible for personal libraries up to billions of files). This avoids a schema migration while dramatically reducing risk.

**Fix (ideal — content-addressable):**
- Compute `sha256(first_64KB_of_file + filepath)` as the ID. This survives renames within the same directory, and near-duplicates in different directories get distinct IDs. Full content hash is too slow for large RAW files; a hybrid approach is a reasonable compromise.
- Schema migration: Add `content_id TEXT` column, populate by re-hashing, then switch primary key. This is a larger change — scope it as a separate, opt-in migration with a flag (`USE_CONTENT_ID=true`).

**Acceptance criteria:**
- Photo IDs are 32 hex characters.
- A library of 1M synthetic files has zero ID collisions in a test run.

---

### 2.6 Introduce a proper schema migration system

**Scope:** M  
**Files:** `database.py`, new `migrations.py`

**Problem:** Schema changes are applied via `ALTER TABLE … ADD COLUMN` inside `try/except Exception: pass` blocks. There is no version tracking, no rollback, and no way to know which migrations have been applied.

**Fix:**
- Add a `schema_version` table: `CREATE TABLE IF NOT EXISTS schema_version (version INTEGER PRIMARY KEY, applied_at TEXT)`.
- Represent each migration as a numbered function `migrate_N(conn)` in a `migrations.py` module.
- On `init_db`, run all unapplied migrations in order (compare `MAX(version)` in `schema_version` against the hardcoded `LATEST_VERSION`).
- Wrap each migration in a transaction so a failed migration does not leave the schema partially applied.
- Remove all existing `try/except: pass` migration blocks.

**Acceptance criteria:**
- Starting a fresh server populates `schema_version` with all current migrations.
- Starting a server against an old database applies only the missing migrations.
- A failing migration (e.g., simulated disk-full) leaves the database unmodified.

---

### 2.7 Add GPS lat/lon as queryable columns

**Scope:** M  
**Files:** `database.py`, `processor.py`, `server.py`

**Problem:** GPS data is stored inside the `exif` JSON blob. `json_extract` on every row for bounding-box queries is an O(N) full-table scan with no index possible.

**Fix:**
- Add `gps_lat REAL DEFAULT NULL` and `gps_lon REAL DEFAULT NULL` to `photos` via a migration.
- Add a spatial index: `CREATE INDEX idx_photos_gps ON photos(gps_lat, gps_lon) WHERE gps_lat IS NOT NULL`.
- In `store_photo`, extract lat/lon from the `exif` dict and store them in the new columns.
- Add `GET /api/photos?lat_min=…&lat_max=…&lon_min=…&lon_max=…` filter to `list_photos`.

**Acceptance criteria:**
- `SELECT COUNT(*) FROM photos WHERE gps_lat BETWEEN 37 AND 38` executes using the index (EXPLAIN QUERY PLAN shows "SEARCH photos USING INDEX").
- `/api/photos?lat_min=37.7&lat_max=37.8&lon_min=-122.5&lon_max=-122.4` returns only photos taken in San Francisco.

---

### 2.8 Paginate `/api/tags`

**Scope:** S  
**Files:** `server.py`

**Problem:** `GET /api/tags` runs `SELECT tag, COUNT(photo_id) … GROUP BY tag` with no limit. Libraries with tens of thousands of tags will return multi-MB responses.

**Fix:**
- Add `limit: int = Query(200, ge=1, le=1000)` and `offset: int = Query(0, ge=0)` parameters.
- Add `LIMIT ? OFFSET ?` to the query.
- Return `{"tags": […], "total_count": <int>}` where `total_count` comes from a separate `SELECT COUNT(DISTINCT tag) FROM tags` query.

**Acceptance criteria:**
- `GET /api/tags?limit=10&offset=0` returns exactly 10 tags with correct `total_count`.
- `GET /api/tags` (no params) returns at most 200 tags.

---

## Phase 3 — Scalability & Operations

**Goal:** Make the server deployable, observable, and safe to run continuously on a home server or small cloud instance. Depends on Phases 1 and 2 being complete (except 3.6 which can begin after Phase 1).

---

### 3.1 Add rate limiting on expensive endpoints

**Scope:** M  
**Files:** `server.py`, `requirements.txt`

**Problem:** `/api/thumbnails/{photo_id}`, `/api/dedup/scan`, and `/api/import` have no rate limiting. A misconfigured client or script can flood thumbnail generation and saturate disk I/O.

**Fix:**
- Add `slowapi` (0.1.x) to `requirements.txt`.
- Apply `@limiter.limit("60/minute")` to thumbnail and full-resolution endpoints.
- Apply `@limiter.limit("2/minute")` to `/api/dedup/scan` and `/api/import` (these are heavy operations).
- Configure `SlowAPIMiddleware` as FastAPI middleware.

**Acceptance criteria:**
- 70 thumbnail requests in one minute from a single IP results in HTTP 429 on requests 61–70.
- 3 dedup scan requests in one minute from a single IP results in HTTP 429 on request 3.

---

### 3.2 Add structured logging and request tracing

**Scope:** M  
**Files:** `server.py`, all modules

**Problem:** All logging is `print()` to stdout with inconsistent formats. There are no request IDs, no timing, and no machine-parseable log format.

**Fix:**
- Add `python-json-logger` and configure a JSON log formatter in `server.py`.
- Add a FastAPI middleware that assigns a `X-Request-ID` UUID to each request, stores it in a `contextvars.ContextVar`, and appends it to the response header.
- Pass the request ID through to all log calls (`extra={"request_id": …}`).
- Log request completion with `method`, `path`, `status_code`, `duration_ms`.
- Replace all `print()` in all modules with `logger.info/warning/error`.

**Acceptance criteria:**
- Every log line is valid JSON with at minimum: `timestamp`, `level`, `message`, `module`, `request_id` (where applicable).
- A single failed import generates log lines traceable via `request_id` from the route handler through `processor.py` and `database.py`.

---

### 3.3 Add Docker deployment config

**Scope:** M  
**Files:** new `Dockerfile`, new `docker-compose.yml`, new `.dockerignore`

**Problem:** There is no reproducible deployment artifact. Running the server requires a correct Python environment, rawpy native deps (libraw), and Pillow's image codec deps — all installed manually.

**Fix:**
- `Dockerfile`: Use `python:3.12-slim` as base. Install system deps (`libraw-dev`, `libjpeg-dev`, `libheif-dev`) via `apt-get`. Copy and `pip install -r requirements.txt`. Set `CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8080"]`.
- `docker-compose.yml`: Define `app` service with volume mounts for `PHOTO_DIR`, `DB_PATH` parent, and `.thumbnails`/`.converted` cache dirs. Expose port 8080.
- `.dockerignore`: Exclude `test-photos/`, `.git/`, `__pycache__/`, `*.db`.
- Add a `HEALTHCHECK` in Dockerfile using `curl -f http://localhost:8080/api/health || exit 1`.

**Acceptance criteria:**
- `docker compose up` starts the server and `GET /api/health` returns 200.
- Photo files mounted via volume are importable and thumbnails are generated.
- Container restart preserves the database (volume-mounted).

---

### 3.4 Enforce thumbnail quality from DB setting at runtime

**Scope:** S  
**Files:** `processor.py`, `server.py`

**Problem:** `THUMBNAIL_QUALITY` is read from an environment variable at startup. Updating it via `PUT /api/settings/thumbnail_quality` has no effect until restart.

**Fix:**
- Refresh `config.thumbnail_quality` from the DB when `put_setting("thumbnail_quality", …)` is called, just as is done for `dedup_enabled`, `auto_tag_camera`, etc.
- Remove the unused `_THUMB_QUALITY` global from `server.py`.

**Acceptance criteria:**
- `PUT /api/settings/thumbnail_quality?value=60` causes subsequently generated thumbnails to use JPEG quality 60 without server restart.

---

### 3.5 Normalize frontend date display to ISO-8601

**Scope:** S  
**Files:** `templates/index.html`

**Problem:** Dates are displayed as raw `created_at` strings from the DB (EXIF format `"2023:07:15 14:30:00"` or ISO-8601 depending on import path — inconsistent). The frontend does no normalization.

**Fix:**
- Add a JS helper `formatDate(str)` that normalizes both EXIF (`YYYY:MM:DD HH:MM:SS`) and ISO-8601 formats to a human-readable locale string using `new Date(str.replace(/^(\d{4}):(\d{2}):(\d{2})/, '$1-$2-$3')).toLocaleDateString(undefined, {year:'numeric', month:'short', day:'numeric'})`.
- Apply this helper wherever `created_at` is rendered.

**Acceptance criteria:**
- All date strings in the gallery and detail modal display as e.g. "Jul 15, 2023" regardless of whether the underlying `created_at` is in EXIF or ISO format.
- No raw colon-separated date strings are visible to the user.

---

### 3.6 Add automated test suite

**Scope:** L  
**Files:** new `tests/test_database.py`, `tests/test_processor.py`, `tests/test_scanner.py`, `tests/test_api.py`, `tests/conftest.py`

**Note:** Can begin after Phase 1 is complete — early tests catch regressions during Phase 2 work.

**Problem:** The only tests are ad-hoc scripts. There are no automated unit tests or integration tests. All testing has been manual.

**Fix:**
- Add `pytest`, `pytest-asyncio`, and `httpx` to a new `requirements-dev.txt`.
- `conftest.py`: Fixture that creates a fresh in-memory SQLite `PhotoDatabase` and a `TestClient` wrapping the FastAPI app.
- `test_database.py`: Test `store_photo`, `get_photo`, `list_photos` (with filters), `merge_tags` atomicity, `add_watch_dir` deduplication.
- `test_scanner.py`: Test `find_sidecar_jpeg` with both `.jpg` and `.JPG` fixtures from `test-photos/`.
- `test_processor.py`: Test `_parse_exif` against a sample JPEG with known EXIF fields; test `generate_thumbnail` output dimensions.
- `test_api.py`: Integration tests for `/api/health`, `/api/photos`, `/api/import`, `/api/dedup/scan` (async, background).

**Acceptance criteria:**
- `pytest tests/` passes with zero failures on a clean checkout.
- All confirmed bugs from the review have at least one regression test.
- Test suite runs in under 30 seconds.

---

## Phase 4 — Polish & Future Features

**Goal:** Developer experience, observability depth, and UX improvements. Depends on Phase 3 completion unless noted.

---

### 4.1 User management (multi-user API keys)

**Scope:** L  
**Files:** `database.py`, `server.py`, `config.py`

**Depends on:** Phase 3.3 (Docker) for deployment safety.

**Problem:** Single `API_KEY` env variable. No per-user permissions, no key rotation, no audit trail.

**Fix:**
- Add `api_keys` table: `(key_hash TEXT PRIMARY KEY, label TEXT, permissions TEXT, created_at TEXT, last_used_at TEXT)`.
- Hash stored keys with `sha256`. The middleware compares `sha256(provided_key)` against stored hashes.
- Add admin-only routes: `POST /api/admin/keys`, `DELETE /api/admin/keys/{label}`, `GET /api/admin/keys`.
- Permissions field is a comma-separated list: `read`, `write`, `admin`.
- Replace the single `_require_api_key` dependency with `require_permission("write")` etc.

**Acceptance criteria:**
- Two different API keys can be issued with different permissions.
- Revoking a key causes subsequent requests with that key to return HTTP 401.
- `last_used_at` is updated on each authenticated request.

---

### 4.2 Prometheus metrics endpoint

**Scope:** M  
**Files:** `server.py`, `requirements.txt`

**Problem:** No observability beyond logs. Can't alert on import failure rate, thumbnail latency, or DB query time.

**Fix:**
- Add `prometheus-fastapi-instrumentator` to requirements.
- Instrument: request count/latency by endpoint, thumbnail cache hit rate, import success/failure counters, dedup scan duration histogram.
- Expose `GET /metrics` (Prometheus text format).

**Acceptance criteria:**
- `GET /metrics` returns valid Prometheus text with at least `http_requests_total` and `http_request_duration_seconds` metrics.
- Import success and failure counts are tracked as separate counter labels.

---

### 4.3 Improve smart collection rule engine

**Scope:** M  
**Files:** `database.py`, `smart_collection.py`

**Depends on:** Phase 1.7 (json_extract fix).

**Problem:** Camera rules use `EXTRACT_JSON` (wrong function name), `REGEXP` operator (not built into SQLite by default), and the engine silently produces no results rather than erroring.

**Fix:**
- After Phase 1.7 (fix `json_extract`), update `_evaluate_rules` to use `json_extract`.
- Remove `REGEXP` support or register a Python regex function via `conn.create_function('REGEXP', 2, lambda p, s: bool(re.search(p, s or '')))`.
- Add `combine` field to `rule_spec` (default `'AND'`, support `'OR'`) so users can build "any of these" collections.

**Acceptance criteria:**
- A smart collection with `camera = "Canon"` correctly returns Canon photos.
- A smart collection with `combine = "OR"` returns photos matching any rule, not all rules.

---

### 4.4 Reverse geocoding for GPS auto-tagging

**Scope:** M  
**Files:** `tags_manager.py`

**Depends on:** Phase 2.7 (GPS columns).

**Problem:** `_geocode_location` uses crude hard-coded lat/lon bounding boxes that produce only continent-level tags. Duplicate continent names are appended for some coordinates.

**Fix:**
- Integrate `reverse-geocoder` (offline, pure Python) or `geopy` with a local Nominatim instance.
- Return city, region/state, and country as separate tags: `["Paris", "Île-de-France", "France"]`.
- Fix the duplicate-append bug in `_geocode_location` (the `'Europe'` string is appended twice on the same branch).

**Acceptance criteria:**
- A photo with GPS coordinates in Paris generates tags `["Paris", "Île-de-France", "France"]`.
- No duplicate tags are generated for any coordinate.

---

### 4.5 Progressive import with SSE progress streaming

**Scope:** L  
**Files:** `server.py`, `templates/index.html`

**Problem:** `POST /api/import` is synchronous. Large imports (10,000+ photos) block for minutes; the caller gets no progress feedback.

**Fix:**
- Wrap the import loop in an async generator and expose it via `StreamingResponse` with `media_type="text/event-stream"` (Server-Sent Events).
- Each event: `data: {"imported": N, "errors": E, "total_scanned": T, "current_file": "…"}\n\n`.
- Add a frontend SSE listener that updates a progress bar during import.

**Acceptance criteria:**
- `POST /api/import?path=/large/dir` begins streaming events within 500ms.
- The frontend shows a progress bar that increments as photos are imported.
- Import completion fires a final event with `{"status": "done", "imported": N, "errors": E}`.

---

## Dependency Map

```
Phase 1 tasks are independent of each other (order within phase is by risk, not dependency).

Phase 2 depends on Phase 1 being complete. Within Phase 2:
  2.6 (migrations) should be done before 2.7 (GPS columns) — GPS uses the new migration system.
  2.1 (logging) should be done before 2.2 (async dedup) — async errors must be logged.

Phase 3 depends on Phase 2 being complete. Within Phase 3:
  3.6 (tests) can begin as soon as Phase 1 is done — early tests catch regressions during Phase 2.
  3.3 (Docker) is independent of 3.1, 3.2, 3.4, 3.5.

Phase 4 depends on Phase 3. Specific cross-phase dependencies:
  4.1 (user management) requires 3.3 (Docker) for deployment safety.
  4.3 (smart collection fix) requires 1.7 (json_extract fix).
  4.4 (geocoding) requires 2.7 (GPS columns).
```

---

## Summary Table

| # | Task | Phase | Scope | Primary Files | Status |
|---|------|-------|-------|---------------|--------|
| 1.1 | Fix `merge_tags` connection/transaction | 1 | S | `tags_manager.py` | ✅ Fixed |
| 1.2 | Fix filewatcher import + `config.get_setting` | 1 | S | `filewatcher.py`, `config.py` | ✅ Fixed |
| 1.3 | Fix RAW cache collision | 1 | S | `decoder.py` | ✅ Fixed |
| 1.4 | Fix sidecar JPEG case sensitivity | 1 | S | `scanner.py` | ✅ Fixed |
| 1.5 | Path traversal validation | 1 | S | `server.py`, `database.py` | ✅ Fixed |
| 1.6 | EXIF date on single-path import | 1 | S | `server.py` | ✅ Fixed |
| 1.7 | Add `exif` column + fix `json_extract` | 1 | M | `database.py`, `server.py` | ✅ Fixed |
| 1.8 | Fix duplicate rows from tag JOIN | 1 | S | `database.py` | ✅ Fixed |
| 1.9 | Fix `scan_count` AttributeError | 1 | S | `scanner.py`, `server.py` | ✅ Fixed |
| 1.10 | Fix thumbnail size param ignored | 1 | S | `processor.py` | ✅ Fixed |
| 1.11 | Fix GPS DMS→decimal conversion | 1 | S | `processor.py` | ✅ Fixed |
| 1.12 | Fix DCT formula in pHash | 1 | S | `dedup_engine.py` | ✅ Fixed |
| 1.13 | Remove deprecated `on_event` / lifespan mix | 1 | S | `server.py` | ✅ Fixed |
| 1.14 | Route handlers bypass ORM methods | 1 | S | `server.py` | ✅ Fixed |
| 2.1 | Structured error handling + logging | 2 | M | All `.py` files | |
| 2.2 | Async dedup scan | 2 | M | `server.py`, `dedup_engine.py` | |
| 2.3 | Bound filewatcher pending map | 2 | S | `filewatcher.py` | |
| 2.4 | Hot-reload watcher on list changes | 2 | M | `filewatcher.py`, `server.py` | |
| 2.5 | Extend photo ID to 32 hex chars | 2 | M | `scanner.py`, `database.py` | |
| 2.6 | Schema migration system | 2 | M | `database.py`, new `migrations.py` | |
| 2.7 | GPS as queryable columns | 2 | M | `database.py`, `processor.py`, `server.py` | |
| 2.8 | Paginate `/api/tags` | 2 | S | `server.py` | |
| 3.1 | Rate limiting | 3 | M | `server.py`, `requirements.txt` | |
| 3.2 | Structured logging + request IDs | 3 | M | All `.py` files | |
| 3.3 | Docker deployment | 3 | M | New `Dockerfile`, `docker-compose.yml` | |
| 3.4 | Thumbnail quality from DB setting | 3 | S | `processor.py`, `server.py` | |
| 3.5 | Normalize frontend dates | 3 | S | `templates/index.html` | |
| 3.6 | Automated test suite | 3 | L | New `tests/` directory | |
| 4.1 | Multi-user API keys | 4 | L | `database.py`, `server.py` | |
| 4.2 | Prometheus metrics | 4 | M | `server.py`, `requirements.txt` | |
| 4.3 | Smart collection rule engine | 4 | M | `database.py`, `smart_collection.py` | |
| 4.4 | Reverse geocoding | 4 | M | `tags_manager.py` | |
| 4.5 | Progressive import SSE | 4 | L | `server.py`, `templates/index.html` | |

**Scope key:** S = hours, M = 1–2 days, L = 3–5 days
