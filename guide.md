# DocMind: commands

Run everything from the `docmind` folder unless it says otherwise.

## Dev (your daily setup)

### Everything at once

```bash
./dev.sh
```

Starts Postgres + Redis (Docker), the AI service, the API, the worker and the web app. Ctrl+C stops all of them.
Web: http://localhost:3000 · API: http://localhost:4000 · AI: http://localhost:8000 (internal).

### Or one by one (one terminal each)

```bash
# 0. Databases (Postgres + Redis)
cd docmind-api-service && docker compose up -d

# 1. AI service
cd docmind-ai-service && uv run uvicorn docmind_ai.app:create_app --factory --reload

# 2. API
cd docmind-api-service && npm run start:dev

# 3. Worker (processes uploaded documents; without it they stay "Queued")
cd docmind-api-service && npm run worker:dev

# 4. Web
cd docmind-web-service && npm run dev
```

Chat uses Ollama (`llama3.2`), so make sure Ollama is running, or switch the AI service's `config/.env` to OpenAI.

### Handy dev commands

```bash
cd docmind-api-service
npm run db:migrate            # apply new migrations to the dev database
npm run db:seed               # demo data
npm test                      # API tests

cd docmind-ai-service && uv run pytest        # AI tests
cd docmind-web-service && npm test            # web unit tests
cd docmind-web-service && npm run e2e         # Playwright end-to-end (needs Postgres + Redis running, no OpenAI key)
cd docmind-web-service && npm run typecheck && npm run lint && npm run build
```

## Prod (Docker)

Setup once: `cp .env.prod.example .env.prod` and fill it in (see `CLAUDE.md`). Always pass `--env-file .env.prod`.
Stop `./dev.sh` first: both use ports 3000 and 4000.

### On your machine (trial)

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

Open http://localhost:3000. It has its own empty database, so register a new account.

### On a server (with HTTPS)

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml --profile proxy up -d --build
```

### Day-to-day

```bash
# status
docker compose --env-file .env.prod -f docker-compose.prod.yml ps

# logs
docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f api worker ai

# stop (keeps data)
docker compose --env-file .env.prod -f docker-compose.prod.yml down

# stop and WIPE all data (database + uploads)
docker compose --env-file .env.prod -f docker-compose.prod.yml down -v

# make an account admin
docker compose --env-file .env.prod -f docker-compose.prod.yml exec postgres psql -U docmind -d docmind -c "update users set role='admin' where email='you@example.com'"
```

Add `--profile proxy` to the commands above when running on the server.
Health check: `curl http://localhost:4000/api/v1/health` (locally) or `curl https://<your-address>/api/v1/health` (server).

## Git flow (4 repos)

Repos (all public, account Eran2001): `docmind-web-service`, `docmind-api-service`, `docmind-ai-service`, and `docmind` (compose file, Caddyfile, deploy scripts, these guides).
Each has `development` (default, push directly) and `production` (protected: PR only, CI must pass).

```bash
# daily work, in whichever repo you changed
git checkout development && git pull
git add . && git commit -m "..." && git push

# release: PR development -> production, in each repo that changed
gh pr create -B production -H development -R Eran2001/<repo> --fill
gh pr checks -R Eran2001/<repo> --watch      # wait for green
gh pr merge  -R Eran2001/<repo> --merge      # merging triggers the Deploy workflow
```

`gh` needs `gh auth login` once. The same can be done in the GitHub UI.
CI runs on every push to `development` and every PR into `development` or `production`.
Never commit `.env`, `.env.prod` or any key. The `docmind` repo's `.gitignore` already skips them and the three service folders.

## Server (not set up yet)

When you are ready, follow `CLAUDE.md` ("Deploy to a server" and "Branches and automatic deploys"). Until the `DEPLOY_HOST` secret exists, merging into `production` deploys nothing and the Deploy workflow just passes with a notice.

## How it all fits together (DevOps view)

Read this when you are ready to put it on a server. It explains what each piece does and in what order things happen.

### The pieces

