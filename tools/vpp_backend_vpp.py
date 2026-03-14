import os


class VPPBackend:

    def __init__(self):
        self.connected = False
        self.socket_path = None

    def connect(self, payload):
        socket_path = payload.get("socket_path", "/run/vpp/api.sock")

        if not os.path.exists(socket_path):
            raise ValueError(f"VPP API socket not found: {socket_path}")

        self.connected = True
        self.socket_path = socket_path

        return {
            "connected": True,
            "socket_path": socket_path,
            "backend": "vpp"
        }

    def disconnect(self, payload):
        if not self.connected:
            return {"disconnected": False}

        self.connected = False

        return {
            "disconnected": True
        }

    def install_profile(self, payload):
        raise NotImplementedError("install_profile not implemented for VPP backend yet")

    def start_profile(self, payload):
        raise NotImplementedError("start_profile not implemented for VPP backend yet")

    def stop_profile(self, payload):
        raise NotImplementedError("stop_profile not implemented for VPP backend yet")

    def remove_profile(self, payload):
        raise NotImplementedError("remove_profile not implemented for VPP backend yet")

    def get_profile_stats(self, payload):
        raise NotImplementedError("get_profile_stats not implemented for VPP backend yet")

    def list_profiles(self, payload):
        raise NotImplementedError("list_profiles not implemented for VPP backend yet")
