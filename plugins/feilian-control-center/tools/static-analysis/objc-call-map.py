#!/usr/bin/env python3
"""Resolve an arm64 ObjC dispatch stub to its selector, without dumping data."""
import argparse
import json
import re
import struct
from pathlib import Path


class Image:
    def __init__(self, filename):
        self.data = Path(filename).read_bytes()
        if self.data[:4] != b"\xcf\xfa\xed\xfe":
            raise ValueError("Expected a thin arm64 Mach-O")
        self.segments = []
        self.sections = {}
        cursor = 32
        for _ in range(struct.unpack_from("<I", self.data, 16)[0]):
            command, size = struct.unpack_from("<II", self.data, cursor)
            if size < 8 or cursor + size > len(self.data):
                raise ValueError("Invalid load command")
            if command == 0x19:
                vm, _, fileoff, filesize = struct.unpack_from("<QQQQ", self.data, cursor + 24)
                if filesize:
                    self.segments.append((vm, vm + filesize, fileoff))
                count = struct.unpack_from("<I", self.data, cursor + 64)[0]
                for index in range(count):
                    section = cursor + 72 + index * 80
                    name = self.data[section:section + 16].split(b"\0")[0].decode()
                    self.sections[name] = struct.unpack_from("<QQ", self.data, section + 32)
            cursor += size
        self.base = min(low for low, _, off in self.segments if off == 0)

    def offset(self, address):
        for low, high, off in self.segments:
            if low <= address < high:
                return address - low + off
        raise ValueError("Unmapped address")

    def pointer(self, address):
        value = struct.unpack_from("<Q", self.data, self.offset(address))[0]
        try:
            self.offset(value)
            return value
        except ValueError:
            decoded = self.base + (value & 0xFFFFFFFF)
            self.offset(decoded)
            return decoded

    def text(self, address):
        offset = self.offset(address)
        text = self.data[offset:self.data.index(0, offset)].decode()
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_:.]*", text):
            raise ValueError("Not an ObjC symbol")
        return text

    def selector(self, address):
        registers = {}
        low, size = self.sections["__objc_selrefs"]
        for index in range(6):
            pc = address + index * 4
            word = struct.unpack_from("<I", self.data, self.offset(pc))[0]
            if word & 0x9F000000 == 0x90000000:  # ADRP
                immediate = ((word >> 5 & 0x7FFFF) << 2) | (word >> 29 & 3)
                if immediate & (1 << 20):
                    immediate -= 1 << 21
                registers[word & 31] = (pc & ~4095) + (immediate << 12)
            elif word & 0xFFC00000 == 0xF9400000:  # LDR (unsigned immediate)
                base, target = (word >> 5) & 31, word & 31
                if base in registers and target == 1:
                    reference = registers[base] + ((word >> 10 & 0xFFF) * 8)
                    if low <= reference < low + size:
                        return self.text(self.pointer(reference))
            elif word & 0x7C000000 == 0x14000000:  # tail branch, stop
                break
        return None


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("macho")
    parser.add_argument("--calls-file", required=True)
    args = parser.parse_args()
    image = Image(args.macho)
    result = []
    for line in Path(args.calls_file).read_text().splitlines():
        match = re.match(r"([0-9a-f]{16})\s+(?:bl|b)\s+(0x[0-9a-f]+)", line)
        if not match:
            continue
        try:
            selector = image.selector(int(match[2], 16))
        except (ValueError, UnicodeDecodeError, struct.error):
            continue
        if selector:
            result.append({"caller": "0x" + match[1], "selector": selector})
    print(json.dumps(result, indent=2))
