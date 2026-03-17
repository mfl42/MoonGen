#!/usr/bin/env python3

import json
from pathlib import Path
import sys


STATE_FILE = Path(".vpp_mock_state.json")


def load_state():
    if not STATE_FILE.exists():
        return {
            "connected": False,
            "socket_path": None,
            "profiles": {},
            "sessions": {},
            "next_session_id": 1,
        }
    return json.loads(STATE_FILE.read_text(encoding="utf-8"))


def save_state(state):
    STATE_FILE.write_text(
        json.dumps(state, indent=2, sort_keys=True),
        encoding="utf-8",
    )


def ok(data=None):
    out = {"ok": True}
    if data is not None:
        out["data"] = data
    print(json.dumps(out))
    raise SystemExit(0)


def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    raise SystemExit(1)


def parse_servers(text):
    servers = []
    if not text:
        return servers
    for item in text.split(","):
        if not item:
            continue
        if ":" not in item:
            fail(f"invalid server format: {item}")
        ip, port = item.rsplit(":", 1)
        servers.append({"ip": ip, "port": int(port)})
    return servers


def require_args(count, usage):
    if len(sys.argv) < count:
        fail(f"usage: {usage}")


def main():
    require_args(2, "vpp_mock_bridge.py <command> [args...]")
    cmd = sys.argv[1]
    state = load_state()

    if cmd == "connect":
        socket_path = sys.argv[2] if len(sys.argv) > 2 else "/run/vpp/api.sock"
        state["connected"] = True
        state["socket_path"] = socket_path
        save_state(state)
        ok({"connected": True, "socket_path": socket_path})

    elif cmd == "disconnect":
        state["connected"] = False
        save_state(state)
        ok({"disconnected": True})

    elif cmd == "udp_send":
        require_args(7, "udp_send <src_ip> <dst_ip> <src_port> <dst_port> <payload>")
        ok(
            {
                "type": "udp",
                "src_ip": sys.argv[2],
                "dst_ip": sys.argv[3],
                "src_port": int(sys.argv[4]),
                "dst_port": int(sys.argv[5]),
                "payload": sys.argv[6],
            }
        )

    elif cmd == "tcp_connect":
        require_args(6, "tcp_connect <src_ip> <dst_ip> <src_port> <dst_port>")
        session_id = state["next_session_id"]
        state["next_session_id"] = session_id + 1
        state["sessions"][str(session_id)] = {
            "type": "tcp",
            "src_ip": sys.argv[2],
            "dst_ip": sys.argv[3],
            "src_port": int(sys.argv[4]),
            "dst_port": int(sys.argv[5]),
            "open": True,
        }
        save_state(state)
        ok(
            {
                "type": "tcp",
                "session_id": session_id,
                "src_ip": sys.argv[2],
                "dst_ip": sys.argv[3],
                "src_port": int(sys.argv[4]),
                "dst_port": int(sys.argv[5]),
            }
        )

    elif cmd == "tcp_send":
        require_args(4, "tcp_send <session_id> <payload>")
        session_id = sys.argv[2]
        session = state["sessions"].get(session_id)
        if not session or not session.get("open"):
            fail(f"unknown or closed session: {session_id}")
        ok({"session_id": int(session_id), "payload": sys.argv[3]})

    elif cmd == "tcp_close":
        require_args(3, "tcp_close <session_id>")
        session_id = sys.argv[2]
        session = state["sessions"].get(session_id)
        if not session or not session.get("open"):
            fail(f"unknown or closed session: {session_id}")
        session["open"] = False
        save_state(state)
        ok({"session_id": int(session_id), "closed": True})

    elif cmd == "install_profile":
        require_args(
            10,
            "install_profile <name> <protocol> <clients> <servers> <cps> <duration_s> <payload> <close_mode> <stats_interval_ms>",
        )
        name = sys.argv[2]
        state["profiles"][name] = {
            "name": name,
            "protocol": sys.argv[3],
            "clients": sys.argv[4],
            "servers": parse_servers(sys.argv[5]),
            "cps": int(sys.argv[6]),
            "duration_s": int(sys.argv[7]),
            "payload": sys.argv[8],
            "close_mode": sys.argv[9],
            "stats_interval_ms": int(sys.argv[10]) if len(sys.argv) > 10 else 1000,
            "status": "installed",
        }
        save_state(state)
        ok(state["profiles"][name])

    elif cmd == "start_profile":
        require_args(3, "start_profile <name>")
        name = sys.argv[2]
        profile = state["profiles"].get(name)
        if not profile:
            fail(f"unknown profile: {name}")
        profile["status"] = "running"
        save_state(state)
        ok({"name": name, "status": "running"})

    elif cmd == "stop_profile":
        require_args(3, "stop_profile <name>")
        name = sys.argv[2]
        profile = state["profiles"].get(name)
        if not profile:
            fail(f"unknown profile: {name}")
        profile["status"] = "stopped"
        save_state(state)
        ok({"name": name, "status": "stopped"})

    elif cmd == "remove_profile":
        require_args(3, "remove_profile <name>")
        name = sys.argv[2]
        if name not in state["profiles"]:
            fail(f"unknown profile: {name}")
        del state["profiles"][name]
        save_state(state)
        ok({"name": name, "removed": True})

    elif cmd == "list_profiles":
        ok({"profiles": list(state["profiles"].values())})

    elif cmd == "get_profile_stats":
        require_args(3, "get_profile_stats <name>")
        name = sys.argv[2]
        profile = state["profiles"].get(name)
        if not profile:
            fail(f"unknown profile: {name}")
        cps = profile["cps"]
        duration = profile["duration_s"]
        running = profile["status"] == "running"
        active = min(cps * 2, 1_000_000) if running else 0
        ok(
            {
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
                "cps_current": cps if running else 0,
            }
        )

    else:
        fail(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
