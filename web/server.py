#!/usr/bin/env python3
"""Local WebRTC browser app server for OpenAI Realtime Translation."""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parent
STATIC_DIR = ROOT / "static"
ENV_PATH = Path.home() / ".keys/openai/mtg-realtime-translator/.env"
OPENAI_CLIENT_SECRETS_URL = "https://api.openai.com/v1/realtime/translations/client_secrets"
TRANSLATION_MODEL = "gpt-realtime-translate"
TRANSCRIPTION_MODEL = "gpt-realtime-whisper"


def load_api_key() -> str:
    load_dotenv(ENV_PATH)
    api_key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError(f"OPENAI_API_KEY not set in environment or {ENV_PATH}")
    return api_key


def create_client_secret(api_key: str, target_language: str) -> tuple[int, bytes]:
    payload = {
        "session": {
            "model": TRANSLATION_MODEL,
            "audio": {
                "input": {
                    "transcription": {
                        "model": TRANSCRIPTION_MODEL,
                    },
                },
                "output": {
                    "language": target_language,
                },
            },
        },
    }
    request = urllib.request.Request(
        OPENAI_CLIENT_SECRETS_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "OpenAI-Safety-Identifier": "local-dev",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(STATIC_DIR), **kwargs)

    def end_headers(self) -> None:
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self) -> None:
        if self.path != "/session":
            self.send_json(404, {"error": "not_found"})
            return

        try:
            length = int(self.headers.get("content-length", "0"))
            body = self.rfile.read(length) if length else b"{}"
            payload = json.loads(body.decode("utf-8"))
            target_language = str(payload.get("targetLanguage") or "ja")
            status, data = create_client_secret(load_api_key(), target_language)
        except Exception as error:
            self.send_json(500, {"error": str(error)})
            return

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_json(self, status: int, payload: dict[str, object]) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args) -> None:
        sys.stderr.write(f"[web] {self.address_string()} {format % args}\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()

    load_api_key()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}"
    print(f"Realtime Translator WebRTC: {url}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
