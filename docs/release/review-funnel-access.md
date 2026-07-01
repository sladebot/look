# Review-Only Public Access via Tailscale Funnel

This sets up a **public HTTPS entry point for App Store Review** while keeping
the raw backend private to your Tailscale tailnet.

- **All app-facing traffic** uses `:5678`.
- `:5678` is the review auth proxy (`api/review_proxy.py`) and requires a
  review key via `X-API-Key` or `Authorization: Bearer`.
- The raw backend is moved to loopback-only `127.0.0.1:5680` and is never
  exposed directly.

```
Tailnet/review app:   http://<mac-studio>.<tailnet>.ts.net:5678      (X-API-Key)
                      http://100.x.x.x:5678                         (X-API-Key)

External (review):    https://<mac-studio>.<tailnet>.ts.net          (Bearer key)
                          → Tailscale Funnel  :443
                          → auth proxy        0.0.0.0:5678
                          → backend           127.0.0.1:5680
```

The proxy accepts the review key as **either** `Authorization: Bearer <key>`
**or** `X-API-Key: <key>` (the header the iOS client already sends). It preserves
HTTP method, path, query string, request/response bodies, status codes, and
headers — dropping only hop-by-hop headers and the inbound credential headers, so
the review key never reaches backend logs.

## Scripted startup

For normal App Store Review setup, use the helper script instead of manually
starting each process:

```bash
# Recommended: point this at a generated/mock review library, not real photos.
export PHOTO_DIR="/path/to/generated-review-photos"
export DB_PATH="$PWD/.local/review-library.db"

# Use an existing key...
export REVIEW_API_KEY="paste-the-hex-string-here"
./scripts/start_review_funnel.sh restart

# ...or generate a local ignored key file.
LOOK_GENERATE_REVIEW_KEY=1 ./scripts/start_review_funnel.sh restart
```

The script:

- starts the backend in a detached `tmux` session named `look-server` on
  `127.0.0.1:5680`;
- starts the review auth proxy in `look-review-proxy` on `0.0.0.0:5678`;
- verifies both local health endpoints;
- runs `tailscale funnel --bg 5678`;
- supports `start`, `restart`, `status`, and `stop`.

The generated key file lives at `.local/review-funnel.env`, which is ignored by
git. Keep the review build's API-key value in sync with `REVIEW_API_KEY`.

---

## 1. Generate a review key

```bash
openssl rand -hex 32
```

Store the output somewhere safe (a password manager). This is the token
reviewers' requests must present.

## 2. Export the key

```bash
export REVIEW_API_KEY="paste-the-hex-string-here"
# or generate inline:
export REVIEW_API_KEY="$(openssl rand -hex 32)"
```

The proxy **fails fast** if `REVIEW_API_KEY` is unset:

```
FATAL: REVIEW_API_KEY is not set.
```

## 3. Start the auth proxy

Start the backend on loopback-only `:5680`, then start the proxy on app-facing
`:5678`:

```bash
./.conda/bin/python -m uvicorn api.server:app --host 127.0.0.1 --port 5680
REVIEW_BACKEND_URL=http://127.0.0.1:5680 \
  ./.conda/bin/python -m uvicorn api.review_proxy:app --host 0.0.0.0 --port 5678
```

Do not bind the raw backend to `0.0.0.0` in review mode. Only the proxy should
own `:5678`.

## 4. Test unauthorized access (expect 401)

```bash
# No token:
curl -i http://127.0.0.1:5678/api/health

# Wrong token:
curl -i -H "Authorization: Bearer wrong" http://127.0.0.1:5678/api/health
```

Both return:

```
HTTP/1.1 401 Unauthorized
{"error":"Unauthorized"}
```

## 5. Test authorized access (expect 200, forwarded to backend)

```bash
curl -i -H "Authorization: Bearer $REVIEW_API_KEY" \
  http://127.0.0.1:5678/api/health

# X-API-Key is accepted too (this is what the iOS client sends):
curl -i -H "X-API-Key: $REVIEW_API_KEY" http://127.0.0.1:5678/api/health

# Query string is preserved:
curl -s -H "Authorization: Bearer $REVIEW_API_KEY" \
  "http://127.0.0.1:5678/api/photos?limit=5"

# Binary/streamed responses pass through unchanged:
curl -s -o /tmp/thumb.jpg -H "Authorization: Bearer $REVIEW_API_KEY" \
  "http://127.0.0.1:5678/api/thumbnails/<photo_id>?size=256" && file /tmp/thumb.jpg
```

