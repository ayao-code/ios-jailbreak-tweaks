import datetime
import importlib.util
import json
import pathlib
import plistlib
import shlex
import subprocess
import sys
import time


spec = importlib.util.spec_from_file_location('ui_action', pathlib.Path(__file__).with_name('ui-action-14pm.py'))
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)
target = 'cn.damai.iphone'
if sys.argv[1:] not in [[], ['--cold-start']]:
    raise SystemExit('usage: observe-damai-launch-14pm.py [--cold-start]')
cold_start = sys.argv[1:] == ['--cold-start']
prefix = 'PATH=/var/jb/usr/bin:/var/jb/usr/sbin:/var/jb/bin:/var/jb/sbin:/usr/bin:/usr/sbin:/bin:/sbin; export PATH; '


def remote(command):
    result = subprocess.run(ui.ssh + [prefix + command], capture_output=True, timeout=15)
    if result.returncode:
        raise SystemExit('remote_command_failed_' + str(result.returncode))
    return result.stdout


def configurations():
    return {name: remote('cat /var/jb/var/mobile/Library/Preferences/' + name)
            for name in ['com.opa334.choicyprefs.plist', 'com.opa334.craneprefs.plist']}


def jobs():
    result = {}
    for line in remote('launchctl list').decode().splitlines():
        fields = line.split()
        if len(fields) != 3:
            continue
        if fields[2] in ['com.apple.SpringBoard', 'com.apple.accountsd']:
            result[fields[2]] = fields[0]
        elif fields[2].startswith('UIKitApplication:' + target + '['):
            result['damai'] = fields[0]
        elif fields[2].startswith('UIKitApplication:com.taobao.taobao4iphone['):
            result['taobao'] = fields[0]
    return result


def frontmost():
    command = '_SafeMode=1 _MSSafeMode=1 ' + shlex.quote(ui.remote_directory + '/ui-input-damai-check')
    result = subprocess.run(ui.ssh + ['/var/jb/usr/bin/timeout 8 /var/jb/bin/sh -c ' +
                                      shlex.quote(command + ' --check ' + target)],
                            capture_output=True, timeout=15)
    if result.returncode:
        raise SystemExit('frontmost_check_failed')
    return json.loads(result.stdout)


if remote('sysctl -n hw.machine').decode().strip() != 'iPhone15,3':
    raise SystemExit('unexpected_device_no_launch')
backup = pathlib.Path(json.loads((ui.output / 'latest-config-backup.json').read_text())['directory'])
before = configurations()
expected = plistlib.loads((backup / 'com.opa334.choicyprefs.plist').read_bytes())
expected['appSettings'][target]['customTweakConfigurationEnabled'] = False
expected['appSettings'][target + '.DMNotificationService'] = {'tweakInjectionDisabled': True}
if plistlib.loads(before['com.opa334.choicyprefs.plist']) != expected:
    raise SystemExit('unexpected_choicy_configuration_no_launch')
if expected['appSettings'][target].get('tweakInjectionDisabled') is not True:
    raise SystemExit('main_injection_not_disabled_no_launch')
if before['com.opa334.craneprefs.plist'] != (backup / 'com.opa334.craneprefs.plist').read_bytes():
    raise SystemExit('crane_changed_no_launch')
crane = plistlib.loads(before['com.opa334.craneprefs.plist'])['appSettings_' + target]
if crane.get('activeContainer') != 'DEFAULT' or crane.get('containerProtectionEnabled') is not True:
    raise SystemExit('unexpected_crane_state_no_launch')
state = frontmost()
if state.get('unlocked_confirmed') is not True:
    raise SystemExit('device_locked_no_launch')
before_jobs = jobs()
systemhook = remote('sha256sum /var/jb/basebin/systemhook.dylib').decode().split()[0]
samples = []
report = {'started_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'model': 'iPhone15,3', 'bundle_id': target, 'jobs_before': before_jobs,
          'main_and_notification_extension_disabled': True, 'widget_injection_policy': 'not_verified',
          'container_switch_performed': False, 'configuration_write_performed_by_observer': False,
          'touch_or_transaction_performed': False, 'container_data_backup_performed': False,
          'dyld_images': 'not_enumerated', 'clean_isolated_ios_environment': 'not_proven',
          'jailbreak_business_detection_result': 'not_proven', 'samples': samples}
report['cold_start_requested'] = cold_start
suffix = 'cold-launch' if cold_start else 'launch'
output = ui.output / ('14pm-damai-' + suffix + '-observation.json')


def save_report():
    output.write_text(json.dumps(report, indent=2) + '\n')
    output.chmod(0o600)


if cold_start:
    previous_pid = before_jobs.get('damai')
    if previous_pid and previous_pid.isdigit():
        if jobs().get('damai') != previous_pid:
            raise SystemExit('target_pid_changed_no_termination')
        remote('launchctl list | /var/jb/usr/bin/grep -F "UIKitApplication:cn.damai.iphone[" | '
               '/var/jb/usr/bin/grep -E ' + shlex.quote('^' + previous_pid + '[[:space:]]') +
               ' >/dev/null && kill -TERM ' + shlex.quote(previous_pid))
        report['target_only_termination_requested'] = True
        save_report()
        for attempt in range(3):
            time.sleep(1)
            if jobs().get('damai') != previous_pid:
                break
        else:
            raise SystemExit('old_target_pid_still_present_no_launch')
    else:
        report['target_only_termination_requested'] = False
remote('/var/jb/usr/bin/uiopen --bundleid ' + target)
report['normal_launch_request_sent'] = True
save_report()
for delay in [2, 5, 10]:
    time.sleep(delay)
    image = ui.capture()
    index = len(samples) + 1
    screenshot = ui.output / ('14pm-damai-' + suffix + '-' + str(index) + '.png')
    image.save(screenshot)
    image.resize((645, 1398)).save(ui.output / ('14pm-damai-' + suffix + '-' + str(index) + '-small.png'))
    current_jobs = jobs()
    current_configs = configurations()
    core_unchanged = systemhook == remote('sha256sum /var/jb/basebin/systemhook.dylib').decode().split()[0]
    shared_unchanged = all(before_jobs.get(label) == current_jobs.get(label)
                           for label in ['com.apple.SpringBoard', 'com.apple.accountsd', 'taobao'])
    sample = {'collected_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'frontmost': frontmost(), 'jobs': current_jobs, 'screenshot': screenshot.name,
              'configuration_bytes_unchanged': before == current_configs,
              'systemhook_unchanged': core_unchanged, 'selected_non_target_pids_unchanged': shared_unchanged}
    samples.append(sample)
    save_report()
    if cold_start and (not current_jobs.get('damai', '').isdigit() or
                       current_jobs.get('damai') == before_jobs.get('damai')):
        raise SystemExit('new_target_pid_not_verified_stop_observation')
    if before != current_configs or not core_unchanged or not shared_unchanged:
        raise SystemExit('non_target_or_configuration_changed_stop_observation')
print('bounded_damai_launch_observation_saved_no_touch_no_transaction')
