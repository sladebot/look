/* Look — shared UI primitives (sidebar, topbar, status bar) */

const { useState, useEffect, useRef, useMemo, useCallback } = React;

// === Inline icons (Lucide-style, 1.5px stroke) ===
const Icon = ({ d, size = 14, fill = "none", stroke = "currentColor", sw = 1.6 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill={fill} stroke={stroke} strokeWidth={sw} strokeLinecap="round" strokeLinejoin="round">
    {Array.isArray(d) ? d.map((p, i) => <path key={i} d={p} />) : <path d={d} />}
  </svg>
);

const icons = {
  search: "M21 21l-4.3-4.3 M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z",
  star: "M12 2l3.09 6.26L22 9.27l-5 4.87L18.18 22 12 18.27 5.82 22 7 14.14 2 9.27l6.91-1.01z",
  heart: "M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z",
  flag: "M4 22v-7 M4 4h12l-2 4 2 4H4",
  folder: "M3 5a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z",
  folderOpen: "M2 7a2 2 0 0 1 2-2h4l2 2h10a2 2 0 0 1 2 2v0H4 M2 9l1.5 9.5A2 2 0 0 0 5.5 20h13a2 2 0 0 0 2-1.5L22 9z",
  photo: "M3 5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z M21 15l-5-5L5 21",
  clock: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M12 6v6l4 2",
  trash: "M3 6h18 M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2 M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6",
  add: "M12 5v14 M5 12h14",
  grid: "M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z",
  rows: "M3 5h18 M3 12h18 M3 19h18",
  map: "M9 2L3 5v17l6-3 6 3 6-3V2l-6 3z M9 2v17 M15 5v17",
  settings: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
  chevR: "M9 18l6-6-6-6",
  chevL: "M15 18l-6-6 6-6",
  chevD: "M6 9l6 6 6-6",
  close: "M18 6L6 18 M6 6l12 12",
  download: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M7 10l5 5 5-5 M12 15V3",
  info: "M12 22a10 10 0 1 0 0-20 10 10 0 0 0 0 20z M12 16v-4 M12 8h.01",
  share: "M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8 M16 6l-4-4-4 4 M12 2v13",
  upload: "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4 M17 8l-5-5-5 5 M12 3v12",
  hardDrive: "M22 12H2 M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z M6 16h.01 M10 16h.01",
  server: "M5 4h14a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z M5 13h14a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-3a2 2 0 0 1 2-2z M7 7h.01 M7 16h.01",
  refresh: "M3 12a9 9 0 1 0 3-6.7L3 8 M3 3v5h5",
  cpu: "M9 2v3 M15 2v3 M9 19v3 M15 19v3 M2 9h3 M2 15h3 M19 9h3 M19 15h3 M5 5h14a0 0 0 0 1 0 0v14a0 0 0 0 1 0 0H5a0 0 0 0 1 0 0V5a0 0 0 0 1 0 0z M9 9h6v6H9z",
  link: "M10 13a5 5 0 0 0 7.07 0l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.72 M14 11a5 5 0 0 0-7.07 0l-3 3a5 5 0 0 0 7.07 7.07l1.72-1.72",
  users: "M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2 M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8z M23 21v-2a4 4 0 0 0-3-3.87",
  laptop: "M3 18l1-1V5a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12l1 1 M3 18h18 M3 18v1a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-1",
  phone: "M5 2h14a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z M12 18h.01",
};

function IconBtn({ d, label, active, onClick, disabled }) {
  return (
    <button className={"icon-btn" + (active ? " active" : "")} title={label} aria-label={label} onClick={onClick} disabled={disabled}>
      <Icon d={d} size={15} />
    </button>
  );
}

// === Topbar ===
function Topbar({ search, setSearch, view, setView, mode, setMode, onOpenAdmin, onImport, onSync, syncing, syncMessage }) {
  const inputRef = useRef(null);
  useEffect(() => {
    function onKey(e) {
      if ((e.key === '/' || (e.key === 'k' && (e.metaKey || e.ctrlKey))) && document.activeElement?.tagName !== 'INPUT') {
        e.preventDefault();
        inputRef.current?.focus();
      }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, []);

  return (
    <div className="topbar">
      <div className="brand">
        <span className="brand-dot" />
        <span className="brand-mark">Look</span>
        <span className="brand-sub">· studio.taila3f2b.ts.net</span>
      </div>

      <div className="search">
        <Icon d={icons.search} size={13} />
        <input
          ref={inputRef}
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder={mode === 'pro' ? "Search by camera, lens, album, date…" : "Search photos…"}
        />
        <span className="search-kbd">⌘K</span>
      </div>

      <div className="topbar-spacer" />

      {mode === 'pro' && (
        <div className="seg" role="tablist" aria-label="View">
          <button className={"seg-btn" + (view === 'grid' ? ' active' : '')} onClick={() => setView('grid')}>
            <Icon d={icons.grid} size={12} /> Grid
          </button>
          <button className={"seg-btn" + (view === 'rows' ? ' active' : '')} onClick={() => setView('rows')}>
            <Icon d={icons.rows} size={12} /> Rows
          </button>
        </div>
      )}

      <div className="seg mode-toggle" title="View mode">
        <button className={"seg-btn" + (mode === 'simple' ? ' active' : '')} onClick={() => setMode('simple')}>Simple</button>
        <button className={"seg-btn" + (mode === 'pro' ? ' active' : '')} onClick={() => setMode('pro')}>Pro</button>
      </div>

      <IconBtn
        d={icons.refresh}
        label={syncMessage || (syncing ? "Syncing photos" : "Refresh library")}
        onClick={onSync}
        disabled={syncing}
        active={syncing}
      />
      <IconBtn d={icons.upload} label="Import photos" onClick={onImport} />
      {mode === 'pro' && <IconBtn d={icons.server} label="Library admin" onClick={onOpenAdmin} />}

      <div className="avatar" title="You">JS</div>
    </div>
  );
}

// === Sidebar ===
function SideItem({ id, label, iconD, count, selected, onSelect, swatch, indent, draggable, onDragOver, onDrop, droppable }) {
  const [over, setOver] = useState(false);
  return (
    <div
      className={"side-item" + (selected ? " selected" : "") + (over ? " drag-over" : "")}
      style={{ paddingLeft: 10 + (indent || 0) * 14 }}
      onClick={() => onSelect(id)}
      onDragOver={droppable ? (e) => { e.preventDefault(); setOver(true); } : undefined}
      onDragLeave={droppable ? () => setOver(false) : undefined}
      onDrop={droppable ? (e) => { setOver(false); onDrop?.(e); } : undefined}
    >
      {swatch
        ? <span className="side-album-swatch" style={{ background: swatch }} />
        : <span className="side-item-icon"><Icon d={iconD} size={13} /></span>}
      <span className="side-item-label">{label}</span>
      {count != null && <span className="side-count">{count.toLocaleString()}</span>}
    </div>
  );
}

function Sidebar({ selected, onSelect, photos, albumTree, mode, onCreateAlbum, onDropOnAlbum }) {
  const counts = useMemo(() => {
    const c = { all: photos.length, recent: 0, favs: 0, picks: 0 };
    const cutoff = new Date(); cutoff.setDate(cutoff.getDate() - 30);
    photos.forEach(p => {
      if (p.date >= cutoff) c.recent++;
      if (p.favorite) c.favs++;
      if (p.flag === 'pick') c.picks++;
    });
    return c;
  }, [photos]);

  // by-date: year > month nested
  const byDate = useMemo(() => {
    const years = new Map();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    photos.forEach(p => {
      const y = p.date.getFullYear();
      const m = p.date.getMonth();
      if (!years.has(y)) years.set(y, { year: y, count: 0, months: new Map() });
      const yr = years.get(y);
      yr.count++;
      const mk = `${y}-${m}`;
      if (!yr.months.has(mk)) yr.months.set(mk, { key: mk, label: months[m], year: y, month: m, count: 0 });
      yr.months.get(mk).count++;
    });
    return [...years.values()]
      .sort((a, b) => b.year - a.year)
      .map(y => ({ ...y, months: [...y.months.values()].sort((a, b) => b.month - a.month) }));
  }, [photos]);

  const [openFolders, setOpenFolders] = useState(() => new Set(['travel']));
  const [openYears, setOpenYears] = useState(() => new Set([2026]));
  const toggleFolder = (id) => setOpenFolders(s => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const toggleYear = (y) => setOpenYears(s => { const n = new Set(s); n.has(y) ? n.delete(y) : n.add(y); return n; });

  return (
    <div className="sidebar">
      <div className="side-section">
        <SideItem id="all" label="All Photos" iconD={icons.photo} count={counts.all} selected={selected === 'all'} onSelect={onSelect} />
        <SideItem id="recent" label="Recently Added" iconD={icons.clock} count={counts.recent} selected={selected === 'recent'} onSelect={onSelect} />
        <SideItem id="favs" label="Favorites" iconD={icons.heart} count={counts.favs} selected={selected === 'favs'} onSelect={onSelect} />
        {mode === 'pro' && (
          <SideItem id="picks" label="Picks" iconD={icons.flag} count={counts.picks} selected={selected === 'picks'} onSelect={onSelect} />
        )}
      </div>

      <div className="side-section">
        <div className="side-label">
          Albums
          <button className="side-add" title="New album" onClick={onCreateAlbum}>
            <Icon d={icons.add} size={12} />
          </button>
        </div>
        {albumTree.map(node => {
          if (node.kind === 'folder') {
            const open = openFolders.has(node.id);
            return (
              <React.Fragment key={node.id}>
                <div className="side-item" onClick={() => toggleFolder(node.id)}>
                  <span className="side-item-icon" style={{ transform: `rotate(${open ? 0 : -90}deg)`, transition: 'transform 120ms ease' }}>
                    <Icon d={icons.chevD} size={11} />
                  </span>
                  <span className="side-item-label" style={{ fontWeight: 500 }}>{node.name}</span>
                  <span className="side-count">{node.children.reduce((s, c) => s + c.count, 0).toLocaleString()}</span>
                </div>
                {open && node.children.map(c => (
                  <SideItem
                    key={c.id}
                    id={`album:${c.id}`}
                    label={c.name}
                    swatch={c.color}
                    count={c.count}
                    selected={selected === `album:${c.id}`}
                    onSelect={onSelect}
                    indent={1}
                    droppable
                    onDrop={(e) => onDropOnAlbum?.(c.id, e)}
                  />
                ))}
              </React.Fragment>
            );
          }
          return (
            <SideItem
              key={node.id}
              id={`album:${node.id}`}
              label={node.name}
              swatch={node.color}
              count={node.count}
              selected={selected === `album:${node.id}`}
              onSelect={onSelect}
              droppable
              onDrop={(e) => onDropOnAlbum?.(node.id, e)}
            />
          );
        })}
      </div>

      <div className="side-section">
        <div className="side-label">By Date</div>
        {byDate.map(y => {
          const open = openYears.has(y.year);
          return (
            <React.Fragment key={y.year}>
              <div className="side-item" onClick={() => toggleYear(y.year)}>
                <span className="side-item-icon" style={{ transform: `rotate(${open ? 0 : -90}deg)`, transition: 'transform 120ms ease' }}>
                  <Icon d={icons.chevD} size={11} />
                </span>
                <span className="side-item-label" style={{ fontWeight: 500 }}>{y.year}</span>
                <span className="side-count">{y.count.toLocaleString()}</span>
              </div>
              {open && y.months.map(m => (
                <SideItem
                  key={m.key}
                  id={`date:${m.key}`}
                  label={m.label}
                  iconD={icons.clock}
                  count={m.count}
                  selected={selected === `date:${m.key}`}
                  onSelect={onSelect}
                  indent={1}
                />
              ))}
            </React.Fragment>
          );
        })}
      </div>
    </div>
  );
}

// === Crumb / view header ===
function Crumbs({ title, meta, mode, filter, setFilter, density, setDensity, sortKey, setSortKey }) {
  return (
    <div className="crumbs">
      <div className="crumbs-title">{title}</div>
      <div className="crumbs-meta">{meta}</div>
      <div className="crumbs-spacer" />

      {mode === 'pro' && (
        <>
          <div className="filter-bar">
            <Chip active={filter.flagged === 'pick'} onClick={() => setFilter(f => ({ ...f, flagged: f.flagged === 'pick' ? null : 'pick' }))}>
              <span className="chip-dot" style={{ background: 'var(--pick)' }} /> Picks
            </Chip>
            <Chip active={filter.flagged === 'reject'} onClick={() => setFilter(f => ({ ...f, flagged: f.flagged === 'reject' ? null : 'reject' }))}>
              <span className="chip-dot" style={{ background: 'var(--reject)' }} /> Rejects
            </Chip>
            <Chip active={filter.minRating >= 4} onClick={() => setFilter(f => ({ ...f, minRating: f.minRating >= 4 ? 0 : 4 }))}>
              ★★★★+
            </Chip>
            <Chip active={!!filter.fav} onClick={() => setFilter(f => ({ ...f, fav: !f.fav }))}>
              <Icon d={icons.heart} size={10} /> Favorites
            </Chip>
          </div>

          <div style={{ width: 1, height: 18, background: 'var(--hairline)', margin: '0 4px' }} />

          <div className="seg" title="Sort">
            <button className={"seg-btn" + (sortKey === 'date' ? ' active' : '')} onClick={() => setSortKey('date')}>Newest</button>
            <button className={"seg-btn" + (sortKey === 'rating' ? ' active' : '')} onClick={() => setSortKey('rating')}>Top-rated</button>
          </div>
        </>
      )}

      <div className="seg" title="Thumbnail size">
        <button className="seg-btn" onClick={() => setDensity(d => Math.max(3, d - 1))}>−</button>
        <button className="seg-btn active" style={{ minWidth: 24, justifyContent: 'center' }}>{density}</button>
        <button className="seg-btn" onClick={() => setDensity(d => Math.min(10, d + 1))}>+</button>
      </div>
    </div>
  );
}

function Chip({ active, onClick, children }) {
  return (
    <button className={"chip" + (active ? " active" : "")} onClick={onClick}>{children}</button>
  );
}

// === Status bar ===
function StatusBar({ status, photoCount, mode }) {
  const pct = Math.round((status.previewsDone / status.previewsTotal) * 100);
  return (
    <div className="statusbar">
      <span className="status-item">
        <span className="dot dot-ok" />
        {mode === 'pro' ? 'Tailscale · studio.taila3f2b.ts.net · 100.74.12.4' : 'Connected to mac-studio'}
      </span>
      {mode === 'pro' && (
        <span className="status-item">
          <Icon d={icons.hardDrive} size={11} /> {status.libraryTB.toFixed(2)} TB · {photoCount.toLocaleString()} photos indexed
        </span>
      )}
      {status.previewsDone < status.previewsTotal ? (
        <span className="preview-progress">
          <span className="dot dot-busy" />
          Generating JPEG previews
          <span className="progress-track"><span className="progress-fill" style={{ width: pct + '%' }} /></span>
          <span>{status.previewsDone.toLocaleString()} / {status.previewsTotal.toLocaleString()}</span>
        </span>
      ) : (
        <span className="status-item">
          <span className="dot dot-ok" /> Previews up to date
        </span>
      )}
      <span className="status-spacer" />
      {mode === 'pro' && <span className="status-item">RTT 14ms · 88 MB/s</span>}
      <span className="status-item">v0.4.2</span>
    </div>
  );
}

// === Import Modal ============================================================

function ImportModal({ open, onClose, onDone }) {
  const [path, setPath] = useState('');
  const [phase, setPhase] = useState('idle'); // idle | running | done | error
  const [result, setResult] = useState(null);
  const inputRef = useRef(null);

  useEffect(() => {
    if (open) { setPhase('idle'); setResult(null); setPath(''); }
  }, [open]);

  useEffect(() => {
    if (open && phase === 'idle') setTimeout(() => inputRef.current?.focus(), 80);
  }, [open, phase]);

  if (!open) return null;

  const handleImport = async () => {
    const trimmed = path.trim();
    if (!trimmed) return;
    setPhase('running');
    setResult(null);
    try {
      const url = trimmed
        ? `/api/import?path=${encodeURIComponent(trimmed)}`
        : '/api/import';
      const res = await fetch(url, { method: 'POST' });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail || 'Import failed');
      setResult(data);
      setPhase('done');
      if ((data.imported || 0) > 0) onDone?.();
    } catch (e) {
      setResult({ error: e.message });
      setPhase('error');
    }
  };

  const steps = [
    { label: 'Scan folder for photos',           done: phase !== 'idle' },
    { label: 'Convert ARW/RAW → JPEG',           done: phase === 'done' || phase === 'error' },
    { label: 'Generate thumbnails',              done: phase === 'done' || phase === 'error' },
    { label: 'Add to library',                   done: phase === 'done' },
  ];

  return (
    <div className="modal-shade" onClick={e => { if (e.target.classList.contains('modal-shade')) onClose(); }}>
      <div className="modal" style={{ width: 500, height: 'auto' }}>

        <div className="modal-head">
          <div>
            <div className="modal-title">Import photos</div>
            <div className="modal-sub">Scan a folder · convert RAW · generate thumbnails</div>
          </div>
          <button className="icon-btn" onClick={onClose} disabled={phase === 'running'}>
            <Icon d={icons.close} size={15} />
          </button>
        </div>

        <div style={{ padding: '18px 18px 0' }}>
          <label style={{ fontSize: 11.5, color: 'var(--text-faint)', display: 'block', marginBottom: 6 }}>
            Folder path
          </label>
          <input
            ref={inputRef}
            value={path}
            onChange={e => setPath(e.target.value)}
            placeholder="/Users/jarvis/Pictures/RAW"
            disabled={phase === 'running'}
            onKeyDown={e => { if (e.key === 'Enter') handleImport(); }}
            style={{
              width: '100%', padding: '8px 10px', fontSize: 13,
              background: 'var(--bg)', borderRadius: 6, color: 'var(--text)',
              boxShadow: 'inset 0 0 0 1px var(--hairline-bright)',
              opacity: phase === 'running' ? 0.5 : 1,
            }}
          />
          <div style={{ fontSize: 11, color: 'var(--text-faint)', marginTop: 5 }}>
            Leave blank to scan all active watch directories.
          </div>
        </div>

        {/* Steps */}
        <div style={{ padding: '16px 18px 0' }}>
          {steps.map((s, i) => {
            const active = phase === 'running' && !s.done;
            const waiting = phase === 'idle' || (phase === 'running' && i > steps.findIndex(x => !x.done));
            return (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '5px 0' }}>
                <div style={{
                  width: 18, height: 18, borderRadius: '50%', flexShrink: 0,
                  display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10,
                  background: s.done ? 'var(--pick)' : active ? 'var(--accent)' : 'var(--panel)',
                  boxShadow: active ? '0 0 8px rgba(74,158,255,0.5)' : 'none',
                  transition: 'background 300ms ease',
                }}>
                  {s.done
                    ? <svg width="10" height="10" viewBox="0 0 12 12"><path d="M2 6l3 3 5-5" stroke="#0a1f10" strokeWidth="1.8" fill="none" strokeLinecap="round"/></svg>
                    : active
                    ? <span style={{ width: 6, height: 6, borderRadius: '50%', background: '#fff', animation: 'pulse 1.2s ease-in-out infinite', display: 'block' }} />
                    : null}
                </div>
                <span style={{
                  fontSize: 12.5,
                  color: s.done ? 'var(--text)' : active ? 'var(--text)' : 'var(--text-faint)',
                  transition: 'color 300ms ease',
                }}>
                  {s.label}
                </span>
              </div>
            );
          })}
        </div>

        {/* Result */}
        {phase === 'done' && result && (
          <div style={{ margin: '16px 18px 0', padding: '12px 14px', background: 'rgba(95,201,122,0.1)', borderRadius: 8, boxShadow: 'inset 0 0 0 1px rgba(95,201,122,0.3)' }}>
            <div style={{ fontSize: 13, fontWeight: 600, color: 'var(--pick)', marginBottom: 4 }}>
              Import complete
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-dim)', fontFamily: 'var(--font-mono)' }}>
              {result.imported} photo{result.imported !== 1 ? 's' : ''} imported
              {result.errors > 0 && <span style={{ color: 'var(--reject)', marginLeft: 10 }}>· {result.errors} errors</span>}
            </div>
            {result.error_details?.length > 0 && (
              <ul style={{ margin: '8px 0 0', padding: '0 0 0 14px', fontSize: 11, color: 'var(--reject)', fontFamily: 'var(--font-mono)' }}>
                {result.error_details.map((e, i) => <li key={i}>{e}</li>)}
              </ul>
            )}
          </div>
        )}

        {phase === 'error' && result?.error && (
          <div style={{ margin: '16px 18px 0', padding: '12px 14px', background: 'rgba(217,106,106,0.1)', borderRadius: 8, boxShadow: 'inset 0 0 0 1px rgba(217,106,106,0.3)' }}>
            <div style={{ fontSize: 12, color: 'var(--reject)', fontFamily: 'var(--font-mono)' }}>{result.error}</div>
          </div>
        )}

        <div className="modal-foot" style={{ marginTop: 18 }}>
          <button className="secondary-btn" onClick={onClose} disabled={phase === 'running'}>
            {phase === 'done' ? 'Close' : 'Cancel'}
          </button>
          <div className="status-spacer" />
          <button
            className="primary-btn"
            onClick={handleImport}
            disabled={phase === 'running' || phase === 'done'}
          >
            {phase === 'running'
              ? <><span style={{ width: 10, height: 10, borderRadius: '50%', border: '1.5px solid rgba(255,255,255,0.3)', borderTopColor: '#fff', display: 'inline-block', animation: 'spin 0.7s linear infinite' }} /> Importing…</>
              : <><Icon d={icons.upload} size={13} /> Import</>}
          </button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { Icon, IconBtn, Topbar, Sidebar, Crumbs, Chip, StatusBar, ImportModal, icons });
