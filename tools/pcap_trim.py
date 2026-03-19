#!/usr/bin/env python3
"""
Trim a classic PCAP file to a maximum byte budget while preserving packet boundaries.
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path


MAGIC_ENDIAN = {
    0xA1B2C3D4: ">",
    0xA1B23C4D: ">",
    0xD4C3B2A1: "<",
    0x4D3CB2A1: "<",
}


def trim_pcap(inp: Path, out: Path, max_bytes: int) -> tuple[int, int]:
    if max_bytes < 24:
        max_bytes = 24

    with inp.open("rb") as fi:
        gh = fi.read(24)
        if len(gh) < 24:
            raise ValueError("input is not a valid pcap (global header missing)")
        magic = struct.unpack("<I", gh[0:4])[0]
        endian = MAGIC_ENDIAN.get(magic)
        if endian is None:
            magic_be = struct.unpack(">I", gh[0:4])[0]
            endian = MAGIC_ENDIAN.get(magic_be)
        if endian is None:
            raise ValueError("unsupported pcap magic (pcapng is not supported)")

        used = 24
        packets = 0
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("wb") as fo:
            fo.write(gh)
            rec_hdr_struct = struct.Struct(endian + "IIII")
            while True:
                rh = fi.read(16)
                if len(rh) == 0:
                    break
                if len(rh) < 16:
                    break
                _ts_sec, _ts_usec, incl_len, _orig_len = rec_hdr_struct.unpack(rh)
                pkt = fi.read(incl_len)
                if len(pkt) < incl_len:
                    break
                rec_size = 16 + incl_len
                if used + rec_size > max_bytes:
                    break
                fo.write(rh)
                fo.write(pkt)
                used += rec_size
                packets += 1

    return used, packets


def main() -> int:
    ap = argparse.ArgumentParser(description="Trim pcap to maximum bytes")
    ap.add_argument("--input", required=True, help="Input pcap path")
    ap.add_argument("--output", required=True, help="Output pcap path")
    ap.add_argument("--max-bytes", type=int, default=102400, help="Maximum output bytes (default: 102400)")
    args = ap.parse_args()

    inp = Path(args.input)
    out = Path(args.output)
    used, packets = trim_pcap(inp, out, max(24, int(args.max_bytes)))
    print(f"output={out} bytes={used} packets={packets}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
