import importlib.util
import json
import pathlib
import subprocess
import sys
import time


spec = importlib.util.spec_from_file_location('ui_action', pathlib.Path(__file__).with_name('ui-action-14pm.py'))
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)


def recognize():
    ui.save(ui.capture())
    data = subprocess.check_output([str(ui.output / 'screen-text'),
                                    str(ui.output / '14pm-screen-observe.png')], timeout=15)
    return json.loads(data)


def title_matches(items, expected):
    return any(item['text'] == expected and 0.05 < item['y'] < 0.10 and
               0.3 < item['x'] < 0.7 and item['confidence'] > 0.9 for item in items)


arguments = sys.argv[1:]
if len(arguments) != 2:
    raise SystemExit('usage: choicy-text-navigation-14pm.py <expected-title> <exact-row-text>')
expected_title, row = arguments
minimum_confidence = 0.5 if expected_title == '应用插件' else 0.9
allowed = {('Choicy', '应用程序'), ('应用程序', '淘宝'), ('淘宝', '应用插件')}
allowed.update({('应用程序', '大麦'), ('大麦', '应用插件')})
executables = [item['executable'] for item in json.loads((ui.output / '14pm-baseline.json').read_text())[
    'taobao_bundle_metadata'] if not item['is_main']]
allowed.update(('应用插件', executable) for executable in executables)
damai_inventory = ui.output / '14pm-damai-inventory.json'
if damai_inventory.exists():
    damai = json.loads(damai_inventory.read_text())
    if damai.get('bundle_id') != 'cn.damai.iphone':
        raise SystemExit('unexpected_damai_inventory')
    allowed.update(('应用插件', item['executable']) for item in damai['bundle_metadata'] if not item['is_main'])
if (expected_title, row) not in allowed:
    raise SystemExit('navigation_target_not_allowed')

for step in range(6):
    items = recognize()
    if not title_matches(items, expected_title):
        raise SystemExit('unexpected_page_no_navigation_dispatched')
    matches = [item for item in items if item['text'] == row and 0.13 < item['y'] < 0.95 and
               item['confidence'] >= minimum_confidence]
    if len(matches) == 1:
        time.sleep(0.6)
        confirmed = recognize()
        second_matches = [item for item in confirmed if item['text'] == row and
                          0.13 < item['y'] < 0.95 and item['confidence'] >= minimum_confidence]
        if not title_matches(confirmed, expected_title) or len(second_matches) != 1 or \
                abs(matches[0]['y'] - second_matches[0]['y']) > 0.002:
            raise SystemExit('target_row_moved_no_navigation_dispatched')
        ui.run_action(['tap', '0.45', str(second_matches[0]['y'])])
        print('text_verified_navigation_requested')
        break
    if expected_title != '应用程序' or matches:
        raise SystemExit('row_not_unambiguously_observed')
    ui.run_action(['swipe', '0.45', '0.85', '0.45', '0.24'])
    time.sleep(0.8)
else:
    raise SystemExit('bounded_navigation_limit_reached')
