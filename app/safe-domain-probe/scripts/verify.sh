#!/bin/bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")/.." && pwd)
bash "$project_dir/scripts/build.sh" host
bash "$project_dir/scripts/build.sh" ios
bash "$project_dir/scripts/build.sh" audit
env -u JBROOT -u SDP_ENV_MARKER_TEST "$project_dir/build/probe-host" > "$project_dir/build/host-report.json"
env JBROOT=probe-marker-validation \
    SDP_ENV_MARKER_TEST=MobileSubstrate:mobilesubstrate:private-validation-value \
    "$project_dir/build/probe-host" \
    > "$project_dir/build/host-positive-control.json"

/usr/bin/python3 - "$project_dir" <<'PY'
import json
import plistlib
import sys
import subprocess
import tempfile
import zipfile
from pathlib import Path

project = Path(sys.argv[1])
baseline = json.loads((project / 'build/host-report.json').read_text())
positive = json.loads((project / 'build/host-positive-control.json').read_text())
for report in (baseline, positive):
    assert report['schema_version'] == 1
    assert report['platform'] == 'macos_host_validation_only'
    assert report['component'] == 'host_validation'
    assert report['probe_version'] == '0.1.6'
    assert report['installation_provenance'] == 'not_attested_by_runtime_probe'
    assert report['build_evidence_scope'] == 'non_app_store_diagnostic_only'
    assert all(report['assessment'][key] == 'not_proven' for key in (
        'ordinary_ios_sandbox', 'isolated_filesystem_and_services', 'clean_ios_environment'))
    assert len(report['path_observations']) == 30
    assert sum(item['path'] == '/var/lib/cydia/' for item in report['path_observations']) == 3
    assert sum(item['path'] == '/User/Applications/' for item in report['path_observations']) == 3
    stat_origin = next(item for item in report['function_origins'] if item['symbol'] == 'stat')
    assert stat_origin['expected_image'] == '/usr/lib/system/libsystem_kernel.dylib'
    assert isinstance(stat_origin['matches_expected_image'], bool)
    assert {item['operation'] for item in report['path_observations']} == {
        'stat_read_only', 'access_f_ok_read_only', 'fopen_read_only'}
    assert report['sentinel_write_observation']['create_result'] == 'not_run_on_host'
    assert report['sentinel_write_observation']['created_by_probe'] is False
    assert report['writable_executable_mapping_observation']['status'] == 'not_run_on_host'
    assert report['writable_executable_mapping_observation']['created_by_probe'] is False
    assert report['writable_executable_mapping_observation']['mapping_result'] == 'not_run_on_host'
    assert report['process_marker_observation']['operation'] == 'sysctl_kern_proc_all'
    assert all(name in {'sshd', 'dropbear', 'frida-server', 'frida', 'Sileo', 'Zebra',
                        'Dopamine', 'RootHide', 'apt', 'dpkg'}
               for name in report['process_marker_observation']['matched_markers'])
    assert [item['scheme'] for item in report['url_scheme_observations']] == [
        'cydia', 'sileo', 'zbra']
    assert all(item['result'] == 'not_run_on_host'
               for item in report['url_scheme_observations'])
    assert [item['port'] for item in report['loopback_port_observations']] == [22, 2222, 44, 27042]
    assert all(item['address'] == '127.0.0.1' and item['operation'] == 'tcp_connect_no_payload'
               for item in report['loopback_port_observations'])
    assert all(isinstance(value, bool) for value in report['environment_presence'].values())
    assert set(report['environment_content_marker_presence']) == {'MobileSubstrate', 'mobilesubstrate'}
    assert all(isinstance(value, bool)
               for value in report['environment_content_marker_presence'].values())
    assert all(isinstance(image['known_jailbreak_marker'], bool) for image in report['loaded_images'])
assert baseline['environment_presence']['JBROOT'] is False
assert positive['environment_presence']['JBROOT'] is True
assert baseline['environment_content_marker_presence'] == {
    'MobileSubstrate': False, 'mobilesubstrate': False}
