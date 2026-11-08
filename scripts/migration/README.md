# Scoped 14PM to 12 mini migration tools

Repository cleanup (2026-11-08): historical backup payloads, reports and device
snapshots under `backups/` have been removed at the user's request. These scripts
remain as source, not ready-to-replay migration jobs. Re-inventory both devices,
provide fresh reviewed inputs and create new dual backups before any execution.
The paths mentioned below describe the original migration, not retained assets.

These tools support the explicitly authorized November 7 migration. They are
not general-purpose device backup or jailbreak installers. Do not rerun them
without rereading the live target identity and the corresponding report files.

## Boundaries

- Source: iPhone15,3 / iOS 16.3 / 20D47.
- Target: iPhone13,1 / iOS 16.3.1 / 20D67.
- Existing target jailbreak/base packages must not be replaced by source ones.
- No Photos/DCIM, native account data, Keychain, or chat-history migration.
- No Ali/Ant, banking/payment/securities, or JD application injection.
- Credentials are supplied interactively or through the existing authorized
  SSH control connection; no credentials belong in scripts or reports.
- Every configuration mutation needs timestamped local and device backups,
  a current consumer/path check, and persisted semantic readback.

## Files

- `install-trollstore-manifest.py`: explicit IPA manifest with hash, bundle ID,
  registration and version readback. It excludes jailbreak/system applications.
  TrollStore status 184 is an installed-app warning for encrypted secondary
  binaries, not proof that all extensions work. Existing applications need a
  separate update/backup review; the script refuses to overwrite them.
- `tweak-prefs.m`: standalone CFPreferences client for bounded tweak domains,
  plus container-limited plugin keys for WeChat and Douyin. It does not inject
  into applications or start background services. Returned preferences may
  include global defaults; only inventoried plugin keys may be migrated.
- `apply-standalone-preferences.py`: applies inventoried standalone tweak
  preferences, preserves backups across resumptions, verifies API and disk,
  and excludes transient audio commands/snapshots. Scope is this migration.
- `controlcenter-settings.m`: uses the live ControlCenterServices serializer
  through a process-local subclass targeting the installed CCSupport config.
  `inspect` and `read` are read-only. `apply` requires the caller's verified
  dual backup and an explicit desired plist. It does not hook system processes.
- `crane-root-settings.m`: uses Crane's own settings writer for two global UI
  options only. It rejects per-App/container/account configuration; container
  identifiers and system-account separation cannot be restored by copying
  missing container data or activation material.
- `reconcile-desktop.py`: recomputes no app inventory itself; it applies the
  previously reviewed current layout candidate to IconOrder's native API,
  preserving other keys, dual backups, original format and metadata. A desktop
  reload and current runtime IconState readback are separate required steps.

IconOrder XML may contain control characters in source folder names that a
strict external XML parser rejects. Its native Foundation reader still accepts
that saved file. `tweak-prefs iconorder-disk-read` checks native disk semantics;
`iconorder-xml` uses IconOrder's own `writeToFile:atomically:` serialization after
the caller has made verified backups. Never "repair" this by stripping folder
names or silently converting the file format.

The source desktop was reread and contains no Crane icon. Do not invent a
source folder position merely because the source has Crane installed. Target
only tools are kept together on the extra final page, with the explicitly
selected source app/folder/Dock relative order retained.

Crane's original XPC self-check is stronger than daemon existence: the current
source passes; the target reports missing support in `containermanagerd`,
`securityd`, `apsd`, `pkd` and `accountsd`. Those observations do not authorize
editing the RootHide whitelist directly or prove that a toggle alone fixes it.
Use the original management UI and rerun the native checks after any approved
action. Do not mark Crane container functionality complete in its current state.

TrollSpeed's `ch.xxtou.hudservices` was missing from target launchd even after
its source-specific path had been reconciled. It has now been loaded with the
native `launchctl load` interface; both launchd PID and process readbacks were
observed. The startup preserved configuration bytes and `-hud` arguments.
Service existence and a single low CPU sample are not full visual or power
validation. Do not start a second instance if this label is already loaded.

