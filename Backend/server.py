#!/usr/bin/env python3
import hmac
import json
import mimetypes
import os
import socket
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib import error as urlerror
from urllib import request as urlrequest
from urllib.parse import parse_qs, quote, urljoin, urlparse


SUPPORTED_EXTENSIONS = {".gif", ".jpg", ".jpeg", ".mp4", ".mov", ".m4v", ".png", ".webm"}
MAX_REQUEST_BYTES = int(os.environ.get("MEMEDROP_MAX_REQUEST_BYTES", "8192"))
REQUEST_SLOTS = threading.BoundedSemaphore(
    max(1, int(os.environ.get("MEMEDROP_MAX_CONCURRENT_REQUESTS", "2")))
)


def json_response(
    *,
    status: str,
    media_url: str | None = None,
    filename: str | None = None,
    mime_type: str | None = None,
    job_id: str | None = None,
    error_message: str | None = None,
):
    return {
        "status": status,
        "mediaURL": media_url,
        "filename": filename,
        "mimeType": mime_type,
        "jobID": job_id,
        "errorMessage": error_message,
    }


def env_flag(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def cobalt_api_url() -> str:
    return os.environ.get("MEMEDROP_COBALT_API_URL", "http://127.0.0.1:9000/").strip()


def fetch_port() -> int:
    return int(os.environ.get("MEMEDROP_FETCH_PORT") or os.environ.get("PORT", "8080"))


def request_is_authorized(authorization: str | None) -> bool:
    expected = os.environ.get("MEMEDROP_API_KEY", "").strip()
    if not expected:
        return True

    scheme, separator, provided = (authorization or "").partition(" ")
    return (
        separator == " "
        and scheme.lower() == "bearer"
        and hmac.compare_digest(provided.strip(), expected)
    )


def cobalt_is_reachable() -> bool:
    parsed = urlparse(cobalt_api_url())
    if not parsed.hostname:
        return False

    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    try:
        with socket.create_connection((parsed.hostname, port), timeout=1):
            return True
    except OSError:
        return False


def cobalt_public_url() -> str:
    return os.environ.get("MEMEDROP_COBALT_PUBLIC_URL", cobalt_api_url()).strip()


def cobalt_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/json",
        "Content-Type": "application/json",
        "User-Agent": "MemeDropFetch/0.2",
    }

    authorization = os.environ.get("MEMEDROP_COBALT_AUTHORIZATION", "").strip()
    api_key = os.environ.get("MEMEDROP_COBALT_API_KEY", "").strip()
    if authorization:
        headers["Authorization"] = authorization
    elif api_key:
        headers["Authorization"] = f"Api-Key {api_key}"

    return headers


def cobalt_request_payload(url: str) -> dict[str, object]:
    payload: dict[str, object] = {
        "url": url,
        "downloadMode": os.environ.get("MEMEDROP_COBALT_DOWNLOAD_MODE", "auto"),
        "filenameStyle": os.environ.get("MEMEDROP_COBALT_FILENAME_STYLE", "basic"),
        "alwaysProxy": env_flag("MEMEDROP_COBALT_ALWAYS_PROXY", False),
    }

    video_quality = os.environ.get("MEMEDROP_COBALT_VIDEO_QUALITY", "").strip()
    if video_quality:
        payload["videoQuality"] = video_quality

    audio_format = os.environ.get("MEMEDROP_COBALT_AUDIO_FORMAT", "").strip()
    if audio_format:
        payload["audioFormat"] = audio_format

    return payload


def guess_mime_type(filename: str | None, media_url: str | None) -> str:
    for candidate in (filename, media_url):
        if not candidate:
            continue
        mime_type, _ = mimetypes.guess_type(candidate)
        if mime_type:
            return mime_type
    return "application/octet-stream"


def choose_extension(item_type: str | None) -> str:
    if item_type == "gif":
        return ".gif"
    if item_type == "photo":
        return ".jpg"
    return ".mp4"


def filename_from_value(value: str | None, *, fallback_stem: str = "download", fallback_extension: str = "") -> str:
    if value:
        parsed = urlparse(value)
        name = os.path.basename(parsed.path)
        if name:
            return name
    return f"{fallback_stem}{fallback_extension}"


def direct_media_response(url: str):
    parsed = urlparse(url)
    _, ext = os.path.splitext(parsed.path.lower())
    if ext not in SUPPORTED_EXTENSIONS:
        return None

    filename = os.path.basename(parsed.path) or f"download{ext}"
    mime_type = guess_mime_type(filename, url)
    return json_response(status="ready", media_url=url, filename=filename, mime_type=mime_type)


