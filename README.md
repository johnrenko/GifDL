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

## Signing and App Group setup

The project uses the App Group `group.dev.jd.memedrop` and default bundle IDs under `dev.jd.*`. For device installs or a fully working signed simulator build, update the signing team in `project.yml` or in Xcode after generation.

If your Mac's LAN IP changes, either update `Shared/Sources/AppConfiguration.swift` or override it at launch with `MEMEDROP_FETCH_BASE_URL`.

If a real-device share seems to succeed but nothing appears in the app, the most likely cause is a broken App Group entitlement. The app now surfaces that condition explicitly; in Xcode, verify that both `MemeDrop` and `MemeDropShareExtension` are signed with the same team and both include the exact same App Group.
