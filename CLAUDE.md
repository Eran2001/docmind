# DocMind: deploy guide (follow this when deploying)

Three services, one Docker stack: `docmind-web-service` (Next.js), `docmind-api-service` (NestJS API + worker), `docmind-ai-service` (FastAPI).
`docker-compose.prod.yml` (repo root) runs them with Postgres (pgvector), Redis and an optional Caddy proxy for HTTPS.
Each service still runs on its own for development (`./dev.sh` starts everything locally); this file is only about deploying.

## Two separate databases (don't mix them up)

| | Dev (`./dev.sh`) | Docker stack (`docker-compose.prod.yml`) |
|---|---|---|
| Postgres container | `docmind-postgres` | `docmind-postgres-1` |
| On your Mac | port 5432 | not published |
| Data | your real accounts and collections | starts empty |
| Uploaded files | `docmind-api-service/storage` | Docker volume `docmind_storage` |

Both want ports 3000 and 4000, so run only one at a time.

## 1. Try it on your machine first

```bash
cp .env.prod.example .env.prod
```

Fill in `.env.prod`:

```
POSTGRES_PASSWORD=<openssl rand -hex 32>
JWT_SECRET=<openssl rand -hex 32>
INTERNAL_API_KEY=<openssl rand -hex 32>
OPENAI_API_KEY=<your key>
NEXT_PUBLIC_SITE_URL=http://localhost:3000
NEXT_PUBLIC_API_URL=http://localhost:4000/api/v1
WEB_ORIGIN=http://localhost:3000
TRUST_PROXY=false
```

Optional, chat on your Mac's Ollama instead of OpenAI (embeddings still use the OpenAI key):

```
LLM_BASE_URL=http://host.docker.internal:11434/v1
LLM_API_KEY=ollama
LLM_MODEL=llama3.2
LLM_FAST_MODEL=llama3.2
```

Stop `./dev.sh` (Ctrl+C), then:

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

Open http://localhost:3000, register a NEW account (the database is empty).
Stop: `docker compose --env-file .env.prod -f docker-compose.prod.yml down` (add `-v` to wipe its data).
Always pass `--env-file .env.prod`; without it Compose reads the notes file `docmind/.env` and fails.

## 2. Deploy to a server (one small VPS + HTTPS)

Web and API share ONE address: Caddy (`Caddyfile`) sends `/api/v1` to the API and everything else to the web app.
So the refresh cookie and CORS just work, and you don't need `app.` / `api.` subdomains or to buy a domain.

1. **Server.** Ubuntu VPS, 2 GB RAM or more (Hetzner, DigitalOcean, Lightsail, about $6-12/mo). In its firewall open ports 22, 80 and 443.
   Install Docker: `curl -fsSL https://get.docker.com | sh`.
2. **Address.** With a domain: add an A record to the server's IP. Without one: use the IP with dashes + `.sslip.io`
   (IP `203.0.113.7` becomes `203-0-113-7.sslip.io`). It is free and Caddy gets an HTTPS certificate for it.
3. **Set the server up once** (as your normal user, not root):
   `curl -fsSL https://raw.githubusercontent.com/Eran2001/docmind/production/setup-server.sh | bash`
   It installs Docker and clones this repo to `/opt/docmind`. Log out and back in once so the docker group applies.
4. **Fill in `/opt/docmind/.env.prod`** (`nano /opt/docmind/.env.prod`):
   - fresh secrets: `POSTGRES_PASSWORD`, `JWT_SECRET`, `INTERNAL_API_KEY` (`openssl rand -hex 32` each) and `OPENAI_API_KEY`
   - `DOMAIN=<address>` (no `https://`)
   - `NEXT_PUBLIC_SITE_URL=https://<address>`, `NEXT_PUBLIC_API_URL=https://<address>/api/v1`, `WEB_ORIGIN=https://<address>`
   - `TRUST_PROXY=true` (Caddy sits in front, so rate limits see the real client IP)
   - Chat models: defaults are OpenAI `gpt-5` / `gpt-5-mini` (costs tokens). The server has no Ollama, so DELETE the `LLM_BASE_URL` / `llama3.2` lines.
5. **First deploy:** `/opt/docmind/deploy.sh`. It pulls the three service repos (branch `production`), builds, starts everything with HTTPS and waits for the health check. Open `https://<address>`.
6. **Make yourself admin** (after registering in the app):
   ```bash
   docker compose --env-file .env.prod -f docker-compose.prod.yml exec postgres psql -U docmind -d docmind -c "update users set role='admin' where email='you@example.com'"
   ```
   Then sign out and back in.

## Branches and automatic deploys

Four public repos on GitHub (account Eran2001): `docmind-web-service`, `docmind-api-service`, `docmind-ai-service` and `docmind` (this one: compose file, Caddyfile, deploy scripts, guides).
Each has `development` (default, where you work and push directly) and `production` (protected: no direct push, only a PR from `development` with CI green).

```
work + push on development ──PR──▶ production ──auto──▶ GitHub Actions "Deploy" ──SSH──▶ /opt/docmind/deploy.sh on the server
```

`deploy.sh` brings all four repos to their `production` branch and rebuilds, so merging in ANY one repo deploys the whole stack. You can also run it by hand on the server, or trigger "Deploy" from a repo's Actions tab.

**One-time: the deploy key and secrets.**
1. On your Mac: `ssh-keygen -t ed25519 -f ~/deploy_key -N "" -C docmind-deploy`
2. Put the PUBLIC key on the server: `ssh-copy-id -i ~/deploy_key.pub <user>@<server>` (or append it to `~/.ssh/authorized_keys` there).
3. In ALL FOUR repos (Settings → Secrets and variables → Actions) add `DEPLOY_HOST` (server IP or name), `DEPLOY_USER` (the SSH user) and `DEPLOY_SSH_KEY` (the whole PRIVATE key file). Or per repo: `gh secret set DEPLOY_SSH_KEY -R Eran2001/<repo> < ~/deploy_key`.
4. Delete the private key from your Mac afterwards (or keep it somewhere safe). Never commit it.

Until `DEPLOY_HOST` exists, the Deploy workflow just prints a notice and succeeds, so merging before the server exists is harmless.

## Day-to-day on the server

- Update: `git pull`, then the same `up -d --build` command.
- Logs: `docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f api worker ai`.
- Health: `curl https://<address>/api/v1/health` shows db / redis / ai as `up`.
- Uploads stuck in Queued: check the worker and AI logs.
- Changing any `NEXT_PUBLIC_*` value means rebuilding the web image (`up -d --build`): they are baked into the bundle.
- Backups: the database is in volume `docmind_pgdata`, uploaded files in `docmind_storage`. Back up both, for example
  `docker run --rm -v docmind_pgdata:/d -v "$PWD":/b alpine tar czf /b/pgdata.tgz -C /d .` (same for `docmind_storage`).
- Old `.doc` files need LibreOffice in the AI image: set `WITH_LIBREOFFICE=true` in `.env.prod` and rebuild (adds ~500 MB).

## Rules

- Never commit `.env.prod` (it is in `.gitignore`) and never paste its contents anywhere.
- Only Caddy (80/443) is public. Web and API ports are bound to localhost, and Postgres, Redis and the AI service are not published at all.
- The AI service is internal: it is only reachable from the API with the `X-Internal-Key` header.
- `INTERNAL_API_KEY` is shared by the API and the AI service; both get it from the same `.env.prod`, so they always match.

## Not verified yet

- The Docker stack was checked with health checks and a page load on a Mac; a full upload + chat through it was not clicked through.
- The Caddy proxy config is valid but has not been run against a real certificate on a real server.
