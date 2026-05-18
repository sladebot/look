"""RAW decoder — converts ARW/CR2/NEF to JPEG using rawpy."""
import os
from pathlib import Path
from typing import Dict, Optional
import rawpy


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
                return converted_path
            
            # Decode using rawpy
            with rawpy.imread(filepath) as raw:
                # Get RGB image
                rgb = raw.postprocess()
                
                # Save as JPEG
                from PIL import Image
                import io
                
                img = Image.fromarray(rgb)
                
                # Ensure output directory exists
                os.makedirs(os.path.dirname(converted_path), exist_ok=True)
                
                # Save as JPEG
                img.save(converted_path, 'JPEG', quality=quality)
                
                return converted_path
                
        except Exception as e:
            print(f"Error decoding {filepath}: {e}")
            return None
    
    def _get_converted_path(self, filepath: str) -> str:
        """Get the path for the converted JPEG file."""
        base = Path(filepath).stem
        converted_dir = Path(self.config.photo_dir) / self.config.converted_dir
        return str(converted_dir / f"{base}.jpg")
    
    def get_converted_file(self, filepath: str) -> Optional[str]:
        """Get the converted file path (creates if needed)."""
        return self.decode(filepath)
