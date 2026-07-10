// Look — real API data layer (wired to look FastAPI backend)

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

// Accepts ISO-8601 ("2024-02-14T14:30:00", "2024-02-14 14:30:00") and
// EXIF-style ("2024:02:14 14:30:00") datetime strings.
function parsePhotoDate(raw) {
  if (!raw) return new Date();
  let s = String(raw).trim();
  const exifMatch = s.match(/^(\d{4}):(\d{2}):(\d{2})(.*)$/);
  if (exifMatch) {
    s = `${exifMatch[1]}-${exifMatch[2]}-${exifMatch[3]}${exifMatch[4]}`;
  }
  s = s.replace(' ', 'T');
  const d = new Date(s);
  return isNaN(d.getTime()) ? new Date() : d;
}

function mapPhoto(p, albumIdForPhoto) {
  const exif = parseExif(p.exif);
  const date = parsePhotoDate(p.created_at || p.indexed_at);

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
    sizeMB: fileSizeMB,
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
    const data = await apiFetch(`/api/photos?limit=${LIMIT}&offset=${offset}`);
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
  const data = await apiFetch('/api/albums');
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
      const data = await apiFetch(`/api/albums/${album.id}`);
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
  const photoMeta = loadPhotoMeta();

  const photos = rawPhotos.map(p => {
    const albumId = albumMap[p.id] || null;
    const photo = mapPhoto(p, albumId);
    if (albumId && albumById[albumId]) {
      photo.albumName = albumById[albumId].name;
    }
    const meta = photoMeta[p.id];
    if (meta) {
      photo.rating = Number(meta.rating) || 0;
      photo.flag = meta.flag || null;
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

// ── Client-side photo meta (ratings / pick flags) ────────────────────────────
// The backend has no storage for ratings or pick/reject flags, so they are
// persisted in localStorage as { [photoId]: { rating, flag } }.

const PHOTO_META_STORAGE_KEY = 'look_photo_meta';

function loadPhotoMeta() {
  try {
    const raw = window.localStorage?.getItem(PHOTO_META_STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : null;
    return (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) ? parsed : {};
  } catch (e) {
    return {};
  }
}

function savePhotoMeta(meta) {
  try {
    window.localStorage?.setItem(PHOTO_META_STORAGE_KEY, JSON.stringify(meta || {}));
  } catch (e) {
    // storage unavailable — non-fatal
  }
}

// ── Formatting helpers ───────────────────────────────────────────────────────

function formatBytes(bytes) {
  const n = Number(bytes);
  if (!isFinite(n) || n <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
  const str = (v >= 100 || i === 0) ? String(Math.round(v)) : v.toFixed(1).replace(/\.0$/, '');
  return `${str} ${units[i]}`;
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

const API_KEY_STORAGE_KEY = 'look_api_key';
const WRITE_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

function apiKeyFromStorage() {
  try {
    return (window.localStorage?.getItem(API_KEY_STORAGE_KEY) || '').trim();
  } catch (e) {
    return '';
  }
}

function apiOptionsWithAuth(options = {}) {
  const method = (options.method || 'GET').toUpperCase();
  if (!WRITE_METHODS.has(method)) return options;

  const apiKey = apiKeyFromStorage();
  if (!apiKey) return options;

  const headers = new Headers(options.headers || {});
  if (!headers.has('X-API-Key')) headers.set('X-API-Key', apiKey);
  return { ...options, headers };
}

function apiError(data, fallback) {
  if (typeof data === 'string' && data) return data;
  if (!data || typeof data !== 'object') return fallback;
  if (Array.isArray(data.detail)) {
    return data.detail.map(item => item?.msg || JSON.stringify(item)).join('; ');
  }
  return data.detail || data.message || data.status || fallback;
}

async function apiFetch(url, options = {}) {
  const method = (options.method || 'GET').toUpperCase();
  const res = await fetch(url, apiOptionsWithAuth(options));
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(apiError(data, `${method} ${url} failed: ${res.status}`));
  }
  return data;
}

async function apiImport(path = null) {
  const url = path ? `/api/import?path=${encodeURIComponent(path)}` : '/api/import';
  return apiFetch(url, { method: 'POST' });
}

async function apiHealth() {
  return apiFetch('/api/health');
}

async function apiAddWatchDir(path) {
  return apiFetch(`/api/watch-list?path=${encodeURIComponent(path)}`, { method: 'POST' });
}

async function apiRemoveWatchDir(path) {
  return apiFetch(`/api/watch-list/${encodeURIComponent(path)}`, { method: 'DELETE' });
}

async function apiSetWatchDirActive(path, active) {
  return apiFetch(`/api/watch-list/${encodeURIComponent(path)}/active?active=${active ? 'true' : 'false'}`, {
    method: 'PATCH',
  });
}

async function apiUpdateWatchDir(path, newPath, active = null) {
  const params = new URLSearchParams({ new_path: newPath });
  if (active !== null) params.set('active', active ? 'true' : 'false');
  return apiFetch(`/api/watch-list/${encodeURIComponent(path)}?${params.toString()}`, {
    method: 'PATCH',
  });
}

async function apiTask(taskId) {
  return apiFetch(`/api/tasks/${encodeURIComponent(taskId)}`);
}

async function apiTasks(limit = 20) {
  const data = await apiFetch(`/api/tasks?limit=${encodeURIComponent(limit)}`);
  return data.tasks || [];
}

async function apiCreateAlbum(name, description = '') {
  return apiFetch(`/api/albums?name=${encodeURIComponent(name)}&description=${encodeURIComponent(description)}`, {
    method: 'POST',
  });
}

async function apiAddPhotoToAlbum(albumId, photoId) {
  return apiFetch(`/api/albums/${albumId}/photos/${photoId}`, { method: 'POST' });
}

async function apiSetFavorite(photoId, value) {
  return apiFetch(
    `/api/photos/${encodeURIComponent(photoId)}/favorite?value=${value ? 'true' : 'false'}`,
    { method: 'POST' },
  );
}

// ── Export ────────────────────────────────────────────────────────────────────

Object.assign(Look, {
  initLibrary,
  mapPhoto,
  loadPhotoMeta,
  savePhotoMeta,
  formatBytes,
  dateLabel,
  monthLabel,
  timeLabel,
  apiSetFavorite,
  apiImport,
  apiHealth,
  apiAddWatchDir,
  apiRemoveWatchDir,
  apiSetWatchDirActive,
  apiUpdateWatchDir,
  apiTask,
  apiTasks,
  apiCreateAlbum,
  apiAddPhotoToAlbum,
});

window.Look = Look;
