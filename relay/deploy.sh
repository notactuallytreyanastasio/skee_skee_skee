#!/bin/bash
# Copy the relay to the Hetzner box and restart it. Like slides-relay it's
# bind-mounted, not built. First-time setup (the compose service, the Caddy
# route and the key) is in relay/README.md.
set -euo pipefail
HOST="${DEPLOY_HOST:-root@5.161.181.91}"
cd "$(dirname "$0")"
rsync -a relay.mjs "$HOST:/opt/skee-relay/"
ssh "$HOST" 'cd /opt/blog && docker compose restart skee-relay'
sleep 2
curl -fsS https://bobbby.online/skee-host/health && echo " relay is up"
