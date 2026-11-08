import datetime
import hashlib
import json
import os
import pathlib
import plistlib
import shlex
import subprocess


project = pathlib.Path(__file__).resolve().parent.parent
socket_path = os.environ['SSH_CONTROL_SOCKET']
ssh = ['ssh', '-S', socket_path, '-o', 'BatchMode=yes', '-T', 'placeholder']
prefix = 'PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/usr/sbin:/bin:/sbin; export PATH; '


def remote(command):
    return subprocess.run(ssh + [prefix + command], capture_output=True, timeout=20, check=True).stdout


if remote('sysctl -n hw.machine').decode().strip() != 'iPhone15,3':
    raise SystemExit('unexpected_device_no_backup_written')

timestamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
destination = project / 'build' / ('config-backup-' + timestamp)
destination.mkdir(mode=0o700)
device_directory = remote('umask 077; mktemp -d /var/jb/tmp/safe-domain-config-backup.XXXXXX').decode().strip()
if not device_directory.startswith('/var/jb/tmp/safe-domain-config-backup.'):
    raise SystemExit('unexpected_remote_backup_directory')

manifest = {'created_at': timestamp, 'device_directory': device_directory, 'files': {}}
for domain in ['choicyprefs', 'craneprefs']:
    name = 'com.opa334.' + domain + '.plist'
    source = '/var/jb/var/mobile/Library/Preferences/' + name
    quoted_source = shlex.quote(source)
    before = remote('cat ' + quoted_source)
    parsed = plistlib.loads(before)
    metadata = remote('stat -c "%u:%g %a %i" ' + quoted_source).decode().strip()
    backup = device_directory + '/' + name
    remote('cp -p ' + quoted_source + ' ' + shlex.quote(backup))
    saved = remote('cat ' + shlex.quote(backup))
    after = remote('cat ' + quoted_source)
    backup_metadata = remote('stat -c "%u:%g %a" ' + shlex.quote(backup)).decode().strip()
    if before != saved or before != after or backup_metadata != ' '.join(metadata.split()[:2]):
        raise SystemExit('backup_or_source_changed_stop')
    local = destination / name
    local.write_bytes(saved)
    local.chmod(0o600)
    manifest['files'][name] = {
        'sha256': hashlib.sha256(saved).hexdigest(),
        'semantic_sha256': hashlib.sha256(plistlib.dumps(parsed, sort_keys=True)).hexdigest(),
        'format': 'binary' if saved.startswith(b'bplist') else 'xml',
        'metadata': metadata,
        'dual_backup_verified': True,
    }

manifest_path = destination / 'manifest.json'
manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
manifest_path.chmod(0o600)
(project / 'build' / 'latest-config-backup.json').write_text(json.dumps({'directory': str(destination)}) + '\n')
print('dual_config_backup_verified_source_unchanged')
