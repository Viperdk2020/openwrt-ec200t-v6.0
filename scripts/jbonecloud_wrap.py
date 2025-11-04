#!/usr/bin/env python3
"""
Wrap an OpenWrt MT7628 image with the JBoneCloud/MTK RAM boot header.

The EC200T bootloader expects a legacy uImage whose magic word is
0x27151967 (not the upstream 0x27051956). This script rewrites the
header, recomputing both the 64-byte header CRC and the payload CRC so
the image passes the dual-slot validation checks.

Usage
-----
    ./jbonecloud_wrap.py <input.bin> [-o output.bin]

The input should already be a combined kernel+rootfs image in legacy
uImage format (e.g. OpenWrt sysupgrade). By default the script keeps the
original load address, entry point, OS/arch/type/comp, timestamp, and
image name.
"""

from __future__ import annotations

import argparse
import struct
import sys
import time
import zlib
from pathlib import Path

UIMAGE_HEADER_FMT = ">IIIIIIIBBBB32s"
UIMAGE_HEADER_LEN = struct.calcsize(UIMAGE_HEADER_FMT)
UIMAGE_MAGIC_STOCK = 0x27051956
UIMAGE_MAGIC_JBC = 0x27151967


class ImageHeader(struct.Struct):
    """Helper to pack/unpack the 64-byte legacy uImage header."""

    def __init__(self) -> None:
        super().__init__(UIMAGE_HEADER_FMT)

    def unpack_from_bytes(self, blob: bytes) -> dict:
        (
            magic,
            hcrc,
            timestamp,
            size,
            load,
            entry,
            dcrc,
            os_id,
            arch,
            img_type,
            comp,
            name_raw,
        ) = self.unpack(blob[: self.size])
        name = name_raw.split(b"\x00", 1)[0].decode("ascii", "ignore")
        return {
            "magic": magic,
            "hcrc": hcrc,
            "timestamp": timestamp,
            "size": size,
            "load": load,
            "entry": entry,
            "dcrc": dcrc,
            "os": os_id,
            "arch": arch,
            "type": img_type,
            "comp": comp,
            "name": name,
        }

    def pack_from_fields(self, fields: dict) -> bytes:
        name_bytes = fields["name"].encode("ascii", "ignore")[:32]
        name_padded = name_bytes.ljust(32, b"\x00")
        return self.pack(
            fields["magic"],
            fields["hcrc"],
            fields["timestamp"],
            fields["size"],
            fields["load"],
            fields["entry"],
            fields["dcrc"],
            fields["os"],
            fields["arch"],
            fields["type"],
            fields["comp"],
            name_padded,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Wrap an OpenWrt MT7628 image with the EC200T vendor header."
    )
    parser.add_argument(
        "input",
        type=Path,
        help="Source image (legacy uImage, typically OpenWrt sysupgrade).",
    )
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        help="Destination path. Defaults to <input>-jbc.bin next to the source.",
    )
    parser.add_argument(
        "--name",
        help="Override image name (default: reuse the original header name).",
    )
    parser.add_argument(
        "--load",
        type=lambda v: int(v, 0),
        help="Override load address (hex or decimal).",
    )
    parser.add_argument(
        "--entry",
        type=lambda v: int(v, 0),
        help="Override entry point (hex or decimal).",
    )
    parser.add_argument(
        "--timestamp",
        type=lambda v: int(v, 0),
        help="Override build timestamp (seconds since epoch).",
    )
    return parser.parse_args()


def compute_header_crc(header: bytearray) -> int:
    """Compute the CRC32 of the 64-byte header with ih_hcrc zeroed."""
    zeroed = header[:]
    zeroed[4:8] = b"\x00\x00\x00\x00"
    return zlib.crc32(zeroed) & 0xFFFFFFFF


def main() -> int:
    args = parse_args()
    blob = args.input.read_bytes()

    if len(blob) < UIMAGE_HEADER_LEN:
        print("error: input is smaller than a uImage header", file=sys.stderr)
        return 1

    header_struct = ImageHeader()
    original = header_struct.unpack_from_bytes(blob)

    if original["magic"] not in {UIMAGE_MAGIC_STOCK, UIMAGE_MAGIC_JBC}:
        print(
            f"warning: unexpected input magic 0x{original['magic']:08x}; continuing",
            file=sys.stderr,
        )

    payload = blob[UIMAGE_HEADER_LEN:]
    payload_len = len(payload)
    kernel_len = original["size"]
    if kernel_len == 0 or kernel_len > payload_len:
        kernel_len = payload_len
    else:
        if kernel_len != payload_len:
            print(
                f"note: header size 0x{original['size']:x} "
                f"differs from payload length 0x{payload_len:x}; "
                "preserving header size for kernel span.",
                file=sys.stderr,
            )
    fields = original.copy()
    fields["magic"] = UIMAGE_MAGIC_JBC
    fields["size"] = kernel_len
    fields["dcrc"] = zlib.crc32(payload[:kernel_len]) & 0xFFFFFFFF
    fields["name"] = args.name if args.name else original["name"]
    fields["load"] = args.load if args.load is not None else original["load"]
    fields["entry"] = args.entry if args.entry is not None else original["entry"]
    fields["timestamp"] = (
        args.timestamp if args.timestamp is not None else original["timestamp"] or int(time.time())
    )

    header_bytes = bytearray(header_struct.pack_from_fields({**fields, "hcrc": 0}))
    fields["hcrc"] = compute_header_crc(header_bytes)
    header_bytes = header_struct.pack_from_fields(fields)

    output_path = (
        args.output
        if args.output
        else args.input.with_suffix(args.input.suffix + "-jbc.bin")
    )
    output_path.write_bytes(header_bytes + payload)

    print(f"Wrote {output_path} ({output_path.stat().st_size} bytes)")
    print(
        f"  magic=0x{fields['magic']:08x} "
        f"hcrc=0x{fields['hcrc']:08x} "
        f"dcrc=0x{fields['dcrc']:08x} "
        f"size=0x{fields['size']:x}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
