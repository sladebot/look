"""RAW decoder — converts ARW/CR2/NEF to JPEG using rawpy."""
import os
import hashlib
import threading
from pathlib import Path
from typing import Dict, Optional
import rawpy
from PIL import Image


class RawDecoder:
    """Decode RAW files (ARW, CR2, NEF, etc.) to JPEG using rawpy."""
    
    def __init__(self, config):
        self.config = config
        self.raw_extensions = ('.arw', '.cr2', '.nef', '.orf', '.raf', '.pef', '.dng')
    
    def decode(self, filepath: str, quality: int = 85) -> Optional[str]:
        """Decode a RAW file to JPEG and return path to the converted file."""
        try:
            ext = Path(filepath).suffix.lower()
            
            # Check if this is a RAW file
            if ext not in self.raw_extensions:
                return None
            
            # Check if already converted
            converted_path = self._get_converted_path(filepath)
            if os.path.exists(converted_path):
                if self._is_valid_jpeg(converted_path):
                    return converted_path
                os.remove(converted_path)
            
            # Decode using rawpy
            with rawpy.imread(filepath) as raw:
                # Get RGB image
                rgb = raw.postprocess(
                    half_size=getattr(self.config, "raw_preview_half_size", True),
                    output_bps=8,
                    use_camera_wb=True,
                )
                
                img = Image.fromarray(rgb)
                
                # Ensure output directory exists
                os.makedirs(os.path.dirname(converted_path), exist_ok=True)
                
                tmp_path = f"{converted_path}.{threading.get_ident()}.tmp.jpg"
                img.save(tmp_path, 'JPEG', quality=quality)
                os.replace(tmp_path, converted_path)
                
                return converted_path
                
        except Exception as e:
            print(f"Error decoding {filepath}: {e}")
            return None

    def _is_valid_jpeg(self, filepath: str) -> bool:
        """Return True if filepath is an existing, readable JPEG."""
        try:
            with Image.open(filepath) as img:
                img.verify()
            return True
        except Exception:
            return False
    
    def _get_converted_path(self, filepath: str) -> str:
        """Get the path for the converted JPEG file."""
        file_hash = hashlib.sha256(filepath.encode()).hexdigest()[:16]
        converted_dir = Path(filepath).parent / self.config.converted_dir
        return str(converted_dir / f"{file_hash}.jpg")
    
    def get_converted_file(self, filepath: str) -> Optional[str]:
        """Get the converted file path (creates if needed)."""
        return self.decode(filepath)
