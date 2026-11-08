#!/usr/bin/env python3
"""Exercise real Foundation staging and the same status policy used by UIKit."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
results = []

with tempfile.TemporaryDirectory(prefix='clonestudio-import-regression-') as work:
    work = Path(work)
    importer = work / 'import-runner'
    subprocess.run(['clang', '-fobjc-arc', '-fblocks', '-DCLONE_HOST_TEST=1', '-I' + str(root),
                    str(root / 'tests/import_runner.m'), str(root / 'IPAImport.m'),
                    '-framework', 'Foundation', '-o', str(importer)], check=True)
    status_runner = work / 'status-runner'
    subprocess.run(['clang', '-fobjc-arc', '-I' + str(root),
                    str(root / 'tests/status_runner.m'), str(root / 'AppInputStatus.m'),
                    str(root / 'MachOInspector.c'), '-framework', 'Foundation',
                    '-o', str(status_runner)], check=True)
    sources = work / 'sources'
    sources.mkdir()
    env = dict(os.environ, CLONE_FIXTURE_OUTPUT=str(work / 'tool-outputs'))
    for name, kind, accept in [('encoded %20 space.ipa', 'file', True),
                               ('fixture.TIPA', 'file', True),
                               ('missing.ipa', 'missing', False),
                               ('empty.ipa', 'empty', False),
                               ('directory.ipa', 'directory', False),
                               ('symlink.ipa', 'symlink', False),
                               ('fixture.txt', 'file', False)]:
        source = sources / name
        if kind == 'file':
            source.write_bytes(b'PK\x03\x04' + bytes(range(256)) * 512)
        elif kind == 'empty':
            source.touch()
        elif kind == 'directory':
            source.mkdir()
        elif kind == 'symlink':
            source.symlink_to(sources / 'fixture.TIPA')
        before = hashlib.sha256(source.read_bytes()).hexdigest() if source.is_file() else None
        run = subprocess.run([str(importer), str(source)], env=env, capture_output=True, timeout=30)
        result = json.loads(run.stdout)
        assert (run.returncode == 0) == accept, result
        assert result['main_thread'], result
        if accept:
            staged = Path(result['path'])
            assert staged.is_file() and staged.read_bytes() == source.read_bytes()
            assert staged.name == name
            assert staged.parent.parent == work / 'tool-outputs/.imports'
            assert staged.parent.stat().st_mode & 0o777 == 0o700
            shutil.rmtree(staged.parent)
        else:
            assert 'error' in result and 'path' not in result
        if before:
            assert hashlib.sha256(source.read_bytes()).hexdigest() == before
        results.append({'case': name, 'passed': True})

    # Exercise the local-HOME/Inbox branch, not just coordinated /tmp files.
    with tempfile.TemporaryDirectory(prefix='clonestudio-own-inbox-', dir=Path.home()) as own:
        source = Path(own) / 'local-inbox.ipa'
        source.write_bytes(b'PK\x03\x04local inbox fixture')
        run = subprocess.run([str(importer), str(source)], env=env, capture_output=True, timeout=30)
        state = json.loads(run.stdout)
        assert run.returncode == 0 and state['main_thread'], state
        staged = Path(state['path'])
        assert staged.read_bytes() == source.read_bytes()
        shutil.rmtree(staged.parent)
        results.append({'case': 'own-home-inbox-copy', 'passed': True})

    app = work / 'Fixture.app'
    app.mkdir()
    (app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': 'Fixture'}))
    # A minimal arm64 Mach-O: disk-header inspection only, never executed.
    header = struct.pack('<8I', 0xfeedfacf, 0x100000c, 0, 2, 1, 24, 0, 0)
    for label, data, expected, selectable in [
            ('unencrypted', header + struct.pack('<6I', 0x2c, 24, 0, 0, 0, 0), 'unencrypted', True),
            ('encrypted', header + struct.pack('<6I', 0x2c, 24, 0, 0, 1, 0), 'encrypted', False),
            ('malformed', header, 'unreadable', False),
            ('not-macho', b'not executable', 'unreadable', False),
            ('missing-main', None, 'unreadable', False)]:
        binary = app / 'Fixture'
        if data is None:
            binary.unlink()
        else:
            binary.write_bytes(data)
        state = json.loads(subprocess.check_output([str(status_runner), str(app)]))
        assert state['status'] == expected and state['selectable'] == selectable, state
        assert state['unknown_rejected'] and state['nil_rejected']
        results.append({'case': label, 'passed': True})
    ui = (root / 'RootViewController.m').read_text()
    assert 'UIColor.systemBlueColor:UIColor.systemRedColor' in ui
    assert 'willSelectRowAtIndexPath' in ui and 'cloneInstalledAppStatus(app[@"path"])' in ui
    assert 'cloneImportRoot().path' in ui
    assert 'documentPickerWasCancelled:' in ui and 'dismissViewControllerAnimated:YES completion:^{[self resumePendingImports];}' in ui
    results.append({'case': 'ui-gates-and-shared-cleanup-root-static', 'passed': True})

print(json.dumps({'checks': len(results), 'passed': len(results), 'results': results,
                  'device_share_ui_verified': False}, indent=2))
