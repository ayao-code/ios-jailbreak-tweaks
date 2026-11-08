#!/usr/bin/env python3
"""Offline notification extension identity experiment; never installs or runs apps."""
import argparse
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('macho_parser', ROOT / 'tests/audit-installed.py')
macho = importlib.util.module_from_spec(spec)
spec.loader.exec_module(macho)


def require(value, message):
    if not value:
        raise ValueError(message)


def identity_candidate(source, output):
    require(not output.exists(), 'Output directory already exists')
    before_hash = macho.digest(source)
    output.parent.mkdir(parents=True, exist_ok=True)
    signer = shutil.which('ldid')
    require(signer, 'ldid unavailable')
    with tempfile.TemporaryDirectory(prefix='.notification-id-', dir=output.parent) as temporary:
        temporary = Path(temporary)
        with zipfile.ZipFile(source) as archive:
            require(len(archive.infolist()) <= 50000 and
                    sum(e.file_size for e in archive.infolist()) <= 2147483648, 'Package too large')
            require(archive.testzip() is None, 'Source ZIP CRC failure')
            main_info_path = 'Payload/DMPortal.app/Info.plist'
            extension_root = 'Payload/DMPortal.app/PlugIns/DMNotificationService.appex/'
            extension_info_path = extension_root + 'Info.plist'
            main_info = plistlib.loads(archive.read(main_info_path))
            extension_info = plistlib.loads(archive.read(extension_info_path))
            clone_id = main_info['CFBundleIdentifier']
            require(clone_id.startswith('cn.damai.iphone.'), 'Only existing Damai clone inputs supported')
            new_id = clone_id + '.DMNotificationService'
            executable = extension_info['CFBundleExecutable']
            require(isinstance(executable, str) and executable and '/' not in executable and
                    executable not in {'.', '..'}, 'Invalid extension executable')
            binary_path = extension_root + executable
            before = archive.read(binary_path)
            parsed_before = macho.slices(before)
            require(not any(s['encrypted'] for s in parsed_before), 'Notification extension is encrypted')
            binary = temporary / 'extension'
            binary.write_bytes(before)
            original_entitlements = plistlib.loads(subprocess.check_output([signer, '-e', str(binary)], timeout=30))
            team = original_entitlements.get('com.apple.developer.team-identifier')
            require(isinstance(team, str) and team, 'Missing original Team ID')
            updated_entitlements = dict(original_entitlements)
            updated_entitlements['application-identifier'] = team + '.' + new_id
            updated_entitlements['com.apple.private.security.container-required'] = new_id
            # Keep groups and every other permission unchanged; no broad grants.
            ent_xml = temporary / 'entitlements.plist'
            ent_xml.write_bytes(plistlib.dumps(updated_entitlements, fmt=plistlib.FMT_XML))
            subprocess.run([signer, '-S' + str(ent_xml), str(binary)], check=True,
                           capture_output=True, timeout=60)
            require(plistlib.loads(subprocess.check_output([signer, '-e', str(binary)], timeout=30)) == updated_entitlements,
                    'Signed entitlement readback mismatch')
            after = binary.read_bytes()
            parsed_after = macho.slices(after)
            require(parsed_before == parsed_after, 'Code/dependency/encryption/OS inspection changed')
            updated_info = dict(extension_info, CFBundleIdentifier=new_id)
            replacements = {extension_info_path: plistlib.dumps(updated_info), binary_path: after}
            candidate = temporary / 'candidate.ipa'
            with zipfile.ZipFile(candidate, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=1) as target:
                target.comment = archive.comment
                for entry in archive.infolist():
                    # ZipFile mutates header offsets on write; do not mutate
                    # entries still needed to read the source archive.
                    with target.open(copy.copy(entry), 'w') as dest:
                        if entry.filename in replacements:
                            dest.write(replacements[entry.filename])
                        elif not entry.is_dir():
                            with archive.open(entry) as src:
                                shutil.copyfileobj(src, dest, 65536)
            with zipfile.ZipFile(candidate) as verified:
                require(verified.testzip() is None and verified.namelist() == archive.namelist(), 'Output ZIP differs')
                changed = []
                for name in archive.namelist():
                    if name.endswith('/'):
                        continue
                    if hashlib.sha256(archive.read(name)).digest() != hashlib.sha256(verified.read(name)).digest():
                        changed.append(name)
                require(set(changed) == set(replacements), 'Unexpected file changes')
                require(verified.read(main_info_path) == archive.read(main_info_path), 'Main Info changed')
        require(macho.digest(source) == before_hash, 'Source changed during operation')
        report = {'source': str(source.resolve()), 'source_sha256': before_hash,
                  'clone_bundle_id_unchanged': clone_id,
                  'old_extension_id': extension_info['CFBundleIdentifier'], 'new_extension_id': new_id,
                  'changed_files': changed, 'old_entitlements': original_entitlements,
                  'new_entitlements': updated_entitlements, 'instruction_and_other_parsed_fields_unchanged': True,
                  'all_other_file_bytes_unchanged': True, 'source_unchanged': True,
                  'candidate_sha256': macho.digest(candidate), 'candidate_bytes': candidate.stat().st_size,
                  'installed': False, 'push_delivery_fixed': False,
                  'limits': ['Only notification service extension registration identity is changed.',
                             'Main app identity, keychain, push topic and server account binding are not changed.',
                             'Widget extension ID collision remains; widgets are not migrated.',
                             'No new push token is fabricated, copied or registered by this tool.',
                             'Installation signature resources may be rebuilt by TrollStore.',
                             'Extension isolation and delivery require device verification.']}
        output.mkdir(mode=0o700)
        try:
            shutil.copy2(candidate, output / 'Damai-notification-extension-experiment.ipa')
            (output / 'comparison.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
        except BaseException:
            shutil.rmtree(output)
            raise
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    report = identity_candidate(args.input, args.output_dir)
    print(json.dumps({k: report[k] for k in ['new_extension_id', 'changed_files', 'installed', 'push_delivery_fixed']}, indent=2))
