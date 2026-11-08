# 桌面文件夹封面修复

修正普通桌面文件夹大图封面的尺寸，避免偏移、留白和右侧裁切。
保留原来的两个插件，不改文件夹内的 4×5 排列、容量、成员、顺序或 App 白名单。
代码会读取 PrimalFolder 的封面设置，拦截限定范围的封面生成，并在发现窄缓存图时
尝试重建该文件夹封面；不是“完全不执行其他代码”，而是没有其他业务功能。

0.1.4 只更新 Sileo 中显示的中文名称和说明。使用 `sh scripts/repackage-metadata.sh`
生成中文包，沿用已验证的 0.1.3 动态库和 Filter，不重新编译。源码功能未改变。
没有后台循环、轮询或定时器，仍有 Hook 调用、少量状态和必要缓存的 CPU/内存开销。
2026-11-08 的 12 mini 观测：动态库映射约 80 KiB，可写数据页约 32 KiB；
这不是全部增量内存，不能据此保证零耗电或量化总开销。桌面两次 CPU 采样 0.0%，
仅代表采样时整个桌面，不是补丁独立 CPU 用量。未进行卸载对照性能基准。

## Technical details / verified scope

Experimental source-owned patch for PrimalFolder2 0.1.2 with BoldersReborn
1.1.2 on RootHide iOS 16.3/16.3.1, iPhone13,1 and iPhone15,3. No third-party
addon binaries or paid authorization code are copied into this project.

## Scope

- Only SpringBoard injection. Positively identify `SBIconLocationRoot`,
  `SBFolderIcon`, parent `SBIconListModel` owned by `SBRootFolder`, and active
  PrimalFolder cover. The two-hop parent chain was read on the actual device.
- A per-thread stack context wraps synchronous desktop image update/fulfilment
  calls. The class factory checks the exact folder/page and binds its own
  layout argument. Geometry hooks act only inside this generation context.
- Consistent square canvas and first-cell rect; nested unrelated page lookups
  clear context. No process-global classification flag writes.
- Non-square cached cover triggers one bounded system per-folder rebuild,
  guarded against notification reentry. A failed image is remembered per view
  to avoid repeated rebuilds of that same image. Never stretch a clipped image.
- No hooks on folder model capacity, rows/columns, IconState, app launching,
  inside-folder layout, or App Library. No polling or heap scans.
- Original addon files, app whitelist and protected-app isolation stay intact.

## Compatibility gates / status

**0.1.0 device validation FAILED. Do not install that package.** On 2026-11-08,
the first SpringBoard load called `UIScreen.mainScreen` in the dylib constructor
before UIKit screen creation and triggered an assertion / SIGABRT. No cover
repair ran. The package was removed, original desktop addons restored, and
whitelist/preferences verified unchanged. The full device crash evidence is
retained under `/tmp/codex-folder-cover-install-mini-20261108-183534/`.

0.1.1 removed constructor-time screen/device calls but was not installed.
0.1.2 also resolves PrimalFolder preferences through this dylib's adjacent
`.jbroot`, rather than assuming the SSH and UIKit filesystem views are equal.
Foundation OS-version check remains; no early screen calls are made.

0.1.2 loaded on the real desktop without a new startup crash, but its direct
root-folder parent check never matched. It is not an effective repair build.
0.1.3 uses the observed `SBFolder -> SBIconListModel -> SBRootFolder` chain.

The same production callbacks pass a Mac fake-object fixture and the standalone
iOS fixture (including 1000 repeated calls). The actual 0.1.2 dylib also passes
an isolated iOS preflight: initialization, actual MSHookMessageEx calls,
square cover generation, bad cache rebuild and non-target pass-through.
The preflight uses fake classes and gate-only UUID stubs, not the original
addons or real UIKit views; it cannot prove real desktop or long-term safety.

Requires the exact audited arm64e image UUIDs and all private method encodings.
Unknown device, OS, addon binary, method signature, location or parent means
no scoped changes. File name uses a late alphabetical position; if required
images are not loaded at constructor time the patch refuses to install hooks.
No retries, delayed function hooks, runtime byte patching or debugger injection.

The rendering paths/signatures were read from the 12 mini live process using
external read-only metadata access. 0.1.3 was installed on iPhone13,1 / iOS
16.3.1 on 2026-11-08. Read-only runtime counters confirmed eight qualified
cover-generation and size calls; all eight cached UIImage and CGImage sizes
were 180x180 pixels. No new SpringBoard crash after this load or safe-mode
marker was observed. Original addon binaries/preferences, app allow-list and
RootHide configuration remained byte-identical to the pre-install backup.
Folder members, paging, order and dock were preserved; a separate additional
second-page app registration was retained rather than overwritten.

This is bounded on-device verification, NOT a permanence guarantee. Real UI
visual checks, long-term recurrence, real App Library behavior and repair of
an existing bad cache without restart are not verified. The bad-cache repair
path was exercised only in isolation. iPhone15,3 is not deployment-verified.
Evidence: `/tmp/folder-cover-reinstall-20261108-185526/final-verification.json`.
Shared-cache use and asynchronous callbacks outside these contexts remain
validation risks. Three device factory methods and image-view entrypoints were
verified by external runtime metadata extraction; there are no guessed ABI
signatures. Installation does not itself reload SpringBoard: no install
script/reboot trigger is supplied. Explicit reload authorization is required.

Build: `sh scripts/build.sh`. RootHide arm64e only; ordinary Dopamine rootless
is not built or validated. Package resides in `packages/`, source stays here.
Local geometry/filter checks: `sh scripts/check.sh`. These checks do not
exercise real private classes or user interfaces; the callback fixture includes
the production code with renamed fake images. Build the isolated iOS dynamic
preflight with `sh scripts/build-preflight.sh`; its gate-only UUID stub files
are test fixtures and must NEVER be copied into a production addon directory.
Keep a rollback package and original config/semantic IconState backup before
live installation; validate initial and regenerated covers, capacity, App
Library non-target behavior and crashes before calling this a usable fix.
