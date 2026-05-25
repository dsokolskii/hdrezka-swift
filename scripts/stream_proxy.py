#!/usr/bin/env python3

from __future__ import annotations

import http.client
import socket
import socketserver
import time
from http.server import BaseHTTPRequestHandler
from urllib.parse import SplitResult, urlsplit, urlunsplit


PORT = 8642
USER_AGENT = "Mozilla/5.0 (AppleTV; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko)"
FETCH_ATTEMPTS = 3
RETRY_DELAY_SECONDS = 0.35
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
    "content-encoding",
}


class ThreadingHTTPServer(socketserver.ThreadingMixIn, socketserver.TCPServer):
    allow_reuse_address = True
    daemon_threads = True


class ProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        self.forward()

    def do_HEAD(self) -> None:
        self.forward()

    def forward(self) -> None:
        target = self.target_url()
        if target is None:
            self.send_error(400, "Bad proxy path")
            return

        try:
            response = self.fetch_with_retries(target)
        except Exception as error:  # pragma: no cover - runtime diagnostic path
            self.send_error(502, str(error))
            return

        try:
            self.send_response(response.status)
            for name, value in response.getheaders():
                lower_name = name.lower()
                if lower_name in HOP_BY_HOP_HEADERS:
                    continue
                self.send_header(name, value)
            self.end_headers()

            if self.command != "HEAD":
                while True:
                    chunk = response.read(64 * 1024)
                    if not chunk:
                        break
                    try:
                        self.wfile.write(chunk)
                    except (BrokenPipeError, ConnectionResetError):
                        break
        finally:
            response.close()

    def fetch_with_retries(self, target: str):
        last_error = None
        for attempt in range(1, FETCH_ATTEMPTS + 1):
            try:
                return self.fetch(target)
            except (ConnectionRefusedError, TimeoutError, socket.timeout, OSError) as error:
                last_error = error
                print(f"proxy fetch failed attempt={attempt} target={target} error={error}", flush=True)
                if attempt < FETCH_ATTEMPTS:
                    time.sleep(RETRY_DELAY_SECONDS * attempt)

        raise last_error or RuntimeError("fetch failed")

    def fetch(self, target: str, redirects_left: int = 5):
        parts = urlsplit(target)
        connection_class = http.client.HTTPSConnection if parts.scheme == "https" else http.client.HTTPConnection
        connection = connection_class(parts.hostname, parts.port, timeout=30)

        path = parts.path or "/"
        if parts.query:
            path += f"?{parts.query}"

        headers = {
            "User-Agent": USER_AGENT,
            "Accept": self.headers.get("Accept", "*/*"),
            "Referer": "https://rezka.fi/",
            "Origin": "https://rezka.fi",
            "Host": parts.netloc,
        }

        range_header = self.headers.get("Range") or "bytes=0-"
        headers["Range"] = range_header

        connection.request(self.command, path, headers=headers)
        response = connection.getresponse()

        if response.status in {301, 302, 303, 307, 308} and redirects_left > 0:
            location = response.getheader("Location")
            if location:
                redirect_target = self.resolve_redirect(parts, location)
                response.read()
                response.close()
                return self.fetch(redirect_target, redirects_left - 1)

        return response

    def resolve_redirect(self, current: SplitResult, location: str) -> str:
        redirect = urlsplit(location)
        if redirect.scheme:
            return location

        scheme = current.scheme
        netloc = current.netloc
        path = redirect.path or current.path
        query = redirect.query
        return urlunsplit((scheme, netloc, path, query, redirect.fragment))

    def target_url(self) -> str | None:
        parts = self.path.split("?", 1)
        path = parts[0]
        query = parts[1] if len(parts) == 2 else ""
        path_parts = path.split("/", 3)
        if len(path_parts) < 4:
            return None

        _, scheme, host, remainder = path_parts
        if not scheme or not host:
            return None

        target = f"{scheme}://{host}/{remainder}"
        if query:
            target += f"?{query}"
        return target

    def log_message(self, format: str, *args) -> None:
        print(f"proxy {self.address_string()} {format % args}")


def main() -> None:
    with ThreadingHTTPServer(("127.0.0.1", PORT), ProxyHandler) as server:
        print(f"stream proxy listening on http://127.0.0.1:{PORT}")
        server.serve_forever()


if __name__ == "__main__":
    main()
