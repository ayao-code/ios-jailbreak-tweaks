import io
import json
import os
import pathlib
import shlex
import subprocess
import sys
import time

from PIL import Image, ImageChops


project = pathlib.Path(__file__).resolve().parent.parent
output = project / 'build'
socket_path = os.environ['SSH_CONTROL_SOCKET']
ssh = ['ssh', '-S', socket_path, '-o', 'BatchMode=yes', '-T', 'placeholder']
state = json.loads((output / '14pm-screen-observe-status.json').read_text())
remote_directory = state['remote_directory']
if not remote_directory.startswith('/var/jb/tmp/safe-domain-observe.'):
    raise SystemExit('unexpected_helper_directory')


def helper(name, arguments):
    command = '_SafeMode=1 _MSSafeMode=1 ' + shlex.quote(remote_directory + '/' + name)
    command += ' ' + shlex.join(arguments)
    result = subprocess.run(ssh + ['/var/jb/usr/bin/timeout 8 /var/jb/bin/sh -c ' + shlex.quote(command)],
                            capture_output=True, timeout=15)
    if result.returncode:
        raise SystemExit('helper_failed_' + str(result.returncode) + '_' + result.stderr.decode().strip())
    return result.stdout


def capture():
    image = Image.open(io.BytesIO(helper('screen-observe-display', []))).convert('RGB')
    if image.size != (1290, 2796) or all(high == 0 for low, high in image.getextrema()):
        raise SystemExit('screen_content_unusable')
    return image


def content(image):
    return image.crop((32, 310, 1230, 2720))


def save(image):
    image.save(output / '14pm-screen-observe.png')
    image.resize((645, 1398)).save(output / '14pm-screen-small.png')


def run_action(arguments):
    if arguments and arguments[0] in ['tap', 'swipe']:
        reference = Image.open(output / '14pm-screen-observe.png').convert('RGB')
        current = capture()
        time.sleep(0.5)
        stable = capture()
        if ImageChops.difference(content(reference), content(current)).getbbox() or \
                ImageChops.difference(content(current), content(stable)).getbbox():
            save(stable)
            raise SystemExit('screen_changed_or_unstable_no_input_dispatched')
        print(helper('ui-input', [arguments[0], 'com.apple.Preferences'] + arguments[1:]).decode().strip())
        time.sleep(2)
    elif arguments != ['capture']:
        raise SystemExit('usage: ui-action-14pm.py capture | tap x y | swipe x1 y1 x2 y2')
    save(capture())
    print('fresh_screen_saved_review_before_next_action')


if __name__ == '__main__':
    run_action(sys.argv[1:])
