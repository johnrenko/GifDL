#!/bin/sh
set -eu

export API_URL="${API_URL:-http://127.0.0.1:9000/}"
export API_LISTEN_ADDRESS="${API_LISTEN_ADDRESS:-127.0.0.1}"
export API_PORT="${API_PORT:-9000}"
export MEMEDROP_COBALT_API_URL="${MEMEDROP_COBALT_API_URL:-$API_URL}"
export MEMEDROP_FETCH_HOST="${MEMEDROP_FETCH_HOST:-0.0.0.0}"

node /app/src/cobalt &
cobalt_pid=$!

python3 /memedrop/server.py &
api_pid=$!

cleanup() {
    trap - EXIT INT TERM
    kill -TERM "$cobalt_pid" "$api_pid" 2>/dev/null || true
    wait "$cobalt_pid" "$api_pid" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

set +e
while kill -0 "$cobalt_pid" 2>/dev/null && kill -0 "$api_pid" 2>/dev/null; do
    sleep 1
done

if ! kill -0 "$cobalt_pid" 2>/dev/null; then
    wait "$cobalt_pid"
    status=$?
else
    wait "$api_pid"
    status=$?
fi
set -e

exit "$status"
