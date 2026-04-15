#!/usr/bin/env bash
set -euo pipefail

RSPAMD_HOST="127.0.0.1"
RSPAMD_PORT="11333"
MAX_WAIT=30

echo "==> Preparing directories..."
mkdir -p /run/rspamd /var/lib/rspamd /etc/rspamd/local.d /var/log/rspamd

echo "==> Writing Rspamd normal worker config..."
cat > /etc/rspamd/local.d/worker-normal.inc <<EOF
bind_socket = "${RSPAMD_HOST}:${RSPAMD_PORT}";
EOF

echo "==> Starting Redis..."
redis-server --daemonize yes

for i in $(seq 1 "$MAX_WAIT"); do
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

echo "==> Starting Rspamd..."
rspamd -f &
RSPAMD_PID=$!

echo "==> Waiting for Rspamd on ${RSPAMD_HOST}:${RSPAMD_PORT}..."
for i in $(seq 1 "$MAX_WAIT"); do
  if curl -sf "http://${RSPAMD_HOST}:${RSPAMD_PORT}/ping" >/dev/null 2>&1; then
    echo "==> Rspamd ready"
    break
  fi

  if ! kill -0 "$RSPAMD_PID" 2>/dev/null; then
    echo "FATAL: Rspamd process died"
    echo "==> Process list:"
    ps aux || true
    echo "==> Listening ports:"
    ss -tlnp || true
    exit 1
  fi

  if [ "$i" -eq "$MAX_WAIT" ]; then
    echo "FATAL: Rspamd did not become ready within ${MAX_WAIT}s"
    echo "==> Process list:"
    ps aux || true
    echo "==> Listening ports:"
    ss -tlnp || true
    exit 1
  fi

  sleep 1
done

echo "==> Starting Uvicorn on port ${PORT:-10000}..."
exec uvicorn app:app --host 0.0.0.0 --port "${PORT:-10000}"
