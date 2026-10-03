#!/usr/bin/env bash
# Runs ON THE SERVER (in /opt/docmind). Brings all four repos to their `production` branch and rebuilds the stack.
# GitHub Actions calls it over SSH when something is merged into `production`; you can also run it by hand.
set -euo pipefail

main() {
  cd "$(dirname "$0")"

  # One deploy at a time: a second merge waits for the first (up to 20 minutes).
  exec 9>/tmp/docmind-deploy.lock
  flock -w 1200 9 || { echo "Another deploy is still running."; exit 1; }

  echo "==> Updating code"
  git fetch -q origin production
  git checkout -q production
  git reset -q --hard origin/production
  for repo in docmind-web-service docmind-api-service docmind-ai-service; do
    if [ ! -d "$repo/.git" ]; then
      git clone -q --branch production "https://github.com/Eran2001/$repo.git" "$repo"
    fi
    git -C "$repo" fetch -q origin production
    git -C "$repo" checkout -q production
    git -C "$repo" reset -q --hard origin/production
    echo "    $repo @ $(git -C "$repo" rev-parse --short HEAD)"
  done

  echo "==> Building and starting"
  docker compose --env-file .env.prod -f docker-compose.prod.yml --profile proxy up -d --build --remove-orphans
  docker image prune -f >/dev/null

  echo "==> Waiting for the API to be healthy"
  domain=$(grep -E '^DOMAIN=' .env.prod | cut -d= -f2-)
  for _ in $(seq 1 60); do
    if curl -fsS "https://$domain/api/v1/health" >/dev/null 2>&1; then
      echo "Deployed: https://$domain"
      return 0
    fi
    sleep 5
  done
  echo "The API did not become healthy in 5 minutes. Check: docker compose --env-file .env.prod -f docker-compose.prod.yml logs api worker ai"
  return 1
}

# The whole script is parsed before it runs, so the `git reset` above can safely replace this very file.
main "$@"
exit $?
