# look
Adobe local photos via tailscale

## Run

```bash
python -m uvicorn api.server:app --host 0.0.0.0 --port 5678
```

The server initializes its database and runtime services lazily on startup or
first request, so importing `api.server` from tests or tooling does not mutate
the default photo library.

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
