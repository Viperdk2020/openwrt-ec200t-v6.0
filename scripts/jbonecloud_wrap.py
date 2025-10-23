#!/usr/bin/env python3
"""Wrap OpenWrt legacy uImages for the EC200T bootloader.

The vendor bootloader expects a legacy uImage header with the magic
0x27151967. This helper rewrites an existing OpenWrt sysupgrade (or
initramfs) image, recomputing both the header and payload CRCs so the
image passes the dual CRC checks performed by U-Boot.
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

    def unpack_from_bytes(self, blob: bytes) -> dict[str, int | str]:
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

    def pack_from_fields(self, fields: dict[str, int | str]) -> bytes:
        name_bytes = str(fields["name"]).encode("ascii", "ignore")[:32]
        name_padded = name_bytes.ljust(32, b"\x00")
        return self.pack(
            int(fields["magic"]),
            int(fields["hcrc"]),
            int(fields["timestamp"]),
            int(fields["size"]),
            int(fields["load"]),
            int(fields["entry"]),
            int(fields["dcrc"]),
            int(fields["os"]),
            int(fields["arch"]),
            int(fields["type"]),
            int(fields["comp"]),
            name_padded,
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Wrap an OpenWrt MT7628 image with the EC200T vendor header.",
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
        type=lambda value: int(value, 0),
        help="Override load address (hex or decimal).",
    )
    parser.add_argument(
        "--entry",
        type=lambda value: int(value, 0),
        help="Override entry point (hex or decimal).",
    )
    parser.add_argument(
        "--timestamp",
        type=lambda value: int(value, 0),
        help="Override build timestamp (seconds since epoch).",
    )
    return parser.parse_args()


def compute_header_crc(header: bytearray) -> int:
    """Compute the CRC32 of the 64-byte header with ih_hcrc zeroed."""
    zeroed = header[:]
    zeroed[4:8] = b"\x00\x00\x00\x00"
    return zlib.crc32(zeroed) & 0xFFFFFFFF


def wrap_image(source: Path, destination: Path | None, overrides: argparse.Namespace) -> Path:
    blob = source.read_bytes()
    if len(blob) < UIMAGE_HEADER_LEN:
        raise ValueError("input is smaller than a uImage header")

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
    elif kernel_len != payload_len:
        print(
            f"note: header size 0x{original['size']:x} differs from payload length "
            f"0x{payload_len:x}; preserving declared size for CRC calculations.",
            file=sys.stderr,
        )

    fields = original.copy()
    fields["magic"] = UIMAGE_MAGIC_JBC
    fields["size"] = kernel_len
    fields["dcrc"] = zlib.crc32(payload[:kernel_len]) & 0xFFFFFFFF
    fields["name"] = overrides.name if overrides.name else original["name"]
    fields["load"] = overrides.load if overrides.load is not None else original["load"]
    fields["entry"] = overrides.entry if overrides.entry is not None else original["entry"]
    fields["timestamp"] = (
        overrides.timestamp
        if overrides.timestamp is not None
        else original["timestamp"] or int(time.time())
    )

    header_bytes = bytearray(header_struct.pack_from_fields({**fields, "hcrc": 0}))
    fields["hcrc"] = compute_header_crc(header_bytes)
    header_bytes = header_struct.pack_from_fields(fields)

    if destination is None:
        destination = source.with_suffix(source.suffix + "-jbc.bin")
    destination.write_bytes(header_bytes + payload)

    print(f"Wrote {destination} ({destination.stat().st_size} bytes)")
    print(
        f"  magic=0x{fields['magic']:08x} "
        f"hcrc=0x{fields['hcrc']:08x} "
        f"dcrc=0x{fields['dcrc']:08x} "
        f"size=0x{fields['size']:x}"
    )
    return destination


def main() -> int:
    args = parse_args()
    destination = wrap_image(args.input, args.output, args)
    return 0 if destination.exists() else 1


if __name__ == "__main__":
    sys.exit(main())
