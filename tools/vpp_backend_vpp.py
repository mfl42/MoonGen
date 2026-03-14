import os
import subprocess


class VPPBackend:
    def __init__(self):
        self.socket_path = None

    def _run_vppctl(self, command):
        if not self.socket_path:
            raise ValueError("missing required field: socket_path")

        env = os.environ.copy()
        env["LD_LIBRARY_PATH"] = (
            os.path.expanduser(
                "~/Projects/vpp/build-root/install-vpp-native/vpp/lib/x86_64-linux-gnu"
            )
            + ":"
            + env.get("LD_LIBRARY_PATH", "")
        )

        result = subprocess.run(
            [
                os.path.expanduser(
                    "~/Projects/vpp/build-root/install-vpp-native/vpp/bin/vppctl"
                ),
                "-s",
                self.socket_path,
            ],
            input=command + "\n",
            text=True,
            capture_output=True,
            env=env,
        )

        output = (result.stdout or "").strip()
        err = (result.stderr or "").strip()

        if result.returncode != 0 and err:
            raise RuntimeError(err)

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

        self.socket_path = socket_path
        output = self._run_vppctl("show session verbose")

        return {
            "backend": "vpp",
            "socket_path": socket_path,
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
