"""Image processor — EXIF extraction and thumbnail generation."""
import hashlib
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

        # GPS tags — extract as top-level gps_lat / gps_lon for DB storage
        # plus keep nested gps dict for the full EXIF blob.
        gps_ifd = exif.get('GPS', {})
        if gps_ifd:
            result['gps'] = {}
            lat_ref = gps_ifd.get(1, b'N')
            if isinstance(lat_ref, bytes):
                lat_ref = lat_ref.decode('utf-8', errors='ignore').strip()
            lon_ref = gps_ifd.get(3, b'E')
            if isinstance(lon_ref, bytes):
                lon_ref = lon_ref.decode('utf-8', errors='ignore').strip()
            if 2 in gps_ifd:
                lat = self._dms_to_decimal(gps_ifd[2])
                if lat is not None:
                    lat_val = lat if lat_ref != 'S' else -lat
                    result['gps']['lat'] = lat_val
                    result['gps_lat'] = lat_val
            if 4 in gps_ifd:
                lon = self._dms_to_decimal(gps_ifd[4])
                if lon is not None:
                    lon_val = lon if lon_ref != 'W' else -lon
                    result['gps']['lon'] = lon_val
                    result['gps_lon'] = lon_val

        # DateTimeOriginal — highest-priority date tag (36867 = EXIF IFD)
        exif_ifd = exif.get('Exif', {})
        if 0x9003 in exif_ifd:  # 36867 = DateTimeOriginal
            result['datetime_original'] = exif_ifd[0x9003].decode('utf-8', errors='ignore')
        if 0x9004 in exif_ifd:  # 36868 = DateTimeDigitized
            result['datetime_digitized'] = exif_ifd[0x9004].decode('utf-8', errors='ignore')

        return result

    def _dms_to_decimal(self, dms) -> float:
        """Convert EXIF GPS DMS 3-tuple of rationals to decimal degrees."""
        try:
            d = dms[0][0] / dms[0][1]
            m = dms[1][0] / dms[1][1]
            s = dms[2][0] / dms[2][1]
            return d + m / 60 + s / 3600
        except Exception:
            return None

    def generate_thumbnail(self, source_path: str, width: int = 512) -> str:
        """Generate a thumbnail from a source image."""
        try:
            thumb_path = self._get_thumbnail_path(source_path, width)

            if os.path.exists(thumb_path):
                return thumb_path  # Already exists

            Path(thumb_path).parent.mkdir(parents=True, exist_ok=True)
            with Image.open(source_path) as img:
                img.thumbnail((width, width), Image.LANCZOS)
                img.save(thumb_path, 'JPEG', quality=self.config.thumbnail_quality)

            return thumb_path
        except Exception as e:
            print(f"Error generating thumbnail: {e}")
            return None

    def _get_thumbnail_path(self, source_path: str, size: int = None) -> str:
        """Get the path for a thumbnail at a specific size."""
        source_hash = hashlib.sha256(self._thumbnail_cache_key(source_path, size).encode()).hexdigest()[:16]
        source_dir = Path(source_path).parent
        if source_dir.name == self.config.converted_dir:
            source_dir = source_dir.parent
        thumb_dir = source_dir / self.config.thumbnails_dir
        suffix = f"_{size}" if size else ""
        return str(thumb_dir / f"{source_hash}{suffix}.jpg")

    def _thumbnail_cache_key(self, source_path: str, size: int = None) -> str:
        try:
            stat = Path(source_path).stat()
            return "|".join([
                source_path,
                str(stat.st_mtime_ns),
                str(stat.st_size),
                str(size or ""),
                str(self.config.thumbnail_quality),
            ])
        except Exception:
            return f"{source_path}|{size or ''}|{self.config.thumbnail_quality}"

    def find_existing_thumbnail(self, source_path: str, size: int = 256) -> Optional[str]:
        """Return an existing thumbnail path without generating new work."""
        thumb_path = self._get_thumbnail_path(source_path, size)
        if os.path.exists(thumb_path):
            return thumb_path

        for possible_size in [1024, 512, 400, 256, 128]:
            if possible_size < size:
                continue
            possible_path = self._get_thumbnail_path(source_path, possible_size)
            if os.path.exists(possible_path):
                return possible_path
        return None

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
