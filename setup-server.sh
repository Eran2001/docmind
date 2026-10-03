#!/usr/bin/env bash
# Run ONCE on a fresh Ubuntu server, as the user that will deploy (not root):
#   curl -fsSL https://raw.githubusercontent.com/Eran2001/docmind/production/setup-server.sh | bash
set -euo pipefail

if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
fi

sudo mkdir -p /opt/docmind
sudo chown "$USER":"$USER" /opt/docmind
if [ ! -d /opt/docmind/.git ]; then
  git clone --branch production https://github.com/Eran2001/docmind.git /opt/docmind
fi
cd /opt/docmind
[ -f .env.prod ] || cp .env.prod.example .env.prod
chmod +x deploy.sh

cat <<'MSG'

Server is ready. Next:
  1. Log out and back in once (so the docker group applies).
  2. Edit /opt/docmind/.env.prod: secrets, OPENAI_API_KEY, DOMAIN and the URLs (see CLAUDE.md).
  3. Run /opt/docmind/deploy.sh once to start everything.
  4. Add the GitHub secrets for automatic deploys (see CLAUDE.md, "Automatic deploys").
MSG
