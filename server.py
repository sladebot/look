"""Local Photo Library Server — Main FastAPI application with web frontend."""
import os
import sys
from pathlib import Path
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from contextlib import asynccontextmanager

# Add project root to path
sys.path.insert(0, str(Path(__file__).parent))

from config import Config
from database import PhotoDatabase
from scanner import DirectoryScanner
from processor import ImageProcessor
from decoder import RawDecoder


# Create config
config = Config()

# Create database
db = PhotoDatabase(config.db_path)

# Initialize watch list from config
for d in config.watch_dirs:
    db.add_watch_dir(d)

# Create scanner (for single-dir fallback)
scanner = DirectoryScanner(config.photo_dir, config.image_extensions)

# Create processor
processor = ImageProcessor(config)

# Create decoder
decoder = RawDecoder(config)


# Create FastAPI app
app = FastAPI(title="Local Photo Library", version="0.2.0")


@app.on_event("startup")
async def startup():
    """Create static files directory."""
    static_dir = Path(__file__).parent / "static"
    static_dir.mkdir(exist_ok=True)
    app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")


# ==================== API Routes ====================

@app.get("/api/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "ok",
        "photo_count": db.get_photo_count(),
        "watch_dirs": db.get_watch_list(),
        "db_path": config.db_path
    }


@app.get("/api/watch-list")
async def get_watch_list():
    """Get all watched directories."""
    return {"directories": db.get_watch_list()}


@app.post("/api/watch-list")
async def add_watch_dir(path: str = Query(..., description="Path to add as watch directory")):
    """Add a directory to the watch list."""
    result = db.add_watch_dir(path)
    if result:
        return {"status": "added", "path": str(Path(path).resolve())}
    return JSONResponse(status_code=409, content={"status": "already_exists", "path": str(Path(path).resolve())})


@app.delete("/api/watch-list/{path:path}")
async def remove_watch_dir(path: str):
    """Remove a directory from the watch list."""
    normalized = str(Path(path).resolve())
    result = db.remove_watch_dir(normalized)
    if result:
        return {"status": "removed", "path": normalized}
    raise HTTPException(status_code=404, detail="Directory not in watch list")


@app.patch("/api/watch-list/{path:path}/active")
async def set_watch_active(path: str, active: bool = Query(..., description="true or false")):
    """Enable or disable a watch directory."""
    normalized = str(Path(path).resolve())
    result = db.set_watch_active(normalized, active)
    if result:
        return {"status": "updated", "path": normalized, "active": active}
    raise HTTPException(status_code=404, detail="Directory not in watch list")


@app.post("/api/import")
async def import_photos(path: str = Query(None, description="Specific directory to import (default: all active watch dirs)")):
    """Import photos from a directory or all active watch directories."""
    import_path = None
    photos = None
    
    if path:
        # Single directory import
        import_path = Path(path).resolve()
        if not import_path.exists():
            # Also try adding to watch list
            db.add_watch_dir(path)
            import_path = str(import_path)
            scanner = DirectoryScanner(import_path, config.image_extensions)
    else:
        # Import from all active watch directories
        photos = db.scan_all_watch_dirs()
        if not photos:
            return {
                "imported": 0,
                "errors": 0,
                "total_scanned": 0,
                "message": "No active watch directories found. Add one first."
            }
    
    imported = 0
    errors = 0
    
    if path:
        # Single directory mode
        imported_photos = scanner.scan(recursive=True)
        for photo_meta in imported_photos:
            try:
                proc_result = processor.process(photo_meta['filepath'])
                if proc_result:
                    photo_meta['width'] = proc_result['width']
                    photo_meta['height'] = proc_result['height']
                    photo_meta['mime_type'] = proc_result['mime_type']
                    
                    if sidecar_jpeg := scanner.find_sidecar_jpeg(Path(photo_meta['filepath'])):
                        photo_meta['is_source_jpeg'] = 1
                        photo_meta['filepath'] = str(sidecar_jpeg)
                    
                    db.store_photo(photo_meta)
                    imported += 1
                    
                    thumb_path = proc_result.get('thumb_path')
                    if thumb_path and os.path.exists(thumb_path):
                        db.mark_thumbnail(photo_meta['id'], True)
                    
            except Exception as e:
                print(f"Error importing {photo_meta['filepath']}: {e}")
                errors += 1
        
        # Log import
        db.log_import(str(import_path), 'completed', imported, f"{errors} errors" if errors else None)
        
    else:
        # Multi-directory mode (scan_all_watch_dirs already returned photos)
        for photo_meta in photos:
            try:
                proc_result = processor.process(photo_meta['filepath'])
                if proc_result:
                    photo_meta['width'] = proc_result['width']
                    photo_meta['height'] = proc_result['height']
                    photo_meta['mime_type'] = proc_result['mime_type']
                    
                    single_scanner = DirectoryScanner(Path(photo_meta['filepath']).parent, config.image_extensions)
                    if sidecar_jpeg := single_scanner.find_sidecar_jpeg(Path(photo_meta['filepath'])):
                        photo_meta['is_source_jpeg'] = 1
                        photo_meta['filepath'] = str(sidecar_jpeg)
                    
                    db.store_photo(photo_meta)
                    imported += 1
                    
                    thumb_path = proc_result.get('thumb_path')
                    if thumb_path and os.path.exists(thumb_path):
                        db.mark_thumbnail(photo_meta['id'], True)
                    
            except Exception as e:
                print(f"Error importing {photo_meta['filepath']}: {e}")
                errors += 1
    
    return {
        "imported": imported,
        "errors": errors,
        "total_scanned": len(photos) if path is None else scanner.scan_count,
        "message": f"Imported {imported} photos from {1 if path else 'multiple'} directory/directories"
    }


