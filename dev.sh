#!/usr/bin/env bash
# Starts everything for local dev: Docker (Postgres + Redis), AI service, API, worker, web.
# Ctrl+C stops all of them.
set -u
cd "$(dirname "$0")"

pids=()
cleanup() {
  trap - INT TERM EXIT
  echo; echo "Stopping all services..."
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null; done
  pkill -P $$ 2>/dev/null
  wait 2>/dev/null
}
trap cleanup INT TERM EXIT

# Run a command in a folder, prefixing every log line with its name.
run() {
  local name=$1 dir=$2; shift 2
  (cd "$dir" && exec "$@") 2>&1 | sed -u "s/^/[$name] /" &
  pids+=($!)
}

(cd docmind-api-service && docker compose up -d)

run ai     docmind-ai-service  uv run uvicorn docmind_ai.app:create_app --factory --reload
sleep 3
run api    docmind-api-service npm run start:dev
run worker docmind-api-service npm run worker:dev
run web    docmind-web-service npm run dev

wait
