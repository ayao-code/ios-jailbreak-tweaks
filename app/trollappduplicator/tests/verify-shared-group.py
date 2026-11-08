#!/usr/bin/env python3
"""Negative preflight fixtures and independent checks of an offline candidate."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('group_migration', ROOT / 'scripts/migrate-shared-group.py')
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


def fixture(text, instruction=False, encrypted=False):
    off = 32 + 152 + 24
    header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 2, 176, 0, 0)
    segment = struct.pack('<II16sQQQQIIII', 0x19, 152, b'__TEXT', 0, off + len(text),
                          0, off + len(text), 7, 5, 1, 0)
    section = struct.pack('<16s16sQQIIIIIIII', b'__cstring', b'__TEXT', off,
                          len(text), off, 0, 0, 0, 0x80000400 if instruction else 2, 0, 0, 0)
    crypt = struct.pack('<6I', 0x2c, 24, off if encrypted else 0, len(text) if encrypted else 0,
                        int(encrypted), 0)
    return header + segment + section + crypt + text


def verify(candidate_dir):
    results = []
    old = migration.OLD_GROUP.encode()
    tests = [('exact-group', old + b'\0', {}, True),
             ('group-OS-alias', old + b'OS\0', {}, True),
             ('two-group-literals', old + b'\0' + old + b'OS\0', {}, True),
             ('encrypted-occurrence', old + b'\0', {'encrypted': True}, False),
             ('instruction-occurrence', old + b'\0', {'instruction': True}, False),
             ('unknown-group-suffix', old + b'Elsewhere\0', {}, False),
             ('substring-not-start', b'prefix' + old + b'\0', {}, False),
             ('unterminated', old, {}, False)]
    for name, text, options, accepted in tests:
        data = fixture(text, **options)
        try:
            matches = migration.map_locations(data, migration.layout(data), old)
            actual = bool(matches)
        except ValueError:
            actual = False
        if actual != accepted:
            raise AssertionError(name)
        results.append({'case': name, 'passed': True})
    try:
        migration.layout(b'\xca\xfe\xba\xbe' + bytes(64))
        raise AssertionError('FAT accepted')
    except ValueError:
        results.append({'case': 'unsupported-fat-rejected', 'passed': True})
    report = json.loads((candidate_dir / 'group-migration-report.json').read_text())
    before_path = Path(report['input_ipa'])
    after_path = candidate_dir / 'Damai-shared-group-experiment.ipa'
    if hashlib.sha256(before_path.read_bytes()).hexdigest() != report['input_sha256']:
        raise AssertionError('Input changed')
    changed = {entry['path'] for entry in report['changed_files']}
    with tempfile.TemporaryDirectory(prefix='shared-group-check-') as work:
        work = Path(work)
        # Independent production C parser/code comparison in addition to Python checks.
        source = work / 'codecheck.c'
        source.write_text('#include "MachOInspector.h"\n'
                          'int main(int n,char **v) { if(n!=3)return 2; '
                          'CloneMachOInfo a=cloneInspectMachO(v[1]),b=cloneInspectMachO(v[2]); '
                          'return !a.malformed && !b.malformed && a.encrypted==b.encrypted && '
                          'a.has_arm64==b.has_arm64 && a.max_minimum_ios==b.max_minimum_ios && '
                          'a.jailbreak_dependency==b.jailbreak_dependency && '
                          'cloneMachOCodeEqual(v[1],v[2]) ? 0 : 1; }\n')
        checker = work / 'codecheck'
        subprocess.run(['clang', '-I' + str(ROOT), str(source), str(ROOT / 'MachOInspector.c'),
                        '-o', str(checker)], check=True)
        with zipfile.ZipFile(before_path) as before, zipfile.ZipFile(after_path) as after:
            if after.testzip() is not None or before.namelist() != after.namelist():
                raise AssertionError('ZIP changed unexpectedly')
            actual_changes = set()
            for name in before.namelist():
                if name.endswith('/'):
                    continue
                a, b = before.read(name), after.read(name)
                if a != b:
                    actual_changes.add(name)
                if name not in changed:
                    if a != b:
                        raise AssertionError('Unrelated file changed: ' + name)
                    continue
                apath, bpath = work / 'before', work / 'after'
                apath.write_bytes(a)
                bpath.write_bytes(b)
                subprocess.run([str(checker), str(apath), str(bpath)], check=True)
                aa, bb = migration.layout(a), migration.layout(b)
                for crypt in aa['crypt']:
                    start, end = crypt['offset'], crypt['offset'] + crypt['size']
                    if a[start:end] != b[start:end]:
                        raise AssertionError('Ciphertext changed: ' + name)
                ea, eb = migration.entitlements('ldid', apath), migration.entitlements('ldid', bpath)
                if {k: v for k, v in ea.items() if k != migration.GROUP_KEY} != {k: v for k, v in eb.items() if k != migration.GROUP_KEY}:
                    raise AssertionError('Non-group entitlements changed: ' + name)
                results.append({'case': 'independent-code-crypt-entitlement-check', 'path': name, 'passed': True})
            if actual_changes != changed:
                raise AssertionError('Changed-file manifest differs')
    results.append({'case': 'exact-file-change-scope-and-zip', 'passed': True})
    result = {'checks': len(results), 'passed': len(results), 'results': results,
              'device_install_or_login_verified': False, 'full_dynamic_group_reference_coverage_proven': False}
    (candidate_dir / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--candidate-dir', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.candidate_dir), indent=2))
