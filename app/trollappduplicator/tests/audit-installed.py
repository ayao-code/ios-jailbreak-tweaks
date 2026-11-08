#!/usr/bin/env python3
"""Offline audit of an explicitly exported installed bundle; never run app code."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zipfile

MAGICS = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf',
          b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf',
          b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'}


def digest(path):
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def slices(data):
    magic = data[:4]
    if magic in {b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf',
                 b'\xbe\xba\xfe\xca', b'\xbf\xba\xfe\xca'}:
        endian = '>' if magic[:2] == b'\xca\xfe' else '<'
        wide = magic in {b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}
        count = struct.unpack_from(endian + 'I', data, 4)[0]
        assert 0 < count <= 64
        result = []
        for index in range(count):
            pos = 8 + index * (32 if wide else 20)
            _, _, off, size = struct.unpack_from(endian + ('IIQQ' if wide else 'IIII'), data, pos)
            assert off + size <= len(data)
            result += slices(data[off:off + size])
        return result
    assert magic in MAGICS
    endian = '<' if magic in {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe'} else '>'
    wide = magic in {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf'}
    cpu, sub, _, count, command_bytes, _ = struct.unpack_from(endian + '6I', data, 4)
    pos = 32 if wide else 28
    end = pos + command_bytes
    assert end <= len(data) and count <= command_bytes // 8
    cryptids, dependencies, minimum, code = [], [], [], []
    for _ in range(count):
        cmd, size = struct.unpack_from(endian + 'II', data, pos)
        assert size >= 8 and pos + size <= end
        if cmd in {0x21, 0x2c}:
            off, length, cryptid = struct.unpack_from(endian + 'III', data, pos + 8)
            assert off + length <= len(data)
            cryptids.append(cryptid)
        elif cmd in {0xc, 0x80000018, 0x8000001f, 0x80000023, 0x20, 0x8000001c}:
            off = struct.unpack_from(endian + 'I', data, pos + 8)[0]
            assert off < size
            dependencies.append(data[pos + off:pos + size].split(b'\0', 1)[0].decode())
        elif cmd in {0x25, 0x32}:
            minimum.append(struct.unpack_from(endian + 'I', data, pos + (12 if cmd == 0x32 else 8))[0])
        elif cmd in {0x1, 0x19}:
            is64 = cmd == 0x19
            nsects = struct.unpack_from(endian + 'I', data, pos + (64 if is64 else 48))[0]
            start, step = (72, 80) if is64 else (56, 68)
            assert start + nsects * step <= size
            for n in range(nsects):
                section = pos + start + n * step
                length = struct.unpack_from(endian + ('Q' if is64 else 'I'), data, section + (40 if is64 else 36))[0]
                offset = struct.unpack_from(endian + 'I', data, section + (48 if is64 else 40))[0]
                flags = struct.unpack_from(endian + 'I', data, section + (64 if is64 else 56))[0]
                if flags & 0x80000400:
                    assert offset + length <= len(data)
                    code.append((data[section:section + 32].hex(), length,
                                 hashlib.sha256(data[offset:offset + length]).hexdigest()))
        pos += size
    assert pos == end
    return [{'cpu': cpu, 'subtype': sub, 'cryptids': cryptids, 'encrypted': any(cryptids),
            'minimum_ios_packed': max(minimum, default=0), 'dependencies': dependencies,
            'instruction_sections': code}]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--evidence', type=Path, required=True)
    parser.add_argument('--source-ipa', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = args.evidence
    bundle = root / 'clone/bundle'
    info = plistlib.loads((bundle / 'Info.plist').read_bytes())
    ent = plistlib.loads((root / 'clone/main-entitlements.plist').read_bytes())
    original_ent = plistlib.loads((root / 'original/main-entitlements.plist').read_bytes())
    reports = [json.loads(p.read_text()) for p in (root / 'generation-reports').glob('*.json')]
    report = next((r for r in reports if r['name'] == info.get('CFBundleDisplayName')), reports[0])
    original_reg = (root / 'original/registration.txt').read_text()
    clone_reg = (root / 'clone/registration.txt').read_text()
    def field(text, label):
        return next((line.split(': ', 1)[1] for line in text.splitlines() if line.startswith(label + ': ')), None)
    original_container = field(original_reg, 'Data Container Path')
    clone_container = field(clone_reg, 'Data Container Path')
    binaries, hashes, errors = [], {}, []
    privileged = ['platform-application', 'com.apple.private.security.no-sandbox',
                  'com.apple.private.security.no-container', 'task_for_pid-allow',
                  'com.apple.private.security.storage.AppDataContainers',
                  'com.apple.private.security.storage.AppBundles']
    with zipfile.ZipFile(args.source_ipa) as source:
        source_main = 'Payload/DMPortal.app/'
        for path in sorted(bundle.rglob('*')):
            if not path.is_file():
                continue
            relative = path.relative_to(bundle).as_posix()
            hashes[relative] = digest(path)
            with path.open('rb') as f:
                magic = f.read(4)
            if magic not in MAGICS:
                continue
            try:
                parsed = slices(path.read_bytes())
                raw = subprocess.check_output(['ldid', '-e', str(path)])
                signed = plistlib.loads(raw) if raw.strip() else {}
                source_slices = slices(source.read(source_main + relative))
                code_same = [s['instruction_sections'] for s in parsed] == [s['instruction_sections'] for s in source_slices]
                known_dependencies = [d for s in parsed for d in s['dependencies']
                                      if any(marker in d for marker in ['/var/jb', '.jbroot', 'Substrate', 'AutoSkip', 'libsubstrate'])]
                record = {'path': relative, 'sha256': hashes[relative], 'slices': parsed,
                          'entitlements': signed, 'instruction_sections_equal_source': code_same,
                          'known_jailbreak_dependencies': known_dependencies}
                binaries.append(record)
            except Exception as error:
                errors.append({'path': relative, 'error': str(error)})
    resource_changes = []
    binary_paths = {b['path'] for b in binaries}
    for name, expected_hash in report['source_file_hashes'].items():
        if name in binary_paths or name.endswith('Info.plist') or name.endswith('InfoPlist.strings') or '_CodeSignature/' in name or name.endswith('embedded.mobileprovision'):
            continue
        if hashes.get(name) != expected_hash:
            resource_changes.append(name)
    excluded = [name for name in hashes if any(m in name for m in ['.troll-fools', 'AutoSkip', 'CydiaSubstrate'])]
    original_schemes = {line.split(': ', 1)[1].lower() for line in original_reg.splitlines() if line.startswith('URL Scheme: ')}
    clone_schemes = {line.split(': ', 1)[1].lower() for line in clone_reg.splitlines() if line.startswith('URL Scheme: ')}
    checks = {
        'source_matches_generation_report': digest(args.source_ipa) == report['source_sha256'],
        'protection_enabled': all(r['protect_original'] for r in reports),
        'bundle_id_matches_report': info['CFBundleIdentifier'] == report['clone_bundle_id'],
        'display_name_matches_report': info.get('CFBundleDisplayName') == report['name'],
        'distinct_data_containers': bool(original_container and clone_container and original_container != clone_container),
        'container_metadata_identity': plistlib.loads((root / 'clone/container-metadata.plist').read_bytes())['MCMMetadataIdentifier'] == info['CFBundleIdentifier'],
        'independent_application_identity': ent['application-identifier'] != original_ent['application-identifier'],
        'exact_independent_keychain_group': ent.get('keychain-access-groups') == [ent['application-identifier']],
        'no_original_keychain_identity': original_ent['application-identifier'] not in ent.get('keychain-access-groups', []),
        'container_required_matches_clone': ent.get('com.apple.private.security.container-required') == info['CFBundleIdentifier'],
        'no_original_group_declaration_or_registration': not ent.get('com.apple.security.application-groups') and 'Group Container:' not in clone_reg,
        'no_callback_conflicts': not clone_schemes and not info.get('CFBundleURLTypes'),
        'no_associated_domain_or_push_entitlement': not ent.get('com.apple.developer.associated-domains') and not ent.get('aps-environment'),
        'no_embedded_extensions': not any('.appex/' in name or name.endswith('.appex') for name in hashes),
        'no_privileged_app_or_framework_signature': not any(any(key in b['entitlements'] for key in privileged) for b in binaries),
        'no_encrypted_or_parse_failure': not errors and not any(s['encrypted'] for b in binaries for s in b['slices']),
        'all_arm64_and_supported_os': bool(binaries) and all(any(s['cpu'] == 0x100000c and s['subtype'] & 0xffffff == 0 for s in b['slices']) and all(s['minimum_ios_packed'] <= 0x100301 for s in b['slices']) for b in binaries),
        'no_known_injected_markers_or_dependencies': not excluded and not any(b['known_jailbreak_dependencies'] for b in binaries),
        'instruction_sections_equal_decrypted_source': bool(binaries) and all(b['instruction_sections_equal_source'] for b in binaries),
        'non_target_resources_unchanged': not resource_changes,
        'installed_main_entitlements_match_generation': ent == next(s['entitlements'] for s in report['signed_objects'] if s['path'] == info['CFBundleExecutable']),
    }
    result = {'checks': checks, 'passed': sum(checks.values()), 'total': len(checks),
              'original_container': original_container, 'clone_container': clone_container,
              'original_url_scheme_count': len(original_schemes), 'clone_url_scheme_count': len(clone_schemes),
              'duplicate_schemes': sorted(original_schemes & clone_schemes),
              'installed_macho_count': len(binaries), 'installed_file_count': len(hashes),
              'binaries': binaries, 'parse_errors': errors, 'changed_resources': resource_changes,
              'removed_components': report['removed_components'],
              'runtime_login_payment_and_original_noninterference_verified': False,
              'runtime_jailbreak_detection_or_loaded_images_verified': False}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ['passed', 'total', 'installed_macho_count', 'original_url_scheme_count', 'clone_url_scheme_count', 'changed_resources', 'parse_errors']}, ensure_ascii=False))
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
