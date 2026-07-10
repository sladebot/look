/* Look — main app, wired to local-photos-server FastAPI backend */

const {
  useState: aaUseState,
  useEffect: aaUseEffect,
  useMemo: aaUseMemo,
  useCallback: aaUseCallback,
  useRef: aaUseRef,
} = React;

const TWEAKS_DEFAULTS = /*EDITMODE-BEGIN*/{
  "density": 6,
  "theme": "dark",
  "aspectPreserve": false,
  "showStarsOnThumb": true,
  "showFavOnThumb": true
}/*EDITMODE-END*/;

const AUTO_SYNC_INTERVAL_MS = 30000;
const STATUS_POLL_INTERVAL_MS = 1500;

// Tweaks persistence (localStorage) — hydrated at startup, written on change.
const TWEAKS_STORAGE_KEY = 'look_tweaks';

function loadStoredTweaks() {
  try {
    const raw = window.localStorage?.getItem(TWEAKS_STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : null;
    return (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) ? parsed : {};
  } catch (e) {
    return {};
  }
}

function saveStoredTweaks(tweaks) {
  try {
    window.localStorage?.setItem(TWEAKS_STORAGE_KEY, JSON.stringify(tweaks));
  } catch (e) {
    // storage unavailable — non-fatal
  }
}

// SWATCH_COLORS is defined in look-data.js (shared global scope)

// ── Loading screen ────────────────────────────────────────────────────────────

function LoadingScreen({ error }) {
  return (
    <div className="look-loading">
      <div className="look-loading-brand">
        <span className="brand-dot" />
        Look
      </div>
      {error
        ? <div className="look-error">Failed to load library:<br />{error}</div>
        : (
          <>
            <div className="look-loading-sub">Loading photo library…</div>
            <div className="look-loading-bar"><div className="look-loading-fill" /></div>
          </>
        )
      }
    </div>
  );
}

// ── App ───────────────────────────────────────────────────────────────────────

function App() {
  // Library data
  const [photos, setPhotos] = aaUseState([]);
  const [albumTree, setAlbumTree] = aaUseState([]);
  const [albums, setAlbums] = aaUseState([]);
  const [loading, setLoading] = aaUseState(true);
  const [loadError, setLoadError] = aaUseState(null);

  // UI state
  const [tweaks, setTweaks] = aaUseState(() => ({ ...TWEAKS_DEFAULTS, ...loadStoredTweaks() }));
  const [mode, setMode] = aaUseState('pro');
  const [selected, setSelected] = aaUseState('all');
  const [search, setSearch] = aaUseState('');
  const [view, setView] = aaUseState('grid');
  const [filter, setFilter] = aaUseState({ flagged: null, minRating: 0, fav: false });
  const [sortKey, setSortKey] = aaUseState('date');
  const [openId, setOpenId] = aaUseState(null);
  const [adminOpen, setAdminOpen] = aaUseState(false);
  const [albumModalOpen, setAlbumModalOpen] = aaUseState(false);
  const [tweaksOpen, setTweaksOpen] = aaUseState(false);
  const [importModalOpen, setImportModalOpen] = aaUseState(false);
  const [syncing, setSyncing] = aaUseState(false);
  const [syncMessage, setSyncMessage] = aaUseState('');
  const syncRunningRef = aaUseRef(false);
  const photoCountRef = aaUseRef(0);

  const [status, setStatus] = aaUseState({
    previewsDone: 0,
    previewsTotal: 1,
    libraryBytes: 0,
    processing: null,
  });

  // ── Load library from API ──────────────────────────────────────────────────
  const reloadLibrary = aaUseCallback(async () => {
    const lib = await Look.initLibrary();
    setPhotos(lib.photos);
    setAlbums(lib.albums);
    setAlbumTree(lib.albumTree);

    const done = lib.photos.filter(p => p._api?.has_thumbnail).length;
    const libraryBytes = lib.photos.reduce((sum, p) => sum + (Number(p._api?.file_size) || 0), 0);
    setStatus(prev => ({
      ...prev,
      previewsDone: done,
      previewsTotal: lib.photos.length,
      libraryBytes,
    }));
    return lib;
  }, []);

  aaUseEffect(() => {
    async function init() {
      try {
        await reloadLibrary();
      } catch (e) {
        setLoadError(e.message || String(e));
      } finally {
        setLoading(false);
      }
    }
    init();
  }, [reloadLibrary]);

  aaUseEffect(() => {
    photoCountRef.current = photos.length;
  }, [photos.length]);

  // Poll background task progress for import/conversion work.
  aaUseEffect(() => {
    if (loading) return;
    let cancelled = false;

    async function refreshProcessingStatus() {
      try {
        const tasks = await Look.apiTasks(20);
        if (cancelled) return;
        const active = tasks.find(t => (
          t.task_type === 'import' &&
          (t.status === 'running' || t.status === 'pending')
        ));
        setStatus(prev => {
          if (!active) return prev.processing ? { ...prev, processing: null } : prev;
          const progress = active.progress || {};
          const total = Number(progress.total_scanned || progress.total || 0);
          const current = Number(progress.current || 0);
          const imported = Number(progress.imported || 0);
          const errors = Number(progress.errors || 0);
          const phase = progress.phase || active.status;
          return {
            ...prev,
            processing: {
              active: true,
              taskId: active.task_id,
              status: active.status,
              phase,
              current,
              total,
              imported,
              errors,
              label: phase === 'scanning' ? 'Scanning photos' : 'Processing photos',
            },
          };
        });
      } catch (_) {
        if (!cancelled) setStatus(prev => prev.processing ? { ...prev, processing: null } : prev);
      }
    }

    refreshProcessingStatus();
    const t = setInterval(refreshProcessingStatus, STATUS_POLL_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(t);
    };
  }, [loading]);

  // Tweaks panel host protocol
  aaUseEffect(() => {
    function onMsg(e) {
      if (e.data?.type === '__activate_edit_mode') setTweaksOpen(true);
      if (e.data?.type === '__deactivate_edit_mode') setTweaksOpen(false);
    }
    window.addEventListener('message', onMsg);
    window.parent.postMessage({ type: '__edit_mode_available' }, '*');
    return () => window.removeEventListener('message', onMsg);
  }, []);

  const setTweak = aaUseCallback((k, v) => {
    setTweaks(prev => {
      const next = typeof k === 'object' ? { ...prev, ...k } : { ...prev, [k]: v };
      saveStoredTweaks(next);
      window.parent.postMessage({ type: '__edit_mode_set_keys', edits: typeof k === 'object' ? k : { [k]: v } }, '*');
      return next;
    });
  }, []);

  // Apply theme
  aaUseEffect(() => {
    document.documentElement.classList.toggle('light', tweaks.theme === 'light');
  }, [tweaks.theme]);

  // ── Filtering ──────────────────────────────────────────────────────────────
  const filtered = aaUseMemo(() => {
    let list = photos;

    if (selected === 'recent') {
      const cutoff = new Date(); cutoff.setDate(cutoff.getDate() - 30);
      list = list.filter(p => p.date >= cutoff);
    } else if (selected === 'favs') {
      list = list.filter(p => p.favorite);
    } else if (selected === 'picks') {
      list = list.filter(p => p.flag === 'pick');
    } else if (selected.startsWith('album:')) {
      const id = selected.slice(6);
      list = list.filter(p => p.album === id);
    } else if (selected.startsWith('date:')) {
      const [y, m] = selected.slice(5).split('-').map(Number);
      list = list.filter(p => p.date.getFullYear() === y && p.date.getMonth() === m);
    }

    const q = search.trim().toLowerCase();
    if (q) {
      list = list.filter(p =>
        p.camera.toLowerCase().includes(q) ||
        (p.lens || '').toLowerCase().includes(q) ||
        (p.albumName || '').toLowerCase().includes(q) ||
        (p.location || '').toLowerCase().includes(q) ||
        p.filename.toLowerCase().includes(q) ||
        Look.dateLabel(p.date).toLowerCase().includes(q) ||
        Look.monthLabel(p.date).toLowerCase().includes(q)
      );
    }

    if (mode === 'pro') {
      if (filter.flagged) list = list.filter(p => p.flag === filter.flagged);
      if (filter.minRating > 0) list = list.filter(p => p.rating >= filter.minRating);
      if (filter.fav) list = list.filter(p => p.favorite);
    }

    if (sortKey === 'rating') {
      list = [...list].sort((a, b) => (b.rating - a.rating) || (b.date - a.date));
    } else {
      list = [...list].sort((a, b) => b.date - a.date);
    }
    return list;
  }, [photos, selected, search, filter, sortKey, mode]);

  const crumbInfo = aaUseMemo(() => {
    if (selected === 'all') return { title: 'All Photos', meta: '' };
    if (selected === 'recent') return { title: 'Recently Added', meta: 'Last 30 days' };
    if (selected === 'favs') return { title: 'Favorites', meta: '' };
    if (selected === 'picks') return { title: 'Picks', meta: 'Flagged as keepers' };
    if (selected.startsWith('album:')) {
      const id = selected.slice(6);
      const a = albums.find(x => x.id === id);
      return { title: a?.name || 'Album', meta: a ? 'Album' : '' };
    }
    if (selected.startsWith('date:')) {
      const [y, m] = selected.slice(5).split('-').map(Number);
      const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
      return { title: `${months[m]} ${y}`, meta: '' };
    }
    return { title: 'All Photos', meta: '' };
  }, [selected, albums]);

  // ── Actions ────────────────────────────────────────────────────────────────

  // Ratings and pick/reject flags have no backend storage — write-through to
  // localStorage ('look_photo_meta') so they survive reloads.
  const updatePhotoMeta = (id, patch) => {
    const meta = Look.loadPhotoMeta();
    const next = { ...(meta[id] || { rating: 0, flag: null }), ...patch };
    if (!next.rating && !next.flag) {
      delete meta[id];
    } else {
      meta[id] = next;
    }
    Look.savePhotoMeta(meta);
  };

  const setRating = (id, v) => {
    setPhotos(ps => ps.map(p => p.id === id ? { ...p, rating: v } : p));
    updatePhotoMeta(id, { rating: v });
  };
  const setFlag = (id, f) => {
    setPhotos(ps => ps.map(p => p.id === id ? { ...p, flag: f } : p));
    updatePhotoMeta(id, { flag: f });
  };

  // Favorites are backend-persisted: optimistic update, rollback on failure.
  const toggleFav = (id) => {
    const photo = photos.find(p => p.id === id);
    if (!photo) return;
    const nextValue = !photo.favorite;
    setPhotos(ps => ps.map(p => p.id === id ? { ...p, favorite: nextValue } : p));
    Look.apiSetFavorite(id, nextValue).catch(err => {
      setPhotos(ps => ps.map(p => p.id === id ? { ...p, favorite: !nextValue } : p));
      setSyncMessage(`Favorite update failed: ${err?.message || String(err)}`);
      console.error('Favorite update failed', err);
    });
  };

  const handleDropOnAlbum = async (albumId, e) => {
    const id = e.dataTransfer.getData('text/photo-id');
    if (!id) return;
    // Optimistic UI update
    const album = albums.find(a => a.id === albumId);
    const previousPhoto = photos.find(p => p.id === id);
    setPhotos(ps => ps.map(p => p.id === id ? { ...p, album: albumId, albumName: album?.name || '' } : p));
    try {
      await Look.apiAddPhotoToAlbum(albumId, id);
    } catch (err) {
      setPhotos(ps => ps.map(p => p.id === id ? {
        ...p,
        album: previousPhoto?.album || null,
        albumName: previousPhoto?.albumName || '',
      } : p));
      const message = err?.message || String(err);
      setSyncMessage(`Album add failed: ${message}`);
      console.error('Album add failed', err);
    }
  };

  const handleCreateAlbum = async (name, serverAlbumId) => {
    const id = serverAlbumId || name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
    const colors = SWATCH_COLORS;
    const album = {
      id,
      name,
      count: 0,
      color: colors[albums.length % colors.length],
      kind: 'album',
      source: 'manual',
    };
    setAlbums(a => [...a, album]);
    setAlbumTree(t => [...t, album]);
    setAlbumModalOpen(false);
    setSelected(`album:${id}`);
  };

  const handleImportDone = async () => {
    await reloadLibrary();
  };

  const handleSyncLibrary = aaUseCallback(async ({ background = false } = {}) => {
    if (syncRunningRef.current) return;
    syncRunningRef.current = true;
    if (!background) {
      setSyncing(true);
      setSyncMessage('Syncing photos…');
    }
    try {
      const tasks = await Look.apiTasks(10);
      const importRunning = tasks.some(t => (
        t.task_type === 'import' &&
        (t.status === 'running' || t.status === 'pending')
      ));
      if (importRunning) {
        if (!background) setSyncMessage('Import already running');
        return;
      }
      const before = photoCountRef.current;
      const result = await Look.apiImport();
      const taskId = result.task_id;
      if (taskId) {
        if (!background) setSyncMessage('Import started in background');
        return;
      }
      const lib = await reloadLibrary();
      const added = Math.max(0, lib.photos.length - before);
      const imported = Number(result.imported || 0);
      const errors = Number(result.errors || 0);
      const main = added > 0
        ? `${added.toLocaleString()} new photo${added === 1 ? '' : 's'} synced`
        : `${imported.toLocaleString()} photo${imported === 1 ? '' : 's'} checked`;
      if (!background || added > 0 || errors > 0) {
        setSyncMessage(errors ? `${main}; ${errors} error${errors === 1 ? '' : 's'}` : main);
      }
    } catch (e) {
      if (!background) {
        setSyncMessage(`Sync failed: ${e.message || String(e)}`);
      }
    } finally {
      syncRunningRef.current = false;
      if (!background) {
        setSyncing(false);
      }
    }
  }, [reloadLibrary]);

  aaUseEffect(() => {
    if (loading || loadError) return;
    const interval = setInterval(() => {
      handleSyncLibrary({ background: true });
    }, AUTO_SYNC_INTERVAL_MS);
    return () => clearInterval(interval);
  }, [handleSyncLibrary, loading, loadError]);

  // Loupe navigation
  const openIdx = openId ? filtered.findIndex(p => p.id === openId) : -1;
  const openLoupe = (id) => setOpenId(id);
  const closeLoupe = () => setOpenId(null);
  const prev = () => { if (openIdx > 0) setOpenId(filtered[openIdx - 1].id); };
  const next = () => { if (openIdx >= 0 && openIdx < filtered.length - 1) setOpenId(filtered[openIdx + 1].id); };

  // ── Render ─────────────────────────────────────────────────────────────────
  if (loading || loadError) return <LoadingScreen error={loadError} />;

  return (
    <div className="app">
      <Topbar
        search={search}
        setSearch={setSearch}
        view={view}
        setView={setView}
        mode={mode}
        setMode={setMode}
        onOpenAdmin={() => setAdminOpen(true)}
        onImport={() => setImportModalOpen(true)}
        onSync={handleSyncLibrary}
        syncing={syncing}
        syncMessage={syncMessage}
      />

      <Sidebar
        selected={selected}
        onSelect={setSelected}
        photos={photos}
        albumTree={albumTree}
        mode={mode}
        onCreateAlbum={() => setAlbumModalOpen(true)}
        onDropOnAlbum={handleDropOnAlbum}
      />

      <div className="main">
        <Crumbs
          title={crumbInfo.title}
          meta={`${filtered.length.toLocaleString()} photo${filtered.length === 1 ? '' : 's'}${crumbInfo.meta ? ' · ' + crumbInfo.meta : ''}`}
          mode={mode}
          filter={filter}
          setFilter={setFilter}
          density={tweaks.density}
          setDensity={(v) => setTweak('density', typeof v === 'function' ? v(tweaks.density) : v)}
          sortKey={sortKey}
          setSortKey={setSortKey}
        />
        <GridView
          photos={filtered}
          density={tweaks.density}
          view={view}
          options={{
            aspectPreserve: tweaks.aspectPreserve,
            showStars: tweaks.showStarsOnThumb,
            showFav: tweaks.showFavOnThumb,
          }}
          mode={mode}
          onOpen={openLoupe}
          selectedId={openId}
        />
      </div>

      <StatusBar status={status} photoCount={photos.length} mode={mode} />

      {openId && (
        <Loupe
          photos={filtered}
          currentIndex={Math.max(0, openIdx)}
          onClose={closeLoupe}
          onPrev={prev}
          onNext={next}
          onGoTo={(i) => setOpenId(filtered[i].id)}
          mode={mode}
          onSetRating={setRating}
          onSetFlag={setFlag}
          onToggleFav={toggleFav}
          albums={albums}
        />
      )}

      <Admin
        open={adminOpen}
        onClose={() => setAdminOpen(false)}
        photos={photos}
        status={status}
        setStatus={setStatus}
      />

      <NewAlbumModal
        open={albumModalOpen}
        onClose={() => setAlbumModalOpen(false)}
        onCreate={handleCreateAlbum}
      />

      <ImportModal
        open={importModalOpen}
        onClose={() => setImportModalOpen(false)}
        onDone={handleImportDone}
      />

      {tweaksOpen && (
        <TweaksPanel onClose={() => { setTweaksOpen(false); window.parent.postMessage({ type: '__edit_mode_dismissed' }, '*'); }} title="Tweaks">
          <TweakSection title="Display">
            <TweakSlider label="Thumbnail size" min={3} max={10} step={1} value={tweaks.density} onChange={(v) => setTweak('density', v)} />
            <TweakRadio label="Theme" options={[{ value: 'dark', label: 'Dark' }, { value: 'light', label: 'Light' }]} value={tweaks.theme} onChange={(v) => setTweak('theme', v)} />
          </TweakSection>
          <TweakSection title="Thumbnails">
            <TweakToggle label="Preserve aspect ratio" value={tweaks.aspectPreserve} onChange={(v) => setTweak('aspectPreserve', v)} />
            <TweakToggle label="Show star ratings" value={tweaks.showStarsOnThumb} onChange={(v) => setTweak('showStarsOnThumb', v)} />
            <TweakToggle label="Show favorite hearts" value={tweaks.showFavOnThumb} onChange={(v) => setTweak('showFavOnThumb', v)} />
          </TweakSection>
        </TweaksPanel>
      )}

    </div>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
