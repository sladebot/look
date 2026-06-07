"""Local Photo Library Server — Main FastAPI application with web frontend."""
import os
import hashlib
import time
from pathlib import Path
from fastapi import FastAPI, HTTPException, Query, Request, Depends
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from contextlib import asynccontextmanager

from .config import Config
from .database import PhotoDatabase
from .scanner import DirectoryScanner
from .processor import ImageProcessor
from .decoder import RawDecoder
from .filewatcher import FileWatcherManager
from .smart_collection import SmartCollectionManager
from .dedup_engine import DedupEngine
from .tags_manager import TagsManager
from .task_queue import TaskQueue
from .rate_limiter import RateLimiter
from .migrations import MigrationManager

# ─── optional EXIF date helpers ──────────────────────────────────────────────
_EXIF_DT_TAG = 'datetime_original'
_THUMB_QUALITY = int(os.environ.get('THUMBNAIL_QUALITY', '85'))


def _to_iso(val: str) -> str:
    """Normalise EXIF date (\"YYYY:MM:DD HH:MM:SS\") → ISO-8601 (\"YYYY-MM-DD HH:MM:SS\").  Idempotent on already-ISO input."""
    if '-' in val:
        return val          # already ISO-like → no-op
    return val.replace(':', '-', 2)


def _best_created_at(raw_meta: dict, exif_data: dict) -> str:
    """Pick created_at from EXIF DateTimeOriginal, then DateTime, then file stat."""
    # 1. DateTimeOriginal (36867 Exif IFD) — camera-captured, most accurate
    val = exif_data.get('datetime_original')
    if val:
        try:
            return _to_iso(val)
        except Exception:
            pass
    # 2. DateTime (0x0132 0th IFD) — file modification timestamp embedded by camera
    val = exif_data.get('datetime')
    if val:
        try:
            return _to_iso(val)
        except Exception:
            pass
    # 3. Fall back to filesystem mtime
    try:
        return time.strftime(
            '%Y-%m-%dT%H:%M:%S',
            time.localtime(Path(raw_meta['filepath']).stat().st_mtime)
        )
    except Exception:
        return raw_meta.get('indexed_at', time.strftime('%Y-%m-%dT%H:%M:%S'))


# ─── app factory / lifespan ───────────────────────────────────────────────────
config = Config()
db = PhotoDatabase(config.db_path)

for d in config.watch_dirs:
    db.add_watch_dir(d)

scanner = DirectoryScanner(config.photo_dir, config.image_extensions)
processor = ImageProcessor(config)
decoder = RawDecoder(config)
smart_albums = SmartCollectionManager(db, processor)
dedup = DedupEngine(db, config, processor)
tags_manager = TagsManager(db, config, processor)
task_queue = TaskQueue(db, dedup_engine=dedup)
rate_limiter = RateLimiter(default_rate=120, default_burst=240)

# Configure rate limits for heavy endpoints (rate/min, burst)
rate_limiter.set_limit("/api/thumbnails/*", rate=30, burst=60)
rate_limiter.set_limit("/api/full/*", rate=10, burst=20)
rate_limiter.set_limit("/api/dedup/scan", rate=5, burst=5)

