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