---

## 6. Tailscale Funnel setup

### Prerequisites (one-time)

Funnel will refuse to start unless the tailnet is configured for it:

- **HTTPS certificates + MagicDNS** enabled for the tailnet
  (Admin console → **DNS**).
- **Funnel enabled** for this node. In the ACL policy file, grant the `funnel`
  node attribute, e.g.:

  ```jsonc
  "nodeAttrs": [
    { "target": ["autogroup:member"], "attr": ["funnel"] }
  ]
  ```

- Confirm the machine's public name with `tailscale status` / the admin console
  (it is `https://<mac-studio>.<tailnet>.ts.net`).

### Start the Funnel

Point the public HTTPS Funnel at the **proxy** (`5678`), never the internal
backend (`5680`):

```bash
tailscale funnel --bg 5678
```

`--bg` runs it in the background so it survives your shell session. Note: flags
must come **before** the port; the port defaults to public HTTPS on 443. (Older
Tailscale builds used `tailscale funnel --https=443 localhost:5678 --bg`, which
newer CLIs reject with `invalid argument format`.)

### Check status

```bash
tailscale funnel status
```

You should see `https://<mac-studio>.<tailnet>.ts.net` proxying to
`localhost:5678`. Then verify end-to-end from *outside* the tailnet
(e.g. phone on cellular):

```bash
curl -i https://<mac-studio>.<tailnet>.ts.net/api/health              # 401
curl -i -H "Authorization: Bearer $REVIEW_API_KEY" \
  https://<mac-studio>.<tailnet>.ts.net/api/health                    # 200
```

## 7. Shut the Funnel down

When review is finished, take the public endpoint down:

```bash
tailscale funnel reset      # removes the public Funnel config
```

Then stop the proxy (Ctrl-C, or kill its uvicorn process). The backend on
`:5678` keeps serving the tailnet as before.

---

## 8. App Store Review note template

> **⚠️ Prerequisite 1 — serve a mock library, not your real photos.** The proxy
> forwards **all HTTP methods** to a **keyless** backend, so while the Funnel is
> up it is a public, Bearer-gated, *write-capable* path to whatever
> `127.0.0.1:5680` is serving. Before enabling the Funnel, point the backend at a
> **throwaway/mock library** (set `PHOTO_DIR` / the watch list to a folder of
> generated demo photos, and use a separate `DB_PATH`). Do **not** expose your
> real archive. The template below tells Apple the data is mock — make that true.
>
> **⚠️ Prerequisite 2 — the iOS review build must send the review key.** The
> proxy accepts `X-API-Key`, which the app already sends (`APIClient.swift`), so
> **no Swift change is required**: point the review build at the Funnel URL and
> set its API-key field to `REVIEW_API_KEY`. (A build sending
> `Authorization: Bearer <REVIEW_API_KEY>` works identically.) Without a matching
> key, every review request returns 401.

Paste into **App Store Connect → App Review Information → Notes**, filling in the
placeholders:

```
This app is a client for a self-hosted "Look" photo server. For review, we run a
public, read-only backend so you do NOT need to install a VPN or Tailscale.

- Review backend URL: https://<mac-studio>.<tailnet>.ts.net
- No VPN, Tailscale, or extra software is required to test the app.
- The app connects to the public HTTPS review backend automatically.
- The app automatically sends the required authorization header on every
  request, so no manual token entry is needed.

Demo credentials (if the app prompts for sign-in):
- Username: <REVIEW_DEMO_USERNAME>
- Password: <REVIEW_DEMO_PASSWORD>

The backend serves a small library of generated mock photos and metadata. It
contains no real or private user data.
```

Keep the Funnel (section 6) and the proxy (section 3) running for the entire
review period, and keep `REVIEW_API_KEY` in sync between the proxy and the
review build.