# Migration manager
migrator = MigrationManager(db)
migrator.register([
    {
        "version": 1,
        "description": "Backfill GPS columns into existing photos (migration for pre-GPS databases)",
        "up_sql": "UPDATE photos SET gps_lat = json_extract(exif, '$.gps_lat'), gps_lon = json_extract(exif, '$.gps_lon') WHERE gps_lat IS NULL",
    },
    {
        "version": 2,
        "description": "Create GIS index for faster geospatial queries",
        "up_sql": "CREATE INDEX IF NOT EXISTS idx_photos_gps ON photos(gps_lat, gps_lon) WHERE gps_lat IS NOT NULL",
    },
])
# Apply migrations immediately at module import time (so DB has GPS columns before any routes are hit)
migrator.apply_all()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    """Mount static files, start optional file watcher on startup."""
    static_dir = Path(__file__).parent.parent / "web" / "static"
    static_dir.mkdir(exist_ok=True)
    _app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    _app.state.file_watcher = None
    try:
        setting = db.get_setting('filewatcher_enabled')
    except Exception:
        setting = None
    if setting and setting.lower() in ('1', 'true', 'yes'):
        fw_manager = FileWatcherManager(config, processor, scanner, db)
        if fw_manager.start():
            _app.state.file_watcher = fw_manager
            print('[look] File watcher started.')
        else:
            print('[look] File watcher FAILED to start — continuing without it.')
    yield
    fw = getattr(_app.state, 'file_watcher', None)
    if fw:
        fw.stop()
        print('[look] File watcher stopped.')

    # Apply pending migrations on startup
    applied = migrator.apply_all()
    if applied:
        print(f'[look] Applied {len(applied)} migration(s) on startup.')
    else:
        print('[look] Database schema is up to date.')


app = FastAPI(title="Local Photo Library", version="0.3.0", lifespan=lifespan)


# ─── middleware: rate limiting ─────────────────────────────────────────────────
@app.middleware("http")
async def rate_limit_middleware(request: Request, call_next):
    """Apply rate limiting to all requests."""
    client_ip = request.client.host if request.client else "unknown"
    endpoint = request.url.path

    allowed, info = rate_limiter.allow_request(client_ip, endpoint)
    if not allowed:
        return JSONResponse(
            status_code=429,
            content={
                "detail": "Rate limit exceeded",
                "retry_after": info.get("retry_after"),
            },
            headers={"Retry-After": str(int(info.get("retry_after", 60)))},
        )

    response = await call_next(request)
    response.headers["X-RateLimit-Remaining"] = str(info.get("remaining", 0))
    return response


# ─── auth middleware ─────────────────────────────────────────────────────────
def _require_api_key(request: Request):
    """Dependency that enforces API_KEY when one is configured."""
    if not config.api_key:
        return  # no auth configured → pass-through
    provided = request.headers.get('X-API-Key', '')
    if provided != config.api_key:
        raise HTTPException(status_code=401, detail='Invalid or missing API key')


_API_AUTH = Depends(_require_api_key)


# ==================== API Routes ===============================================


@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "photo_count": db.get_photo_count(),
        "watch_dirs": db.get_watch_list(),
        "db_path": config.db_path,
        "filewatcher_running": bool(getattr(app.state, 'file_watcher', None)),
    }


# ─── watch list ───────────────────────────────────────────────────────────────
@app.get("/api/watch-list")
async def get_watch_list():
    return {"directories": db.get_watch_list()}


@app.post("/api/watch-list")
async def add_watch_dir(path: str = Query(..., description="Path to add as watch directory"), _auth=_API_AUTH):
    resolved = Path(path).resolve()
    if not resolved.is_dir():
        raise HTTPException(status_code=400, detail=f"Path does not exist or is not a directory: {resolved}")
    result = db.add_watch_dir(str(resolved))
    if result:
        return {"status": "added", "path": str(resolved)}
    return JSONResponse(status_code=409, content={"status": "already_exists", "path": str(resolved)})


@app.delete("/api/watch-list/{path:path}")
async def remove_watch_dir(path: str, _auth=_API_AUTH):
    normalized = str(Path(path).resolve())
    result = db.remove_watch_dir(normalized)
    if result:
        return {"status": "removed", "path": normalized}
    raise HTTPException(status_code=404, detail="Directory not in watch list")


@app.patch("/api/watch-list/{path:path}/active")
async def set_watch_active(path: str, active: bool = Query(..., description="true or false"), _auth=_API_AUTH):
    normalized = str(Path(path).resolve())
    result = db.set_watch_active(normalized, active)
    if result:
        return {"status": "updated", "path": normalized, "active": active}
    raise HTTPException(status_code=404, detail="Directory not in watch list")


