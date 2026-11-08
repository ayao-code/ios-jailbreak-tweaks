#!/usr/bin/env python3
import shutil
"""Create twice from identical input/name with a seeded legacy ID; never install."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve()
    source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    legacy = 'cn.damai.iphone.00000000-0000-0000-0000-000000000000'
    results = []
    with tempfile.TemporaryDirectory(prefix='clone-new-identity-') as work:
        env = dict(os.environ, CLONE_FIXTURE_OUTPUT=work, CLONE_FIXTURE_SIGNER=(shutil.which('ldid') or 'ldid'))
        for _ in range(2):
            run = subprocess.run(['/tmp/clonestudio-host-build/upstream-runner', str(source),
                                  '1', '大麦分身2号', '1', legacy],
                                 env=env, capture_output=True, timeout=180)
            assert run.returncode == 0, run.stdout.decode() + run.stderr.decode()
            result = json.loads(run.stdout)
            assert result['cloneID'] != legacy
            with zipfile.ZipFile(result['ipa']) as archive:
                assert archive.testzip() is None
                info = plistlib.loads(archive.read('Payload/DMPortal.app/Info.plist'))
                assert info['CFBundleIdentifier'] == result['cloneID']
                assert info['CFBundleDisplayName'] == '大麦分身2号'
                assert 'CFBundleURLTypes' not in info
            results.append({'clone_id': result['cloneID'], 'group': result['new_group'],
                            'name': '大麦分身2号', 'old_identity_ignored': True})
        assert results[0]['clone_id'] != results[1]['clone_id']
        assert results[0]['group'] != results[1]['group']
        assert hashlib.sha256(source.read_bytes()).hexdigest() == source_hash
    report = {'same_source_and_name': True, 'distinct_new_bundle_ids': True,
              'distinct_group_names': True, 'source_unchanged': True, 'results': results,
              'existing_device_apps_modified': False, 'runtime_login_verified': False}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
