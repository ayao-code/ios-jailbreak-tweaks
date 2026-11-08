#!/usr/bin/env python3
import os
"""Authorized SMS/WeChat test: scoped HID scroll + LCD counters, no injection."""
import argparse
import hashlib
import io
import json
import pathlib
import shlex
import subprocess
import time

from PIL import Image, ImageChops

parser = argparse.ArgumentParser()
parser.add_argument('--bundle', choices=['com.apple.MobileSMS', 'com.tencent.xin'], required=True)
parser.add_argument('--mode', choices=['static', 'slow', 'fast'], required=True)
parser.add_argument('--direction', choices=['up', 'down'], default='up')
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
ssh = ['ssh', '-o', 'ControlPath=/tmp/codex-pm-move-mobile', '-o', 'UserKnownHostsFile=/tmp/codex-icon-110.known_hosts', '-o', 'StrictHostKeyChecking=yes', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', os.environ["DEVICE_SSH_TARGET"]]
prefix = 'export PATH=/usr/bin:/usr/sbin:/bin:/rootfs/usr/bin:/rootfs/bin; '
helper = '/tmp/hz-observe-20261108-2037/'


def remote(command, timeout=15):
    result = subprocess.run(ssh + [prefix + command], capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError('remote failed: ' + result.stderr.decode(errors='replace'))
    return result.stdout


def check():
    value = json.loads(remote('timeout 8 env _SafeMode=1 _MSSafeMode=1 ' + helper + 'ui-input-hz --check ' + shlex.quote(args.bundle)))
    if not value.get('unlocked_confirmed') or not value.get('expected_frontmost_confirmed'):
        raise RuntimeError('unlocked/frontmost not confirmed; no input dispatched')
    return value


def capture():
    image = Image.open(io.BytesIO(remote('timeout 8 env _SafeMode=1 _MSSafeMode=1 ' + helper + 'screen-observe-console'))).convert('RGB')
    if image.size != (1290, 2796):
        raise RuntimeError('unexpected display size')
    # Chat/message pixels are neither written to disk nor printed.
    return image.crop((40, 400, 1250, 2450))


remote('timeout 8 env _SafeMode=1 _MSSafeMode=1 ' + helper + 'screen-observe-console --wake')
remote('/usr/bin/uiopen --bundleid ' + shlex.quote(args.bundle))
time.sleep(2)
before_state = check()
before = capture()
time.sleep(0.5)
stable = capture()
if ImageChops.difference(before, stable).getbbox():
    raise RuntimeError('screen content changed before gesture; no input dispatched')
check()
metric = subprocess.Popen(ssh + [prefix + 'timeout 9 env _SafeMode=1 _MSSafeMode=1 ' + helper + 'render-performance-debug --sample'], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
first = metric.stdout.readline()
args.output.joinpath('metadata.txt').write_text(first)
rows = []
initial = metric.stdout.readline()
rows.append(initial)
parts = initial.split()
if len(parts) != 5 or parts[0] != 'sample':
    rest, errors = metric.communicate(timeout=15)
    args.output.joinpath('counters.log').write_text(first + initial + rest + errors)
    raise RuntimeError('no valid initial LCD sample; no input dispatched')
gesture_text = ''
if args.mode != 'static':
    time.sleep(0.5)
    y1, y2 = ('0.78', '0.30') if args.direction == 'up' else ('0.30', '0.78')
    gesture_text = remote('timeout 8 env _SafeMode=1 _MSSafeMode=1 ' + helper + 'ui-input-hz swipe-' + args.mode + ' ' + shlex.quote(args.bundle) + ' 0.5 ' + y1 + ' 0.5 ' + y2).decode()
rest, errors = metric.communicate(timeout=15)
rows.extend(rest.splitlines(keepends=True))
args.output.joinpath('counters.log').write_text(first + ''.join(rows) + errors)
args.output.joinpath('gesture.log').write_text(gesture_text)
if metric.returncode:
    raise RuntimeError('counter sampling failed')
after_state = check()
after = capture()
points = []
for line in rows:
    parts = line.split()
    if len(parts) == 5 and parts[0] == 'sample':
        points.append((float(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])))
if len(points) < 30:
    raise RuntimeError('insufficient counter samples')
intervals = []
for a, b in zip(points, points[1:]):
    dt = b[0] - a[0]
    if dt <= 0 or b[1] < a[1] or b[2] < a[2]:
        raise RuntimeError('counter reset or clock discontinuity')
    intervals.append({'t': (a[0] + b[0])/2, 'seconds': dt, 'frames': b[1]-a[1], 'skipped':b[2]-a[2], 'compositor_fps':(b[1]-a[1])/dt})
phase = {}
if gesture_text:
    lines = gesture_text.splitlines()
    start = next(float(x.split()[1]) for x in lines if x.startswith('touch_begin '))
    end = next(float(x.split()[1]) for x in lines if x.startswith('touch_end '))
    for name, lo, hi in [('contact', start, end), ('after_release_1s', end, end+1), ('after_release_2s',end,end+2)]:
        selected = [x for x in intervals if lo <= x['t'] <= hi]
        if selected:
            phase[name] = {'samples':len(selected), 'seconds':sum(x['seconds'] for x in selected), 'frames':sum(x['frames'] for x in selected), 'skipped_frames':sum(x['skipped'] for x in selected)}
            phase[name]['compositor_fps'] = phase[name]['frames']/phase[name]['seconds']
summary = {'bundle':args.bundle, 'mode':args.mode, 'direction':args.direction,
    'scope':'LCD compositor, NOT app internal FPS or physical panel refresh',
    'counter_samples':len(points), 'total_frames':points[-1][1]-points[0][1],
    'total_skipped_frames':points[-1][2]-points[0][2], 'duration_s':points[-1][0]-points[0][0],
    'body_pixels_changed':bool(ImageChops.difference(before,after).getbbox()),
    'before_body_sha256':hashlib.sha256(before.tobytes()).hexdigest(),
    'after_body_sha256':hashlib.sha256(after.tobytes()).hexdigest(),
    'before_state':before_state,'after_state':after_state,'phases':phase,
    'intervals':intervals}
args.output.joinpath('result.json').write_text(json.dumps(summary,indent=2))
print(json.dumps({k:v for k,v in summary.items() if k not in ['intervals','before_body_sha256','after_body_sha256']},indent=2))
