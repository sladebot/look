"""Directory scanner for photo library."""
import os
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional


class DirectoryScanner:
    """Scan a directory for photo files and return metadata."""
    
    def __init__(self, photo_dir: str, image_extensions: tuple):
        self.photo_dir = Path(photo_dir).resolve()
        self.image_extensions = image_extensions
    
    def scan(self, recursive: bool = True) -> List[Dict]:
        """Scan directory for photo files."""
        photos = []
        
        if not self.photo_dir.exists():
            return photos
        
        if recursive:
            files = self.photo_dir.rglob('*')
        else:
            files = self.photo_dir.iterdir()
        
        for filepath in files:
            if filepath.is_file() and filepath.suffix.lower() in self.image_extensions:
                photo = self._scan_file(filepath)
                if photo:
                    photos.append(photo)
        
        return photos
    
    def _scan_file(self, filepath: Path) -> Optional[Dict]:
        """Scan a single file and return metadata."""
        try:
            stat = filepath.stat()
            
            return {
                'id': self._hash_filepath(str(filepath)),
                'filename': filepath.name,
                'filepath': str(filepath),
                'file_size': stat.st_size,
                'created_at': self._extract_date(filepath),
                'indexed_at': datetime.now().isoformat(),
                'has_thumbnail': False,
                'is_favorite': False,
                'color_tag': 'none',
                'is_source_jpeg': False  # Will be set during processing
            }
        except Exception as e:
            print(f"Error scanning {filepath}: {e}")
            return None
    
    def _hash_filepath(self, filepath: str) -> str:
        """Generate a unique ID for a photo based on its filepath."""
        import hashlib
        return hashlib.sha256(filepath.encode()).hexdigest()[:16]
    
    def _extract_date(self, filepath: Path) -> str:
        """Extract date from file metadata or filename."""
        # Try EXIF first (handled by processor)
        # Fallback to file modification time
        try:
            mtime = filepath.stat().st_mtime
            return datetime.fromtimestamp(mtime).isoformat()
        except:
            return datetime.now().isoformat()
    
    def find_sidecar_jpeg(self, arw_path: Path) -> Optional[Path]:
        """Find a sidecar JPEG for a given RAW file (case-insensitive suffix match)."""
        for candidate in arw_path.parent.iterdir():
            if (candidate.stem.lower() == arw_path.stem.lower()
                    and candidate.suffix.lower() in ('.jpg', '.jpeg')
                    and candidate != arw_path):
                return candidate
        return None
    
    def find_thumbnails_dir(self) -> Path:
        """Get the thumbnails directory path."""
        return self.photo_dir / '.thumbnails'
    
    def find_converted_dir(self) -> Path:
        """Get the converted files directory path."""
        return self.photo_dir / '.converted'