def cobalt_error_message(payload: dict) -> str:
    error_payload = payload.get("error") or {}
    if isinstance(error_payload, dict):
        code = error_payload.get("code", "unknown")
        context = error_payload.get("context")
        if isinstance(context, dict) and context:
            return f"cobalt error: {code} ({json.dumps(context, sort_keys=True)})"
        return f"cobalt error: {code}"
    return "cobalt returned an unknown error."


def cobalt_origin() -> str:
    parsed = urlparse(cobalt_public_url())
    return f"{parsed.scheme}://{parsed.netloc}"


def cobalt_path_prefix() -> str:
    parsed = urlparse(cobalt_public_url())
    return parsed.path.rstrip("/")


def build_proxy_url(base_url: str, target_url: str) -> str:
    return f"{base_url}/proxy?target={quote(target_url, safe='')}"


def normalize_cobalt_response(payload: dict, *, proxy_base_url: str):
    response_status = payload.get("status")

    if response_status in {"redirect", "tunnel"}:
        original_url = payload.get("url")
        media_url = original_url
        if response_status == "tunnel" and isinstance(original_url, str):
            media_url = build_proxy_url(proxy_base_url, original_url)
        filename = payload.get("filename") or filename_from_value(original_url if isinstance(original_url, str) else media_url)
        return json_response(
            status="ready",
            media_url=media_url,
            filename=filename,
            mime_type=guess_mime_type(filename, original_url if isinstance(original_url, str) else media_url),
        )

    if response_status == "picker":
        picker = payload.get("picker")
        if not isinstance(picker, list) or not picker:
            return json_response(status="failed", error_message="cobalt returned an empty media picker.")

        # The current app only imports one item per shared URL, so pick the first asset.
        first_item = next((item for item in picker if isinstance(item, dict) and item.get("url")), None)
        if not first_item:
            return json_response(status="failed", error_message="cobalt did not provide a downloadable picker item.")

        item_type = first_item.get("type")
        media_url = first_item.get("url")
        extension = choose_extension(item_type if isinstance(item_type, str) else None)
        filename = filename_from_value(media_url, fallback_stem="download", fallback_extension=extension)
        return json_response(
            status="ready",
            media_url=media_url,
            filename=filename,
            mime_type=guess_mime_type(filename, media_url),
        )

    if response_status == "local-processing":
        output = payload.get("output") if isinstance(payload.get("output"), dict) else {}
        filename = output.get("filename") if isinstance(output, dict) else None
        mime_type = output.get("type") if isinstance(output, dict) else None
        return json_response(
            status="failed",
            filename=filename if isinstance(filename, str) else None,
            mime_type=mime_type if isinstance(mime_type, str) else None,
            error_message="This link requires cobalt local processing, which MemeDrop does not support yet.",
        )

    if response_status == "error":
        return json_response(status="failed", error_message=cobalt_error_message(payload))

    return json_response(status="failed", error_message=f"Unsupported cobalt response status: {response_status}")


def resolve_via_cobalt(url: str):
    request_body = json.dumps(cobalt_request_payload(url)).encode("utf-8")
    request = urlrequest.Request(
        cobalt_api_url(),
        data=request_body,
        headers=cobalt_headers(),
        method="POST",
    )
    timeout = float(os.environ.get("MEMEDROP_COBALT_TIMEOUT", "30"))

    try:
        with urlrequest.urlopen(request, timeout=timeout) as response:
            payload = json.loads(response.read() or b"{}")
    except urlerror.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(body)
        except json.JSONDecodeError:
            payload = None

        if isinstance(payload, dict):
            return normalize_cobalt_response(payload, proxy_base_url="")
        return json_response(status="failed", error_message=f"cobalt request failed with HTTP {exc.code}: {body or exc.reason}")
    except urlerror.URLError as exc:
        return json_response(status="failed", error_message=f"Unable to reach cobalt at {cobalt_api_url()}: {exc.reason}")
    except TimeoutError:
        return json_response(status="failed", error_message="Timed out while waiting for cobalt to resolve the link.")

    if not isinstance(payload, dict):
        return json_response(status="failed", error_message="cobalt returned an invalid response body.")
    return payload


