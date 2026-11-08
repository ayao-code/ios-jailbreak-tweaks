#!/usr/bin/env python3
"""Offline, exact-length App Group experiment. Never installs or runs app code."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import tempfile
import unicodedata
import zipfile

OLD_GROUP = 'group.cn.damai.damaiApp'
GROUP_KEY = 'com.apple.security.application-groups'
MAGICS = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
          b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf',
          b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def layout(data):
    """This prototype refuses FAT/32-bit; all current inputs are thin arm64."""
    require(data[:4] == b'\xcf\xfa\xed\xfe', 'Only thin little-endian 64-bit Mach-O supported')
    require(len(data) >= 32, 'Truncated Mach-O header')
    cpu, sub, _, count, size, _ = struct.unpack_from('<6I', data, 4)
    require(cpu == 0x100000c and sub & 0xffffff == 0, 'Not ordinary arm64')
    end = 32 + size
    require(end <= len(data) and count <= size // 8, 'Invalid load commands')
    pos, sections, crypt, signature = 32, [], [], None
    for _ in range(count):
        require(pos + 8 <= end, 'Missing load command')
        cmd, length = struct.unpack_from('<II', data, pos)
        require(length >= 8 and pos + length <= end, 'Invalid command size')
        if cmd == 0x19:
            require(length >= 72, 'Invalid segment')
            nsects = struct.unpack_from('<I', data, pos + 64)[0]
            require(72 + 80 * nsects <= length, 'Invalid section count')
            for n in range(nsects):
                start = pos + 72 + n * 80
                sect, seg = struct.unpack_from('<16s16s', data, start)
                address, nbytes, offset = struct.unpack_from('<QQI', data, start + 32)
                flags = struct.unpack_from('<I', data, start + 64)[0]
                kind = flags & 255
                if kind not in {1, 0xc, 0x12}:
                    require(offset + nbytes <= len(data), 'Section beyond file')
                sections.append({'name': seg.rstrip(b'\0').decode() + ',' + sect.rstrip(b'\0').decode(),
                                 'address': address, 'offset': offset, 'size': nbytes, 'flags': flags,
                                 'zero_fill': kind in {1, 0xc, 0x12}})
        elif cmd in {0x21, 0x2c}:
            require(length >= 20, 'Invalid encryption command')
            off, nbytes, cryptid = struct.unpack_from('<III', data, pos + 8)
            require(off + nbytes <= len(data), 'Encryption range beyond file')
            crypt.append({'offset': off, 'size': nbytes, 'cryptid': cryptid})
        elif cmd == 0x1d:
            require(length >= 16 and signature is None, 'Invalid signature command')
            off, nbytes = struct.unpack_from('<II', data, pos + 8)
            require(off + nbytes <= len(data), 'Signature beyond file')
            signature = {'offset': off, 'size': nbytes}
        pos += length
    require(pos == end, 'Incomplete load commands')
    return {'sections': sections, 'crypt': crypt, 'signature': signature}


def entitlements(signer, binary):
    raw = subprocess.check_output([signer, '-e', str(binary)], timeout=30)
    documents = re.findall(rb'<\?xml[\s\S]*?</plist>', raw)
    require(not raw.strip() or documents, 'Unparseable entitlements')
    values = [plistlib.loads(document) for document in documents]
    require(all(isinstance(value, dict) for value in values), 'Invalid entitlement type')
    require(not values or all(value == values[0] for value in values), 'Conflicting slice entitlements')
    return values[0] if values else {}


def map_locations(data, parsed, old):
    locations, cursor = [], 0
    while True:
        offset = data.find(old, cursor)
        if offset < 0:
            break
        cursor = offset + len(old)
        signature = parsed['signature']
        if signature and signature['offset'] <= offset and offset + len(old) <= signature['offset'] + signature['size']:
            # XML/DER signature data is rewritten by ldid, never raw-patched.
            continue
        section = next((s for s in parsed['sections'] if not s['zero_fill'] and
                        s['offset'] <= offset and offset + len(old) <= s['offset'] + s['size']), None)
        require(section is not None and section['name'].endswith(',__cstring'),
                f'Group occurrence outside allowed cstring at {offset}')
        require(not section['flags'] & 0x80000400, 'Group occurrence in instruction section')
        require(offset == section['offset'] or data[offset - 1] == 0, 'Group occurrence is not a string start')
        string_end = data.find(b'\0', offset, section['offset'] + section['size'])
        require(string_end >= 0 and data[offset:string_end] in {old, old + b'OS'},
                'Unknown group-name suffix; refusing prefix-wide replacement')
        for c in parsed['crypt']:
            require(not (c['cryptid'] and offset < c['offset'] + c['size'] and c['offset'] < offset + len(old)),
                    'Group occurrence overlaps ciphertext')
        locations.append({'offset': offset, 'section': section['name'],
                          'old_string': data[offset:string_end].decode()})
    return locations


def migrate_binary(signer, binary, scratch, old_group, new_group):
    before = binary.read_bytes()
    parsed = layout(before)
    locations = map_locations(before, parsed, old_group.encode())
    old_ent = entitlements(signer, binary)
    groups = old_ent.get(GROUP_KEY, [])
    require(isinstance(groups, list) and all(isinstance(g, str) for g in groups), 'Invalid group grant')
    expected_ent = dict(old_ent)
    if GROUP_KEY in old_ent:
        expected_ent[GROUP_KEY] = [new_group + g[len(old_group):] if g in {old_group, old_group + 'OS'} else g for g in groups]
    if not locations and expected_ent == old_ent:
        return None
    patched = bytearray(before)
    for location in locations:
        offset = location['offset']
        patched[offset:offset + len(old_group)] = new_group.encode()
    binary.write_bytes(patched)
    xml = scratch / 'group-entitlements.plist'
    xml.write_bytes(plistlib.dumps(expected_ent, fmt=plistlib.FMT_XML))
    subprocess.run([signer, '-S' + str(xml), str(binary)], check=True, capture_output=True, timeout=60)
    after = binary.read_bytes()
    final = layout(after)
    require(entitlements(signer, binary) == expected_ent, 'Signed entitlement readback differs')
    require(final['sections'] == parsed['sections'], 'Section layout changed while signing')
    require(final['crypt'] == parsed['crypt'], 'Encryption commands changed while signing')
    for section in parsed['sections']:
        if section['zero_fill']:
            continue
        start, end = section['offset'], section['offset'] + section['size']
        require(after[start:end] == patched[start:end], f"Signing altered section {section['name']}")
    for crypt in parsed['crypt']:
        start, end = crypt['offset'], crypt['offset'] + crypt['size']
        require(after[start:end] == before[start:end], 'Crypt range bytes changed')
    # Re-scan old group name: occurrences in the original string pool must be gone.
    require(not map_locations(after, final, old_group.encode()), 'Old cstring group remains after signing')
    require(not any(g in {old_group, old_group + 'OS'} for g in entitlements(signer, binary).get(GROUP_KEY, [])),
            'Old group grant remains')
    return {'path': str(binary.name), 'cstring_patches': locations,
            'entitlements_before': old_ent, 'entitlements_after': expected_ent,
            'sha256_before': sha(before), 'sha256_after': sha(after),
            'encrypted': any(c['cryptid'] for c in parsed['crypt']),
            'section_bytes_equal_planned_patch': True, 'crypt_range_bytes_unchanged': True,
            'instruction_sections_unchanged': True}


def migrate(input_path, output_dir, signer):
    input_path = input_path.resolve()
    output_dir = output_dir.resolve()
    require(not output_dir.exists(), 'Output directory must not already exist')
    source_hash = sha(input_path.read_bytes())
    output_dir.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.shared-group-work-', dir=output_dir.parent) as work:
        work = Path(work)
        tree = work / 'tree'
        tree.mkdir()
        with zipfile.ZipFile(input_path) as archive:
            entries = archive.infolist()
            require(len(entries) <= 50000, 'Too many ZIP entries')
            require(sum(e.file_size for e in entries) <= 2147483648, 'Expanded archive too large')
            require(shutil.disk_usage(work).free >= sum(e.file_size for e in entries) * 2 + 268435456,
                    'Insufficient workspace')
            seen = set()
            for entry in entries:
                parts = PurePosixPath(entry.filename).parts
                key = unicodedata.normalize('NFC', entry.filename.rstrip('/')).lower()
                require(parts and not entry.filename.startswith('/') and '\\' not in entry.filename and
                        '..' not in parts and '.' not in entry.filename.rstrip('/').split('/') and
                        '' not in entry.filename.rstrip('/').split('/') and key not in seen,
                        'Unsafe/duplicate ZIP entry')
                mode = entry.external_attr >> 16
                require(stat.S_IFMT(mode) in {0, stat.S_IFREG, stat.S_IFDIR}, 'Special ZIP file unsupported')
                require(not entry.flag_bits & 1, 'ZIP encrypted entries unsupported')
                seen.add(key)
                path = tree / entry.filename
                require(path.resolve().is_relative_to(tree.resolve()), 'ZIP path escapes workspace')
                if entry.is_dir():
                    path.mkdir(parents=True, exist_ok=True)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with archive.open(entry) as src, path.open('wb') as dest:
                        shutil.copyfileobj(src, dest, 65536)
                    if mode & 0o777:
                        path.chmod(mode & 0o777)
            info_paths = list((tree / 'Payload').glob('*.app/Info.plist'))
            require(len(info_paths) == 1 and len(list((tree / 'Payload').iterdir())) == 1, 'Expected one main app')
            info = plistlib.loads(info_paths[0].read_bytes())
            clone_id = info['CFBundleIdentifier']
            require(isinstance(clone_id, str) and clone_id.startswith('cn.damai.iphone.'),
                    'Only already-created Damai clones accepted; never modify original identity')
            new_group = 'group.cn.damai.' + hashlib.sha256((clone_id + '\0' + OLD_GROUP).encode()).hexdigest()[:8]
            require(len(new_group.encode()) == len(OLD_GROUP.encode()) and new_group != OLD_GROUP,
                    'Replacement must have identical byte length')
            before_hashes = {e.filename: sha((tree / e.filename).read_bytes()) for e in entries if not e.is_dir()}
            changed, binaries, nonbinary_hits = [], [], []
            for name in before_hashes:
                path = tree / name
                with path.open('rb') as f:
                    magic = f.read(4)
                if magic in MAGICS:
                    record = migrate_binary(signer, path, work, OLD_GROUP, new_group)
                    binaries.append(name)
                    if record:
                        record['path'] = name
                        changed.append(record)
                else:
                    data = path.read_bytes()
                    if OLD_GROUP.encode() in data:
                        nonbinary_hits.append(name)
            require(not nonbinary_hits, 'Group name found in non-Mach-O resources; needs separate plan: ' + str(nonbinary_hits))
            require(changed, 'No eligible group references or grants')
            require(any(r['path'] == str(info_paths[0].parent.relative_to(tree) / info['CFBundleExecutable']) for r in changed),
                    'Main binary did not migrate')
            allowed = {r['path'] for r in changed}
            after_hashes = {name: sha((tree / name).read_bytes()) for name in before_hashes}
            require(all(before_hashes[n] == after_hashes[n] for n in before_hashes if n not in allowed),
                    'Unrelated file changed')
            temp_ipa = work / 'candidate.ipa'
            with zipfile.ZipFile(temp_ipa, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as dest:
                dest.comment = archive.comment
                for entry in entries:
                    # Preserve entry names, permissions and metadata; update CRC/size.
                    with dest.open(entry, 'w') as target:
                        if not entry.is_dir():
                            with (tree / entry.filename).open('rb') as src:
                                shutil.copyfileobj(src, target, 65536)
            with zipfile.ZipFile(temp_ipa) as final:
                require(final.testzip() is None, 'Output ZIP CRC failure')
                require(final.namelist() == [e.filename for e in entries], 'Output entry set/order changed')
                require(all(sha(final.read(n)) == after_hashes[n] for n in after_hashes), 'Packaged bytes differ')
        require(sha(input_path.read_bytes()) == source_hash, 'Source changed during operation')
        report = {'input_ipa': str(input_path), 'input_sha256': source_hash,
                  'clone_id_unchanged': clone_id, 'old_group': OLD_GROUP, 'new_group': new_group,
                  'aliases': {OLD_GROUP + 'OS': new_group + 'OS'},
                  'changed_files': changed, 'macho_count': len(binaries),
                  'unchanged_non_target_file_count': len(before_hashes) - len(allowed),
                  'ipa_sha256': sha(temp_ipa.read_bytes()), 'ipa_bytes': temp_ipa.stat().st_size,
                  'source_unchanged': True, 'zip_crc_valid': True,
                  'app_identity_keychain_callbacks_and_extensions_unchanged': True,
                  'instructions_and_crypt_ranges_unchanged': True,
                  'installed': False, 'runtime_verified': False,
                  'limits': ['Only discovered static C strings and existing grants migrated; dynamic group construction not proven.',
                             'Encrypted extensions retained with cryptid unchanged, not decrypted.',
                             'AppIntents originally had no group grant; none added.',
                             'No data or push tokens copied; new group initializes empty.',
                             'No independent APNs, keychain isolation, or login compatibility guaranteed.',
                             'Only thin arm64 and exact-length cstring replacements supported.']}
        output_dir.mkdir(mode=0o700)
        try:
            shutil.copy2(temp_ipa, output_dir / 'Damai-shared-group-experiment.ipa')
            (output_dir / 'group-migration-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        except BaseException:
            shutil.rmtree(output_dir)
            raise
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--signer', default=shutil.which('ldid'))
    args = parser.parse_args()
    require(args.signer, 'ldid is required')
    report = migrate(args.input, args.output_dir, args.signer)
    print(json.dumps({k: report[k] for k in ['new_group', 'clone_id_unchanged', 'macho_count',
                                            'ipa_bytes', 'installed', 'runtime_verified']}, indent=2))


if __name__ == '__main__':
    main()
