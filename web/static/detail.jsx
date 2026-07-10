/* Look — detail / loupe view */

const { useState: dUseState, useEffect: dUseEffect, useMemo: dUseMemo, useRef: dUseRef } = React;

function Loupe({ photos, currentIndex, onClose, onPrev, onNext, onGoTo, mode, onSetRating, onSetFlag, onToggleFav, albums }) {
  const photo = photos[currentIndex];
  const [tab, setTab] = dUseState('info');
  const stripRef = dUseRef(null);
  const [fullLoaded, setFullLoaded] = dUseState(false);

  dUseEffect(() => {
    function onKey(e) {
      if (e.target?.tagName === 'INPUT') return;
      if (e.key === 'Escape') { onClose(); }
      else if (e.key === 'ArrowLeft') { onPrev(); }
      else if (e.key === 'ArrowRight') { onNext(); }
      else if (e.key >= '0' && e.key <= '5' && mode === 'pro') { onSetRating(photo.id, +e.key); }
      else if (e.key.toLowerCase() === 'p' && mode === 'pro') { onSetFlag(photo.id, photo.flag === 'pick' ? null : 'pick'); }
      else if (e.key.toLowerCase() === 'x' && mode === 'pro') { onSetFlag(photo.id, photo.flag === 'reject' ? null : 'reject'); }
      else if (e.key.toLowerCase() === 'f') { onToggleFav(photo.id); }
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [photo, mode, onClose, onPrev, onNext, onSetRating, onSetFlag, onToggleFav]);

  dUseEffect(() => {
    setFullLoaded(false);
    // scroll filmstrip to keep current visible
    const el = stripRef.current?.querySelector('.strip-thumb.current');
    el?.scrollIntoView({ inline: 'center', block: 'nearest' });
  }, [currentIndex]);

  if (!photo) return null;

  return (
    <div className="loupe" onClick={(e) => { if (e.target.classList.contains('loupe-stage')) onClose(); }}>
      <div className="loupe-top">
        <button className="icon-btn" onClick={onClose} title="Close (Esc)">
          <Icon d={icons.close} size={15} />
        </button>
        <div className="loupe-id">{photo.filename}</div>
        <div className="loupe-id-sub">· {Look.dateLabel(photo.date)} · {Look.timeLabel(photo.date)} · {photo.albumName}</div>
        <div className="crumbs-spacer" />
        <div className="loupe-id-sub">{currentIndex + 1} / {photos.length}</div>
        <button className="icon-btn" onClick={() => onToggleFav(photo.id)} title="Favorite (F)">
          <Icon d={icons.heart} size={15} fill={photo.favorite ? '#e85a7a' : 'none'} stroke={photo.favorite ? '#e85a7a' : 'currentColor'} />
        </button>
        <button className="icon-btn" title="Share">
          <Icon d={icons.share} size={14} />
        </button>
        <button className="icon-btn" title="Info" onClick={() => setTab('info')}>
          <Icon d={icons.info} size={15} />
        </button>
      </div>

      <div className="loupe-stage">
        {!fullLoaded && <div className="thumb-skeleton" style={{ width: 600, height: 400, maxWidth: '90%', maxHeight: '90%', borderRadius: 4 }} />}
        <img
          src={photo.full}
          alt=""
          style={{ display: fullLoaded ? 'block' : 'none' }}
          onLoad={() => setFullLoaded(true)}
          onClick={(e) => e.stopPropagation()}
        />
        <button className="loupe-nav prev" onClick={onPrev} title="Previous (←)">
          <Icon d={icons.chevL} size={18} />
        </button>
        <button className="loupe-nav next" onClick={onNext} title="Next (→)">
          <Icon d={icons.chevR} size={18} />
        </button>
      </div>

      <div className="loupe-strip" ref={stripRef}>
        {photos.map((p, i) => (
          <div
            key={p.id}
            className={"strip-thumb" + (i === currentIndex ? ' current' : '')}
            onClick={() => onGoTo(i)}
            title={p.filename}
          >
            <img src={p.thumb} alt="" loading="lazy" />
          </div>
        ))}
      </div>

      <aside className="loupe-side">
        <div className="side-tabs">
          <button className={"side-tab" + (tab === 'info' ? ' active' : '')} onClick={() => setTab('info')}>Info</button>
          {mode === 'pro' && <button className={"side-tab" + (tab === 'edit' ? ' active' : '')} onClick={() => setTab('edit')}>Edit</button>}
          <button className={"side-tab" + (tab === 'map' ? ' active' : '')} onClick={() => setTab('map')}>Map</button>
        </div>

        {tab === 'info' && <InfoPanel photo={photo} mode={mode} onSetRating={onSetRating} onSetFlag={onSetFlag} albums={albums} />}
        {tab === 'edit' && <EditPanel photo={photo} />}
        {tab === 'map' && <MapPanel photo={photo} />}
      </aside>
    </div>
  );
}

function StarRating({ value, onChange }) {
  const [hover, setHover] = dUseState(0);
  return (
    <div className="rating-stars" onMouseLeave={() => setHover(0)}>
      {[1,2,3,4,5].map(n => (
        <button
          key={n}
          className={(hover ? n <= hover : n <= value) ? 'on' : ''}
          onMouseEnter={() => setHover(n)}
          onClick={() => onChange(value === n ? 0 : n)}
          title={`${n} star${n > 1 ? 's' : ''}`}
        >★</button>
      ))}
    </div>
  );
}

function InfoPanel({ photo, mode, onSetRating, onSetFlag, albums }) {
  const album = albums.find(a => a.id === photo.album);
  return (
    <div className="meta">
      {mode === 'pro' && (
        <div className="meta-block">
          <div className="meta-h">Rating & Flag</div>
          <div className="meta-row">
            <span className="k">Stars</span>
            <StarRating value={photo.rating} onChange={(v) => onSetRating(photo.id, v)} />
          </div>
          <div className="flag-row">
            <button
              className={"flag-btn" + (photo.flag === 'pick' ? ' on-pick' : '')}
              onClick={() => onSetFlag(photo.id, photo.flag === 'pick' ? null : 'pick')}
            >
              <span style={{ width: 8, height: 8, background: 'var(--pick)', borderRadius: 2, display: 'inline-block' }} />
              Pick
            </button>
            <button
              className={"flag-btn" + (photo.flag === 'reject' ? ' on-reject' : '')}
              onClick={() => onSetFlag(photo.id, photo.flag === 'reject' ? null : 'reject')}
            >
              <span style={{ width: 8, height: 8, background: 'var(--reject)', borderRadius: 2, display: 'inline-block' }} />
              Reject
            </button>
          </div>
        </div>
      )}

      <div className="meta-block">
        <div className="meta-h">Capture</div>
        <div className="meta-row"><span className="k">Camera</span><span className="v">{photo.camera}</span></div>
        <div className="meta-row"><span className="k">Lens</span><span className="v">{photo.lens}</span></div>
        {mode === 'pro' && (
          <>
            <div className="meta-row"><span className="k">Focal length</span><span className="v">{photo.focal} mm</span></div>
            <div className="meta-row"><span className="k">Aperture</span><span className="v">ƒ/{photo.aperture}</span></div>
            <div className="meta-row"><span className="k">Shutter</span><span className="v">{photo.shutter} s</span></div>
            <div className="meta-row"><span className="k">ISO</span><span className="v">{photo.iso}</span></div>
          </>
        )}
        <div className="meta-row"><span className="k">When</span><span className="v">{Look.dateLabel(photo.date)} · {Look.timeLabel(photo.date)}</span></div>
        <div className="meta-row"><span className="k">Where</span><span className="v">{photo.location}</span></div>
      </div>

      <div className="meta-block">
        <div className="meta-h">File</div>
        <div className="meta-row"><span className="k">Album</span><span className="v">{album?.name || photo.albumName}</span></div>
        <div className="meta-row"><span className="k">Dimensions</span><span className="v">{photo.pixelW} × {photo.pixelH}</span></div>
        <div className="meta-row"><span className="k">Size</span><span className="v">{photo.sizeMB} MB</span></div>
        {photo.raw && <div className="meta-row"><span className="k">Original</span><span className="v">{photo.rawFilename}</span></div>}
      </div>

      <div className="meta-block">
        <a className="dl-btn" href={`/api/download/jpeg/${photo.id}`}>
          <Icon d={icons.download} size={13} />
          Download JPG
          {!photo.raw && (
            <span style={{ marginLeft: 'auto', fontFamily: 'var(--font-mono)', fontSize: 10, color: 'rgba(255,255,255,0.6)' }}>
              {photo.sizeMB} MB
            </span>
          )}
        </a>
        {photo.raw && (
          <a className="dl-btn secondary-download" href={`/api/download/raw/${photo.id}`} style={{ marginTop: 8 }}>
            <Icon d={icons.download} size={13} />
            Download RAW
            <span style={{ marginLeft: 'auto', fontFamily: 'var(--font-mono)', fontSize: 10, color: 'rgba(255,255,255,0.6)' }}>
              {photo.sizeMB} MB
            </span>
          </a>
        )}
        <div style={{ fontSize: 10.5, color: 'var(--text-faint)', marginTop: 6, lineHeight: 1.5 }}>
          Streams over Tailscale from <span style={{ fontFamily: 'var(--font-mono)' }}>mac-studio</span>.
          JPEG previews are generated locally for fast browsing.
        </div>
      </div>
    </div>
  );
}

function EditPanel({ photo }) {
  const [vals, setVals] = dUseState({
    exposure: 0, contrast: 0, highlights: 0, shadows: 0, whites: 0, blacks: 0,
    temp: 0, tint: 0, vibrance: 0, saturation: 0,
  });
  const slider = (key, label, min = -100, max = 100) => (
    <div className="edit-slider" key={key}>
      <div className="lbl">{label}</div>
      <input type="range" min={min} max={max} value={vals[key]} onChange={e => setVals(v => ({ ...v, [key]: +e.target.value }))} />
      <div className="val">{vals[key] > 0 ? '+' + vals[key] : vals[key]}</div>
    </div>
  );

  return (
    <div className="meta">
      <div className="meta-block">
        <div className="meta-h">Light</div>
        {slider('exposure', 'Exposure', -5, 5)}
        {slider('contrast', 'Contrast')}
        {slider('highlights', 'Highlights')}
        {slider('shadows', 'Shadows')}
        {slider('whites', 'Whites')}
        {slider('blacks', 'Blacks')}
      </div>
      <div className="meta-block">
        <div className="meta-h">Color</div>
        {slider('temp', 'Temperature')}
        {slider('tint', 'Tint')}
        {slider('vibrance', 'Vibrance')}
        {slider('saturation', 'Saturation')}
      </div>
      <div style={{ fontSize: 10.5, color: 'var(--text-faint)', padding: '0 0 12px', lineHeight: 1.5 }}>
        Edits are saved as a non-destructive sidecar (<span style={{ fontFamily: 'var(--font-mono)' }}>.xmp</span>) next to the original on mac-studio.
      </div>
    </div>
  );
}

function MapPanel({ photo }) {
  return (
    <div className="meta">
      <div className="map-stub">
        <div className="map-dotgrid" />
        <div className="map-pin" style={{ left: '50%', top: '50%' }}>
          <span className="map-pin-dot" />
          <span className="map-pin-ring" />
        </div>
      </div>
      <div className="meta-block">
        <div className="meta-h">Location</div>
        <div className="meta-row"><span className="k">Place</span><span className="v">{photo.location}</span></div>
        <div className="meta-row"><span className="k">Latitude</span><span className="v">{photo.lat.toFixed(4)}°</span></div>
        <div className="meta-row"><span className="k">Longitude</span><span className="v">{photo.lng.toFixed(4)}°</span></div>
      </div>
    </div>
  );
}

window.Loupe = Loupe;
