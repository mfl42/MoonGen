import os
import subprocess

from vmoongen_env import vpp_lib_dir, vppctl_bin, vppctl_timeout


class VPPBackend:
    def __init__(self):
        self.socket_path = None
        self._vppctl_bin = vppctl_bin()
        self._vpp_lib_dir = vpp_lib_dir()

    def _run_vppctl(self, command):
        if not self.socket_path:
            raise ValueError("missing required field: socket_path")
        if not self._vppctl_bin.exists():
            raise FileNotFoundError(f"vppctl not found: {self._vppctl_bin}")

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = (
            str(self._vpp_lib_dir)
            + ":"
            + env.get("LD_LIBRARY_PATH", "")
        )

        result = subprocess.run(
            [
                str(self._vppctl_bin),
                "-s",
                self.socket_path,
            ],
            input=command + "\n",
            text=True,
            capture_output=True,
            env=env,
            timeout=vppctl_timeout(),
        )

        output = (result.stdout or "").strip()
        err = (result.stderr or "").strip()

        if result.returncode != 0:
            raise RuntimeError(err or output or f"vppctl exited with status {result.returncode}")

        return output

    def connect(self, payload):
        socket_path = payload.get("socket_path")
        if not socket_path:
            raise ValueError("missing required field: socket_path")

        if not os.path.exists(socket_path):
            raise ValueError(f"VPP socket not found: {socket_path}")

        self.socket_path = socket_path

        return {
            "connected": True,
            "socket_path": socket_path,
            "backend": "vpp",
        }

    def show_version(self, payload):
        socket_path = payload.get("socket_path")
        if not socket_path:
            raise ValueError("missing required field: socket_path")

        self.socket_path = socket_path
        output = self._run_vppctl("show version")

        return {
            "backend": "vpp",
            "socket_path": socket_path,
            "output": output,
        }
    def show_interfaces(self, payload):
        socket_path = payload.get("socket_path")
        if not socket_path:
            raise ValueError("missing required field: socket_path")

        self.socket_path = socket_path
        output = self._run_vppctl("show interface")

        return {
            "backend": "vpp",
            "socket_path": socket_path,
            "output": output,
        }
    def set_interface_state(self, payload):
        socket_path = payload.get("socket_path")
        if not socket_path:
            raise ValueError("missing required field: socket_path")

        interface = payload.get("interface")
        if not interface:
            raise ValueError("missing required field: interface")

        state = payload.get("state")
        if state not in {"up", "down"}:
            raise ValueError("state must be 'up' or 'down'")

        self.socket_path = socket_path
        output = self._run_vppctl(f"set interface state {interface} {state}")

        return {
            "backend": "vpp",
            "socket_path": socket_path,
            "interface": interface,
            "state": state,
            "output": output,
        }
    def show_plugins(self, payload):
        socket_path = payload.get("socket_path")
        if not socket_path:
            raise ValueError("missing required field: socket_path")

        self.socket_path = socket_path
        output = self._run_vppctl("show plugins")

        return {
            "backend": "vpp",
            "socket_path": socket_path,
            "output": output,
        }
    def show_sessions(self, payload):
        socket_path = payload.get("socket_path")
        if not socket_path:
            raise ValueError("missing required field: socket_path")

        detail = str(payload.get("detail") or "summary").strip().lower()
        if detail not in {"summary", "verbose"}:
            raise ValueError("detail must be 'summary' or 'verbose'")

        self.socket_path = socket_path
        output = self._run_vppctl("show session verbose" if detail == "verbose" else "show session")

        return {
            "backend": "vpp",
            "socket_path": socket_path,
            "detail": detail,
            "output": output,
        }
    def run_cli(self, payload):
        socket_path = payload.get("socket_path")
        if not socket_path:
            raise ValueError("missing required field: socket_path")

        command = payload.get("command")
        if not command:
            raise ValueError("missing required field: command")

        self.socket_path = socket_path
        output = self._run_vppctl(command)

        return {
            "backend": "vpp",
            "socket_path": socket_path,
            "command": command,
            "output": output,
        }
