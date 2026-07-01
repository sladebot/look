#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON_BIN="${LOOK_PYTHON:-$ROOT/.conda/bin/python}"
TMUX_BIN="${TMUX_BIN:-$(command -v tmux || true)}"
if [[ "${TAILSCALE_BIN+x}" ]]; then
  TAILSCALE_BIN="${TAILSCALE_BIN}"
else
  TAILSCALE_BIN="$(command -v tailscale || true)"
fi

BACKEND_HOST="${LOOK_BACKEND_HOST:-127.0.0.1}"
BACKEND_PORT="${LOOK_BACKEND_PORT:-5680}"
PROXY_HOST="${LOOK_REVIEW_PROXY_HOST:-0.0.0.0}"
PROXY_PORT="${LOOK_REVIEW_PROXY_PORT:-5678}"
BACKEND_SESSION="${LOOK_BACKEND_SESSION:-look-server}"
PROXY_SESSION="${LOOK_REVIEW_PROXY_SESSION:-look-review-proxy}"
LOCAL_ENV="$ROOT/.local/review-funnel.env"

ACTION="${1:-start}"

usage() {
  cat <<EOF
Usage:
  $0 start      Start backend, review proxy, and Tailscale Funnel
  $0 restart    Restart backend/proxy, then start Tailscale Funnel
  $0 status     Show tmux, local health, and Funnel status
  $0 stop       Stop Funnel, review proxy, and backend tmux sessions

Environment:
  REVIEW_API_KEY              Required unless LOOK_GENERATE_REVIEW_KEY=1
  LOOK_GENERATE_REVIEW_KEY=1  Generate and save a local review key
  PHOTO_DIR                   Optional mock photo library path for review
  DB_PATH                     Optional mock SQLite DB path for review
  LOOK_BACKEND_API_KEY        Optional backend API key; defaults empty/keyless
  LOOK_BACKEND_PORT           Internal backend port; defaults 5680
  LOOK_REVIEW_PROXY_PORT      App/Funnel-facing proxy port; defaults 5678
  LOOK_SKIP_FUNNEL=1          Start backend/proxy only; useful for local validation
EOF
}

log() {
  printf '[look-review] %s\n' "$*"
}

shell_join() {
  local out=""
  local item
  for item in "$@"; do
    printf -v item '%q' "$item"
    out+="$item "
  done
  printf '%s' "$out"
}

require_command() {
  local name="$1"
  local path="$2"
  if [[ -z "$path" ]]; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

listener_pids() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  fi
}

require_port_available() {
  local port="$1"
  local label="$2"
  local pids
  pids="$(listener_pids "$port")"
  if [[ -n "$pids" ]]; then
    echo "$label port $port is already listening outside the expected tmux session." >&2
    echo "PIDs: $pids" >&2
    echo "Stop that process first, or run: lsof -nP -iTCP:$port -sTCP:LISTEN" >&2
    exit 1
  fi
}

