#!/usr/bin/env python3
import json
import sys

from vpp_backend_mock import MockBackend

VERSION = 1


def respond_ok(data):
    print(json.dumps({
        "ok": True,
        "version": VERSION,
        "data": data
    }))
    raise SystemExit(0)


def respond_err(message):
    print(json.dumps({
        "ok": False,
        "version": VERSION,
        "error": message
    }))
    raise SystemExit(1)


def main():
    raw = sys.stdin.read()
    if not raw.strip():
        respond_err("missing JSON request")

    try:
        request = json.loads(raw)
    except json.JSONDecodeError as exc:
        respond_err(f"invalid JSON: {exc}")

    version = request.get("version")
    action = request.get("action")
    payload = request.get("payload", {})

    if version != VERSION:
        respond_err(f"unsupported version: {version}")

    backend = MockBackend()

    if not hasattr(backend, action):
        respond_err(f"unknown action: {action}")

    handler = getattr(backend, action)

    try:
        data = handler(payload)
    except ValueError as exc:
        respond_err(str(exc))
    except Exception as exc:
        respond_err(f"backend error: {exc}")

    respond_ok(data)


if __name__ == "__main__":
    main()