# ─── import ──────────────────────────────────────────────────────────────────
def _prepare_photo_for_import(photo_meta: dict, import_scanner: DirectoryScanner) -> dict:
    """Process metadata and eagerly prepare JPEG previews for imported photos."""
    original_path = photo_meta['filepath']
    if not os.access(original_path, os.R_OK):
        raise RuntimeError("File is not readable by the server process; fix file permissions or run the server as the file owner")

    proc_result = processor.process(original_path)
    if not proc_result:
        raise RuntimeError("Unsupported or unreadable image file")

    preview_path = original_path

    if Path(original_path).suffix.lower() in decoder.raw_extensions:
        sidecar_jpeg = import_scanner.find_sidecar_jpeg(Path(original_path))
        if sidecar_jpeg:
            preview_path = str(sidecar_jpeg)
            photo_meta['is_source_jpeg'] = 1
            photo_meta['filepath'] = preview_path
            proc_result = processor.process(preview_path) or proc_result
        else:
            # No sidecar — convert via rawpy, cache as JPEG
            converted_path = decoder.decode(original_path)
            if not converted_path:
                raise RuntimeError("Failed to convert RAW file to JPEG preview — check file permissions and rawpy installation")
            preview_path = converted_path
            converted_result = processor.process(converted_path)
            if converted_result:
                proc_result = {**proc_result, **converted_result, 'mime_type': proc_result.get('mime_type', 'image/x-raw')}

    photo_meta['width'] = proc_result['width']
    photo_meta['height'] = proc_result['height']
    photo_meta['mime_type'] = proc_result['mime_type']
    photo_meta['exif'] = proc_result.get('exif', {})
    photo_meta['created_at'] = _best_created_at(photo_meta, photo_meta['exif'])

    # Extract GPS coordinates from processed EXIF
    exif_result = proc_result.get('exif', {})
    photo_meta['gps_lat'] = exif_result.get('gps_lat')
    photo_meta['gps_lon'] = exif_result.get('gps_lon')

    thumb_path = processor.get_thumbnail(preview_path, config.max_thumbnail_width)
    photo_meta['has_thumbnail'] = bool(thumb_path and os.path.exists(thumb_path))

    return photo_meta


@app.post("/api/import")
async def import_photos(path: str = Query(None, description="Specific directory to import (default: all active watch dirs)"), _auth=_API_AUTH):
    import_path = None
    photos = None

    if path:
        import_path = Path(path).resolve()
        if not import_path.is_dir():
            raise HTTPException(status_code=400, detail=f"Path does not exist or is not a directory: {import_path}")
        db.add_watch_dir(str(import_path))
        scanner_local = DirectoryScanner(str(import_path), config.image_extensions)
    else:
        active_watch_dirs = [entry for entry in db.get_watch_list() if entry['active']]
        if not active_watch_dirs:
            return {
                "imported": 0,
                "errors": 0,
                "total_scanned": 0,
                "message": "No active watch directories found. Add or enable one first."
            }

        photos = db.scan_all_watch_dirs(image_extensions=config.image_extensions)
        if not photos:
            return {
                "imported": 0,
                "errors": 0,
                "total_scanned": 0,
                "message": "No supported photos found in active watch directories."
            }

    imported = 0
    errors = 0
    error_details = []

    if path:
        imported_photos = scanner_local.scan(recursive=True)
        total_scanned = len(imported_photos)
        for photo_meta in imported_photos:
            try:
                photo_meta = _prepare_photo_for_import(photo_meta, scanner_local)
                db.store_photo(photo_meta)
                imported += 1
            except Exception as e:
                detail = f"{photo_meta['filepath']}: {e}"
                print(f"Error importing {detail}")
                error_details.append(detail)
                errors += 1

        db.log_import(str(import_path), 'completed', imported, f"{errors} errors" if errors else None)

    else:
        total_scanned = len(photos)
        for photo_meta in photos:
            try:
                single_scanner = DirectoryScanner(Path(photo_meta['filepath']).parent, config.image_extensions)
                photo_meta = _prepare_photo_for_import(photo_meta, single_scanner)
                db.store_photo(photo_meta)
                imported += 1
            except Exception as e:
                detail = f"{photo_meta['filepath']}: {e}"
                print(f"Error importing {detail}")
                error_details.append(detail)
                errors += 1

    message = f"Imported {imported} photos from {1 if path else 'multiple'} directory/directories"
    if errors:
        message += f" ({errors} failed; see error_details)"

    return {
        "imported": imported,
        "errors": errors,
        "total_scanned": total_scanned,
        "message": message,
        "error_details": error_details[:10]
    }


