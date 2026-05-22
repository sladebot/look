/* Look — backend admin panel wired to local-photos-server API */

const { useState: aUseState, useEffect: aUseEffect } = React;

function Admin({ open, onClose, photos, status, setStatus }) {
  // All hooks must be called unconditionally (before any early return)
  const [tab, setTab] = aUseState('overview');
  const [health, setHealth] = aUseState(null);
  const [importing, setImporting] = aUseState(false);
  const [importResult, setImportResult] = aUseState(null);

  aUseEffect(() => {
    if (!open) return;
    Look.apiHealth().then(setHealth).catch(() => {});
  }, [open]);

  if (!open) return null;

  const totalRaw = photos.filter(p => p.raw).length;
  const totalJpeg = photos.length;

  const watchDirs = health?.watch_dirs || [];
  const photoCount = health?.photo_count ?? totalJpeg;
  const fwRunning = health?.filewatcher_running ?? false;

  const triggerImport = async () => {
    setImporting(true);
    setImportResult(null);
    try {
      const result = await Look.apiImport();
      setImportResult(result);
      // refresh health
      const h = await Look.apiHealth();
      setHealth(h);
    } catch (e) {
      setImportResult({ error: e.message });
    } finally {
      setImporting(false);
    }
  };

  return (
    <div className="modal-shade" onClick={(e) => { if (e.target.classList.contains('modal-shade')) onClose(); }}>
      <div className="modal">
        <div className="modal-head">
          <div>
            <div className="modal-title">Library Admin</div>
            <div className="modal-sub">mac-studio · {health?.db_path || '—'}</div>
          </div>
          <button className="icon-btn" onClick={onClose} title="Close">
            <Icon d={icons.close} size={15} />
          </button>
        </div>

        <div className="modal-tabs">
          {['overview','storage','previews','devices','logs'].map(t => (
            <button key={t} className={"modal-tab" + (tab === t ? ' active' : '')} onClick={() => setTab(t)}>
              {t.charAt(0).toUpperCase() + t.slice(1)}
            </button>
          ))}
        </div>

        <div className="modal-body">

          {tab === 'overview' && (
            <div className="admin-grid">
              <Stat label="Photos indexed" value={photoCount.toLocaleString()}
                    sub={`${totalRaw.toLocaleString()} RAW · ${(photoCount - totalRaw).toLocaleString()} JPEG-only`} />
              <Stat label="Daemon" value={fwRunning ? 'File watcher on' : 'Watcher off'}
                    sub={fwRunning ? 'Auto-importing new files' : 'Manual import only'}
                    dot={fwRunning ? 'ok' : 'warn'} />
              <Stat label="Tailscale" value="Connected"
                    sub="studio.taila3f2b.ts.net · open network" dot="ok" />
              <Stat label="Preview queue" value={`${(status.previewsTotal - status.previewsDone).toLocaleString()} pending`}
                    sub={`${status.previewsDone.toLocaleString()} / ${status.previewsTotal.toLocaleString()} generated`}
                    dot={status.previewsDone < status.previewsTotal ? 'busy' : 'ok'} />
              <Stat label="Database" value="SQLite (WAL)"
                    sub={health?.db_path ? health.db_path.split('/').slice(-2).join('/') : '—'} dot="ok" />
              <Stat label="Watch dirs" value={watchDirs.length.toLocaleString()}
                    sub={watchDirs.filter(d => d.active).length + ' active'} dot="ok" />

              <div className="admin-card admin-card-wide">
                <div className="admin-card-h">Watch directories</div>
                {watchDirs.length === 0
                  ? <div style={{ color: 'var(--text-faint)', fontSize: 11.5 }}>No watch directories configured.</div>
                  : (
                  <table className="admin-table">
                    <thead><tr><th>Path</th><th>Status</th></tr></thead>
                    <tbody>
                      {watchDirs.map((d, i) => (
                        <tr key={i}>
                          <td className="mono">{d.path}</td>
                          <td>
                            <span className={`dot dot-${d.active ? 'ok' : 'warn'}`} style={{ marginRight: 6 }} />
                            {d.active ? 'Active' : 'Paused'}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>

              {importResult && (
                <div className="admin-card admin-card-wide" style={{ marginTop: 0 }}>
                  <div className="admin-card-h">Last import result</div>
                  {importResult.error
                    ? <div style={{ color: 'var(--reject)', fontFamily: 'var(--font-mono)', fontSize: 11 }}>{importResult.error}</div>
                    : (
                    <div style={{ fontSize: 12, color: 'var(--text-dim)' }}>
                      {importResult.message} — {importResult.imported} imported, {importResult.errors} errors
                      {importResult.error_details?.length > 0 && (
                        <ul style={{ marginTop: 8, paddingLeft: 16, color: 'var(--reject)', fontSize: 11, fontFamily: 'var(--font-mono)' }}>
                          {importResult.error_details.map((e, i) => <li key={i}>{e}</li>)}
                        </ul>
                      )}
                    </div>
                  )}
                </div>
              )}
            </div>
          )}

          {tab === 'storage' && (
            <div>
              <div className="admin-grid">
                <Stat label="Watch directories" value={watchDirs.length} sub={watchDirs.filter(d=>d.active).length + ' active'} dot="ok" />
                <Stat label="Photos indexed" value={photoCount.toLocaleString()} sub={`${totalRaw} with RAW originals`} />
                <Stat label="Database" value="SQLite WAL" sub="Foreign keys · WAL mode" dot="ok" />
              </div>
              <div className="admin-card admin-card-wide" style={{ marginTop: 18 }}>
                <div className="admin-card-h">Folder map</div>
                {watchDirs.length === 0
                  ? <div style={{ color: 'var(--text-faint)', fontSize: 11.5 }}>No watch directories configured. Add one via the API or settings.</div>
                  : (
                  <table className="admin-table">
                    <thead><tr><th>Path</th><th>Active</th><th>Added</th></tr></thead>
                    <tbody>
                      {watchDirs.map((d, i) => (
                        <tr key={i}>
                          <td className="mono">{d.path}</td>
                          <td>{d.active ? '✓' : '—'}</td>
                          <td style={{ color: 'var(--text-faint)', fontFamily: 'var(--font-mono)', fontSize: 10.5 }}>
                            {d.added_at ? d.added_at.slice(0,10) : '—'}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
              </div>
            </div>
          )}

          {tab === 'previews' && (
            <div>
              <div className="admin-card admin-card-wide">
                <div className="admin-card-h">JPEG preview generation</div>
                <p className="admin-p">
                  Look serves JPEG thumbnails to the browser for fast loading. Originals (RAW) are kept untouched
                  on disk and only streamed when explicitly downloaded. Thumbnails are generated on-demand and
                  cached in <span className="mono">.thumbnails/</span> next to each photo directory.
                </p>
                <div className="big-progress">
                  <div className="big-progress-track">
                    <div className="big-progress-fill" style={{ width: `${Math.round((status.previewsDone / status.previewsTotal) * 100)}%` }} />
                  </div>
                  <div className="big-progress-meta">
                    <span className="mono">{status.previewsDone.toLocaleString()} / {status.previewsTotal.toLocaleString()}</span>
                    <span style={{ color: 'var(--text-faint)' }}>
                      {status.previewsDone >= status.previewsTotal ? 'All previews up to date' : 'Generating…'}
                    </span>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: 10, marginTop: 16, flexWrap: 'wrap' }}>
                  <button className="primary-btn" onClick={triggerImport} disabled={importing}>
                    <Icon d={icons.refresh} size={13} />
                    {importing ? 'Importing…' : 'Rescan & import all'}
                  </button>
                  <button className="secondary-btn" disabled>
                    Clear thumbnail cache
                  </button>
                </div>
              </div>
              <div className="admin-grid" style={{ marginTop: 18 }}>
                <Stat label="Thumbnail quality" value="JPEG q=85" sub="Configurable via settings API" />
                <Stat label="Max width" value="1024 px" sub="Long-edge constraint" />
                <Stat label="Cache location" value=".thumbnails/" sub="Sibling to each photo dir" />
              </div>
            </div>
          )}

          {tab === 'devices' && (
            <div>
              <div className="admin-card admin-card-wide">
                <div className="admin-card-h">Tailscale access</div>
                <p className="admin-p">
                  Look relies on Tailscale for private network access. All devices on your Tailnet can reach
                  the server at <span className="mono">studio.taila3f2b.ts.net:8080</span>.
                  Read access is open; write operations (import, settings) require an API key if configured.
                </p>
                <table className="admin-table">
                  <thead><tr><th></th><th>Device</th><th>Role</th><th>Notes</th></tr></thead>
                  <tbody>
                    <tr>
                      <td><Icon d={icons.server} size={13} /></td>
                      <td className="mono">mac-studio <span className="badge-host">this device</span></td>
                      <td>Server</td>
                      <td style={{ color: 'var(--text-faint)', fontSize: 11 }}>Hosts photos + DB</td>
                    </tr>
                    <tr>
                      <td><Icon d={icons.laptop} size={13} /></td>
                      <td className="mono">macbook-pro</td>
                      <td>Client</td>
                      <td style={{ color: 'var(--text-faint)', fontSize: 11 }}>Browse + download</td>
                    </tr>
                    <tr>
                      <td><Icon d={icons.phone} size={13} /></td>
                      <td className="mono">iphone / ipad</td>
                      <td>Client</td>
                      <td style={{ color: 'var(--text-faint)', fontSize: 11 }}>Mobile browser</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div className="admin-card admin-card-wide" style={{ marginTop: 14 }}>
                <div className="admin-card-h">Sharing</div>
                <p className="admin-p">
                  To grant family members access, invite them to your Tailnet. They'll reach Look at the same
                  address — no port forwarding, no exposing to the public internet.
                </p>
              </div>
            </div>
          )}

          {tab === 'logs' && (
            <div className="admin-card admin-card-wide">
              <div className="admin-card-h">Server log (stdout)</div>
              <p className="admin-p" style={{ marginBottom: 12 }}>
                Logs are written to stdout. Run <span className="mono">python server.py 2&gt;&amp;1 | tee look.log</span> to persist them.
              </p>
              <pre className="log-pre">
{`[INFO]  local-photos-server started
[INFO]  Database: ${health?.db_path || '~/.local/local-photos/library.db'}
[INFO]  Watch dirs: ${watchDirs.map(d => d.path).join(', ') || 'none configured'}
[INFO]  File watcher: ${fwRunning ? 'running' : 'disabled'}
[INFO]  FastAPI / Uvicorn ready on :${window.location.port || '8765'}
[INFO]  OpenAPI docs at ${window.location.origin}/docs`}
              </pre>
            </div>
          )}
        </div>

        <div className="modal-foot">
          <button className="secondary-btn" onClick={triggerImport} disabled={importing}>
            <Icon d={icons.refresh} size={13} /> {importing ? 'Importing…' : 'Rescan library'}
          </button>
          <div className="status-spacer" />
          <span style={{ fontFamily: 'var(--font-mono)', fontSize: 10.5, color: 'var(--text-faint)' }}>
            local-photos-server v0.3.0 · FastAPI
          </span>
        </div>
      </div>
    </div>
  );
}

function Stat({ label, value, sub, dot }) {
  return (
    <div className="admin-card">
      <div className="admin-card-h">
        {label}
        {dot && <span className={`dot dot-${dot}`} style={{ marginLeft: 'auto' }} />}
      </div>
      <div className="admin-card-v">{value}</div>
      <div className="admin-card-sub">{sub}</div>
    </div>
  );
}

function NewAlbumModal({ open, onClose, onCreate }) {
  const [name, aSetName] = aUseState('');
  const [busy, setBusy] = aUseState(false);
  if (!open) return null;

  const submit = async () => {
    if (!name.trim()) return;
    setBusy(true);
    try {
      const result = await Look.apiCreateAlbum(name.trim());
      onCreate(name.trim(), result.id);
      aSetName('');
    } catch (e) {
      // fallback: pass name and let App generate local id
      onCreate(name.trim(), null);
      aSetName('');
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="modal-shade" onClick={(e) => { if (e.target.classList.contains('modal-shade')) onClose(); }}>
      <div className="modal" style={{ width: 420, height: 'auto' }}>
        <div className="modal-head">
          <div className="modal-title">New album</div>
          <button className="icon-btn" onClick={onClose}><Icon d={icons.close} size={15} /></button>
        </div>
        <div style={{ padding: 18 }}>
          <label style={{ fontSize: 11.5, color: 'var(--text-faint)', display: 'block', marginBottom: 6 }}>Album name</label>
          <input
            value={name}
            onChange={e => aSetName(e.target.value)}
            autoFocus
            placeholder="Iceland 2025"
            style={{
              width: '100%', padding: '8px 10px', fontSize: 13,
              background: 'var(--bg)', borderRadius: 6,
              boxShadow: 'inset 0 0 0 1px var(--hairline-bright)', color: 'var(--text)'
            }}
            onKeyDown={(e) => { if (e.key === 'Enter') submit(); }}
          />
          <div style={{ display: 'flex', gap: 10, marginTop: 16, justifyContent: 'flex-end' }}>
            <button className="secondary-btn" onClick={onClose}>Cancel</button>
            <button className="primary-btn" disabled={!name.trim() || busy} onClick={submit}>
              {busy ? 'Creating…' : 'Create album'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

window.Admin = Admin;
window.NewAlbumModal = NewAlbumModal;
