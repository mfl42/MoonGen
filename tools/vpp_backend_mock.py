import json
from pathlib import Path

STATE_FILE = Path(".vpp_contract_state.json")


class MockBackend:
    def __init__(self):
        self.state = self._load_state()

    def _load_state(self):
        if not STATE_FILE.exists():
            return {
                "connected": False,
                "socket_path": None,
                "profiles": {}
            }
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))

    def _save_state(self):
        STATE_FILE.write_text(
            json.dumps(self.state, indent=2, sort_keys=True),
            encoding="utf-8"
        )

    def connect(self, payload):
        socket_path = payload.get("socket_path", "/run/vpp/api.sock")
        self.state["connected"] = True
        self.state["socket_path"] = socket_path
        self._save_state()
        return {
            "connected": True,
            "socket_path": socket_path
        }

    def disconnect(self, payload):
        self.state["connected"] = False
        self._save_state()
        return {
            "disconnected": True
        }

    def install_profile(self, payload):
        for key in ["name", "protocol", "clients", "servers", "cps", "duration_s"]:
            if key not in payload:
                raise ValueError(f"missing required field: {key}")

        name = payload["name"]

        self.state["profiles"][name] = {
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

        self._save_state()
        return self.state["profiles"][name]

    def start_profile(self, payload):
        name = payload.get("name")
        if not name:
            raise ValueError("missing required field: name")

        profile = self.state["profiles"].get(name)
        if not profile:
            raise ValueError(f"unknown profile: {name}")

        profile["status"] = "running"
        self._save_state()
        return {
            "name": name,
            "status": "running"
        }

    def stop_profile(self, payload):
        name = payload.get("name")
        if not name:
            raise ValueError("missing required field: name")

        profile = self.state["profiles"].get(name)
        if not profile:
            raise ValueError(f"unknown profile: {name}")

        profile["status"] = "stopped"
        self._save_state()
        return {
            "name": name,
            "status": "stopped"
        }

    def remove_profile(self, payload):
        name = payload.get("name")
        if not name:
            raise ValueError("missing required field: name")

        if name not in self.state["profiles"]:
            raise ValueError(f"unknown profile: {name}")

        del self.state["profiles"][name]
        self._save_state()
        return {
            "name": name,
            "removed": True
        }

    def get_profile_stats(self, payload):
        name = payload.get("name")
        if not name:
            raise ValueError("missing required field: name")

        profile = self.state["profiles"].get(name)
        if not profile:
            raise ValueError(f"unknown profile: {name}")

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

    def list_profiles(self, payload):
        return {
            "profiles": list(self.state["profiles"].values())
        }