load_or_create_review_key() {
  mkdir -p "$ROOT/.local"
  chmod 700 "$ROOT/.local" 2>/dev/null || true

  local should_persist_key=0
  local env_review_api_key="${REVIEW_API_KEY:-}"

  if [[ "${LOOK_GENERATE_REVIEW_KEY:-}" == "1" && -n "$env_review_api_key" ]]; then
    REVIEW_API_KEY="$env_review_api_key"
    should_persist_key=1
    log "Using REVIEW_API_KEY from environment"
  elif [[ -f "$LOCAL_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$LOCAL_ENV"
    log "Loaded REVIEW_API_KEY from $LOCAL_ENV"
  fi

  if [[ -z "${REVIEW_API_KEY:-}" && "${LOOK_GENERATE_REVIEW_KEY:-}" == "1" ]]; then
    require_command openssl "$(command -v openssl || true)"
    REVIEW_API_KEY="$(openssl rand -hex 32)"
    should_persist_key=1
    log "Generated REVIEW_API_KEY"
  fi

  if [[ "$should_persist_key" == "1" ]]; then
    umask 077
    printf 'REVIEW_API_KEY=%q\n' "$REVIEW_API_KEY" > "$LOCAL_ENV"
    log "Saved REVIEW_API_KEY to $LOCAL_ENV"
  fi

  if [[ -z "${REVIEW_API_KEY:-}" ]]; then
    cat >&2 <<EOF
REVIEW_API_KEY is not set.

Set it explicitly:
  export REVIEW_API_KEY="\$(openssl rand -hex 32)"

Or generate a local ignored key file:
  LOOK_GENERATE_REVIEW_KEY=1 $0 start
EOF
    exit 1
  fi
}

tmux_has_session() {
  "$TMUX_BIN" has-session -t "$1" >/dev/null 2>&1
}

tmux_kill_session() {
  local session="$1"
  if tmux_has_session "$session"; then
    "$TMUX_BIN" kill-session -t "$session"
  fi
}

start_backend() {
  if tmux_has_session "$BACKEND_SESSION"; then
    log "Backend already running in tmux session $BACKEND_SESSION"
    return
  fi
  require_port_available "$BACKEND_PORT" "Backend"

  local env_args=(
    env
    "HOST=$BACKEND_HOST"
    "PORT=$BACKEND_PORT"
    "API_KEY=${LOOK_BACKEND_API_KEY:-}"
  )
  [[ -n "${PHOTO_DIR:-}" ]] && env_args+=("PHOTO_DIR=$PHOTO_DIR")
  [[ -n "${DB_PATH:-}" ]] && env_args+=("DB_PATH=$DB_PATH")
  [[ -n "${THUMBNAILS_DIR:-}" ]] && env_args+=("THUMBNAILS_DIR=$THUMBNAILS_DIR")
  [[ -n "${CONVERTED_DIR:-}" ]] && env_args+=("CONVERTED_DIR=$CONVERTED_DIR")

  local cmd
  cmd="cd $(shell_join "$ROOT") && $(shell_join "${env_args[@]}" "$PYTHON_BIN" -m uvicorn api.server:app --host "$BACKEND_HOST" --port "$BACKEND_PORT")"
  "$TMUX_BIN" new-session -d -s "$BACKEND_SESSION" "$cmd"
  log "Started backend in tmux session $BACKEND_SESSION on $BACKEND_HOST:$BACKEND_PORT"
}

start_proxy() {
  if tmux_has_session "$PROXY_SESSION"; then
    log "Review proxy already running in tmux session $PROXY_SESSION"
    return
  fi
  require_port_available "$PROXY_PORT" "Review proxy"

  local backend_url="http://127.0.0.1:$BACKEND_PORT"
  local cmd
  cmd="cd $(shell_join "$ROOT") && $(shell_join env "REVIEW_API_KEY=$REVIEW_API_KEY" "REVIEW_BACKEND_URL=$backend_url" "$PYTHON_BIN" -m uvicorn api.review_proxy:app --host "$PROXY_HOST" --port "$PROXY_PORT")"
  "$TMUX_BIN" new-session -d -s "$PROXY_SESSION" "$cmd"
  log "Started review proxy in tmux session $PROXY_SESSION on $PROXY_HOST:$PROXY_PORT"
}

wait_for_health() {
  local url="$1"
  local label="$2"

  for _ in {1..30}; do
    if [[ "${3:-}" == "auth" ]]; then
      curl -fsS -H "X-API-Key: $REVIEW_API_KEY" "$url" >/dev/null 2>&1 && {
        log "$label is responding"
        return
      }
    elif curl -fsS "$url" >/dev/null 2>&1; then
      log "$label is responding"
      return
    fi
    sleep 1
  done

  echo "$label did not respond at $url" >&2
  exit 1
}

start_funnel() {
  if [[ "${LOOK_SKIP_FUNNEL:-}" == "1" ]]; then
    log "LOOK_SKIP_FUNNEL=1; skipping Tailscale Funnel"
    return
  fi
  require_command tailscale "$TAILSCALE_BIN"
  log "Starting Tailscale Funnel to localhost:$PROXY_PORT"
  "$TAILSCALE_BIN" funnel --bg "$PROXY_PORT"
  "$TAILSCALE_BIN" funnel status || true
}

start_all() {
  require_command tmux "$TMUX_BIN"
  [[ -x "$PYTHON_BIN" ]] || { echo "Python not found/executable: $PYTHON_BIN" >&2; exit 1; }
  load_or_create_review_key

  log "Review key is set. Keep the matching key in the App Store review build."
  log "Use PHOTO_DIR/DB_PATH for a mock library before exposing review access."
  log "Topology: proxy $PROXY_HOST:$PROXY_PORT -> backend 127.0.0.1:$BACKEND_PORT"
  start_backend
  wait_for_health "http://127.0.0.1:$BACKEND_PORT/api/health" "Backend"
  start_proxy
  wait_for_health "http://127.0.0.1:$PROXY_PORT/api/health" "Review proxy" auth
  start_funnel
}

status_all() {
  require_command tmux "$TMUX_BIN"
  load_or_create_review_key

  log "tmux sessions:"
  "$TMUX_BIN" list-sessions 2>/dev/null | grep -E "^($BACKEND_SESSION|$PROXY_SESSION):" || true

  log "backend health:"
  curl -fsS "http://127.0.0.1:$BACKEND_PORT/api/health" || true
  printf '\n'

  log "proxy health:"
  curl -fsS -H "X-API-Key: $REVIEW_API_KEY" "http://127.0.0.1:$PROXY_PORT/api/health" || true
  printf '\n'

  if [[ -n "$TAILSCALE_BIN" ]]; then
    log "tailscale funnel status:"
    "$TAILSCALE_BIN" funnel status || true
  fi
}

stop_all() {
  require_command tmux "$TMUX_BIN"
  if [[ -n "$TAILSCALE_BIN" && "${LOOK_SKIP_FUNNEL:-}" != "1" ]]; then
    log "Stopping Tailscale Funnel"
    "$TAILSCALE_BIN" funnel reset || true
  elif [[ "${LOOK_SKIP_FUNNEL:-}" == "1" ]]; then
    log "LOOK_SKIP_FUNNEL=1; leaving Tailscale Funnel unchanged"
  fi
  tmux_kill_session "$PROXY_SESSION"
  tmux_kill_session "$BACKEND_SESSION"
  log "Stopped review proxy and backend sessions"
}

case "$ACTION" in
  start)
    start_all
    ;;
  restart)
    stop_all
    start_all
    ;;
  status)
    status_all
    ;;
  stop)
    stop_all
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