@app.get("/api/photos")
async def list_photos(
    album: str = Query(None, description="Filter by album ID"),
    tag: str = Query(None, description="Filter by tag"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0)
):
    """List photos with optional filtering."""
    photos = db.list_photos(album=album, tag=tag, limit=limit, offset=offset)
    return {"photos": photos, "total": len(photos)}


@app.get("/api/photos/{photo_id}")
async def get_photo(photo_id: str):
    """Get a single photo's metadata."""
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    return photo


@app.get("/api/thumbnails/{photo_id}")
async def get_thumbnail(photo_id: str, size: int = Query(256, ge=128, le=1024)):
    """Get or generate a thumbnail for a photo."""
    photo = db.get_photo(photo_id)
    if not photo:
        raise HTTPException(status_code=404, detail="Photo not found")
    
    filepath = photo['filepath']
    sidecar_jpeg = scanner.find_sidecar_jpeg(Path(filepath))
    if sidecar_jpeg:
        filepath = str(sidecar_jpeg)
    
    if Path(filepath).suffix.lower() in decoder.raw_extensions:
        converted = decoder.decode(filepath)
        if converted:
            filepath = converted
    
    thumb_path = processor.get_thumbnail(filepath, size)
    
    if not thumb_path or not os.path.exists(thumb_path):
        try:
            thumb_path = processor.generate_thumbnail(filepath, size)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to generate thumbnail: {e}")
    
    return FileResponse(thumb_path, media_type="image/jpeg")


@app.get("/api/full/{photo_id}")
async def get_full_photo(photo_id: str):
    """Get the full-resolution photo (or converted JPEG for RAW files)."""
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


@app.get("/api/albums")
async def list_albums():
    """List all albums."""
    albums = db.get_albums()
    return {"albums": albums}


@app.post("/api/albums")
async def create_album(name: str, description: str = "", source: str = "manual", folder: str = None):
    """Create a new album."""
    album_id = db.create_album(name, description, source, folder)
    return {"id": album_id, "name": name}


@app.get("/api/albums/{album_id}")
async def get_album(album_id: str):
    """Get album with photos."""
    album = db.get_album(album_id)
    if not album:
        raise HTTPException(status_code=404, detail="Album not found")
    return album


@app.put("/api/albums/{album_id}")
async def update_album(album_id: str, name: str = None, description: str = None):
    """Update an album."""
    if not db.update_album(album_id, name, description):
        raise HTTPException(status_code=404, detail="Album not found")
    return {"status": "ok"}


@app.delete("/api/albums/{album_id}")
async def delete_album(album_id: str):
    """Delete an album (does not delete photos)."""
    if not db.delete_album(album_id):
        raise HTTPException(status_code=404, detail="Album not found")
    return {"status": "ok"}


@app.post("/api/albums/{album_id}/photos/{photo_id}")
async def add_photo_to_album(album_id: str, photo_id: str):
    """Add a photo to an album."""
    db.add_photo_to_album(album_id, photo_id)
    return {"status": "ok"}


@app.delete("/api/albums/{album_id}/photos/{photo_id}")
async def remove_photo_from_album(album_id: str, photo_id: str):
    """Remove a photo from an album."""
    db.remove_photo_from_album(album_id, photo_id)
    return {"status": "ok"}


@app.get("/api/search")
async def search_photos(q: str = Query(..., min_length=1), limit: int = 50):
    """Search photos by filename, tags, or filepath."""
    photos = db.search_photos(q, limit)
    return {"photos": photos}


# ==================== Web Frontend ====================

templates_dir = Path(__file__).parent / "templates"
templates_dir.mkdir(exist_ok=True)

static_dir = Path(__file__).parent / "static"
static_dir.mkdir(exist_ok=True)

templates = Jinja2Templates(directory=str(templates_dir))


@app.get("/")
async def web_root(request: Request):
    """Serve the web frontend."""
    return templates.TemplateResponse("index.html", {
        "request": request,
        "db_path": config.db_path
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
