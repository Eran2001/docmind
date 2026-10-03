# DocMind

**Ask questions about your own documents and get answers you can verify.**

DocMind lets you upload PDFs, Word files, text, Markdown or web pages into collections, then chat with them in plain language.
The AI answers **only from your documents** and cites the exact page and passage behind every claim. If your documents don't
contain the answer, it says so instead of guessing.

It is a full-stack AI project (retrieval-augmented generation, "RAG"): three services that work together.

## What problem it solves

People have a lot of documents (policies, contracts, manuals, research papers, meeting notes) and waste time hunting for one answer
inside them. Keyword search misses answers that use different words. A general chatbot doesn't know your files, and when it doesn't
know, it can invent a confident answer with no way to check it.

DocMind searches your documents by meaning **and** by keyword, hands the best passages to the AI model, and makes it answer from
those passages only, with citations you can open.

## Who it's for

- **Small businesses and HR teams:** staff ask the handbook instead of messaging HR.
- **Support teams:** answers from product manuals and FAQs, with the page to quote to a customer.
- **Students and researchers:** ask questions across papers and see which paper said what.
- **Freelancers and consultants:** query a client's contracts, briefs and reports.
- **Finance or legal admins:** find clauses and figures across long documents.

## How a customer uses it

1. **Create a collection**, a folder for one topic (for example "HR policies").
2. **Add documents:** drag in PDFs, Word files, text or Markdown, or paste a web page address. Wait for each one to say Ready.
3. **Ask questions**, then follow-ups ("what about contractors?").
4. **Check the source:** click a citation to read the exact passage and page.
5. **Optional:** rate answers, and run an eval set (test questions with known answers) to see whether quality improves or drops
   after you change documents or settings.

Don't want to sign up first? **Try the demo** on the landing page gives you a private sandbox with sample documents
(5 questions and 1 upload; changing the account and creating or deleting collections are switched off).

## What it isn't (yet)

- One person per account: collections can't be shared with a team, and there are no company roles.
- Upload only: no Google Drive, Notion, email or Slack import, and no sync.
- Limits: 20 MB per file and 50 documents per collection. Scanned PDFs without text won't work (there is no OCR).
- Answer quality depends on the model you configure: a small local model (Ollama `llama3.2`) is decent, a stronger one is better.

## The three services

| Service | Folder                | Stack                                   | Job                                                                                         |
| ------- | --------------------- | --------------------------------------- | ------------------------------------------------------------------------------------------- |
| Web     | `docmind-web-service` | Next.js, TypeScript, Tailwind, TanStack | The UI: sign-in, collections, uploads, chat with citations, evals, usage                    |
| API     | `docmind-api-service` | NestJS, Postgres + pgvector, Redis      | Users, data and auth; background jobs; chat orchestration. The only service with a database |
| AI      | `docmind-ai-service`  | Python, FastAPI                         | Parsing, chunking, embeddings, model calls, judging. Internal and stateless                 |

The browser only talks to the API; the API talks to the AI service with an internal key. Each folder has its own README with the
details (endpoints, configuration, decisions), and a `CLAUDE.md` with the rules for working in it.

## Run it locally

You need Node 22+, Docker, and [uv](https://docs.astral.sh/uv/) for Python. For answers you also need a model: a local one through
[Ollama](https://ollama.com) (`ollama pull llama3.2`), or an OpenAI key (see `docmind-ai-service/config/.env.example`).

```bash
# one-time setup
cd docmind-api-service && npm install && cp .env.example .env     # set JWT_SECRET and INTERNAL_API_KEY
cd ../docmind-web-service && npm install                            # copy .env.example to .env
cd ../docmind-ai-service && uv sync && cp config/.env.example config/.env   # INTERNAL_API_KEY must match the API's

# start everything: Postgres + Redis, AI service, API, worker, web
./dev.sh

# in another terminal, once: create tables and the sample data used by "Try the demo"
cd docmind-api-service && npm run db:migrate && npm run db:seed
```

Open http://localhost:3000. The web app is on `:3000`, the API on the port in its `.env`, and the AI service on `:8000`.
`INTERNAL_API_KEY` must be the **same value** in the API's `.env` and the AI service's `config/.env`.

## Quality checks

GitHub Actions (`.github/workflows/ci.yml`) runs on every push and pull request: the API (typecheck, lint, tests against real
Postgres and Redis, build), the web app (typecheck, lint, build) and the AI service (ruff, mypy, pytest).

## Deploy with Docker

`docker-compose.prod.yml` runs the whole stack: Postgres (pgvector), Redis, the AI service, the API, the worker and the web app, plus an optional Caddy proxy for HTTPS. The database, Redis and the AI service stay on the private network, and migrations run automatically before the API and worker start.

### Try it on your machine

```bash
cp .env.prod.example .env.prod        # fill in the secrets (openssl rand -hex 32)
# for a local trial set: NEXT_PUBLIC_SITE_URL=http://localhost:3000, NEXT_PUBLIC_API_URL=http://localhost:4000/api/v1,
# WEB_ORIGIN=http://localhost:3000, TRUST_PROXY=false
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

Open http://localhost:3000. This stack has its own empty database, separate from `./dev.sh`.

### On a server (one small VPS)

1. Create an Ubuntu server (2 GB RAM or more), open ports 22, 80 and 443 in its firewall, and install Docker (`curl -fsSL https://get.docker.com | sh`).
2. Point a name at it. With a domain, add an A record to the server's IP. Without one, use `<ip-with-dashes>.sslip.io` (IP `203.0.113.7` becomes `203-0-113-7.sslip.io`).
3. Copy the project to the server (git clone or rsync), then `cp .env.prod.example .env.prod` and set the secrets, `OPENAI_API_KEY`, `DOMAIN`, the three URLs (all `https://<DOMAIN>`, API URL ending `/api/v1`) and `TRUST_PROXY=true`.
4. Chat models: the defaults use OpenAI (`gpt-5` / `gpt-5-mini`). The server has no Ollama, so remove the `LLM_BASE_URL` / `llama3.2` lines.
5. Start it: `docker compose --env-file .env.prod -f docker-compose.prod.yml --profile proxy up -d --build`. Caddy gets the HTTPS certificate by itself on the first request.
6. Register in the app, then make yourself admin: `docker compose --env-file .env.prod -f docker-compose.prod.yml exec postgres psql -U docmind -d docmind -c "update users set role='admin' where email='you@example.com'"`.

Web and API share one address (Caddy sends `/api/v1` to the API), so the refresh cookie and CORS just work. Update with `git pull` and the same `up -d --build`.

- `NEXT_PUBLIC_*` values are baked into the web bundle at build time, so changing them means rebuilding.
- Uploaded files live in the `storage` volume and the database in `pgdata`: back both up (`docker run --rm -v docmind_pgdata:/d -v "$PWD":/b alpine tar czf /b/pgdata.tgz -C /d .`, same for `docmind_storage`).
- Old `.doc` files need LibreOffice in the AI image: set `WITH_LIBREOFFICE=true` and rebuild (adds ~500 MB).
