#!/usr/bin/env bash
set -e

RSPAMD_HOST="127.0.0.1"
RSPAMD_PORT="11333"
MAX_WAIT=30

mkdir -p /run/rspamd /var/lib/rspamd /etc/rspamd/local.d

# ── Ensure Rspamd normal worker binds to expected port ──
cat > /etc/rspamd/local.d/worker-normal.inc << EOF
bind_socket = "${RSPAMD_HOST}:${RSPAMD_PORT}";
EOF

# ── 1. Start Redis ──
echo "==> Starting Redis..."
redis-server --daemonize yes
for i in $(seq 1 $MAX_WAIT); do
  if redis-cli ping 2>/dev/null | grep -q PONG; then
    echo "==> Redis ready"
    break
  fi
  if [ "$i" -eq "$MAX_WAIT" ]; then
    echo "FATAL: Redis did not start within ${MAX_WAIT}s"
    exit 1
  fi
  sleep 1
done

# ── 2. Start Rspamd ──
echo "==> Starting Rspamd..."
rspamd -f &
RSPAMD_PID=$!

echo "==> Waiting for Rspamd on ${RSPAMD_HOST}:${RSPAMD_PORT}..."
for i in $(seq 1 $MAX_WAIT); do
  if curl -sf "http://${RSPAMD_HOST}:${RSPAMD_PORT}/ping" >/dev/null 2>&1; then
    echo "==> Rspamd ready (responded to /ping)"
    break
  fi
  if ! kill -0 "$RSPAMD_PID" 2>/dev/null; then
    echo "FATAL: Rspamd process died. Output:"
    cat /var/log/rspamd/rspamd.log 2>/dev/null || echo "(no log found)"
    echo "Listening ports:"
    ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || true
    exit 1
  fi
  if [ "$i" -eq "$MAX_WAIT" ]; then
    echo "FATAL: Rspamd did not bind to ${RSPAMD_HOST}:${RSPAMD_PORT} within ${MAX_WAIT}s"
    echo "Rspamd process status:"
    kill -0 "$RSPAMD_PID" 2>/dev/null && echo "  PID $RSPAMD_PID alive" || echo "  PID $RSPAMD_PID dead"
    echo "Listening ports:"
    ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || true
    echo "Rspamd logs:"
    tail -50 /var/log/rspamd/rspamd.log 2>/dev/null || echo "(no log)"
    exit 1
  fi
  sleep 1
done

# ── 3. Start Uvicorn ──
echo "==> Starting Uvicorn on port ${PORT:-10000}..."
exec uvicorn app:app --host 0.0.0.0 --port "${PORT:-10000}"
