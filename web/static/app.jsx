/* Look — main app, wired to local-photos-server FastAPI backend */

const {
  useState: aaUseState,
  useEffect: aaUseEffect,
  useMemo: aaUseMemo,
  useCallback: aaUseCallback,
} = React;

const TWEAKS_DEFAULTS = /*EDITMODE-BEGIN*/{
  "density": 6,
  "theme": "dark",
  "aspectPreserve": false,
  "showStarsOnThumb": true,
  "showFavOnThumb": true
}/*EDITMODE-END*/;

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
  const [tweaks, setTweaks] = aaUseState(TWEAKS_DEFAULTS);
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

  // Simulated preview-gen progress (based on real photo count once loaded)
  const [status, setStatus] = aaUseState({ previewsDone: 0, previewsTotal: 1, libraryTB: 0 });

  // ── Load library from API ──────────────────────────────────────────────────
  aaUseEffect(() => {
    async function init() {
      try {
        const lib = await Look.initLibrary();
        setPhotos(lib.photos);
        setAlbums(lib.albums);
        setAlbumTree(lib.albumTree);

        // Seed simulated preview progress from real photo count
        const done = lib.photos.filter(p => p._api?.has_thumbnail).length;
        setStatus({
          previewsDone: done,
          previewsTotal: lib.photos.length,
          libraryTB: 0,
        });
      } catch (e) {
        setLoadError(e.message || String(e));
      } finally {
        setLoading(false);
      }
    }
    init();
  }, []);

  // Animate preview progress bar while generating
  aaUseEffect(() => {
    if (loading) return;
    const t = setInterval(() => {
      setStatus(s => {
        if (s.previewsDone >= s.previewsTotal) return s;
        return { ...s, previewsDone: Math.min(s.previewsTotal, s.previewsDone + Math.floor(Math.random() * 5 + 1)) };
      });
    }, 1200);
    return () => clearInterval(t);
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
  const setRating = (id, v) => setPhotos(ps => ps.map(p => p.id === id ? { ...p, rating: v } : p));
  const setFlag   = (id, f) => setPhotos(ps => ps.map(p => p.id === id ? { ...p, flag: f }   : p));
  const toggleFav = (id)    => setPhotos(ps => ps.map(p => p.id === id ? { ...p, favorite: !p.favorite } : p));

  const handleDropOnAlbum = (albumId, e) => {
    const id = e.dataTransfer.getData('text/photo-id');
    if (!id) return;
    // Optimistic UI update
    const album = albums.find(a => a.id === albumId);
    setPhotos(ps => ps.map(p => p.id === id ? { ...p, album: albumId, albumName: album?.name || '' } : p));
    // Persist to API
    Look.apiAddPhotoToAlbum(albumId, id).catch(() => {});
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
    // Reload library after a successful import
    const lib = await Look.initLibrary();
    setPhotos(lib.photos);
    setAlbums(lib.albums);
    setAlbumTree(lib.albumTree);
  };

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
