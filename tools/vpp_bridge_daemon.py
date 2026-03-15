#!/usr/bin/env python3
import argparse
import json
import os
import signal
import socket
import sys
import traceback
from typing import Any, Dict


def load_backend():
    backend_name = os.environ.get("VMOONGEN_BACKEND", "vpp")
    if backend_name == "vpp":
        from vpp_backend_vpp import VPPBackend
        return VPPBackend()
    if backend_name == "mock":
        from vpp_backend_mock import MockBackend
        return MockBackend()
    raise ValueError(f"unsupported backend: {backend_name}")


def make_response(ok: bool, version: int, *, data: Any = None, error: str = None) -> bytes:
    payload: Dict[str, Any] = {"ok": ok, "version": version}
    if ok:
        payload["data"] = data
    else:
        payload["error"] = error or "unknown error"
    return (json.dumps(payload) + "\n").encode("utf-8")


def handle_request(backend: Any, raw: bytes) -> bytes:
    try:
        request = json.loads(raw.decode("utf-8"))
        version = int(request.get("version", 1))
        action = request.get("action")
        payload = request.get("payload", {}) or {}

        if not action:
            return make_response(False, version, error="missing action")

        if not hasattr(backend, action):
            return make_response(False, version, error=f"unknown action: {action}")

        method = getattr(backend, action)
        result = method(payload)
        return make_response(True, version, data=result)
    except Exception as exc:
        version = 1
        try:
            version = int(json.loads(raw.decode("utf-8")).get("version", 1))
        except Exception:
            pass
        return make_response(False, version, error=f"backend error: {exc}")


class Daemon:
    def __init__(self, socket_path: str):
        self.socket_path = socket_path
        self.server = None
        self.backend = load_backend()
        self.running = True

    def stop(self, *_args):
        self.running = False
        if self.server is not None:
            try:
                self.server.close()
            except Exception:
                pass

    def serve_forever(self):
        if os.path.exists(self.socket_path):
            os.unlink(self.socket_path)

        self.server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.server.bind(self.socket_path)
        os.chmod(self.socket_path, 0o660)
        self.server.listen(128)

        while self.running:
            try:
                conn, _addr = self.server.accept()
            except OSError:
                if self.running:
                    raise
                break

            with conn:
                data = bytearray()
                while True:
                    chunk = conn.recv(65536)
                    if not chunk:
                        break
                    data.extend(chunk)
                    if b"\n" in chunk:
                        break

                if not data:
                    continue

                raw = bytes(data.split(b"\n", 1)[0]).strip()
                if not raw:
                    continue

                response = handle_request(self.backend, raw)
                conn.sendall(response)

        self.cleanup()

    def cleanup(self):
        if self.server is not None:
            try:
                self.server.close()
            except Exception:
                pass
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except Exception:
                pass


def main():
    parser = argparse.ArgumentParser(description="vMoonGen persistent bridge daemon")
    parser.add_argument(
        "--socket",
        default="/tmp/vmoongen.sock",
        help="UNIX socket path for the daemon (default: /tmp/vmoongen.sock)",
    )
    args = parser.parse_args()

    daemon = Daemon(args.socket)
    signal.signal(signal.SIGINT, daemon.stop)
    signal.signal(signal.SIGTERM, daemon.stop)

    try:
        daemon.serve_forever()
        return 0
    except Exception:
        traceback.print_exc()
        daemon.cleanup()
        return 1


if __name__ == "__main__":
    sys.exit(main())
