import argparse
import bisect
import collections
import json
import math
from pathlib import Path


def build_plan(anchors, restored):
    if not anchors or not restored:
        raise ValueError('Both existing assets and restored receipts are required')
    anchor_ids = [item['ZUUID'] for item in anchors]
    restored_ids = [item['local_identifier'].split('/')[0] for item in restored]
    if len(set(anchor_ids)) != len(anchor_ids) or len(set(restored_ids)) != len(restored_ids):
        raise ValueError('Asset UUIDs must be unique')
    if set(anchor_ids) & set(restored_ids):
        raise ValueError('Existing and restored scopes must not overlap')
    capture_times = [item['export_capture_time'] for item in anchors]
    added_times = [item['ZADDEDDATE'] for item in anchors]
    if not all(math.isfinite(value) for value in capture_times + added_times):
        raise ValueError('Anchor dates must be finite')
    if any(left > right for left, right in zip(capture_times, capture_times[1:])):
        raise ValueError('Backup dates do not match the existing Recents order')
    if any(left >= right for left, right in zip(added_times, added_times[1:])):
        raise ValueError('Existing added dates must be strictly increasing')
    groups = collections.defaultdict(list)
    for item in restored:
        if not item['backup_name'].lower().endswith('.cr3'):
            raise ValueError('This planning scope is limited to restored CR3 assets')
        if not all(math.isfinite(item[key]) for key in ['export_capture_time', 'creation_date']):
            raise ValueError('Restored dates must be finite')
        gap = bisect.bisect_right(capture_times, item['export_capture_time'])
        if gap == 0 or gap == len(anchors):
            raise ValueError('Restored asset lacks two existing Recents neighbors')
        groups[gap].append(item)
    planned = []
    for gap, members in sorted(groups.items()):
        left = anchors[gap - 1]
        right = anchors[gap]
        members.sort(key=lambda item: (
            item['export_capture_time'], item['creation_date'],
            item['backup_name'], item['local_identifier']))
        for position, item in enumerate(members, start=1):
            target = left['ZADDEDDATE'] + (
                right['ZADDEDDATE'] - left['ZADDEDDATE']) * position / (len(members) + 1)
            if not left['ZADDEDDATE'] < target < right['ZADDEDDATE']:
                raise ValueError('Added-date gap has insufficient precision')
            planned.append({
                'uuid': item['local_identifier'].split('/')[0],
                'created': item['creation_date'],
                'targetAdded': target,
                'sha256': item['sha256'],
                'backup_name': item['backup_name'],
                'export_capture_time': item['export_capture_time'],
                'left': left,
                'right': right,
            })
    target_times = [item['targetAdded'] for item in planned]
    if len(set(target_times)) != len(planned) or set(target_times) & set(added_times):
        raise ValueError('Planned added dates collide with existing or restored assets')
    simulated = [(item['ZADDEDDATE'], item['ZUUID'], False) for item in anchors]
    simulated.extend((item['targetAdded'], item['uuid'], True) for item in planned)
    if [identifier for _, identifier, is_restored in sorted(simulated) if not is_restored] != anchor_ids:
        raise ValueError('Simulation changed existing asset order')
    return {
        'rule': 'insert_after_same_backup_second_without_changing_existing_added_dates',
        'existingCount': len(anchors),
        'restoredCount': len(planned),
        'existingOrderPreserved': True,
        'UIOrderVerified': False,
        'items': planned,
    }


def main():
    parser = argparse.ArgumentParser(description='Plan CR3 Recents insertion; no device writes')
    parser.add_argument('anchors', type=Path)
    parser.add_argument('restored', type=Path)
    parser.add_argument('output', type=Path)
    arguments = parser.parse_args()
    anchors = json.loads(arguments.anchors.read_text())
    restored = json.loads(arguments.restored.read_text())
    plan = build_plan(anchors, restored)
    with arguments.output.open('x') as output:
        json.dump(plan, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({key: value for key, value in plan.items() if key != 'items'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
