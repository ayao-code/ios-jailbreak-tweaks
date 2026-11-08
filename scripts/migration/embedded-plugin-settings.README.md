# Reset 14PM WeChat / Douyin plugin settings

The user authorized restoring plugin settings from the collected 12 mini
snapshot, without App injection policy changes or native account/chat transfer.
The November 7 10:07 snapshot has 65 WeChat main-suite keys, 60 WeChatTweak
suite keys, and 45 DYYY keys. Exact keys are retained in
`embedded-plugin-keys.h`, generated from the reviewed plugin-only manifest.
Source absence never causes a target key to be deleted.

`embedded-plugin-prefs.m` uses the verified container-specific NSUserDefaults
initializer, reads only those exact plugin keys, and accepts a `set` patch
without removal operations. Unlike `dictionaryRepresentation`,
`persistentDomainForName:` returned an empty dictionary in this execution
context. Raw global defaults are not plugin evidence and must not be copied.
Do not substitute that API or use inherited global keys as app settings.

Raw disk readback uses the verified SSH `/rootfs/private/var/mobile/...` view;
ordinary Foundation paths in a jbroot helper were mapped differently. Only
container-specific native API plugin keys matching raw disk were accepted.
The target jbroot changed during this task; the restore script derives the
live root from helper and policy canonical paths instead of hardcoding it.

Build with the retained iPhoneOS16.5 SDK:

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" -fobjc-arc -O2 \
  -Wall -Wextra -Werror -framework Foundation \
  scripts/migration/embedded-plugin-prefs.m -o /tmp/embedded-plugin-prefs
ldid -Sscripts/tools/tweak-preferences/entitlements.plist /tmp/embedded-plugin-prefs
```

`restore-embedded-plugin-settings.py` requires the verified current SSH socket
and helper. It checks installed plugins, exact container, native/disk equality,
dual timestamped byte backups, existing format/metadata and concurrent edits.
It applies only reviewed saved keys, waits for disk persistence, checks all
non-target values, rereads the native consumer, and preserves all RootHide
policy bytes. No App is launched, terminated, hooked, or debugged. The helper
is temporary and is removed after readback; source and backup evidence remain.

The completed restore report is
`backups/restore12-to14pm-20261107/reports/embedded-plugin-settings-restored.json`.
These are persisted settings, not proof of every plugin feature working on the
new App Store versions. WeChat was currently allowed by the user; Aweme was
not allowed. The agent did not enable either App or change those decisions.
No custom image assets, activation material, or license claims were migrated.
