import importlib.util
import json
import pathlib
import plistlib
import subprocess
import sys


spec = importlib.util.spec_from_file_location('ui_action', pathlib.Path(__file__).with_name('ui-action-14pm.py'))
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)
inventory = json.loads((ui.output / '14pm-damai-inventory.json').read_text())
if inventory.get('bundle_id') != 'cn.damai.iphone':
    raise SystemExit('unexpected_damai_inventory')
extensions = [item for item in inventory['bundle_metadata'] if not item['is_main']]
if len(extensions) != 2:
    raise SystemExit('unexpected_damai_extension_count')
arguments = sys.argv[1:]
if arguments == ['main-custom-off']:
    target = 'cn.damai.iphone'
    title = '大麦'
    row = '自定义插件配置'
    key = 'customTweakConfigurationEnabled'
    desired = False
elif len(arguments) == 2 and arguments[0] == 'extension' and arguments[1] in ['0', '1']:
    extension = extensions[int(arguments[1])]
    target = extension['bundle_id']
    title = extension['executable']
    row = '禁用插件注入'
    key = 'tweakInjectionDisabled'
    desired = True
else:
    raise SystemExit('usage: disable-choicy-damai-14pm.py main-custom-off | extension <0|1>')
backup = pathlib.Path(json.loads((ui.output / 'latest-config-backup.json').read_text())['directory'])
baseline = plistlib.loads((backup / 'com.opa334.choicyprefs.plist').read_bytes())
path = '/var/jb/var/mobile/Library/Preferences/com.opa334.choicyprefs.plist'


def read_preferences():
    result = subprocess.run(ui.ssh + ['cat ' + path], capture_output=True, timeout=15, check=True)
    return plistlib.loads(result.stdout)


current = read_preferences()
expected_current = plistlib.loads(plistlib.dumps(baseline))
if current['appSettings']['cn.damai.iphone'].get('tweakInjectionDisabled') is not True:
    raise SystemExit('damai_main_injection_not_disabled_stop')
if current['appSettings']['cn.damai.iphone'].get('customTweakConfigurationEnabled') is False:
    expected_current['appSettings']['cn.damai.iphone']['customTweakConfigurationEnabled'] = False
for extension in extensions:
    identifier = extension['bundle_id']
    if current['appSettings'].get(identifier) == {'tweakInjectionDisabled': True}:
        expected_current['appSettings'][identifier] = {'tweakInjectionDisabled': True}
if current != expected_current:
    raise SystemExit('unexpected_preexisting_semantic_change_stop')
crane_path = '/var/jb/var/mobile/Library/Preferences/com.opa334.craneprefs.plist'
crane_before = subprocess.run(ui.ssh + ['cat ' + crane_path], capture_output=True,
                              timeout=15, check=True).stdout
if crane_before != (backup / 'com.opa334.craneprefs.plist').read_bytes():
    raise SystemExit('crane_configuration_changed_stop')
if current['appSettings'].get(target, {}).get(key) is desired:
    raise SystemExit('target_already_configured_no_input_dispatched')
ui.save(ui.capture())
items = json.loads(subprocess.check_output([str(ui.output / 'screen-text'),
                                           str(ui.output / '14pm-screen-observe.png')], timeout=15))
if not any(item['text'] == title and 0.05 < item['y'] < 0.10 and 0.3 < item['x'] < 0.7 and
           item['confidence'] >= (0.9 if title == '大麦' else 0.5) for item in items):
    raise SystemExit('target_page_title_not_confirmed')
matches = [item for item in items if item['text'] == row and 0.13 < item['y'] < 0.35 and
           item['confidence'] >= 0.9]
if len(matches) != 1:
    raise SystemExit('target_switch_row_not_unique')
expected = plistlib.loads(plistlib.dumps(current))
expected['appSettings'].setdefault(target, {})[key] = desired
ui.run_action(['tap', '0.848', str(matches[0]['y'])])
if read_preferences() != expected:
    raise SystemExit('unexpected_post_action_semantic_change_stop')
crane_after = subprocess.run(ui.ssh + ['cat ' + crane_path], capture_output=True,
                             timeout=15, check=True).stdout
if crane_before != crane_after:
    raise SystemExit('concurrent_crane_change_stop')
print('exact_damai_target_only_diff_verified')
