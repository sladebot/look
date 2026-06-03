// Look — real API data layer (wired to local-photos-server FastAPI backend)

window.Look = window.Look || {};
const Look = window.Look;

const SWATCH_COLORS = [
  '#7aa7c7','#e5b27a','#c98a8a','#7fb285',
  '#b896c4','#7c9cb5','#9ab8a3','#d4a27a',
];

// ── Photo mapping ────────────────────────────────────────────────────────────

function parseExif(raw) {
  if (!raw) return {};
  if (typeof raw === 'object') return raw;
  try { return JSON.parse(raw); } catch (e) { return {}; }
}

function mapPhoto(p, albumIdForPhoto) {
  const exif = parseExif(p.exif);
  const dateRaw = p.created_at || p.indexed_at;
  const date = dateRaw ? new Date(dateRaw.replace(' ', 'T')) : new Date();

  const w = p.width || 3;
  const h = p.height || 2;
  const fileSizeMB = p.file_size ? +(p.file_size / 1048576).toFixed(1) : 0;

  const gps = exif.gps || {};
  const lat = typeof gps.lat === 'number' ? gps.lat : 0;
  const lng = typeof gps.lon === 'number' ? gps.lon : 0;

  const make = (exif.make || '').trim().replace(/\0/g, '');
  const model = (exif.model || '').trim().replace(/\0/g, '');
  const camera = make && model ? `${make} ${model}` : (model || make || '');

  const isRaw = p.mime_type === 'image/x-raw';

  return {
    id: p.id,
    filename: p.filename,
    filepath: p.filepath,
    thumb: `/api/thumbnails/${p.id}?size=400`,
    full: `/api/full/${p.id}`,
    ratio: [w, h],
    pixelW: w,
    pixelH: h,
    date,
    camera: camera || 'Unknown',
    lens: (exif.lens || '').trim().replace(/\0/g, ''),
    iso: exif.iso || null,
    aperture: exif.aperture || null,
    shutter: exif.shutter || null,
    focal: exif.focal_length || null,
    rating: 0,
    flag: null,
    raw: isRaw,
    rawSizeMB: fileSizeMB,
    jpegSizeMB: isRaw ? +(fileSizeMB * 0.12).toFixed(1) : fileSizeMB,
    mime_type: p.mime_type,
    album: albumIdForPhoto || null,
    albumName: '',           // filled in by caller after album lookup
    favorite: !!p.is_favorite,
    location: (lat && lng) ? `${lat.toFixed(3)}°, ${lng.toFixed(3)}°` : '',
    lat,
    lng,
    rawFilename: p.filename,
    // keep raw API data for admin
    _api: p,
  };
}

// ── Fetch all photos (paginated) ─────────────────────────────────────────────

async function loadAllPhotos() {
  const all = [];
  let offset = 0;
  const LIMIT = 200;
  while (true) {
    const res = await fetch(`/api/photos?limit=${LIMIT}&offset=${offset}`);
    if (!res.ok) throw new Error(`/api/photos failed: ${res.status}`);
    const data = await res.json();
    const batch = data.photos || [];
    all.push(...batch);
    if (batch.length < LIMIT) break;
    offset += LIMIT;
    if (all.length >= 5000) break; // safety cap
  }
  return all;
}

// ── Fetch albums ─────────────────────────────────────────────────────────────

async function loadAlbumData() {
  const res = await fetch('/api/albums');
  if (!res.ok) throw new Error(`/api/albums failed: ${res.status}`);
  const data = await res.json();
  const rawAlbums = (data.albums || []).filter(a => a.source !== 'smart_collection');

  const albums = rawAlbums.map((a, i) => ({
    id: a.id,
    name: a.name,
    description: a.description || '',
    count: 0,
    color: SWATCH_COLORS[i % SWATCH_COLORS.length],
    kind: 'album',
    source: a.source,
  }));

  // Flat album tree — backend has no folder concept yet
  const tree = albums;

  return { albums, tree };
}

// ── Build photo→album membership map ─────────────────────────────────────────
// Loads each album's photo list (capped to first 30 albums to stay fast).

async function buildAlbumPhotoMap(albums) {
  const map = {}; // photo_id → album_id
  const ALBUM_CAP = 30;
  for (const album of albums.slice(0, ALBUM_CAP)) {
    try {
      const res = await fetch(`/api/albums/${album.id}`);
      if (!res.ok) continue;
      const data = await res.json();
      const photos = data.photos || [];
      album.count = photos.length;
      for (const p of photos) {
        if (!map[p.id]) map[p.id] = album.id;
      }
    } catch (e) {
      // non-fatal
    }
  }
  return map;
}

// ── Full init: load everything, return ready state ───────────────────────────

async function initLibrary() {
  const [rawPhotos, albumData] = await Promise.all([
    loadAllPhotos(),
    loadAlbumData(),
  ]);

  const albumMap = await buildAlbumPhotoMap(albumData.albums);
  const albumById = Object.fromEntries(albumData.albums.map(a => [a.id, a]));

  const photos = rawPhotos.map(p => {
    const albumId = albumMap[p.id] || null;
    const photo = mapPhoto(p, albumId);
    if (albumId && albumById[albumId]) {
      photo.albumName = albumById[albumId].name;
    }
    return photo;
  });

  // Update counts from actual membership
  albumData.albums.forEach(a => {
    if (a.count === 0) {
      a.count = photos.filter(p => p.album === a.id).length;
    }
  });

  return { photos, albums: albumData.albums, albumTree: albumData.tree };
}

// ── Date helpers ─────────────────────────────────────────────────────────────

function dateLabel(d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${months[d.getMonth()]} ${d.getDate()}, ${d.getFullYear()}`;
}
function monthLabel(d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${months[d.getMonth()]} ${d.getFullYear()}`;
}
function timeLabel(d) {
  let h = d.getHours();
  const m = String(d.getMinutes()).padStart(2, '0');
  const ap = h >= 12 ? 'PM' : 'AM';
  h = h % 12 || 12;
  return `${h}:${m} ${ap}`;
}

// ── API helpers ───────────────────────────────────────────────────────────────

async function apiImport(path = null) {
  const url = path ? `/api/import?path=${encodeURIComponent(path)}` : '/api/import';
  const res = await fetch(url, { method: 'POST' });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(data.detail || data.message || `/api/import failed: ${res.status}`);
  }
  return data;
}

async function apiHealth() {
  const res = await fetch('/api/health');
  return res.json();
}

async function apiCreateAlbum(name, description = '') {
  const res = await fetch(`/api/albums?name=${encodeURIComponent(name)}&description=${encodeURIComponent(description)}`, {
    method: 'POST',
  });
  return res.json();
}

async function apiAddPhotoToAlbum(albumId, photoId) {
  await fetch(`/api/albums/${albumId}/photos/${photoId}`, { method: 'POST' });
}

// ── Export ────────────────────────────────────────────────────────────────────

Object.assign(Look, {
  initLibrary,
  mapPhoto,
  dateLabel,
  monthLabel,
  timeLabel,
  apiImport,
  apiHealth,
  apiCreateAlbum,
  apiAddPhotoToAlbum,
});

window.Look = Look;