class Handler(BaseHTTPRequestHandler):
    server_version = "MemeDropFetch/0.2"

    def do_POST(self):
        if self.path != "/resolve":
            self.respond({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)
            return

        if not self.authorize():
            return

        if not REQUEST_SLOTS.acquire(blocking=False):
            self.respond({"error": "Service busy"}, status=HTTPStatus.TOO_MANY_REQUESTS)
            return

        try:
            self.resolve_media()
        finally:
            REQUEST_SLOTS.release()

    def resolve_media(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length > MAX_REQUEST_BYTES:
            self.respond({"error": "Request body too large"}, status=HTTPStatus.REQUEST_ENTITY_TOO_LARGE)
            return

        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            self.respond({"error": "Invalid JSON payload"}, status=HTTPStatus.BAD_REQUEST)
            return

        raw_url = str(payload.get("url", "")).strip()
        if not raw_url:
            self.respond({"error": "Missing url"}, status=HTTPStatus.BAD_REQUEST)
            return

        resolved = direct_media_response(raw_url)
        if resolved is None:
            cobalt_payload = resolve_via_cobalt(raw_url)
            if "mediaURL" in cobalt_payload:
                resolved = cobalt_payload
            else:
                resolved = normalize_cobalt_response(cobalt_payload, proxy_base_url=self.public_base_url())
        self.respond(resolved)

    def do_GET(self):
        if self.path == "/":
            cobalt_url = cobalt_api_url()
            self.respond(
                {
                    "service": "MemeDrop fetch service",
                    "resolver": "cobalt",
                    "cobaltAPIURL": cobalt_url,
                }
            )
            return

        if self.path.startswith("/proxy"):
            if not self.authorize():
                return
            if not REQUEST_SLOTS.acquire(blocking=False):
                self.respond({"error": "Service busy"}, status=HTTPStatus.TOO_MANY_REQUESTS)
                return
            try:
                self.proxy_media()
            finally:
                REQUEST_SLOTS.release()
            return

        if self.path.startswith("/jobs/"):
            job_id = self.path.split("/")[-1]
            self.respond(
                json_response(
                    status="failed",
                    job_id=job_id,
                    error_message="This resolver no longer creates async jobs. Re-share the original link to retry it.",
                )
            )
            return

        if self.path == "/health":
            if cobalt_is_reachable():
                self.respond({"status": "ok"})
            else:
                self.respond({"status": "starting"}, status=HTTPStatus.SERVICE_UNAVAILABLE)
            return

        self.respond({"error": "Not found"}, status=HTTPStatus.NOT_FOUND)

    def log_message(self, format, *args):
        return

    def authorize(self) -> bool:
        if request_is_authorized(self.headers.get("Authorization")):
            return True
        self.respond(
            {"error": "Unauthorized"},
            status=HTTPStatus.UNAUTHORIZED,
            headers={"WWW-Authenticate": "Bearer"},
        )
        return False

    def public_base_url(self) -> str:
        host = self.headers.get("Host")
        if not host:
            host = f"{self.server.server_address[0]}:{self.server.server_address[1]}"
        proto = self.headers.get("X-Forwarded-Proto", "http")
        return f"{proto}://{host}"

    def proxy_media(self):
        query = parse_qs(urlparse(self.path).query)
        target = (query.get("target") or [""])[0]
        if not target:
            self.respond({"error": "Missing target"}, status=HTTPStatus.BAD_REQUEST)
            return

        parsed_target = urlparse(target)
        if f"{parsed_target.scheme}://{parsed_target.netloc}" != cobalt_origin():
            self.respond({"error": "Unsupported proxy target"}, status=HTTPStatus.BAD_REQUEST)
            return
        prefix = cobalt_path_prefix()
        if prefix and not parsed_target.path.startswith(f"{prefix}/") and parsed_target.path != prefix:
            self.respond({"error": "Unsupported proxy path"}, status=HTTPStatus.BAD_REQUEST)
            return

        headers = {"User-Agent": "MemeDropFetch/0.2"}
        authorization = cobalt_headers().get("Authorization")
        if authorization:
            headers["Authorization"] = authorization

        request = urlrequest.Request(target, headers=headers, method="GET")
        try:
            with urlrequest.urlopen(request, timeout=60) as response:
                self.send_response(response.status)
                for header in ("Content-Type", "Content-Length", "Content-Disposition", "Accept-Ranges", "ETag", "Last-Modified"):
                    value = response.headers.get(header)
                    if value:
                        self.send_header(header, value)
                self.end_headers()
                while True:
                    chunk = response.read(64 * 1024)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
        except urlerror.HTTPError as exc:
            self.respond({"error": f"Upstream cobalt proxy failed with HTTP {exc.code}"}, status=HTTPStatus.BAD_GATEWAY)
        except urlerror.URLError as exc:
            self.respond({"error": f"Unable to reach cobalt proxy target: {exc.reason}"}, status=HTTPStatus.BAD_GATEWAY)

    def respond(self, payload, status=HTTPStatus.OK, headers=None):
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    host = os.environ.get("MEMEDROP_FETCH_HOST", "0.0.0.0")
    port = fetch_port()
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"MemeDrop fetch service listening on http://{host}:{port}")
    print(f"Proxying supported links to cobalt at {urljoin(cobalt_api_url(), '/')}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
