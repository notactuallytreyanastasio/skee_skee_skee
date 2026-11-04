# The host relay

The App Store build can't carry the DeepSeek key, because anything in an app
can be read out of a downloaded copy. This holds the key and forwards haggles.
The model, reply size and conversation size are fixed here, each address gets
40 requests per 10 minutes, and the whole relay gets 5000 a day. Over a limit it
returns 429 and the app's scripted host answers. Chat text is never logged.

Anyone can still call it, since a token in the app would be as readable as the
key. The limits are what bound the bill. App Attest is the next step if that
stops being enough.

    node --test relay/relay.test.mjs
    DEEPSEEK_API_KEY=... PORT=8799 node relay/relay.mjs
    skee haggle --first --relay http://127.0.0.1:8799/chat

## First-time setup on the box

In `/opt/blog/docker-compose.yml`, beside `slides-relay`:

```yaml
  skee-relay:
    image: node:24-alpine
    restart: always
    working_dir: /app
    command: ["node", "relay.mjs"]
    environment:
      PORT: "8788"
      DEEPSEEK_API_KEY: ${DEEPSEEK_API_KEY}
    expose:
      - "8788"
    volumes:
      - /opt/skee-relay:/app:ro
```

In `/opt/blog/Caddyfile`, inside the `bobbby.online` site, before the Phoenix
fallback:

```
	handle_path /skee-host/* {
		reverse_proxy skee-relay:8788 {
			header_up X-Real-IP {client_ip}
		}
	}
```

It shares the stack's `DEEPSEEK_API_KEY` with marginalia. Run `relay/deploy.sh`,
`docker compose up -d --no-deps skee-relay`, and reload Caddy.
