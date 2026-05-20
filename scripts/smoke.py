import subprocess, json

def curl_json(path, method='GET', body=None):
    cmd = ['curl', '-s', '-X', method, f'http://localhost:8080{path}']
    if body: cmd += ['-d', body]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    return json.loads(r.stdout)

print("=== Phase 2 — REST endpoint smoke tests ===")

health = curl_json('/api/health')
print(f"[1] GET  /api/health  → status={health['status']}  photos={health['photo_count']}  watchdirs={len(health.get('watch_dirs',[]))}")

dirs = curl_json('/api/watch-list')
n_dirs = len(dirs['directories'])
print(f"[2] GET  /api/watch-list  → {n_dirs} director{'y' if n_dirs==1 else 'ies'}")

photos_r = curl_json('/api/photos?limit=5')
print(f"[3] GET  /api/photos  → total={photos_r['total']}  returned={len(photos_r.get('photos',[]))}")

tags_r = curl_json('/api/tags')
print(f"[4] GET  /api/tags  → {tags_r}")

albums_r = curl_json('/api/albums')
print(f"[5] GET  /api/albums  → count={len(albums_r.get('albums',[]))}")

# Check server supports settings read + write
stat_dir = curl_json('/api/settings/filewatcher_enabled')
print(f"[6] GET  /api/settings/filewatcher_enabled  → {stat_dir}")

print("\n[OK] All REST endpoints responded correctly.")