assert positive['environment_content_marker_presence'] == {
    'MobileSubstrate': True, 'mobilesubstrate': True}
assert any(item.get('kind') == 'environment_variable_present' and item.get('name') == 'JBROOT'
           for item in positive['findings'])
assert sum(item.get('kind') == 'environment_content_marker_present'
           for item in positive['findings']) == 2
assert 'probe-marker-validation' not in json.dumps(positive)
assert 'private-validation-value' not in json.dumps(positive)
with tempfile.TemporaryDirectory(prefix='safedomain-audit-') as fixture_dir:
    fixture = Path(fixture_dir)
    (fixture / 'openstep.plist').write_text('{ Filter = { Bundles = ("com.apple.springboard"); }; }')
    (fixture / 'service.plist').write_bytes(plistlib.dumps({'Filter': {'Executables': ['securityd']}}))
    output = subprocess.check_output([str(project / 'build/audit-filters'), str(fixture)])
    audit = json.loads(output)
    assert audit['counts']['parsed'] == 2 and audit['counts']['unparsed'] == 0
    assert audit['counts']['springboard'] == 1 and audit['counts']['shared_services'] == 1
    assert any(item['format'] == 'openstep' for item in audit['filters'])
    (fixture / 'invalid.plist').write_text('not-a-filter')
    invalid = subprocess.run([str(project / 'build/audit-filters'), str(fixture)], capture_output=True)
    assert invalid.returncode == 3 and json.loads(invalid.stdout)['counts']['unparsed'] == 1
archive_path = project / 'build/SafeDomainProbe-0.1.6-unsigned.ipa'
with zipfile.ZipFile(archive_path) as archive:
    main_info = plistlib.loads(archive.read('Payload/SafeDomainProbe.app/Info.plist'))
    extension_info = plistlib.loads(archive.read(
        'Payload/SafeDomainProbe.app/PlugIns/SafeDomainProbeShare.appex/Info.plist'))
    assert main_info['CFBundleIdentifier'] == 'com.ayao.safedomainprobe'
    assert main_info['CFBundleShortVersionString'] == '0.1.6'
    assert main_info['CFBundleVersion'] == '7'
    assert main_info['LSApplicationQueriesSchemes'] == ['cydia', 'sileo', 'zbra']
    assert extension_info['CFBundleIdentifier'] == main_info['CFBundleIdentifier'] + '.share'
    assert extension_info['CFBundleShortVersionString'] == '0.1.6'
    assert extension_info['CFBundleVersion'] == '7'
    assert extension_info['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.share-services'
    assert extension_info['NSExtension']['NSExtensionPrincipalClass'] == 'SDPShareViewController'
    extension_binary = archive.read(
        'Payload/SafeDomainProbe.app/PlugIns/SafeDomainProbeShare.appex/SafeDomainProbeShare')
    assert b'_OBJC_CLASS_$_UIApplication' not in extension_binary
    assert all(not name.endswith('.mobileprovision') for name in archive.namelist())
summary = {
    'host_serialization': 'passed',
    'environment_positive_and_negative_controls': 'passed',
    'environment_content_markers_are_boolean_only': 'passed',
    'main_and_extension_archive_structure': 'passed',
    'fixed_loopback_no_payload_checks': 'passed',
    'fixed_path_stat_access_fopen_checks': 'passed',
    'exclusive_sentinel_create_cleanup_contract': 'host_not_run_source_verified',
    'writable_executable_mapping_cleanup_contract': 'host_not_run_source_verified',
    'fixed_url_scheme_checks': 'passed',
    'allowlisted_process_marker_reporting': 'passed',
    'share_extension_has_no_uiapplication_reference': 'passed',
    'xml_and_openstep_filter_audit': 'passed',
    'invalid_filter_prevents_success': 'passed',
    'image_count_host_only': len(baseline['loaded_images']),
    'iphone_runtime': 'not_run',
    'clean_ios_environment': 'not_proven',
    'ordinary_signed_installation': 'not_available',
}
(project / 'build/verification-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary, indent=2))
PY
