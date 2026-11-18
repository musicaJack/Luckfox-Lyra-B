#!/usr/bin/env python3
"""Pack ili9488.txt into the panel-mipi-dbi firmware ili9488.bin."""

import pathlib
import sys

MAGIC = b"MIPI DBI" + b"\x00" * 7


def parse(text: str) -> bytes:
    out = bytearray()
    for lineno, raw in enumerate(text.splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        kind = parts[0]
        if kind == "command":
            values = [int(x, 0) for x in parts[1:]]
            if not values:
                raise SystemExit(f"{lineno}: command needs an opcode")
            cmd, params = values[0], values[1:]
            if cmd == 0 and len(params) == 1:
                raise SystemExit(f"{lineno}: command 0x00 is the delay encoding")
            if len(params) > 255:
                raise SystemExit(f"{lineno}: too many parameters")
            out.append(cmd)
            out.append(len(params))
            out.extend(params)
        elif kind == "delay":
            if len(parts) != 2:
                raise SystemExit(f"{lineno}: delay needs one millisecond value")
            ms = int(parts[1], 0)
            if not 0 <= ms <= 255:
                raise SystemExit(f"{lineno}: delay {ms} does not fit in one byte")
            out.extend((0x00, 0x01, ms))
        else:
            raise SystemExit(f"{lineno}: unknown word {kind}")
    if len(out) < 2:
        raise SystemExit("no commands")
    return bytes(out)


def check(blob: bytes) -> None:
    if len(blob) < 16 + 2 or blob[:15] != MAGIC or blob[15] != 1:
        raise SystemExit("bad firmware header")
    commands = blob[16:]
    i = 0
    while i + 1 < len(commands):
        num = commands[i + 1]
        i += 2 + num
        if i > len(commands):
            raise SystemExit("command overflows")
    if i != len(commands):
        raise SystemExit("malformed command array")


def main() -> None:
    here = pathlib.Path(__file__).resolve().parent
    text = (here / "ili9488.txt").read_text()
    blob = MAGIC + bytes([1]) + parse(text)
    check(blob)
    dest = here / "ili9488.bin"
    dest.write_bytes(blob)
    print(f"wrote {dest.name} ({len(blob)} bytes)")


if __name__ == "__main__":
    sys.exit(main())
