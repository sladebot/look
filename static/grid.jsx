/* Look — grid view + thumbnails (with drag-to-album) */

const { useState: gUseState, useEffect: gUseEffect, useMemo: gUseMemo } = React;

function Thumb({ photo, selected, onClick, aspectPreserve, showStars, showFav, mode, onDragStart }) {
  const [loaded, setLoaded] = gUseState(false);
  return (
    <div
      className={"thumb" + (selected ? " selected" : "") + (aspectPreserve ? " aspect-preserve" : "")}
      style={aspectPreserve ? { aspectRatio: `${photo.ratio[0]} / ${photo.ratio[1]}` } : null}
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={e => { if (e.key === 'Enter' || e.key === ' ') onClick(); }}
      draggable
      onDragStart={(e) => {
        e.dataTransfer.setData('text/photo-id', photo.id);
        e.dataTransfer.effectAllowed = 'copy';
        onDragStart?.(photo.id);
      }}
    >
      {!loaded && <div className="thumb-skeleton" />}
      <img
        src={photo.thumb}
        loading="lazy"
        alt=""
        className={loaded ? '' : 'loading'}
        onLoad={() => setLoaded(true)}
      />

      <div className="thumb-overlay">
        <div className="thumb-top">
          <div style={{ display: 'flex', gap: 4 }}>
            {mode === 'pro' && photo.flag === 'pick' && <span className="badge badge-pick">PICK</span>}
            {mode === 'pro' && photo.flag === 'reject' && <span className="badge badge-reject">✗</span>}
          </div>
          <div />
        </div>
        <div className="thumb-bot">
          <div>
            {mode === 'pro' && showStars && photo.rating > 0 && (
              <span className="thumb-stars">{'★'.repeat(photo.rating)}<span style={{ opacity: 0.35 }}>{'★'.repeat(5 - photo.rating)}</span></span>
            )}
          </div>
          <div>
            {showFav && photo.favorite && (
              <span className="thumb-fav"><Icon d={icons.heart} size={12} fill="currentColor" sw={0} /></span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

function groupByDay(photos) {
  const out = [];
  let cur = null;
  for (const p of photos) {
    const label = Look.dateLabel(p.date);
    if (!cur || cur.label !== label) {
      cur = { label, photos: [], albums: new Set() };
      out.push(cur);
    }
    cur.photos.push(p);
    cur.albums.add(p.albumName);
  }
  return out;
}

function GridView({ photos, density, view, options, mode, onOpen, selectedId, onDragStart }) {
  const cols = density;
  const gap = density >= 7 ? 2 : density >= 5 ? 4 : 6;
  const groups = gUseMemo(() => groupByDay(photos), [photos]);

  if (photos.length === 0) {
    return (
      <div className="grid-scroll">
        <div style={{ padding: 64, textAlign: 'center', color: 'var(--text-faint)' }}>
          <div style={{ fontSize: 36, marginBottom: 12, opacity: 0.4 }}>—</div>
          No photos match these filters.
        </div>
      </div>
    );
  }

  return (
    <div className="grid-scroll">
      {groups.map(g => (
        <div key={g.label}>
          <div className="grid-section-header">
            <span className="grid-section-title">{g.label}</span>
            <span className="grid-section-sub">
              {g.photos.length} photo{g.photos.length === 1 ? '' : 's'}
              {mode === 'pro' && ' · ' + [...g.albums].join(' · ')}
            </span>
          </div>
          <div className="grid" style={{ '--cols': cols, '--gap': gap + 'px' }}>
            {g.photos.map(p => (
              <Thumb
                key={p.id}
                photo={p}
                selected={selectedId === p.id}
                aspectPreserve={view === 'rows' || options.aspectPreserve}
                showStars={options.showStars}
                showFav={options.showFav}
                mode={mode}
                onClick={() => onOpen(p.id)}
                onDragStart={onDragStart}
              />
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

window.GridView = GridView;
window.Thumb = Thumb;