AutoFaceUnlock has separate source preferences in jbroot and real-system
namespaces. The latter includes `CheckFlashlight=true`, which is absent from the
former. Its obfuscated consumer path is not established; the target's real
namespace file is absent. Do not claim that the three copied jbroot keys prove
all source settings are effective, and do not copy both files without proving
the producer/consumer paths and obtaining the required write approval.

Static inspection decoded its literal input path as
`/var/mobile/Library/Preferences/com.netskao.autofaceunlock.plist` and the
`CheckFlashlight` key. That literal is not proof of the runtime-mapped path.
The `autoface-system-preferences.m` read-only suite probe returned the three
jbroot values on both devices, not the source's four real-system values.
Consequently no `apply` operation was executed; the temporary probes were
removed. Do not use that interface to claim real-system preference alignment.

## Namespace handling

SSH executes in jbroot while TrollStore helpers execute in the real system
namespace. Upload through `/rootfs/var/mobile/Media` and give TrollStore the
corresponding `/var/mobile/Media` path. Standalone Foundation clients also need
the canonical real patch path; resolve it rather than assuming `/var/jb`.

## Native API and build evidence

The inspected iOS 16.3.1 ControlCenterServices class exposes `_readSettings`,
not the iOS 17 `_readSettingsWithVersion:` selector. The client chooses only a
selector actually present at runtime. Its native writer produced the same XML
bytes and permissions as the source 19-module configuration. This proves
configuration persistence, not GUI/module functionality.

Build standalone Objective-C clients using the existing iPhoneOS16.5 SDK,
`-target arm64-apple-ios16.0`, ARC, Foundation, and `-Wall -Wextra -Werror`.
Sign the preferences clients with the existing
`scripts/tools/tweak-preferences/entitlements.plist`. Successful compilation or
signing alone does not prove execution; keep device readback evidence separate.

Detailed current evidence and incomplete requirements are in
`backups/migration-14pm-to-mini-20261107/reports/progress.json`.
The GUI pipeline currently cannot pass its `fluxcli` prerequisite: the installed
`@bytedance-dev/flux` package exposes `flux`, without the expected `bytest`
subcommand. Do not fake an alias or silently skip the gate.

## Authorized Alibaba/Ant blacklist on reset 14PM

The later restore targets iPhone15,3 / iOS16.3 / 20D47. Its artifacts are in
`backups/restore12-to14pm-20261107`, separate from the earlier opposite-direction
migration. The user explicitly authorized independent Alibaba/Ant deny entries
while retaining PiliPlus's shared `Runner` allowance.

`apply-ali-blacklist.py` changes only `RootHideConfig.plist/appconfig`. It first
backs up original blacklist existence/content and all three allowlist-related
files on Mac and device, checks source-derived bundle IDs, validates native
mutable XML dictionary semantics, and atomically installs the same-directory
temporary file. Non-target keys, existing metadata and allowance bytes must be
unchanged. If service readback fails, it rolls back only its exact published
bytes, never a concurrent user edit. The bounded query client source is retained
in `blacklist-consumer-check.m`; its temporary executable was removed.

29 explicit IDs were verified: 11 parent apps from the authorized backup plus
18 extension IDs from the live 12 mini app bundles. The jailbreak service's
original XPC bundle-blacklist query returned true for every ID and false for
PiliPlus and Tools. Original RootHide Manager launched without a newly observed
named crash. Its UI toggle roundtrip and sensitive-app process image scans
were not performed, so these are configuration/native-service evidence only.

The zqbb release is not fully represented by w2599's public ordinary-Dopamine
branch. Mode/precedence claims were checked against the actual target
`libroothider.dylib` and `systemhook` instructions, not inferred from filenames.
Ordinary executables use system/user whitelists. Only executable names enabled
in `cn.zqbb.inject.wantsblacklist.plist` consult per-App blacklist first; that
deny overrides their user allowance. A normal Alibaba executable must therefore
remain unallowed even when its Bundle ID is prelisted in appconfig. These are
explicit IDs, not a wildcard covering future apps or newly added extensions.

LeftPan 2.0 and its five live 12 mini settings were subsequently restored.
All Alibaba deny records and the system/special maps stayed byte-identical.
User allowance files changed concurrently, so Crane restoration was deferred;
the agent did not write or revert those user allowances.

Privacy cleanup: device-bound one-off restoration scripts were moved out of this public checkout. The retained tools require fresh authorized inputs.
