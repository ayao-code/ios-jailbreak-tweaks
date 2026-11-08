import os
"""Package unchanged user-provided binary for isolated A/B, never into a daily App."""
from pathlib import Path
import plistlib, shutil, hashlib

app = Path('dist-original/Payload/AutoSkipOriginalFixture.app')
original = Path(os.environ["AUTOSKIP_ORIGINAL_DYLIB"])
assert hashlib.sha256(original.read_bytes()).hexdigest() == 'f25526df81e240a9fabb8596e27902df39f31c035a305825687ffe494575fb5f'
shutil.copy2(original, app / 'Frameworks/AutoSkipOriginal.dylib')
info = plistlib.loads(Path('Info.plist').read_bytes())
info.update(CFBundleIdentifier='ayao.autoskip.originalfixture', CFBundleExecutable='AutoSkipOriginalFixture',
            CFBundleName='AutoSkipOriginalFixture', CFBundleDisplayName='AutoSkip Original Fixture')
info['CFBundleURLTypes'][0]['CFBundleURLSchemes'] = ['asgoriginal']
(app / 'Info.plist').write_bytes(plistlib.dumps(info, fmt=plistlib.FMT_XML))
