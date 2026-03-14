#!/usr/bin/env python3
import json
import sys
from pathlib import Path

STATE_FILE = Path(".vpp_contract_state.json")
VERSION = 1


def load_state():
    if not STATE_FILE.exists():
        return {
            "connected": False,
            "socket_path": None,
            "profiles": {}
        }
    return json.loads(STATE_FILE.read_text(encoding="utf-8"))


def save_state(state):
    STATE_FILE.write_text(
        json.dumps(state, indent=2, sort_keys=True),
        encoding="utf-8"
    )


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


def require(payload, key):
    if key not in payload:
        respond_err(f"missing required field: {key}")


def handle_connect(state, payload):
    socket_path = payload.get("socket_path", "/run/vpp/api.sock")
    state["connected"] = True
    state["socket_path"] = socket_path
    save_state(state)
    return {
        "connected": True,
        "socket_path": socket_path
    }


def handle_disconnect(state, payload):
    state["connected"] = False
    save_state(state)
    return {
        "disconnected": True
    }


def handle_install_profile(state, payload):
    for key in ["name", "protocol", "clients", "servers", "cps", "duration_s"]:
        require(payload, key)

    name = payload["name"]

    state["profiles"][name] = {
        "name": name,
        "protocol": payload["protocol"],
        "clients": payload["clients"],
        "servers": payload["servers"],
        "cps": int(payload["cps"]),
        "duration_s": int(payload["duration_s"]),
        "payload": payload.get("payload", ""),
        "close_mode": payload.get("close_mode", "graceful"),
        "stats_interval_ms": int(payload.get("stats_interval_ms", 1000)),
        "status": "installed"
    }

    save_state(state)
    return state["profiles"][name]


def handle_start_profile(state, payload):
    require(payload, "name")
    name = payload["name"]

    profile = state["profiles"].get(name)
    if not profile:
        respond_err(f"unknown profile: {name}")

    profile["status"] = "running"
    save_state(state)
    return {
        "name": name,
        "status": "running"
    }


def handle_stop_profile(state, payload):
    require(payload, "name")
    name = payload["name"]

    profile = state["profiles"].get(name)
    if not profile:
        respond_err(f"unknown profile: {name}")

    profile["status"] = "stopped"
    save_state(state)
    return {
        "name": name,
        "status": "stopped"
    }


def handle_remove_profile(state, payload):
    require(payload, "name")
    name = payload["name"]

    if name not in state["profiles"]:
        respond_err(f"unknown profile: {name}")

    del state["profiles"][name]
    save_state(state)
    return {
        "name": name,
        "removed": True
    }


def handle_get_profile_stats(state, payload):
    require(payload, "name")
    name = payload["name"]

    profile = state["profiles"].get(name)
    if not profile:
        respond_err(f"unknown profile: {name}")

    cps = profile["cps"]
    duration = profile["duration_s"]
    running = profile["status"] == "running"
    active = min(cps * 2, 1000000) if running else 0

    return {
        "name": name,
        "status": profile["status"],
        "active_sessions": active,
        "sessions_started": cps * min(duration, 10),
        "sessions_closed": 0 if running else cps * min(duration, 10),
        "connection_failures": 0,
        "tx_bytes": active * 128,
        "rx_bytes": active * 512,
        "tx_packets": active,
        "rx_packets": active,
        "worker_count": 4,
        "cps_current": cps if running else 0
    }


def handle_list_profiles(state, payload):
    return {
        "profiles": list(state["profiles"].values())
    }


HANDLERS = {
    "connect": handle_connect,
    "disconnect": handle_disconnect,
    "install_profile": handle_install_profile,
    "start_profile": handle_start_profile,
    "stop_profile": handle_stop_profile,
    "remove_profile": handle_remove_profile,
    "get_profile_stats": handle_get_profile_stats,
    "list_profiles": handle_list_profiles,
}


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

    if action not in HANDLERS:
        respond_err(f"unknown action: {action}")

    state = load_state()
    data = HANDLERS[action](state, payload)
    respond_ok(data)


if __name__ == "__main__":
    main()
