#!/usr/bin/env python3
"""Summarize DukeX Insignia packet captures without external dependencies."""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import socket
import struct
from pathlib import Path


SERVICE_MARKERS = (
    b"sg\x1b\x02S1",
    b"sg\x1b\x02S2",
    b"sg\x1b\x02S3",
    b"sg\x1b\x02S4",
    b"krbtgt",
    b"insignia.live",
    b"Xbox Version=",
)


def iter_udp_packets(path: Path):
    data = path.read_bytes()
    if len(data) < 24:
        raise ValueError("pcap is too small")

    magic = data[:4]
    if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1"):
        endian = "<"
    elif magic in (b"\xa1\xb2\xc3\xd4", b"\xa1\xb2\x3c\x4d"):
        endian = ">"
    else:
        raise ValueError("unsupported pcap magic")

    offset = 24
    while offset + 16 <= len(data):
        ts_sec, ts_frac, incl_len, _orig_len = struct.unpack(endian + "IIII", data[offset:offset + 16])
        offset += 16
        frame = data[offset:offset + incl_len]
        offset += incl_len

        if len(frame) < 42 or frame[12:14] != b"\x08\x00":
            continue

        ip_offset = 14
        ihl = (frame[ip_offset] & 0x0F) * 4
        if ihl < 20 or len(frame) < ip_offset + ihl + 8:
            continue

        proto = frame[ip_offset + 9]
        if proto != 17:
            continue

        src_ip = socket.inet_ntoa(frame[ip_offset + 12:ip_offset + 16])
        dst_ip = socket.inet_ntoa(frame[ip_offset + 16:ip_offset + 20])
        udp_offset = ip_offset + ihl
        src_port, dst_port, udp_len, _checksum = struct.unpack("!HHHH", frame[udp_offset:udp_offset + 8])
        payload = frame[udp_offset + 8:udp_offset + udp_len]
        yield ts_sec + ts_frac / 1_000_000, src_ip, src_port, dst_ip, dst_port, payload


def ascii_preview(payload: bytes, limit: int = 48) -> str:
    return "".join(chr(byte) if 32 <= byte < 127 else "." for byte in payload[:limit])


def format_time(timestamp: float) -> str:
    return dt.datetime.fromtimestamp(timestamp).isoformat(timespec="milliseconds")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pcap", type=Path, help="Path to latest.pcap")
    args = parser.parse_args()

    packets = list(iter_udp_packets(args.pcap))
    print(f"Capture: {args.pcap}")
    print(f"UDP packets: {len(packets)}")

    print("\nDNS / Kerberos")
    for timestamp, src, sport, dst, dport, payload in packets:
        if sport in (53, 88) or dport in (53, 88):
            print(f"{format_time(timestamp)} {src}:{sport} -> {dst}:{dport} len={len(payload)}")

    sg_flows: dict[tuple[str, int, str, int], list[bytes]] = collections.defaultdict(list)
    for _timestamp, src, sport, dst, dport, payload in packets:
        if sport == 3074 or dport == 3074:
            sg_flows[(src, sport, dst, dport)].append(payload)

    print("\nSecure Gateway Flows")
    for flow, payloads in sorted(sg_flows.items(), key=lambda item: len(item[1]), reverse=True):
        lengths = collections.Counter(len(payload) for payload in payloads).most_common(8)
        src, sport, dst, dport = flow
        print(f"{len(payloads):4} {src}:{sport} -> {dst}:{dport} lengths={lengths}")
        for index, payload in enumerate(payloads[:3], start=1):
            print(f"     #{index:02} len={len(payload):4} first32={payload[:32].hex()} ascii={ascii_preview(payload)}")

    print("\nVisible Markers")
    marker_rows = []
    for timestamp, src, sport, dst, dport, payload in packets:
        for marker in SERVICE_MARKERS:
            offset = payload.find(marker)
            if offset >= 0:
                marker_rows.append((timestamp, src, sport, dst, dport, len(payload), marker, offset))

    if not marker_rows:
        print("none")
    else:
        for timestamp, src, sport, dst, dport, length, marker, offset in marker_rows:
            print(f"{format_time(timestamp)} {src}:{sport} -> {dst}:{dport} len={length} marker={marker!r} at={offset}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