# ─── photo read ───────────────────────────────────────────────────────────────
@app.get("/api/photos")
async def list_photos(
    album: str = Query(None, description="Filter by album ID"),
    tag: str = Query(None, description="Filter by tag"),
    q: str = Query(None, description="Free-text search across filename, tags, filepath"),
    camera: str = Query(None, description="Filter by camera make or model"),
    start_date: str = Query(None, description="Filter: created_at >= start_date (ISO)"),
    end_date: str = Query(None, description="Filter: created_at <= end_date (ISO)"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """List photos with optional filtering."""
    photos = db.list_photos(
        album=album, tag=tag, q=q, camera=camera,
        start_date=start_date, end_date=end_date,
        limit=limit, offset=offset,
    )
    return {"photos": photos, "total": len(photos)}


@app.get("/api/photos/{photo_id}")
async def get_photo(photo_id: str):
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    return photo


# ─── thumbnail ───────────────────────────────────────────────────────────────
@app.get("/api/thumbnails/{photo_id}")
async def get_thumbnail(photo_id: str, size: int = Query(256, ge=128, le=1024)):
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")

    filepath = photo['filepath']

    # Resolve sidecar JPEG or convert via rawpy for RAW files
    if Path(filepath).suffix.lower() in decoder.raw_extensions:
        sidecar_jpeg = scanner.find_sidecar_jpeg(Path(filepath))
        if sidecar_jpeg:
            filepath = str(sidecar_jpeg)
        else:
            converted = decoder.decode(filepath)
            if not converted:
                raise HTTPException(status_code=500, detail="RAW conversion failed — check file permissions")
            filepath = converted

    thumb_path = processor.get_thumbnail(filepath, size)

    if not thumb_path or not os.path.exists(thumb_path):
        try:
            thumb_path = processor.generate_thumbnail(filepath, size)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to generate thumbnail: {e}")

    return FileResponse(thumb_path, media_type="image/jpeg")


# ─── full resolution ─────────────────────────────────────────────────────────
@app.get("/api/full/{photo_id}")
async def get_full_photo(photo_id: str):
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")

    filepath = photo['filepath']

    sidecar_jpeg = scanner.find_sidecar_jpeg(Path(filepath))
    if sidecar_jpeg:
        return FileResponse(str(sidecar_jpeg), media_type="image/jpeg")

    if Path(filepath).suffix.lower() in decoder.raw_extensions:
        converted = decoder.decode(filepath)
        if converted:
            return FileResponse(converted, media_type="image/jpeg")
        else:
            raise HTTPException(status_code=500, detail="Failed to decode RAW file")

    if os.path.exists(filepath):
        return FileResponse(filepath, media_type=photo['mime_type'])

    raise HTTPException(status_code=404, detail="File not found on disk")


# ─── albums ──────────────────────────────────────────────────────────────────
@app.get("/api/albums")
async def list_albums():
    albums = db.get_albums()
    return {"albums": albums}


@app.post("/api/albums")
async def create_album(name: str, description: str = "", source: str = "manual", folder: str = None, _auth=_API_AUTH):
    album_id = db.create_album(name, description, source, folder)
    return {"id": album_id, "name": name}


@app.get("/api/albums/{album_id}")
async def get_album(album_id: str):
    album = db.get_album(album_id)
    if not album:
        raise HTTPException(status_code=404, detail="Album not found")
    return album


@app.put("/api/albums/{album_id}")
async def update_album(album_id: str, name: str = None, description: str = None, _auth=_API_AUTH):
    if not db.update_album(album_id, name, description):
        raise HTTPException(status_code=404, detail="Album not found")
    return {"status": "ok"}


@app.delete("/api/albums/{album_id}")
async def delete_album(album_id: str, _auth=_API_AUTH):
    if not db.delete_album(album_id):
        raise HTTPException(status_code=404, detail="Album not found")
    return {"status": "ok"}


@app.post("/api/albums/{album_id}/photos/{photo_id}")
async def add_photo_to_album(album_id: str, photo_id: str, _auth=_API_AUTH):
    db.add_photo_to_album(album_id, photo_id)
    return {"status": "ok"}


@app.delete("/api/albums/{album_id}/photos/{photo_id}")
async def remove_photo_from_album(album_id: str, photo_id: str, _auth=_API_AUTH):
    db.remove_photo_from_album(album_id, photo_id)
    return {"status": "ok"}


# ─── tags ────────────────────────────────────────────────────────────────────
@app.get("/api/photos/{photo_id}/tags")
async def get_photo_tags(photo_id: str):
    """Return all tags for a given photo."""
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    tags = db.get_tags(photo_id)
    return {"photo_id": photo_id, "tags": tags}


@app.post("/api/photos/{photo_id}/tags")
async def add_photo_tag(photo_id: str, tag: str = Query(..., min_length=1, max_length=64), _auth=_API_AUTH):
    """Add a tag to a photo."""
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    db.add_tag(photo_id, tag)
    tags = db.get_tags(photo_id)
    return {"photo_id": photo_id, "tags": tags}


@app.delete("/api/photos/{photo_id}/tags/{tag}")
async def remove_photo_tag(photo_id: str, tag: str, _auth=_API_AUTH):
    """Remove a single tag from a photo."""
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    tags_manager.remove_tag_with_history(photo_id, tag)
    return {"status": "ok", "photo_id": photo_id, "tag": tag}


@app.get("/api/tags")
async def all_tags():
    """Return all tags with photo counts."""
    return {"tags": tags_manager.get_all_tags()}


# ─── search ──────────────────────────────────────────────────────────────────
@app.get("/api/search")
async def search_photos(
    q: str = Query(..., min_length=1),
    limit: int = 50,
):
    """Full-text search: filename, tags, filepath."""
    photos = db.search_photos(q, limit)
    return {"photos": photos}


# ─── settings ────────────────────────────────────────────────────────────────
@app.get("/api/settings")
async def get_settings():
    """Return all server settings (sanitized)."""
    with db._connect() as conn:
        rows = conn.execute("SELECT key, value FROM server_settings").fetchall()
    return {"settings": {r['key']: r['value'] for r in rows}}


@app.put("/api/settings/{key}")
async def put_setting(key: str, value: str = Query(...), _auth=_API_AUTH):
    db.set_setting(key, value)
    return {"status": "ok", "key": key, "value": value}


# ─── smart albums ────────────────────────────────────────────────────────────
@app.get("/api/smart-collections")
async def list_smart_collections():
    """Return all smart albums."""
    collections = db.get_smart_collections()
    return {"collections": collections}


@app.post("/api/smart-collections")
async def create_smart_collection(name: str, description: str = "", rule_spec: str = "{}", _auth=_API_AUTH):
    """Create a new smart album with rule specifications.

    Args:
        name: Album name
        description: Optional description
        rule_spec: JSON string with 'rules' list

    Example rule_spec:
        {"rules": [{"field": "camera", "op": "contains", "value": "Canon"}]}
    """
    try:
        import json
        rule_spec = json.loads(rule_spec)
        SmartCollectionManager.validate_rules(rule_spec)
    except (json.JSONDecodeError, ValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid rule spec: {e}")

    album_id = smart_albums.create_smart_album(name, description, rule_spec)
    # Evaluate immediately
    smart_albums.evaluate(album_id)
    return {"id": album_id, "name": name, "rule_spec": rule_spec}


@app.get("/api/smart-collections/{album_id}")
async def get_smart_collection(album_id: str):
    """Get a smart album and its matched photos."""
    with db._connect() as conn:
        album = conn.execute(
            "SELECT * FROM albums WHERE id = ? AND source = 'smart_collection'", (album_id,)
        ).fetchone()
        if not album:
            raise HTTPException(status_code=404, detail="Smart album not found")

        album = dict(album)
        # Get matched photos
        photos = conn.execute("""
            SELECT p.* FROM photos p
            JOIN album_photos ap ON p.id = ap.photo_id
            WHERE ap.album_id = ?
            ORDER BY p.created_at DESC
        """, (album_id,)).fetchall()
    album['photos'] = [dict(p) for p in photos]
    return album


@app.put("/api/smart-collections/{album_id}")
async def update_smart_collection(album_id: str, name: str = None, description: str = None,
                                    rule_spec: str = "{}", _auth=_API_AUTH):
    """Update a smart album (name, description, and/or rules)."""
    try:
        import json
        parsed_spec = json.loads(rule_spec)
        SmartCollectionManager.validate_rules(parsed_spec)
    except (json.JSONDecodeError, ValueError) as e:
        raise HTTPException(status_code=400, detail=f"Invalid rule spec: {e}")

    # Update album info
    db.update_album(album_id, name, description)

    # Update rules and re-evaluate
    db.update_album_rule(album_id, json.dumps(parsed_spec))
    smart_albums.evaluate(album_id)

    return {"status": "ok", "album_id": album_id}


@app.post("/api/smart-collections/{album_id}/eval")
async def eval_smart_collection(album_id: str):
    """Force re-evaluate a smart album."""
    count = smart_albums.evaluate(album_id)
    return {"status": "ok", "photos_matched": count}


@app.delete("/api/smart-collections/{album_id}")
async def delete_smart_collection(album_id: str, _auth=_API_AUTH):
    """Delete a smart album (the album and its rules, not the photos)."""
    success = db.delete_album(album_id)
    if not success:
        raise HTTPException(status_code=404, detail="Smart album not found")
    return {"status": "ok", "album_id": album_id}


# ─── deduplication ────────────────────────────────────────────────────────────
@app.post("/api/dedup/scan")
async def submit_dedup_scan(_auth=_API_AUTH):
    """Submit a background dedup scan task. Returns task_id for polling."""
    if not config.dedup_enabled:
        return {"status": "disabled", "message": "Deduplication is not enabled. Set DEDUP_ENABLED=true."}

    task_id = task_queue.submit_task("dedup_scan", {"tolerance": config.dedup_tolerance})
    return {"status": "submitted", "task_id": task_id}


@app.get("/api/dedup/scan")
async def get_dedup_scan_status(task_id: str = Query(..., description="Task ID from POST")):
    """Get status of a submitted dedup scan (blocking scan for backwards compat if no task_id)."""
    if not config.dedup_enabled:
        return {"status": "disabled", "message": "Deduplication is not enabled. Set DEDUP_ENABLED=true."}

    if task_id:
        task = task_queue.get_task(task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="Task not found")
        return task
    # Backwards compat: synchronous scan (no task polling)
    groups = dedup.scan()
    return {"status": "ok", "groups": groups, "total_groups": len(groups)}


@app.get("/api/tasks")
async def list_tasks(limit: int = Query(50, ge=1, le=200), offset: int = Query(0, ge=0)):
    """List all background tasks."""
    return {"tasks": task_queue.list_tasks(limit=limit, offset=offset)}


@app.get("/api/tasks/{task_id}")
async def get_task_status(task_id: str):
    """Get status of a background task."""
    task = task_queue.get_task(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@app.post("/api/tasks/{task_id}/cancel")
async def cancel_task(task_id: str, _auth=_API_AUTH):
    """Cancel a running or pending task."""
    success = task_queue.cancel_task(task_id)
    if not success:
        task = task_queue.get_task(task_id)
        if task is None:
            raise HTTPException(status_code=404, detail="Task not found")
        raise HTTPException(status_code=409, detail=f"Cannot cancel task in state: {task['status']}")
    return {"status": "cancelled", "task_id": task_id}


@app.post("/api/dedup/merge")
async def merge_duplicate(group_id: int = Query(..., description="Group index to merge"),
                          keep_photo_id: str = Query(..., description="Photo ID to keep"),
                          _auth=_API_AUTH):
    """Archive all photos in a duplicate group except the keeper."""
    if not config.dedup_enabled:
        return {"status": "disabled"}

    result = dedup.merge_group(group_id, keep_photo_id)
    return {"status": "ok", "result": result}


@app.get("/api/dedup/settings")
async def get_dedup_settings():
    """Return current deduplication settings."""
    return {
        "dedup_enabled": config.dedup_enabled,
        "dedup_tolerance": config.dedup_tolerance
    }


@app.put("/api/dedup/settings")
async def update_dedup_settings(
    enabled: bool = Query(None, description="Enable/disable dedup"),
    tolerance: int = Query(None, description="Hamming distance threshold (0-256)"),
    _auth=_API_AUTH
):
    """Update deduplication settings."""
    if enabled is not None:
        config.dedup_enabled = enabled
    if tolerance is not None:
        config.dedup_tolerance = max(0, min(256, tolerance))
    return {"status": "ok", "settings": {"dedup_enabled": config.dedup_enabled, "dedup_tolerance": config.dedup_tolerance}}


# ==================== Geospatial Queries ========================================

@app.get("/api/photos/nearby")
async def nearby_photos(
    lat: float = Query(..., description="Latitude"),
    lon: float = Query(..., description="Longitude"),
    radius_km: float = Query(5.0, ge=0.01, description="Search radius in kilometers"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
):
    """Find photos within radius_km of (lat, lon). Returns photos with gps_lat/gps_lon set."""
    photos = db.geo_query(lat, lon, radius_km, limit=limit, offset=offset)
    return {"photos": photos, "total": len(photos), "center": {"lat": lat, "lon": lon}, "radius_km": radius_km}


# ==================== Migrations ================================================

@app.get("/api/migrate")
async def get_migration_status():
    """Get current database schema version and pending migrations."""
    info = migrator.get_info()
    return info


@app.post("/api/migrate")
async def run_migrations(_auth=_API_AUTH):
    """Apply all pending migrations. Requires API key."""
    applied = migrator.apply_all()
    return {
        "status": "applied" if applied else "up_to_date",
        "applied_count": len(applied),
        "migrations": [m["description"] for m in applied],
    }


@app.post("/api/migrate/rollback")
async def rollback_migrations(target_version: int = Query(..., description="Rollback to this version"),
                              _auth=_API_AUTH):
    """Rollback all migrations down to (not including) target_version. Requires API key."""
    result = migrator.rollback(target_version, _auth=_API_AUTH)
    return result


# ─── tags 2.0 ────────────────────────────────────────────────────────────────
@app.get("/api/photos/{photo_id}/tags/history")
async def get_photo_tag_history(photo_id: str):
    """Get the tag change history for a photo."""
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    history = tags_manager.get_tag_history(photo_id)
    return {"photo_id": photo_id, "history": history}


@app.post("/api/photos/{photo_id}/tags/auto")
async def auto_tag_photo(photo_id: str, _auth=_API_AUTH):
    """Auto-tag a photo based on its EXIF data (if enabled)."""
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")

    exif = photo.get('exif', {})
    if not exif:
        return {"status": "ok", "tags_added": [], "message": "No EXIF data available"}

    added = tags_manager.auto_tag_from_exif(photo_id, exif)
    return {"status": "ok", "tags_added": added}


@app.get("/api/photos/{photo_id}/tags/suggest")
async def suggest_photo_tags(photo_id: str):
    """Suggest auto-tags for a photo (without adding)."""
    suggestions = tags_manager.suggest_auto_tags(photo_id)
    return {"photo_id": photo_id, "suggestions": suggestions}


@app.post("/api/tags/merge")
async def merge_tags(source: str = Query(..., description="Tag to merge"),
                     target: str = Query(..., description="Target tag"),
                     _auth=_API_AUTH):
    """Merge all occurrences of source tag into target tag."""
    result = tags_manager.merge_tags(source, target)
    return {"status": "ok", "result": result}


@app.get("/api/tags/suggest")
async def suggest_duplicate_tags():
    """Find tags that differ only in case or spacing (potential duplicates)."""
    suggestions = tags_manager.get_duplicate_tag_suggestions()
    return {"suggestions": suggestions}


# ─── settings for Phase 3 ────────────────────────────────────────────────────
@app.put("/api/settings/auto_tag_gps")
async def update_auto_tag_gps(value: bool = Query(...), _auth=_API_AUTH):
    config.auto_tag_gps = value
    db.set_setting('auto_tag_gps', str(value))
    return {"status": "ok", "auto_tag_gps": value}


@app.put("/api/settings/auto_tag_camera")
async def update_auto_tag_camera(value: bool = Query(...), _auth=_API_AUTH):
    config.auto_tag_camera = value
    db.set_setting('auto_tag_camera', str(value))
    return {"status": "ok", "auto_tag_camera": value}


@app.put("/api/settings/tag_history_enabled")
async def update_tag_history(value: bool = Query(...), _auth=_API_AUTH):
    config.tag_history_enabled = value
    db.set_setting('tag_history_enabled', str(value))
    return {"status": "ok", "tag_history_enabled": value}


@app.put("/api/settings/smart_albums_enabled")
async def update_smart_albums(value: bool = Query(...), _auth=_API_AUTH):
    config.smart_albums_enabled = value
    db.set_setting('smart_albums_enabled', str(value))
    return {"status": "ok", "smart_albums_enabled": value}


@app.put("/api/settings/dedup_enabled")
async def update_dedup_setting(value: bool = Query(...), _auth=_API_AUTH):
    config.dedup_enabled = value
    db.set_setting('dedup_enabled', str(value))
    return {"status": "ok", "dedup_enabled": value}


# ==================== Web Frontend =============================================

templates_dir = Path(__file__).parent.parent / "web" / "templates"
templates_dir.mkdir(exist_ok=True)

static_dir = Path(__file__).parent.parent / "web" / "static"
static_dir.mkdir(exist_ok=True)

templates = Jinja2Templates(directory=str(templates_dir))


@app.get("/")
async def web_root(request: Request):
    """Serve the web frontend."""
    return templates.TemplateResponse("index.html", {
        "request": request,
        "db_path": config.db_path,
    })


@app.get("/static/{filename}")
async def serve_static(filename: str):
    """Serve static files from the static directory."""
    static_path = static_dir / filename
    if static_path.exists() and static_path.is_file():
        media_type = "text/html" if filename.endswith(".html") else None
        return FileResponse(static_path, media_type=media_type)
    raise HTTPException(status_code=404, detail="Static file not found")


if __name__ == "__main__":
    import uvicorn

    print(f"Starting Local Photo Library Server...")
    print(f"Watch directories: {db.get_watch_list()}")
    print(f"Database: {config.db_path}")
    print(f"Server URL: http://{config.host}:{config.port}")

    uvicorn.run(app, host=config.host, port=config.port, log_level=config.log_level)
