#!/usr/bin/env python3
"""Read ObjC metadata from an authorized unencrypted 64-bit Mach-O slice.

Only prints class/method names, signatures and implementation offsets. Does not
dump strings, credentials, instance state, Swift field values or App options.
"""
import argparse
import json
import re
import struct
from pathlib import Path


def inspect(path, pattern):
    data = Path(path).read_bytes()
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a thin little-endian 64-bit Mach-O")
    commands = struct.unpack_from("<I", data, 16)[0]
    segments, sections = [], {}
    offset = 32
    for _ in range(commands):
        command, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > len(data):
            raise ValueError("Invalid load command")
        if command == 0x19:
            vm, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, offset + 24)
            segments.append((vm, vm + filesize, fileoff))
            count = struct.unpack_from("<I", data, offset + 64)[0]
            for index in range(count):
                start = offset + 72 + index * 80
                name = data[start:start + 16].split(b"\0")[0].decode()
                addr, length = struct.unpack_from("<QQ", data, start + 32)
                sections[name] = (addr, length)
        offset += size

    def location(address):
        for low, high, fileoff in segments:
            if low <= address < high:
                return address - low + fileoff
        raise ValueError("Unmapped metadata address")

    def u64(address):
        value = struct.unpack_from("<Q", data, location(address))[0]
        if value == 0:
            return 0
        try:
            location(value & ~7)
            return value
        except ValueError:
            # arm64e chained/authenticated pointers in an on-disk image encode
            # image-relative targets rather than ordinary process addresses.
            candidate = min(seg[0] for seg in segments if seg[2] == 0 and seg[1] > seg[0]) + (value & 0xFFFFFFFF)
            location(candidate & ~7)
            return candidate

    def text(address):
        start = location(address)
        end = data.index(0, start)
        return data[start:end].decode(errors="replace")

    def methods(address):
        if not address:
            return []
        pos = location(address)
        flags, count = struct.unpack_from("<II", data, pos)
        small = flags & 0x80000000
        direct = flags & 0x40000000
        stride = flags & 0xFFFF
        if not 0 < stride <= 128 or count > 10000:
            raise ValueError("Invalid method list")
        result = []
        for index in range(count):
            entry = address + 8 + index * stride
            if small:
                n, t, imp = struct.unpack_from("<iii", data, location(entry))
                nameaddr = entry + n
                if not direct:
                    nameaddr = u64(nameaddr)
                typeaddr, implementation = entry + 4 + t, entry + 8 + imp
            else:
                nameaddr, typeaddr, implementation = struct.unpack_from("<QQQ", data, location(entry))
            result.append({"selector": text(nameaddr), "types": text(typeaddr),
                           "implementation": hex(implementation)})
        return result

    address, length = sections["__objc_classlist"]
    for index in range(length // 8):
        try:
            cls = u64(address + index * 8)
            ro = u64(cls + 32) & ~7
            name = text(u64(ro + 24))
            if not re.search(pattern, name):
                continue
            instance_methods = methods(u64(ro + 32))
            meta = u64(cls)
            try:
                meta_ro = u64(meta + 32) & ~7
                class_methods = methods(u64(meta_ro + 32))
            except (ValueError, struct.error):
                class_methods = None
            yield {"class": name, "instance": instance_methods,
                   "class_methods": class_methods}
        except (ValueError, struct.error):
            # Swift classes may not have a directly readable ObjC class_ro.
            continue


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("macho")
    parser.add_argument("--class-pattern", required=True)
    args = parser.parse_args()
    print(json.dumps(list(inspect(args.macho, args.class_pattern)), indent=2))
