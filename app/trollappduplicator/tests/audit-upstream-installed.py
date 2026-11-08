#!/usr/bin/env python3
"""Compare exported code packages only, never account files or running processes."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import importlib.util
import zipfile

spec = importlib.util.spec_from_file_location('installed_parser', Path(__file__).with_name('audit-installed.py'))
parser_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser_module)


def fingerprints(archive):
    prefix = 'Payload/DMPortal.app/'
    return {name[len(prefix):]: hashlib.sha256(archive.read(name)).hexdigest()
            for name in archive.namelist() if name.startswith(prefix) and not name.endswith('/')}


def changes(before, after):
    return {key: {'before': before.get(key), 'after': after.get(key)}
            for key in before.keys() | after.keys() if before.get(key) != after.get(key)}


def main():
    args_parser = argparse.ArgumentParser()
    args_parser.add_argument('--evidence', type=Path, required=True)
    args_parser.add_argument('--source-ipa', type=Path, required=True)
    args = args_parser.parse_args()
    root = args.evidence
    package = next((root / 'input').glob('*.ipa'))
    bundle = root / 'clone/bundle'
    state = json.loads((root / 'current-state.json').read_text())
    records, info_changes = [], []
    with zipfile.ZipFile(args.source_ipa) as source, zipfile.ZipFile(package) as generated:
        source_crc = source.testzip()
        generated_crc = generated.testzip()
        before, after = fingerprints(source), fingerprints(generated)
        source_diff = {'added': sorted(after.keys() - before.keys()),
                       'removed': sorted(before.keys() - after.keys()),
                       'changed': sorted(k for k in before.keys() & after.keys() if before[k] != after[k])}
        source_info = plistlib.loads(source.read('Payload/DMPortal.app/Info.plist'))
        generated_info = plistlib.loads(generated.read('Payload/DMPortal.app/Info.plist'))
        installed_info = plistlib.loads((bundle / 'Info.plist').read_bytes())
        raw_resource_changes, signing_resource_changes = [], []
        installed_extra = sorted(p.relative_to(bundle).as_posix() for p in bundle.rglob('*')
                                 if p.is_file() and p.relative_to(bundle).as_posix() not in after)
        for name in sorted(after):
            data = generated.read('Payload/DMPortal.app/' + name)
            path = bundle / name
            if not path.exists():
                raw_resource_changes.append(name)
                continue
            installed_data = path.read_bytes()
            if data[:4] not in parser_module.MAGICS:
                if data != installed_data:
                    if name.endswith('Info.plist'):
                        info_changes.append({'path': name,
                                             'changes': changes(plistlib.loads(data), plistlib.loads(installed_data))})
                    elif '/_CodeSignature/' in '/' + name:
                        signing_resource_changes.append(name)
                    else:
                        raw_resource_changes.append(name)
                continue
            generated_slices = parser_module.slices(data)
            installed_slices = parser_module.slices(installed_data)
            raw_ent = subprocess.check_output(['ldid', '-e', str(path)])
            ent = plistlib.loads(raw_ent) if raw_ent.strip() else {}
            dependency_markers = [dependency for s in installed_slices for dependency in s['dependencies']
                                  if any(marker in dependency for marker in ['/var/jb', '.jbroot', 'Substrate', 'AutoSkip', 'libsubstrate'])]
            records.append({'path': name,
                            'generated_encrypted': any(s['encrypted'] for s in generated_slices),
                            'installed_encrypted': any(s['encrypted'] for s in installed_slices),
                            'installed_minimum_ios_packed': [s['minimum_ios_packed'] for s in installed_slices],
                            'code_sections_unchanged_at_install': [s['instruction_sections'] for s in generated_slices] == [s['instruction_sections'] for s in installed_slices],
                            'known_jailbreak_dependencies': dependency_markers, 'installed_entitlements': ent})
    original_ent = plistlib.loads((root / 'original/main-entitlements.plist').read_bytes())
    installed_ent = plistlib.loads((root / 'clone/main-entitlements.plist').read_bytes())
    expected = dict(source_info, CFBundleIdentifier=state['clone']['id'],
                    CFBundleDisplayName=generated_info['CFBundleDisplayName'])
    expected.pop('CFBundleURLTypes', None)
    original_group_lines = state['original']['group_containers']
    clone_group_lines = state['clone']['group_containers']
    summary = {
        'source_ipa_sha256': hashlib.sha256(args.source_ipa.read_bytes()).hexdigest(),
        'generated_ipa_sha256': hashlib.sha256(package.read_bytes()).hexdigest(),
        'generated_ipa_bytes': package.stat().st_size,
        'zip_crc_valid': source_crc is None and generated_crc is None,
        'source_to_generated_file_changes': source_diff,
        'source_to_generated_main_info_changes': changes(source_info, generated_info),
        'metadata_only_matches_upstream_toggle': generated_info == expected and source_diff == {'added': [], 'removed': [], 'changed': ['Info.plist']},
        'installed_main_info_changes': changes(generated_info, installed_info),
        'installation_bundle_info_changes': info_changes,
        'unexpected_resource_changes_at_install': raw_resource_changes,
        'resigning_resource_changes_at_install': signing_resource_changes,
        'installed_extra_files': installed_extra,
        'macho_count': len(records),
        'encrypted_installed_paths': [r['path'] for r in records if r['installed_encrypted']],
        'too_high_minimum_ios_paths': [r['path'] for r in records if any(v > 0x100301 for v in r['installed_minimum_ios_packed'])],
        'installed_instruction_sections_unchanged': bool(records) and all(r['code_sections_unchanged_at_install'] for r in records),
        'known_jailbreak_dependencies': [r for r in records if r['known_jailbreak_dependencies']],
        'distinct_ordinary_data_containers': state['original']['data_container'] != state['clone']['data_container'],
        'same_registered_app_group': bool(set(original_group_lines) & set(clone_group_lines)),
        'same_application_identifier': original_ent.get('application-identifier') == installed_ent.get('application-identifier'),
        'installed_entitlement_changes_vs_original': changes(original_ent, installed_ent),
        'same_extension_ids': sorted(plistlib.loads(p.read_bytes()).get('CFBundleIdentifier', '')
                                     for p in bundle.rglob('Info.plist') if '.appex/' in str(p)),
        'clone_url_schemes': state['clone']['url_schemes'],
        'original_url_scheme_count': len(state['original']['url_schemes']),
        'login_success_user_reported': True,
        'sms_request_and_complete_login_agent_verified': False,
        'keychain_or_app_group_account_contents_read': False,
        'fully_isolated': False,
        'macho_records': records,
    }
    (root / 'package-audit.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in summary.items() if k not in ['macho_records', 'source_to_generated_main_info_changes', 'installation_bundle_info_changes']}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
