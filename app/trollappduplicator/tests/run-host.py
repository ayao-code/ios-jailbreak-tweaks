#!/usr/bin/env python3
"""Run the real packager on self-created fixtures only, never installed apps."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
binary = root / '.theos/_/Applications/TrollAppDuplicator.app/TrollAppDuplicator'
runner = Path('/tmp/clonestudio-host-build/runner')
ldid = shutil.which('ldid')
results = []

def pack(tree, path):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in sorted(tree.rglob('*')):
            if p.is_file():
                z.write(p, p.relative_to(tree))

def entitlements(data, directory):
    p = directory / 'read-entitlement-binary'
    p.write_bytes(data)
    raw = subprocess.check_output([ldid, '-e', str(p)])
    return plistlib.loads(raw)

with tempfile.TemporaryDirectory(prefix='clonestudio-fixtures-') as work:
    work = Path(work)
    tree = work / 'tree'
    app = tree / 'Payload/Fixture.app'
    app.mkdir(parents=True)
    (app / 'Fixture').write_bytes(binary.read_bytes())
    source_ent = {'application-identifier': 'ORIGINAL.com.example.fixture',
                  'com.apple.security.application-groups': ['group.original.fixture'],
                  'com.apple.developer.associated-domains': ['applinks:example.invalid'],
                  'aps-environment': 'production', 'platform-application': True,
                  'com.apple.private.security.no-sandbox': True,
                  'com.apple.private.security.storage.AppDataContainers': True,
                  'keychain-access-groups': ['ORIGINAL.*']}
    xml = work / 'original-entitlements.plist'
    xml.write_bytes(plistlib.dumps(source_ent))
    subprocess.run([ldid, '-S' + str(xml), str(app / 'Fixture')], check=True)
    info = {'CFBundleIdentifier': 'com.example.fixture', 'CFBundleExecutable': 'Fixture',
            'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1',
            'CFBundleURLTypes': [{'CFBundleURLSchemes': ['original-callback']}],
            'UIBackgroundModes': ['remote-notification'],
            'CFBundleDocumentTypes': [{'CFBundleTypeName': 'Original'}]}
    (app / 'Info.plist').write_bytes(plistlib.dumps(info))
    (app / 'zh-Hans.lproj').mkdir()
    (app / 'zh-Hans.lproj/InfoPlist.strings').write_bytes(plistlib.dumps({'CFBundleDisplayName': 'Old'}))
    extension = app / 'PlugIns/Fixture.appex'
    extension.mkdir(parents=True)
    (extension / 'FixtureExt').write_bytes((app / 'Fixture').read_bytes())
    (extension / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleIdentifier': 'com.example.fixture.ext', 'CFBundleExecutable': 'FixtureExt',
        'CFBundlePackageType': 'XPC!', 'CFBundleVersion': '1'}))
    (app / 'asset.txt').write_text('immutable fixture resource')
    fixture = work / 'fixture.ipa'
    pack(tree, fixture)
    input_hash = hashlib.sha256(fixture.read_bytes()).hexdigest()
    env = dict(os.environ, CLONE_FIXTURE_SIGNER=ldid, CLONE_FIXTURE_OUTPUT=str(work / 'outputs'))
    for mode in [1, 0, 1]:
        run = subprocess.run([str(runner), str(fixture), str(mode)], env=env, capture_output=True)
        assert run.returncode == 0, run.stdout.decode() + run.stderr.decode()
        generated = json.loads(run.stdout)
        report = json.loads(Path(generated['report']).read_text())
        with zipfile.ZipFile(generated['ipa']) as z:
            assert z.testzip() is None
            assert all(n.startswith('Payload/') for n in z.namelist()), z.namelist()
            next_info = plistlib.loads(z.read('Payload/Fixture.app/Info.plist'))
            ent = entitlements(z.read('Payload/Fixture.app/Fixture'), work)
            assert next_info['CFBundleIdentifier'] == generated['cloneID']
            assert ent['com.apple.private.security.container-required'] == generated['cloneID']
            assert ent['application-identifier'] == 'AYAOCLONE.' + generated['cloneID']
            assert ent['keychain-access-groups'] == [ent['application-identifier']]
            assert 'platform-application' not in ent and 'com.apple.private.security.no-sandbox' not in ent
            assert 'com.apple.private.security.storage.AppDataContainers' not in ent
            assert ('com.apple.security.application-groups' not in ent) == bool(mode)
            assert ('CFBundleURLTypes' not in next_info) == bool(mode)
            assert ('UIBackgroundModes' not in next_info) == bool(mode)
            has_extension = 'Payload/Fixture.app/PlugIns/Fixture.appex/FixtureExt' in z.namelist()
            assert has_extension == (mode == 0)
            if has_extension:
                ext_info = plistlib.loads(z.read('Payload/Fixture.app/PlugIns/Fixture.appex/Info.plist'))
                ext_ent = entitlements(z.read('Payload/Fixture.app/PlugIns/Fixture.appex/FixtureExt'), work)
                assert ext_info['CFBundleIdentifier'].startswith(generated['cloneID'] + '.ext')
                assert ext_ent['com.apple.private.security.container-required'] == ext_info['CFBundleIdentifier']
                assert 'com.apple.private.security.storage.AppDataContainers' not in ext_ent
            assert z.read('Payload/Fixture.app/asset.txt') == b'immutable fixture resource'
            assert plistlib.loads(z.read('Payload/Fixture.app/zh-Hans.lproj/InfoPlist.strings'))['CFBundleDisplayName'] == '测试分身'
        results.append({'case': 'packager-mode-' + str(mode), 'passed': True, 'clone_id': generated['cloneID']})
    assert results[0]['clone_id'] == results[2]['clone_id']
    assert results[0]['clone_id'] != results[1]['clone_id']
    assert hashlib.sha256(fixture.read_bytes()).hexdigest() == input_hash
    results.append({'case': 'identity-reuse-and-input-immutability', 'passed': True})

    def reject(path, case):
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        run = subprocess.run([str(runner), str(path), '1'], env=env, capture_output=True)
        assert run.returncode != 0, case
        assert hashlib.sha256(path.read_bytes()).hexdigest() == before
        results.append({'case': case, 'passed': True, 'error': json.loads(run.stdout)['error']})

    for member, case in [('Payload/Fixture.app/../../escape', 'zip-traversal'),
                         ('Payload/Fixture.app/ASSET.TXT', 'zip-case-collision')]:
        bad = work / (case + '.ipa')
        shutil.copyfile(fixture, bad)
        with zipfile.ZipFile(bad, 'a') as z:
            z.writestr(member, 'bad')
        reject(bad, case)
    injected = work / 'injected.ipa'
    shutil.copyfile(fixture, injected)
    with zipfile.ZipFile(injected, 'a') as z:
        z.writestr('Payload/Fixture.app/PlugIns/Dummy.appex/.troll-fools', 'marker')
    reject(injected, 'injected-marker-before-component-removal')
    symlink = work / 'symlink.ipa'
    shutil.copyfile(fixture, symlink)
    with zipfile.ZipFile(symlink, 'a') as z:
        link = zipfile.ZipInfo('Payload/Fixture.app/link')
        link.create_system = 3
        link.external_attr = 0o120777 << 16
        z.writestr(link, '/outside')
    reject(symlink, 'zip-symlink-rejected')
    original_info = (app / 'Info.plist').read_bytes()
    incompatible = work / 'high-plist-ios.ipa'
    high = dict(info, MinimumOSVersion='17.0')
    (app / 'Info.plist').write_bytes(plistlib.dumps(high))
    pack(tree, incompatible)
    reject(incompatible, 'high-plist-ios-rejected')
    (app / 'Info.plist').write_bytes(original_info)
    high_code = work / 'high-binary-ios.ipa'
    (app / 'Fixture').write_bytes(
        struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        + struct.pack('<6I', 0x32, 24, 2, 17 << 16, 17 << 16, 0))
    pack(tree, high_code)
    reject(high_code, 'high-binary-ios-rejected')
    # Set an encryption command on a self-created minimal Mach-O.
    encrypted = work / 'encrypted.ipa'
    code = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
    code += struct.pack('<6I', 0x2c, 24, 56, 4, 1, 0) + b'lock'
    (app / 'Fixture').write_bytes(code)
    pack(tree, encrypted)
    reject(encrypted, 'encrypted-main-rejected')
    (app / 'Fixture').write_bytes(b'\xcf\xfa\xed\xfe' + b'\0' * 5)
    malformed = work / 'malformed.ipa'
    pack(tree, malformed)
    reject(malformed, 'malformed-main-rejected')
    # Confirm the real code-invariance checker rejects instruction mutation.
    checker_source = work / 'code-check.c'
    checker_source.write_text('#include "MachOInspector.h"\nint main(int n,char **v){return n==3 && cloneMachOCodeEqual(v[1],v[2])?0:1;}\n')
    checker = work / 'code-check'
    subprocess.run(['clang', '-I' + str(root), str(checker_source),
                    str(root / 'MachOInspector.c'), '-o', str(checker)], check=True)
    data = bytearray(binary.read_bytes())
    assert data[:4] == b'\xcf\xfa\xed\xfe'
    command = 32
    mutation = None
    for _ in range(struct.unpack_from('<I', data, 16)[0]):
        kind, size = struct.unpack_from('<II', data, command)
        if kind == 0x19:
            for i in range(struct.unpack_from('<I', data, command + 64)[0]):
                section = command + 72 + i * 80
                flags = struct.unpack_from('<I', data, section + 64)[0]
                if flags & 0x80000400:
                    mutation = struct.unpack_from('<I', data, section + 48)[0]
                    break
        if mutation is not None:
            break
        command += size
    assert mutation is not None
    assert subprocess.run([str(checker), str(binary), str(binary)]).returncode == 0
    data[mutation] ^= 1
    changed = work / 'changed-instruction-binary'
    changed.write_bytes(data)
    assert subprocess.run([str(checker), str(binary), str(changed)]).returncode != 0
    results.append({'case': 'instruction-mutation-rejected', 'passed': True})
    assert not list((work / 'outputs').glob('.work-*'))
    # This fixture cannot prove device signing/execution compatibility.
print(json.dumps({'cases': len(results), 'passed': len(results), 'results': results,
                  'device_installation_or_runtime_verified': False}, ensure_ascii=False, indent=2))
