#!/usr/bin/env python3
"""Fail closed on sensitive material in staged blobs and supported archives."""
import argparse
import io
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys
import tarfile
import zipfile

RULES = {
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA |ENCRYPTED )?PRIVATE KEY-----',
    'jwt': rb'\beyJ[A-Za-z0-9_-]{6,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b',
    'provider-key': rb'\b(?:sk-(?:proj-|ant-)?[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{12,})\b',
    'credential-url': rb'https?://[^\s/:@\x22\x27]{1,50}:[^\s/@\x22\x27]{3,100}@',
    'authorization-value': rb'\b(?:Bearer|Basic)\s+[A-Za-z0-9+/_.=-]{20,}',
    'device-udid': rb'(?i)(?<![0-9a-f])[0-9a-f]{8}-[0-9a-f]{16}(?![0-9a-f])',
    'private-network-address': rb'(?<![0-9.])(?:192\.168\.\d{1,3}\.\d{1,3}|10\.(?:\d{1,3}\.){2}\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?![0-9.])',
    'personal-home-path': rb'/(?:Users|home)/[A-Za-z0-9_.-]+/',
    'internal-endpoint': rb'(?i)[A-Za-z0-9_.-]+\.(?:byted\.org|bytedance\.net|byteintl\.net|tiktok-row\.net|tiktok-us\.net|bytedance\.com)\b',
    'device-container-id': rb'(?i)(?:Containers/(?:Data|Bundle)/Application|Containers/Shared/AppGroup|Bundle/Application)/[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',
    'live-jailbreak-root': rb'(?i)\.jbroot-[0-9a-f]{16}',
}
ASSIGNMENT = re.compile(rb'''(?i)(?:password|passwd|sudo_password|ssh_password|token|api[_-]?key|secret|authorization|cookie|SSHPASS)\s*[:=]\s*["']([^"'\r\n]{3,200})["']''')
PATTERNS = {name: re.compile(value) for name, value in RULES.items()}
LIMIT = 100 * 1024 * 1024


def inspect(data, path, errors, depth=0):
    if len(data) > LIMIT or depth > 5:
        errors.append(('unscanned-large-or-deep-member', path))
        return
    try:
        if data.startswith(b'PK\x03\x04'):
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                for entry in archive.infolist():
                    if entry.is_dir():
                        continue
                    if entry.file_size > LIMIT or entry.flag_bits & 1:
                        errors.append(('unscanned-archive-member', path + '!' + entry.filename))
                        continue
                    inspect(archive.read(entry), path + '!' + entry.filename, errors, depth + 1)
            return
        if data.startswith(b'!<arch>\n'):
            pos = 8
            while pos + 60 <= len(data):
                header = data[pos:pos + 60]
                name = header[:16].decode().strip().rstrip('/')
                size = int(header[48:58].decode().strip())
                pos += 60
                if name.startswith(('data.tar', 'control.tar')):
                    inspect(data[pos:pos + size], path + '!' + name, errors, depth + 1)
                pos += size + size % 2
            return
        if data.startswith(b'\x28\xb5\x2f\xfd'):
            data = subprocess.check_output(['zstd', '-q', '-d', '-c'], input=data, timeout=30)
            if len(data) > LIMIT:
                errors.append(('unscanned-large-decompressed-member', path))
                return
        if data.startswith((b'\x1f\x8b', b'\xfd7zXZ\x00', b'BZh')) or data[257:262] == b'ustar':
            with tarfile.open(fileobj=io.BytesIO(data), mode='r:*') as archive:
                for entry in archive:
                    if entry.isfile():
                        if entry.size > LIMIT:
                            errors.append(('unscanned-archive-member', path + '!' + entry.name))
                            continue
                        inspect(archive.extractfile(entry).read(), path + '!' + entry.name, errors, depth + 1)
            return
        if data.startswith(b'bplist'):
            data = plistlib.dumps(plistlib.loads(data), fmt=plistlib.FMT_XML)
    except Exception:
        errors.append(('archive-or-plist-read-failed', path))
        return
    for name, pattern in PATTERNS.items():
        if pattern.search(data):
            errors.append((name, path))
    for match in ASSIGNMENT.finditer(data):
        value = match.group(1).lower()
        if any(term in value for term in [b'example', b'placeholder', b'redacted', b'required', b'${', b'<', b'getpass', b'environment', b'stdin']):
            continue
        errors.append(('literal-credential-candidate', path))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--staged', action='store_true')
    args = parser.parse_args()
    if not args.staged:
        parser.error('--staged is required')
    names = subprocess.check_output(['git', 'diff', '--cached', '--name-only', '--diff-filter=ACMRT', '-z']).decode().split('\0')
    errors = []
    count = 0
    for name in filter(None, names):
        count += 1
        data = subprocess.check_output(['git', 'show', ':' + name])
        inspect(data, name, errors)
    for key in ['user.email', 'user.name']:
        value = subprocess.check_output(['git', 'config', key]).strip()
        if key == 'user.email' and (b'@' not in value or not value.endswith((b'@example.invalid', b'@users.noreply.github.com'))):
            errors.append(('non-anonymous-commit-email-review-required', 'Git author/committer metadata'))
    if errors:
        for kind, name in sorted(set(errors)):
            print('BLOCKED:', kind, name, file=sys.stderr)
        return 1
    print('Privacy gate passed for', count, 'staged paths; manual review is still required.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
