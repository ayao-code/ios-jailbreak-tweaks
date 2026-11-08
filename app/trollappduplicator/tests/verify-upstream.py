#!/usr/bin/env python3
"""Check metadata-only upstream variants without installing or executing apps."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNNER = Path('/tmp/clonestudio-host-build/upstream-runner')


def sha(path):
    with path.open('rb') as file:
        return hashlib.file_digest(file, 'sha256').hexdigest()


def generate(source, output, disable, name):
    env = dict(os.environ, CLONE_FIXTURE_OUTPUT=str(output), CLONE_FIXTURE_SIGNER='/does-not-exist')
    run = subprocess.run([str(RUNNER), str(source), str(int(disable)), name],
                         env=env, capture_output=True, timeout=180)
    result = json.loads(run.stdout)
    assert run.returncode == 0, result
    assert 'report' not in result
    return result


def verify_pair(source, output, name):
    before_hash = sha(source)
    variants = [generate(source, output, disable, name) for disable in [True, False]]
    with zipfile.ZipFile(source) as z:
        assert z.testzip() is None
        base = {n: hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if not n.endswith('/')}
        main = next(n for n in base if len(n.split('/')) == 3 and n.endswith('/Info.plist'))
        original = plistlib.loads(z.read(main))
    checks = []
    for disable, variant in zip([True, False], variants):
        with zipfile.ZipFile(variant['ipa']) as z:
            assert z.testzip() is None
            hashes = {n: hashlib.sha256(z.read(n)).hexdigest() for n in z.namelist() if not n.endswith('/')}
            assert hashes.keys() == base.keys()
            assert all(hashes[n] == base[n] for n in base if n != main)
            expected = dict(original, CFBundleIdentifier=variant['cloneID'], CFBundleDisplayName=name)
            if disable:
                expected.pop('CFBundleURLTypes', None)
            assert plistlib.loads(z.read(main)) == expected
        checks.append({'callbacks_disabled': disable, 'ipa': variant['ipa'],
                       'clone_id': variant['cloneID'], 'sha256': sha(Path(variant['ipa'])),
                       'all_other_file_bytes_unchanged': True, 'only_changed_file': main})
    assert variants[0]['cloneID'] != variants[1]['cloneID']
    assert sha(source) == before_hash
    assert not list(output.glob('.upstream-work-*'))
    return {'source': str(source), 'source_sha256': before_hash, 'source_unchanged': True,
            'fresh_identity_per_creation': True, 'variants': checks,
            'installed': False, 'runtime_login_verified': False, 'isolated': False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-ipa', type=Path)
    parser.add_argument('--output-dir', type=Path)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    records = []
    with tempfile.TemporaryDirectory(prefix='clonestudio-upstream-check-') as temp:
        temp = Path(temp)
        source = temp / 'fixture.ipa'
        binary = (ROOT / '.theos-upstream/_/Applications/TrollAppDuplicator.app/TrollAppDuplicator').read_bytes()
        info = {'CFBundleIdentifier': 'com.example.upstreamfixture', 'CFBundleExecutable': 'Fixture',
                'CFBundleDisplayName': 'Original', 'CFBundleName': 'OriginalInternal',
                'CFBundleURLTypes': [{'CFBundleURLSchemes': ['fixture-callback']}],
                'UIBackgroundModes': ['remote-notification'], 'MinimumOSVersion': '15.0'}
        with zipfile.ZipFile(source, 'w') as z:
            z.writestr('Payload/Fixture.app/Info.plist', plistlib.dumps(info))
            z.writestr('Payload/Fixture.app/Fixture', binary)
            z.writestr('Payload/Fixture.app/PlugIns/Ext.appex/Info.plist', plistlib.dumps({'CFBundleIdentifier': 'com.example.ext'}))
            # Kept unchanged intentionally; upstream only checks the main binary.
            z.writestr('Payload/Fixture.app/PlugIns/Ext.appex/Ext', b'encrypted-extension-placeholder')
            z.writestr('Payload/Fixture.app/_CodeSignature/CodeResources', b'original-signature-resource')
            z.writestr('Payload/Fixture.app/asset', b'immutable asset')
        records.append(verify_pair(source, temp / 'out', 'Trial'))
        for label, source_path in [('missing', temp / 'missing.ipa'), ('malformed', temp / 'bad.ipa')]:
            if label == 'malformed':
                source_path.write_bytes(b'not a zip')
            env = dict(os.environ, CLONE_FIXTURE_OUTPUT=str(temp / 'reject'))
            run = subprocess.run([str(RUNNER), str(source_path), '1'], env=env, capture_output=True)
            assert run.returncode != 0
            records.append({'case': label, 'rejected': True})
        encrypted = temp / 'encrypted.ipa'
        header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
        with zipfile.ZipFile(encrypted, 'w') as z:
            z.writestr('Payload/Fixture.app/Info.plist', plistlib.dumps(info))
            z.writestr('Payload/Fixture.app/Fixture', header + struct.pack('<6I', 0x2c, 24, 0, 0, 1, 0))
        env = dict(os.environ, CLONE_FIXTURE_OUTPUT=str(temp / 'reject'))
        run = subprocess.run([str(RUNNER), str(encrypted), '1'], env=env, capture_output=True)
        assert run.returncode != 0
        records.append({'case': 'encrypted-main', 'rejected': True})
    if args.source_ipa:
        assert args.output_dir is not None
        records.append(verify_pair(args.source_ipa.resolve(), args.output_dir.resolve(), '大麦分身实验'))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({'records': records, 'passed': True,
                                      'scope': '本地逐文件和元数据对照，非安装或功能测试'}, ensure_ascii=False, indent=2) + '\n')
    print(args.report)


if __name__ == '__main__':
    main()
