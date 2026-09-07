#!/usr/bin/env python3
"""Report APK ELF segment alignment and fail on under-aligned 64-bit libs."""

from __future__ import annotations

import argparse
import struct
import sys
import zipfile


PT_LOAD = 1
PT_GNU_RELRO = 0x6474E552
MIN_64_BIT_ALIGNMENT = 16 * 1024


def inspect_elf(data: bytes) -> tuple[int, list[int], bool]:
    if len(data) < 64 or data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    elf_class = data[4]
    byte_order = data[5]
    prefix = "<" if byte_order == 1 else ">" if byte_order == 2 else None
    if prefix is None:
        raise ValueError("unsupported ELF byte order")

    if elf_class == 2:
        header = struct.unpack_from(prefix + "HHIQQQIHHHHHH", data, 16)
        program_header_format = prefix + "IIQQQQQQ"
    elif elf_class == 1:
        header = struct.unpack_from(prefix + "HHIIIIIHHHHHH", data, 16)
        program_header_format = prefix + "IIIIIIII"
    else:
        raise ValueError("unsupported ELF class")

    program_offset = header[4]
    program_entry_size = header[8]
    program_count = header[9]
    expected_size = struct.calcsize(program_header_format)
    if program_entry_size < expected_size:
        raise ValueError("invalid program header size")

    alignments: list[int] = []
    has_relro = False
    for index in range(program_count):
        offset = program_offset + index * program_entry_size
        values = struct.unpack_from(program_header_format, data, offset)
        segment_type = values[0]
        if segment_type == PT_LOAD:
            alignments.append(values[7])
        elif segment_type == PT_GNU_RELRO:
            has_relro = True
    return elf_class, alignments, has_relro


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk")
    args = parser.parse_args()

    failures: list[str] = []
    with zipfile.ZipFile(args.apk) as apk:
        libraries = sorted(
            name
            for name in apk.namelist()
            if name.startswith("lib/") and name.endswith(".so")
        )
        if not libraries:
            raise SystemExit("APK contains no native libraries")
        for name in libraries:
            elf_class, alignments, has_relro = inspect_elf(apk.read(name))
            print(f"{name}: PT_LOAD align={alignments}, GNU_RELRO={has_relro}")
            if elf_class == 2 and (
                not alignments
                or any(value < MIN_64_BIT_ALIGNMENT for value in alignments)
            ):
                failures.append(name)

    if failures:
        print(
            "64-bit libraries below 16 KiB alignment: " + ", ".join(failures),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
