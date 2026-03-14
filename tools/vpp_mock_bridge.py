#!/usr/bin/env python3

import json
import sys


def ok(data=None):
    out = {"ok": True}
    if data is not None:
        out["data"] = data
    print(json.dumps(out))
    sys.exit(0)


def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    sys.exit(1)


def main():
    if len(sys.argv) < 2:
        fail("missing command")

    cmd = sys.argv[1]

    if cmd == "connect":
        socket_path = sys.argv[2] if len(sys.argv) > 2 else "/run/vpp/api.sock"
        ok({"connected": True, "socket_path": socket_path})

    elif cmd == "disconnect":
        ok({"disconnected": True})

    elif cmd == "udp_send":
        if len(sys.argv) < 7:
            fail("usage: udp_send <src_ip> <dst_ip> <src_port> <dst_port> <payload>")
        ok({
            "type": "udp",
            "src_ip": sys.argv[2],
            "dst_ip": sys.argv[3],
            "src_port": int(sys.argv[4]),
            "dst_port": int(sys.argv[5]),
            "payload": sys.argv[6],
        })

    elif cmd == "tcp_connect":
        if len(sys.argv) < 6:
            fail("usage: tcp_connect <src_ip> <dst_ip> <src_port> <dst_port>")
        ok({
            "type": "tcp",
            "session_id": 1,
            "src_ip": sys.argv[2],
            "dst_ip": sys.argv[3],
            "src_port": int(sys.argv[4]),
            "dst_port": int(sys.argv[5]),
        })

    elif cmd == "tcp_send":
        if len(sys.argv) < 4:
            fail("usage: tcp_send <session_id> <payload>")
        ok({
            "session_id": int(sys.argv[2]),
            "payload": sys.argv[3],
        })

    elif cmd == "tcp_close":
        if len(sys.argv) < 3:
            fail("usage: tcp_close <session_id>")
        ok({
            "session_id": int(sys.argv[2]),
            "closed": True,
        })

    else:
        fail(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
#!/usr/bin/env python3

import json
import os
import sys

STATE_FILE = ".vpp_mock_state.json"


def load_state():
    if not os.path.exists(STATE_FILE):
        return {"connected": False, "profiles": {}}
    with open(STATE_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def save_state(state):
    with open(STATE_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, sort_keys=True)


def ok(data=None):
    out = {"ok": True}
    if data is not None:
        out["data"] = data
    print(json.dumps(out))
    sys.exit(0)


def fail(message):
    print(json.dumps({"ok": False, "error": message}))
    sys.exit(1)


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


def main():
    if len(sys.argv) < 2:
        fail("missing command")

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

    elif cmd == "install_profile":
        if len(sys.argv) < 10:
            fail("usage: install_profile <name> <protocol> <clients> <servers> <cps> <duration_s> <payload> <close_mode> <stats_interval_ms>")
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
        name = sys.argv[2]
        profile = state["profiles"].get(name)
        if not profile:
            fail(f"unknown profile: {name}")
        profile["status"] = "running"
        save_state(state)
        ok({"name": name, "status": "running"})

    elif cmd == "stop_profile":
        name = sys.argv[2]
        profile = state["profiles"].get(name)
        if not profile:
            fail(f"unknown profile: {name}")
        profile["status"] = "stopped"
        save_state(state)
        ok({"name": name, "status": "stopped"})

    elif cmd == "remove_profile":
        name = sys.argv[2]
        if name not in state["profiles"]:
            fail(f"unknown profile: {name}")
        del state["profiles"][name]
        save_state(state)
        ok({"name": name, "removed": True})

    elif cmd == "list_profiles":
        ok({"profiles": list(state["profiles"].values())})

    elif cmd == "get_profile_stats":
        name = sys.argv[2]
        profile = state["profiles"].get(name)
        if not profile:
            fail(f"unknown profile: {name}")

        cps = profile["cps"]
        duration = profile["duration_s"]
        active = min(cps * 2, 1000000)

        ok({
            "name": name,
            "status": profile["status"],
            "active_sessions": active if profile["status"] == "running" else 0,
            "sessions_started": cps * min(duration, 10),
            "sessions_closed": 0 if profile["status"] == "running" else cps * min(duration, 10),
            "connection_failures": 0,
            "tx_bytes": active * 128,
            "rx_bytes": active * 512,
            "tx_packets": active,
            "rx_packets": active,
            "worker_count": 4,
            "cps_current": cps if profile["status"] == "running" else 0,
        })

    else:
        fail(f"unknown command: {cmd}")


if __name__ == "__main__":
    main()
