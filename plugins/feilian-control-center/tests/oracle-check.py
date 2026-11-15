#!/usr/bin/env python3
"""Static guards for test-oracle early exits, not device regression evidence."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
stress=(root/'tools/live-acceptance/assertion-close-stress.m').read_text()
assert 'if(!ready){[client close];Log(@"STRESS_ACQUIRE_FAILED=1");return;}' in stress
assert 'if(stillOpen){[client close];Log(@"LEASE_EXPIRY_FAILED=1");return;}' in stress
assert 'if([client probe]){Log(@"STRESS_CLOSED_PROBE_FAILED=1");return;}' in stress
probe=(root/'EasyVPNHelper/native-probe.m').read_text()
assert 'return done && valid && [Target connected] ? 0 : 1;' in probe
host=(root/'tools/live-acceptance/host.m').read_text()
assert 'Log(@"NETWORK_FAILED=1");Stop();return;' in host
ipc=(root/'Shared/VPNIPC.m').read_text()
constructor=ipc[ipc.index('- (instancetype)initWithProvider:(NSString *)provider command:'):]
assert '[probe open]' not in constructor
assert 'error!=ECONNREFUSED' in constructor
assert 'current.st_dev!=st.st_dev || current.st_ino!=st.st_ino' in constructor
print('ORACLE_SOURCE_CHECKS=8 PASS=1 (static only)')
