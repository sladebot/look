"""Local Photo Library Server — Configuration"""
import os
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Config:
    """Server configuration."""
    
    # Watch directories (multi-dir support)
    watch_dirs: list = field(default_factory=list)  # list of absolute paths
    
    # Default single photo_dir (backwards compat, also added to watch_dirs)
    photo_dir: str = os.environ.get("PHOTO_DIR", str(Path.home() / "Pictures" / "Photos"))
    
    # Server settings
    host: str = os.environ.get("HOST", "0.0.0.0")
    port: int = int(os.environ.get("PORT", "8080"))
    
    # Database
    db_path: str = os.environ.get("DB_PATH", str(Path.home() / ".local" / "local-photos" / "library.db"))
    
    # Thumbnails directory (relative to photo_dir)
    thumbnails_dir: str = os.environ.get("THUMBNAILS_DIR", "thumbnails")

    # Converted RAW files (relative to photo_dir)
    converted_dir: str = os.environ.get("CONVERTED_DIR", "converted")
    
    # API key (optional, for authentication)
    api_key: Optional[str] = os.environ.get("API_KEY", None)
    
    # Thumbnail quality (1-100)
    thumbnail_quality: int = int(os.environ.get("THUMBNAIL_QUALITY", "85"))
    
    # Max thumbnail size (pixels, width)
    max_thumbnail_width: int = int(os.environ.get("MAX_THUMBNAIL_WIDTH", "1024"))
    
    # Log level
    log_level: str = os.environ.get("LOG_LEVEL", "info")
    
    # Allowed photo extensions
    image_extensions: tuple = field(default_factory=lambda: (
        ".jpg", ".jpeg", ".png", ".heic", ".heif",
        ".arw", ".cr2", ".nef", ".orf", ".raf", ".pef", ".dng"
    ))

    # Smart album settings
    smart_albums_enabled: bool = os.environ.get("SMART_ALBUMS_ENABLED", "false").lower() in ("true", "1", "yes")
    smart_album_max_photos: int = int(os.environ.get("SMART_ALBUM_MAX_PHOTOS", "1000"))

    # Deduplication settings
    dedup_enabled: bool = os.environ.get("DEDUP_ENABLED", "false").lower() in ("true", "1", "yes")
    dedup_tolerance: int = int(os.environ.get("DEDUP_TOLERANCE", "20"))  # max hamming distance

    # Tags 2.0 settings
    tag_history_enabled: bool = os.environ.get("TAG_HISTORY_ENABLED", "true").lower() in ("true", "1", "yes")
    auto_tag_gps: bool = os.environ.get("AUTO_TAG_GPS", "false").lower() in ("true", "1", "yes")
    auto_tag_camera: bool = os.environ.get("AUTO_TAG_CAMERA", "false").lower() in ("true", "1", "yes")

    # Filewatcher cooldown (seconds)
    filewatcher_cooldown: str = os.environ.get("FILEWATCHER_COOLDOWN", "3")
    
    def __post_init__(self):
        """Create directories if they don't exist, populate watch_dirs."""
        # Ensure backward compat: add default photo_dir to watch_dirs
        if self.photo_dir and self.photo_dir not in self.watch_dirs:
            self.watch_dirs.append(self.photo_dir)
        
        for d in self.watch_dirs:
            Path(d).mkdir(parents=True, exist_ok=True)
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
