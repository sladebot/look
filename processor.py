"""Image processor — EXIF extraction and thumbnail generation."""
import os
from pathlib import Path
from PIL import Image
import piexif
from typing import Dict, Optional


class ImageProcessor:
    """Process images: extract EXIF, generate thumbnails."""

    def __init__(self, config):
        self.config = config

    def process(self, filepath: str) -> Dict:
        """Process an image and return metadata + path to thumbnail."""
        try:
            ext = Path(filepath).suffix.lower()

            # Handle HEIC files (convert to JPEG)
            if ext in ['.heic', '.heif']:
                return self._process_heic(filepath)

            # Handle JPEG/PNG
            elif ext in ['.jpg', '.jpeg', '.png']:
                return self._process_standard(filepath)

            # Handle RAW files (mark for conversion)
            elif ext in ['.arw', '.cr2', '.nef', '.orf', '.raf', '.pef', '.dng']:
                return self._process_raw(filepath)

            else:
                return None
        except Exception as e:
            print(f"Error processing {filepath}: {e}")
            return None

    def _process_standard(self, filepath: str) -> Dict:
        """Process standard image formats (JPEG, PNG)."""
        try:
            with Image.open(filepath) as img:
                width, height = img.size

                # Extract EXIF data
                exif_data = {}
                try:
                    exif_bytes = img.info.get('exif')
                    if exif_bytes:
                        exif = piexif.load(exif_bytes)
                        exif_data = self._parse_exif(exif)
                except:
                    pass

                mime_type = 'image/jpeg' if filepath.lower().endswith(('.jpg', '.jpeg')) else 'image/png'

                # Generate thumbnail path
                thumb_path = self._get_thumbnail_path(filepath, width)

                return {
                    'width': width,
                    'height': height,
                    'mime_type': mime_type,
                    'exif': exif_data,
                    'thumb_path': thumb_path,
                    'has_thumbnail': os.path.exists(thumb_path)
                }
        except Exception as e:
            print(f"Error in _process_standard: {e}")
            return None

    def _process_raw(self, filepath: str) -> Dict:
        """Process RAW files (mark for conversion)."""
        # RAW files need to be converted first
        # Return metadata indicating this is a RAW file
        return {
            'width': None,  # Unknown until converted
            'height': None,
            'mime_type': 'image/x-raw',
            'exif': {},
            'thumb_path': None,
            'has_thumbnail': False,
            'is_raw': True  # Mark as needing conversion
        }

    def _process_heic(self, filepath: str) -> Dict:
        """Process HEIC files (convert to JPEG)."""
        try:
            with Image.open(filepath) as img:
                # HEIC files can be opened by Pillow if libheif is available
                width, height = img.size
                mime_type = 'image/jpeg'  # Will save as JPEG

                # Generate thumbnail path
                thumb_path = self._get_thumbnail_path(filepath, width)

                # Save as JPEG (Pillow will handle conversion if libheif is available)
                jpg_path = str(Path(filepath).with_suffix('.jpg'))
                img.save(jpg_path, 'JPEG', quality=95)

                return {
                    'width': width,
                    'height': height,
                    'mime_type': mime_type,
                    'exif': {},
                    'thumb_path': thumb_path,
                    'has_thumbnail': os.path.exists(thumb_path),
                    'converted_path': jpg_path  # Path to converted JPEG
                }
        except Exception as e:
            print(f"Error in _process_heic: {e}")
            return None

    def _parse_exif(self, exif: dict) -> Dict:
        """Parse EXIF data from piexif format."""
        result = {}

        # Image tags
        img_tags = exif.get('0th', {})
        if 0x010F in img_tags:  # Make
            result['make'] = img_tags[0x010F].decode('utf-8', errors='ignore')
        if 0x0110 in img_tags:  # Model
            result['model'] = img_tags[0x0110].decode('utf-8', errors='ignore')
        if 0x0132 in img_tags:  # DateTime
            result['datetime'] = img_tags[0x0132].decode('utf-8', errors='ignore')

        # GPS tags
        gps_ifd = exif.get('GPS', {})
        if gps_ifd:
            result['gps'] = {}
            if 0 in gps_ifd:  # Latitude ref
                result['gps']['lat_ref'] = gps_ifd[0].decode('utf-8', errors='ignore')
            if 2 in gps_ifd:  # Latitude
                lat = gps_ifd[2]
                if lat:
                    result['gps']['lat'] = self._convert_exif_float(lat)
            if 4 in gps_ifd:  # Longitude
                lon = gps_ifd[4]
                if lon:
                    result['gps']['lon'] = self._convert_exif_float(lon)

        # DateTimeOriginal — highest-priority date tag (36867 = EXIF IFD)
        exif_ifd = exif.get('Exif', {})
        if 0x9003 in exif_ifd:  # 36867 = DateTimeOriginal
            result['datetime_original'] = exif_ifd[0x9003].decode('utf-8', errors='ignore')
        if 0x9004 in exif_ifd:  # 36868 = DateTimeDigitized
            result['datetime_digitized'] = exif_ifd[0x9004].decode('utf-8', errors='ignore')

        return result

    def _convert_exif_float(self, exif_value) -> float:
        """Convert EXIF rational to float."""
        try:
            # EXIF stores as (numerator, denominator) tuples
            if isinstance(exif_value, tuple):
                return exif_value[0] / exif_value[1]
            return float(exif_value)
        except:
            return 0.0

    def generate_thumbnail(self, source_path: str, width: int = 512) -> str:
        """Generate a thumbnail from a source image."""
        try:
            thumb_dir = self.config.thumbnails_dir
            thumb_path = self._get_thumbnail_path(source_path, width)

            if os.path.exists(thumb_path):
                return thumb_path  # Already exists

            with Image.open(source_path) as img:
                img.thumbnail((width, width), Image.LANCZOS)
                img.save(thumb_path, 'JPEG', quality=self.config.thumbnail_quality)

            return thumb_path
        except Exception as e:
            print(f"Error generating thumbnail: {e}")
            return None

    def _get_thumbnail_path(self, source_path: str, original_width: int = None) -> str:
        """Get the path for a thumbnail."""
        import hashlib
        source_hash = hashlib.sha256(source_path.encode()).hexdigest()[:16]
        thumb_dir = Path(self.config.photo_dir) / self.config.thumbnails_dir
        return str(thumb_dir / f"{source_hash}.jpg")

    def get_thumbnail(self, source_path: str, size: int = 256) -> Optional[str]:
        """Get or generate a thumbnail at the specified size."""
        thumb_path = self._get_thumbnail_path(source_path, size)

        if os.path.exists(thumb_path):
            return thumb_path

        # Try to find a larger thumbnail and resize
        for possible_size in [1024, 512, 256, 128]:
            possible_path = self._get_thumbnail_path(source_path, possible_size)
            if os.path.exists(possible_path):
                # Resize and save
                with Image.open(possible_path) as img:
                    img.thumbnail((size, size), Image.LANCZOS)
                    img.save(thumb_path, 'JPEG', quality=self.config.thumbnail_quality)
                return thumb_path

        # Generate from source
        return self.generate_thumbnail(source_path, size)
