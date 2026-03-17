import os
from pathlib import Path


def _path_from_env(*names: str, default: Path) -> Path:
    for name in names:
        value = os.environ.get(name)
        if value:
            return Path(value).expanduser()
    return default


def repo_root() -> Path:
    return _path_from_env("VMOONGEN_ROOT", default=Path(__file__).resolve().parent.parent)


def vpp_root() -> Path:
    for name in ("VPP_ROOT", "VMOONGEN_VPP_ROOT"):
        value = os.environ.get(name)
        if value:
            return Path(value).expanduser()

    repo = repo_root()
    candidates = [
        repo.parent / "vpp",
        Path.home() / "Projects" / "vpp",
        Path.home() / "vpp",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return Path.home() / "Projects" / "vpp"


def vpp_install_dir() -> Path:
    return _path_from_env(
        "VPP_INSTALL_DIR",
        default=vpp_root() / "build-root" / "install-vpp-native" / "vpp",
    )


def vppctl_bin() -> Path:
    return _path_from_env("VPP_CTL_BIN", default=vpp_install_dir() / "bin" / "vppctl")


def vpp_lib_dir() -> Path:
    return _path_from_env(
        "VPP_LIB_DIR",
        default=vpp_install_dir() / "lib" / "x86_64-linux-gnu",
    )


def bridge_socket() -> str:
    return os.environ.get("VMOONGEN_BRIDGE_SOCKET", "/tmp/vmoongen.sock")


def vpp_socket() -> str:
    return os.environ.get("VPP_SOCKET", str(vpp_root() / "run" / "cli.sock"))


def vppctl_timeout() -> float:
    return float(os.environ.get("VMOONGEN_VPPCTL_TIMEOUT", "5"))
