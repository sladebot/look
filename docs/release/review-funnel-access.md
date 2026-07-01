# Review-Only Public Access via Tailscale Funnel

This sets up a **public HTTPS entry point for App Store Review** while keeping
the raw backend private to your Tailscale tailnet.

- **Tailnet devices** keep talking to the backend directly on `:5678`, **no API
  key** required.
- **External reviewers** reach the backend through a **public HTTPS Funnel URL**
  that terminates at a small **auth proxy** (`api/review_proxy.py`) requiring an
  `Authorization: Bearer` token.
- The raw backend on `:5678` is **never** exposed to the public internet.

```
Tailnet (internal):   http://<mac-studio>.<tailnet>.ts.net:5678      (no key)
                      http://100.x.x.x:5678

External (review):    https://<mac-studio>.<tailnet>.ts.net          (Bearer key)
                          → Tailscale Funnel  :443
                          → auth proxy        127.0.0.1:5679
                          → backend           127.0.0.1:5678
```

The proxy accepts the review key as **either** `Authorization: Bearer <key>`
**or** `X-API-Key: <key>` (the header the iOS client already sends). It preserves
HTTP method, path, query string, request/response bodies, status codes, and
headers — dropping only hop-by-hop headers and the inbound credential headers, so
the review key never reaches backend logs.

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

Keep the backend running as usual on `:5678`, then start the proxy on `:5679`:

```bash
./.conda/bin/python -m uvicorn api.review_proxy:app --host 127.0.0.1 --port 5679
```

Bind to `127.0.0.1` only — the proxy should be reachable via the Funnel, not
directly from the network.

## 4. Test unauthorized access (expect 401)

```bash
# No token:
curl -i http://127.0.0.1:5679/api/health

# Wrong token:
curl -i -H "Authorization: Bearer wrong" http://127.0.0.1:5679/api/health
```

Both return:

```
HTTP/1.1 401 Unauthorized
{"error":"Unauthorized"}
```

## 5. Test authorized access (expect 200, forwarded to backend)

```bash
curl -i -H "Authorization: Bearer $REVIEW_API_KEY" \
  http://127.0.0.1:5679/api/health

# X-API-Key is accepted too (this is what the iOS client sends):
curl -i -H "X-API-Key: $REVIEW_API_KEY" http://127.0.0.1:5679/api/health

# Query string is preserved:
curl -s -H "Authorization: Bearer $REVIEW_API_KEY" \
  "http://127.0.0.1:5679/api/photos?limit=5"

# Binary/streamed responses pass through unchanged:
curl -s -o /tmp/thumb.jpg -H "Authorization: Bearer $REVIEW_API_KEY" \
  "http://127.0.0.1:5679/api/thumbnails/<photo_id>?size=256" && file /tmp/thumb.jpg
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

Point the public HTTPS Funnel at the **proxy** (`5679`), never the backend
(`5678`):

```bash
tailscale funnel --https=443 localhost:5679 --bg
```

`--bg` runs it in the background so it survives your shell session.

### Check status

```bash
tailscale funnel status
```

You should see `https://<mac-studio>.<tailnet>.ts.net` proxying to
`localhost:5679`. Then verify end-to-end from *outside* the tailnet
(e.g. phone on cellular):

```bash
curl -i https://<mac-studio>.<tailnet>.ts.net/api/health              # 401
curl -i -H "Authorization: Bearer $REVIEW_API_KEY" \
  https://<mac-studio>.<tailnet>.ts.net/api/health                    # 200
```

## 7. Shut the Funnel down

When review is finished, take the public endpoint down:

```bash
tailscale funnel --https=443 off
```

Then stop the proxy (Ctrl-C, or kill its uvicorn process). The backend on
`:5678` keeps serving the tailnet as before.

---

## 8. App Store Review note template

> **⚠️ Prerequisite 1 — serve a mock library, not your real photos.** The proxy
> forwards **all HTTP methods** to a **keyless** backend, so while the Funnel is
> up it is a public, Bearer-gated, *write-capable* path to whatever
> `127.0.0.1:5678` is serving. Before enabling the Funnel, point the backend at a
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
