import argparse
import collections
import json
import math
import sqlite3
from pathlib import Path


def read_assets(snapshot):
    connection = sqlite3.connect(snapshot.as_uri() + '?mode=ro&immutable=1', uri=True)
    connection.row_factory = sqlite3.Row
    if connection.execute('PRAGMA quick_check').fetchone()[0] != 'ok':
        raise ValueError('Invalid Photos snapshot')
    assets = [dict(row) for row in connection.execute(
        'SELECT ZUUID,ZFILENAME,ZDATECREATED,ZADDEDDATE,ZKIND,ZKINDSUBTYPE '
        'FROM ZASSET WHERE ZTRASHEDSTATE=0 AND ZBUNDLESCOPE=0 ORDER BY ZADDEDDATE,Z_PK')]
    connection.close()
    return assets


def choose_gap(target, fixed, dated_indices, previous_dated, next_dated):
    best = None
    left_greater = 0
    right_less = sum(fixed[index]['ZDATECREATED'] < target['ZDATECREATED'] for index in dated_indices)
    dated_set = set(dated_indices)
    for gap in range(1, len(fixed)):
        moved = gap - 1
        if moved in dated_set:
            left_greater += fixed[moved]['ZDATECREATED'] > target['ZDATECREATED']
            right_less -= fixed[moved]['ZDATECREATED'] < target['ZDATECREATED']
        inversion_cost = left_greater + right_less
        neighbors = []
        if previous_dated[gap] is not None:
            index = previous_dated[gap]
            neighbors.append((abs(fixed[index]['ZDATECREATED'] - target['ZDATECREATED']), gap - 1 - index))
        if next_dated[gap] is not None:
            index = next_dated[gap]
            neighbors.append((abs(fixed[index]['ZDATECREATED'] - target['ZDATECREATED']), index - gap))
        nearest_delta, missing_distance = min(neighbors)
        displacement = abs(gap - target['fixedGapBefore'])
        score = (inversion_cost, nearest_delta, missing_distance, displacement, gap)
        if best is None or score < best[0]:
            best = (score, gap)
    return best[1], best[0]


def build_plan(assets, target_ids, missing_ids):
    identifiers = [item['ZUUID'] for item in assets]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError('Asset UUIDs are not unique')
    if target_ids & missing_ids:
        raise ValueError('Target and missing-date scopes overlap')
    if not target_ids <= set(identifiers) or not missing_ids <= set(identifiers):
        raise ValueError('Planned scope is absent from snapshot')
    fixed = [item for item in assets if item['ZUUID'] not in target_ids]
    fixed_positions = {item['ZUUID']: index for index, item in enumerate(fixed)}
    dated_indices = [index for index, item in enumerate(fixed) if item['ZUUID'] not in missing_ids]
    dated_set = set(dated_indices)
    previous_dated = [None] * (len(fixed) + 1)
    previous = None
    for gap in range(len(fixed) + 1):
        previous_dated[gap] = previous
        if gap < len(fixed) and gap in dated_set:
            previous = gap
    next_dated = [None] * (len(fixed) + 1)
    following = None
    for gap in range(len(fixed), -1, -1):
        if gap < len(fixed) and gap in dated_set:
            following = gap
        next_dated[gap] = following
    targets = []
    fixed_seen = 0
    for item in assets:
        if item['ZUUID'] in target_ids:
            targets.append({**item, 'fixedGapBefore': fixed_seen})
        else:
            fixed_seen += 1
    assignments = collections.defaultdict(list)
    for target in targets:
        gap, score = choose_gap(target, fixed, dated_indices, previous_dated, next_dated)
        target['targetGap'] = gap
        target['inversionCost'] = score[0]
        assignments[gap].append(target)
    planned = []
    for gap, members in assignments.items():
        members.sort(key=lambda item: (item['ZDATECREATED'], item['ZUUID']))
        left_added = fixed[gap - 1]['ZADDEDDATE']
        right_added = fixed[gap]['ZADDEDDATE']
        if not left_added < right_added:
            raise ValueError('Fixed added dates are not strictly increasing')
        for position, item in enumerate(members, start=1):
            target_added = left_added + (right_added - left_added) * position / (len(members) + 1)
            if not left_added < target_added < right_added or not math.isfinite(target_added):
                raise ValueError('Added-date gap has insufficient precision')
            planned.append({
                'uuid': item['ZUUID'],
                'filename': item['ZFILENAME'],
                'created': item['ZDATECREATED'],
                'originalAdded': item['ZADDEDDATE'],
                'targetAdded': target_added,
                'oldRecentsIndex': identifiers.index(item['ZUUID']),
                'targetGap': gap,
                'leftUUID': fixed[gap - 1]['ZUUID'],
                'leftFilename': fixed[gap - 1]['ZFILENAME'],
                'rightUUID': fixed[gap]['ZUUID'],
                'rightFilename': fixed[gap]['ZFILENAME'],
            })
    target_by_id = {item['uuid']: item for item in planned}
    simulated = list(fixed)
    for gap in sorted(assignments, reverse=True):
        members = sorted(assignments[gap], key=lambda item: (item['ZDATECREATED'], item['ZUUID']))
        simulated[gap:gap] = members
    simulated_ids = [item['ZUUID'] for item in simulated]
    for item in planned:
        item['newRecentsIndex'] = simulated_ids.index(item['uuid'])
    valid = [item for item in simulated if item['ZUUID'] not in missing_ids]
    inversions = [(left['ZUUID'], right['ZUUID']) for left, right in zip(valid, valid[1:])
                  if left['ZDATECREATED'] > right['ZDATECREATED']]
    fixed_before = [item['ZUUID'] for item in assets if item['ZUUID'] not in target_ids]
    fixed_after = [item['ZUUID'] for item in simulated if item['ZUUID'] not in target_ids]
    if fixed_before != fixed_after:
        raise ValueError('Simulation changed non-target relative order')
    return {
        'rule': 'move only target added dates to minimize creation-date inversions; missing-date assets are not anchors',
        'targetCount': len(planned),
        'fixedCount': len(fixed),
        'missingDateAnchorExclusionCount': len(missing_ids),
        'nonTargetRelativeOrderPreserved': True,
        'residualValidDateAdjacentInversions': len(inversions),
        'residualInversionPairs': inversions,
        'items': sorted(planned, key=lambda item: item['uuid']),
    }


def main():
    parser = argparse.ArgumentParser(description='Plan a target-only Recents reorder without changing capture dates')
    parser.add_argument('snapshot', type=Path)
    parser.add_argument('target_json', type=Path)
    parser.add_argument('missing_json', type=Path)
    parser.add_argument('output', type=Path)
    arguments = parser.parse_args()
    target_data = json.loads(arguments.target_json.read_text())
    missing_data = json.loads(arguments.missing_json.read_text())
    target_ids = {item['ZUUID'] for item in target_data['items']}
    missing_ids = {item['uuid'] for item in missing_data['items']}
    plan = build_plan(read_assets(arguments.snapshot), target_ids, missing_ids)
    with arguments.output.open('x') as output:
        json.dump(plan, output, ensure_ascii=False, indent=2)
        output.write('\n')
    print(json.dumps({key: value for key, value in plan.items() if key not in {'items', 'residualInversionPairs'}}, ensure_ascii=False))


if __name__ == '__main__':
    main()