| Piece | Where it lives | Job |
|---|---|---|
| Web, API (+ worker), AI code | 3 service repos, each with its own `Dockerfile` | The app itself. Each repo only knows how to build its own image. |
| `docker-compose.prod.yml` | `docmind` repo | Wires everything into one stack: Postgres (pgvector), Redis, AI, migrate (runs once), API, worker, web, and Caddy (only with `--profile proxy`). |
| `Caddyfile` | `docmind` repo | HTTPS and routing: `/api/v1/*` goes to the API, everything else to the web app. One address, so cookies and CORS just work. |
| `.env.prod` | ONLY on the server (and your Mac for trials), never in git | All secrets and the public URLs. Compose reads it with `--env-file .env.prod`. |
| `deploy.sh` | `docmind` repo, runs on the server | Updates all 4 repos to `production`, rebuilds, restarts, waits for the health check. |
| `setup-server.sh` | `docmind` repo, run once on a new server | Installs Docker and clones `docmind` to `/opt/docmind`. |
| `.github/workflows/ci.yml` | each service repo | Tests on every push/PR (lint, types, unit tests, build, end-to-end for web). |
| `.github/workflows/deploy.yml` | all 4 repos (same file) | On a merge into `production`: SSH to the server and run `deploy.sh`. |

### Branches

```
feature work ──push──▶ development ──PR (CI green)──▶ production ──auto──▶ server
                       (default branch)               (protected)
```

- `development`: you push here directly. CI runs on every push.
- `production`: nobody pushes here, not even you. The only way in is a PR from `development` with CI green. A merge is what deploys.

### What happens on a release

1. You merge a PR into `production` in any one repo.
2. GitHub Actions starts the **Deploy** workflow in that repo.
3. It SSHes into the server (using the `DEPLOY_*` secrets) and runs `/opt/docmind/deploy.sh`.
4. `deploy.sh` takes a lock (one deploy at a time), then pulls `production` of all four repos (`/opt/docmind`, plus the three service folders inside it).
5. `docker compose ... --profile proxy up -d --build` rebuilds only what changed. The `migrate` container applies new database migrations first, then API, worker and web restart.
6. `deploy.sh` waits for `https://<DOMAIN>/api/v1/health` and fails the workflow if the API doesn't come up within 5 minutes.

A merge in one repo redeploys the whole stack from each repo's current `production`, so merging in just one repo is enough. Repos you didn't change stay as they were.

### Layout on the server

```
/opt/docmind                      <- the `docmind` repo (production branch)
├── docker-compose.prod.yml, Caddyfile, deploy.sh, ...
├── .env.prod                     <- secrets, created by hand, never in git
├── docmind-web-service/          <- cloned by deploy.sh (production branch)
├── docmind-api-service/
└── docmind-ai-service/
```

Docker volumes hold the data: `docmind_pgdata` (database), `docmind_storage` (uploaded files), `docmind_redisdata`, `caddy_data` (the HTTPS certificates). Only Caddy listens publicly (ports 80 and 443). Postgres, Redis and the AI service are never published.

### Secrets: what goes where

| Secret | Where it lives |
|---|---|
| `POSTGRES_PASSWORD`, `JWT_SECRET`, `INTERNAL_API_KEY`, `OPENAI_API_KEY` | `/opt/docmind/.env.prod` on the server only |
| `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_SSH_KEY` | GitHub Actions secrets, in all four repos |
| The deploy key's public half | `~/.ssh/authorized_keys` on the server |

The repos are public, so nothing secret is ever committed. GitHub does not expose Actions secrets to workflows run from forks.

### Doing it later: the order

1. **Release the code:** PR `development` to `production` in each service repo, wait for green, merge. (Deploy passes with a notice, since no server is set up yet.)
2. **Create the server** (Ubuntu, 2 GB RAM or more, ports 22/80/443 open) and note its IP. Address without a domain: the IP with dashes + `.sslip.io`.
3. **Run `setup-server.sh`** on it, fill in `/opt/docmind/.env.prod`, run `/opt/docmind/deploy.sh` once, open the site, register, make yourself admin.
4. **Turn on automatic deploys:** create the deploy key, install its public half on the server, add the three `DEPLOY_*` secrets to all four repos.
5. From then on: work on `development`, release by PR into `production`.

Exact commands for steps 2-4 are in `CLAUDE.md` ("Deploy to a server" and "Branches and automatic deploys").

### If something goes wrong

- Deploy workflow red: open the run in the repo's Actions tab; the last lines are `deploy.sh`'s output.
- Site down after a deploy: `cd /opt/docmind && docker compose --env-file .env.prod -f docker-compose.prod.yml --profile proxy ps` and `logs -f api worker ai`.
- Roll back: open a PR on GitHub that reverts the bad merge into `production` and merge it. The deploy then runs again with the old code. (Editing the server by hand doesn't stick, because `deploy.sh` always resets each repo to `origin/production`.)
- Database migrations only go forward. Back up `docmind_pgdata` before a release that changes the schema.
