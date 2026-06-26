# Look

Look is a lightweight, self-hosted photo library for a private Tailscale
network. It is designed to run on a machine you control, reachable from your
own devices over a Tailnet, with no public cloud photo storage.

> **Deployment model:** Look assumes private-network access through Tailscale.
> Do not expose the server directly to the public internet. If your Tailnet is
> shared, set `API_KEY` so write actions require an application-level key.

## Run

```bash
python -m uvicorn api.server:app --host 0.0.0.0 --port 5678
```

Then open the server from another Tailnet device using either:

- MagicDNS: `http://your-machine.your-tailnet.ts.net:5678`
- Tailscale IP: `http://100.x.y.z:5678`

Binding to `0.0.0.0` is intended for trusted private interfaces such as
Tailscale or a trusted LAN. It is not a recommendation to publish port `5678`
on the open internet.

The server initializes its database and runtime services lazily on startup or
first request, so importing `api.server` from tests or tooling does not mutate
the default photo library.

## Security Model

Look treats Tailnet membership as the primary network boundary:

- Read endpoints expose photo metadata, thumbnails, and image files to devices
  that can reach the server.
- `API_KEY` is optional and protects write actions when configured.
- Plain HTTP is acceptable only under the private Tailnet deployment model,
  because Tailscale encrypts node-to-node transport.
- For any public or semi-public deployment, put Look behind a real HTTPS
  reverse proxy and tighten authentication before exposing it.

## Test

```bash
pytest -q
```

The test harness sets the repository root on `PYTHONPATH` through `pytest.ini`.

## Web API Key

When `API_KEY` is configured on the server, the web client sends it on write
requests if it is present in browser storage:

```js
localStorage.setItem("look_api_key", "your-key")
```
