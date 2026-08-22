# MemeDrop

MemeDrop is a greenfield SwiftUI iPhone app plus share extension for saving GIFs and short videos into a local meme library, then re-sharing them anywhere.

## Workspace layout

- `project.yml`: XcodeGen spec for the app target, share extension, and tests.
- `App/`: SwiftUI app shell, list/detail UI, and share sheet wrapper.
- `ShareExtension/`: share extension that accepts files or URLs and writes pending imports into the App Group container.
- `Shared/`: models, persistence, import processing, and fetch service client used by both targets.
- `Backend/server.py`: standalone fetch service implementing `POST /resolve` and translating cobalt responses into the app's existing fetch contract.
- `scripts/build_and_launch.sh`: CLI-first generate/build/launch workflow.

## Build

```bash
xcodegen generate
./scripts/build_and_launch.sh
./scripts/build_and_launch.sh --launch
```

The script defaults to `iPhone 17 Pro` on iOS `26.4` and builds with `CODE_SIGNING_ALLOWED=NO` for simulator validation.

## Fetch service

Start a local cobalt instance first, then run the MemeDrop fetch service before testing URL-based imports:

```bash
docker run --rm -p 9000:9000 -e API_URL=http://127.0.0.1:9000/ ghcr.io/imputnet/cobalt:11
python3 Backend/server.py
```

By default the backend listens on all interfaces at port `8080`, expects cobalt at `http://127.0.0.1:9000/`, and the iOS app defaults to `http://192.168.1.97:8080` for device testing on your local network.

The backend still resolves direct media URLs immediately, but non-direct platform links are now sent to a self-hosted cobalt instance. Useful environment variables:

```bash
MEMEDROP_COBALT_API_URL=http://127.0.0.1:9000/
MEMEDROP_COBALT_API_KEY=...
MEMEDROP_COBALT_AUTHORIZATION="Bearer ..."
MEMEDROP_COBALT_DOWNLOAD_MODE=auto
MEMEDROP_COBALT_ALWAYS_PROXY=false
```

The backend proxies cobalt tunnel downloads back through itself, so a phone talking to `MEMEDROP_FETCH_BASE_URL` does not need separate reachability to the cobalt port. The current app model is still single-item per shared URL, so when cobalt returns a `picker` response for multi-item posts the backend imports the first asset. cobalt `local-processing` responses are surfaced as failed imports until the app gains a local remux/transcode path.

## Internet deployment

The repository now includes a minimal production stack:

- `docker-compose.yml`: runs the Python bridge, a private cobalt instance, and Caddy.
- `Backend/Dockerfile`: container image for the Python bridge.
- `deploy/Caddyfile`: HTTPS reverse proxy for a public domain.
- `.env.production.example`: deployment variables to copy and edit.

Typical VPS flow:

```bash
cp .env.production.example .env.production
# edit .env.production and set MEMEDROP_DOMAIN to your real hostname
docker compose --env-file .env.production up -d --build
```

This stack keeps cobalt private on the Docker network by default. Public traffic terminates at Caddy on ports `80` and `443`, then only the Python bridge is exposed. That is the intended topology for MemeDrop because the app already downloads tunnel media through `/proxy`.

After deploy:

1. Point your DNS record for `MEMEDROP_DOMAIN` at the VPS.
2. Open inbound TCP ports `80` and `443`.
3. Wait for Caddy to provision TLS automatically.
4. Update `MEMEDROP_FETCH_BASE_URL` in the app to `https://your-domain.example`.

### Render Free

Render runs MemeDrop and cobalt together in one container so cobalt stays on
localhost and only the Python bridge is public. The included `render.yaml` uses
the Free web-service plan, the Frankfurt region, and `/health` for health checks.

1. In Render, create a Blueprint from this repository.
2. Review the `memedrop-fetch` service and apply the Blueprint.
3. Wait for `https://<service>.onrender.com/health` to return `{"status": "ok"}`.
4. Copy the generated `MEMEDROP_API_KEY` from Render's Environment page.
5. Set the app's default URL and local API key configuration to the Render values.

Free services sleep after inactivity, so the first request can take around a
minute while the container starts. The filesystem is ephemeral by design: both
the bridge and cobalt stream media without requiring persistent storage.
The generated bearer token protects `/resolve` and `/proxy`; `/health` remains
public so Render can check readiness without exposing the token.

If you decide to expose cobalt separately later, set `MEMEDROP_COBALT_PUBLIC_URL` and `COBALT_API_URL` to that public URL. The backend will then accept cobalt tunnel URLs on that configured public origin as well.

## Signing and App Group setup

The project uses the App Group `group.dev.jd.memedrop` and default bundle IDs under `dev.jd.*`. For device installs or a fully working signed simulator build, update the signing team in `project.yml` or in Xcode after generation.

If your Mac's LAN IP changes, either update `Shared/Sources/AppConfiguration.swift` or override it at launch with `MEMEDROP_FETCH_BASE_URL`.

If a real-device share seems to succeed but nothing appears in the app, the most likely cause is a broken App Group entitlement. The app now surfaces that condition explicitly; in Xcode, verify that both `MemeDrop` and `MemeDropShareExtension` are signed with the same team and both include the exact same App Group.
