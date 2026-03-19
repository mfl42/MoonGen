#!/usr/bin/env python3
"""
Minimal AF_PACKET PCAP capture helper.

This utility is used as a fallback when tcpdump is not available.
It writes a classic pcap file and runs until it receives SIGINT/SIGTERM.
"""

from __future__ import annotations

import argparse
import os
import signal
import socket
import struct
import sys
import time
from pathlib import Path


STOP = False


def _on_signal(_signum: int, _frame) -> None:
    global STOP
    STOP = True


def write_global_header(f) -> None:
    # little-endian pcap, v2.4, snaplen 65535, linktype Ethernet (1)
    f.write(struct.pack("<IHHIIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))


def main() -> int:
    ap = argparse.ArgumentParser(description="Capture packets to classic pcap")
    ap.add_argument("--iface", required=True, help="Interface name")
    ap.add_argument("--output", required=True, help="Output pcap path")
    ap.add_argument("--snaplen", type=int, default=192, help="Captured bytes per packet")
    ap.add_argument("--poll-timeout-ms", type=int, default=500, help="Socket receive timeout in ms")
    args = ap.parse_args()

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)

    signal.signal(signal.SIGINT, _on_signal)
    signal.signal(signal.SIGTERM, _on_signal)

    snaplen = max(64, int(args.snaplen))
    timeout_s = max(1, int(args.poll_timeout_ms)) / 1000.0

    try:
        sock = socket.socket(socket.AF_PACKET, socket.SOCK_RAW, socket.ntohs(0x0003))
        sock.bind((args.iface, 0))
        sock.settimeout(timeout_s)
    except PermissionError:
        print("permission denied: root/CAP_NET_RAW is required", file=sys.stderr)
        return 2
    except OSError as exc:
        print(f"socket setup failed: {exc}", file=sys.stderr)
        return 3

    packets = 0
    bytes_written = 24

    with out.open("wb") as f:
        write_global_header(f)
        while not STOP:
            try:
                data, _addr = sock.recvfrom(65535)
            except socket.timeout:
                continue
            except OSError as exc:
                print(f"recv error: {exc}", file=sys.stderr)
                break

            ts = time.time()
            ts_sec = int(ts)
            ts_usec = int((ts - ts_sec) * 1_000_000)
            orig_len = len(data)
            incl_len = min(orig_len, snaplen)
            payload = data[:incl_len]

            f.write(struct.pack("<IIII", ts_sec, ts_usec, incl_len, orig_len))
            f.write(payload)
            packets += 1
            bytes_written += 16 + incl_len

            # Flush regularly so abrupt stop still leaves readable pcap.
            if packets % 128 == 0:
                f.flush()
                os.fsync(f.fileno())

        f.flush()
        os.fsync(f.fileno())

    sock.close()
    print(f"output={out} packets={packets} bytes={bytes_written}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
