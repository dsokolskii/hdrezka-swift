#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.tmp"
LOG_FILE="$LOG_DIR/stream_proxy.log"
PID_FILE="$LOG_DIR/stream_proxy.pid"
PORT=8642

mkdir -p "$LOG_DIR"

is_running() {
  lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P >/dev/null 2>&1
}

start_proxy() {
  if is_running; then
    echo "Proxy already running on 127.0.0.1:$PORT"
    return 0
  fi

  nohup bash -lc "while true; do python3 -u '$ROOT_DIR/scripts/stream_proxy.py' >>'$LOG_FILE' 2>&1; echo \"proxy process exited with \$? at \$(date)\" >>'$LOG_FILE'; sleep 1; done" >/dev/null 2>&1 &
  echo "$!" >"$PID_FILE"
  sleep 1

  if is_running; then
    echo "Proxy started on 127.0.0.1:$PORT"
  else
    echo "Failed to start proxy. Check $LOG_FILE"
    exit 1
  fi
}

stop_proxy() {
  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" >/dev/null 2>&1 || true
    rm -f "$PID_FILE"
  fi
  pkill -f "python3 -u .*scripts/stream_proxy.py" >/dev/null 2>&1 || true
  pkill -f "while true; do python3 -u .*scripts/stream_proxy.py" >/dev/null 2>&1 || true
  local pids
  pids="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN -n -P 2>/dev/null || true)"
  if [[ -n "$pids" ]]; then
    kill $pids >/dev/null 2>&1 || true
    sleep 0.3
  fi

  if is_running; then
    echo "Proxy is still running; stop manually."
    exit 1
  fi

  echo "Proxy stopped"
}

status_proxy() {
  if is_running; then
    echo "Proxy is running on 127.0.0.1:$PORT"
    lsof -iTCP:"$PORT" -sTCP:LISTEN -n -P
  else
    echo "Proxy is not running"
  fi
}

show_logs() {
  if [[ -f "$LOG_FILE" ]]; then
    tail -n 50 "$LOG_FILE"
  else
    echo "No log file yet: $LOG_FILE"
  fi
}

healthcheck_proxy() {
  if is_running; then
    local code
    code="$(curl -sS -o /dev/null -w "%{http_code}" --max-time 10 "http://127.0.0.1:${PORT}/https/example.com/" || true)"
    if [[ "$code" == "200" || "$code" == "206" ]]; then
      echo "Proxy healthcheck passed (HTTP $code)"
      return 0
    fi
    echo "Proxy healthcheck failed (HTTP ${code:-n/a})"
    return 1
  fi

  echo "Proxy healthcheck failed: proxy is not running"
  return 1
}

ensure_proxy() {
  if is_running; then
    healthcheck_proxy
    return $?
  fi

  echo "Proxy was not running; starting now..."
  start_proxy
  healthcheck_proxy
}

case "${1:-}" in
  start) start_proxy ;;
  stop) stop_proxy ;;
  restart) stop_proxy; start_proxy ;;
  status) status_proxy ;;
  logs) show_logs ;;
  health) healthcheck_proxy ;;
  ensure) ensure_proxy ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|logs|health|ensure}"
    exit 1
    ;;
esac
