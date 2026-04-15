#!/usr/bin/env bash
set -e

mkdir -p /run/rspamd /var/lib/rspamd /etc/rspamd/local.d

# Start Redis in background
redis-server --daemonize yes

# Start Rspamd in foreground-but-backgrounded for this script
rspamd -f &
sleep 5

# Start wrapper API on Render's assigned port
exec uvicorn app:app --host 0.0.0.0 --port "${PORT:-10000}"
