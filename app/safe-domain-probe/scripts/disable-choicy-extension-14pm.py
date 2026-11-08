import importlib.util
import json
import pathlib
import plistlib
import subprocess
import sys


spec = importlib.util.spec_from_file_location('ui_action', pathlib.Path(__file__).with_name('ui-action-14pm.py'))
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)
extensions = [item for item in json.loads((ui.output / '14pm-baseline.json').read_text())[
    'taobao_bundle_metadata'] if not item['is_main']]
if len(sys.argv) != 2 or not sys.argv[1].isdigit() or int(sys.argv[1]) not in range(len(extensions)):
    raise SystemExit('extension_index_not_allowed')
target = extensions[int(sys.argv[1])]
filename = 'com.opa334.choicyprefs.plist'
backup_directory = pathlib.Path(json.loads((ui.output / 'latest-config-backup.json').read_text())['directory'])
baseline = plistlib.loads((backup_directory / filename).read_bytes())
path = '/var/jb/var/mobile/Library/Preferences/' + filename


def read_preferences():
    result = subprocess.run(ui.ssh + ['cat ' + path], capture_output=True, timeout=15, check=True)
    return plistlib.loads(result.stdout)


current = read_preferences()
expected = plistlib.loads((backup_directory / filename).read_bytes())
expected['appSettings']['com.taobao.taobao4iphone'].update(
    customTweakConfigurationEnabled=False, tweakInjectionDisabled=True)
for extension in extensions:
    identifier = extension['bundle_id']
    if identifier in current['appSettings'] and identifier not in baseline['appSettings']:
        expected['appSettings'][identifier] = {'tweakInjectionDisabled': True}
if current != expected:
    raise SystemExit('unexpected_preexisting_semantic_change_stop')
ui.save(ui.capture())
items = json.loads(subprocess.check_output([str(ui.output / 'screen-text'),
                                           str(ui.output / '14pm-screen-observe.png')], timeout=15))
if not any(item['text'] == target['executable'] and 0.05 < item['y'] < 0.10 and
           item['confidence'] >= 0.5 for item in items):
    raise SystemExit('extension_page_title_not_confirmed')
if current['appSettings'].get(target['bundle_id'], {}).get('tweakInjectionDisabled') is True:
    raise SystemExit('extension_already_disabled_no_input_dispatched')
ui.run_action(['tap', '0.848', '0.166'])
expected['appSettings'][target['bundle_id']] = {'tweakInjectionDisabled': True}
if read_preferences() != expected:
    raise SystemExit('unexpected_post_action_semantic_change_stop')
print('exact_extension_only_diff_verified_' + str(int(sys.argv[1]) + 1))
