# Reset 14PM native App Store restoration

This is the November 7, 2026 authorized restoration, targeting only
`iPhone15,3 / iOS 16.3 / 20D47`. Crane is excluded by the user; unavailable
apps, including the employee-only Soda Music listing, may be skipped.

`native-app-store-ui.py` opens exact Apple catalog item IDs and requests native
re-downloads using the phone's existing authenticated session. It does not read
account credentials, tokens, Keychain, or application sandboxes. It does not
purchase apps, change RootHide policies, inject code, or open downloaded apps.

Supporting source is retained in:

- `app/safe-domain-probe/tools/ui-input/main.m`, compiled using
  `SDP_ALI_RESTORE_UI=1`; input is limited to App Store/RootHide Manager, and the
  Python caller only requests App Store input after checking the exact title.
- `app/safe-domain-probe/tools/screen-observe/main.m`; use its default UIKit
  capture, not `--render`: the latter produced a partially black screenshot on
  this target and cannot justify input coordinates.
- `app/safe-domain-probe/tools/ui-input/screen-text.swift`; Apple Vision OCR
  runs locally on the Mac, never in a target application or remote service.
- The helper entitlement sets additionally need the existing standalone
  `no-sandbox=true` and `container-required=false` settings for this non-App
  execution context. Without these settings the target terminated the helper
  (exit 137). These are helper-only entitlements, not target app changes.

The native cloud icon template is cropped from a manually reviewed screenshot
of the exact Douyin listing. Mask matching uses only the blue download icon;
the app title and button crop must also remain pixel-stable before input.
Both app title and store name derive from an exact Bundle ID match in Apple's
lookup response, not from a fuzzy app search. A paid listing is permitted only
when a positively recognized re-download cloud is shown; a price/purchase
button is never clicked.

Screenshots and request evidence are stored under
`backups/restore12-to14pm-20261107/target14pm/store-download-ui*`. Request status
alone does not prove installation: re-read the current registered bundle's
Info.plist/version/build separately. Metadata/configuration evidence is not
proof of app functionality or zero loaded process images.

The helpers are temporary, contain no background services, and should be
removed after the complete request/readback workflow. Retain source/evidence.

## App Store UI automation logic

This section records the required logic for migrating sensitive App Store apps
such as Ali/Ant, JD, bank/payment/finance, and ecommerce apps. These apps must
be restored only from the official App Store on the target phone.

The preferred automation operates through the public UI accessibility layer, using
WebDriverAgent/Appium or `pymobiledevice3 developer wda` when a valid XCUITest
runner is already installed and launchable. It must read the element tree and
locate controls by text, accessibility identifier, label, name, type, enabled
state, visibility, and hittability. It must not use fixed screen coordinates as
the primary action path. The later explicitly authorized standalone fallback
below uses fresh, reviewed screenshot-derived coordinates with foreground,
lock-state and stable-control checks; it does not claim element-tree coverage.

Safe execution order:

1. Confirm the exact target device by UDID, product type, iOS version, and USB
   pairing state before starting any UI session.
2. Load a static allowlist containing the exact App Store item ID, expected
   bundle ID, and human-readable name for each app.
3. For each allowlisted app, open only its exact `itms-apps://` or App Store URL;
   do not search by fuzzy name.
4. Read the WDA/Appium element tree for the current App Store page and verify
   that the visible title or metadata matches the allowlisted app.
5. Find a download control by attributes, accepting only ordinary free download
   states such as `获取`, `下载`, a re-download/cloud button, or their localized
   accessibility labels.
6. Reject price, subscription, trial, purchase, payment, Apple ID password,
   two-factor authentication, profile trust, developer trust, login, privacy
   agreement, or any non-whitelisted prompt.
7. Click only the verified App Store download control and only ordinary system
   confirmation buttons such as `安装`, `继续`, `好`, or `允许` when the prompt is
   clearly part of a free App Store download flow.
8. When final installation verification is requested, poll the installed app
   registry or target filesystem for the expected bundle ID and record display
   name, version, build, and install path. For request-only work, confirm the
   post-tap download state and switch listings without waiting; a click request
   alone is not final installation proof.
9. Do not launch the restored sensitive app after installation. The user must
   manually handle login, privacy agreements, notification permissions, payment,
   cards, biometrics, and any account recovery.
10. Keep an audit log containing the URL opened, matched element attributes,
    clicked label/name/type, prompt handled, and bundle readback result.

Forbidden operations for sensitive apps:

- Do not sideload, TrollStore-install, re-sign, clone, or decrypt the app.
- Do not inject dylibs, hook methods, attach Frida/debugserver, or add the app to
  any tweak filter or RootHide injection list.
- Do not read or write its sandbox, Keychain, App Group container, cookies,
  tokens, login state, purchase data, or account data.
- Do not auto-accept in-app privacy terms or perform login/payment/identity
  verification on behalf of the user.

### Historical WDA attempt on 2026-11-17 (superseded for download requests)

Target device: `iPhone13,1 / iOS 16.3.1 / 20D67`. The actual paired-device
identifier is provided at runtime and omitted from public documentation.

Observed WDA/Appium state:

- Appium `4.0.0` and `xcuitest@13.1.1` are installed in
  a private, session-specific temporary directory.
- The bundled prebuilt runner is present at
  `node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/prebuilt-agents/WebDriverAgentRunner-Runner.zip`.
- Direct installation with `pymobiledevice3 apps install` failed with
  `ApplicationVerificationFailed: Failed to verify code signature ... 0xe8008001`.
- Packaging the runner as an IPA and installing through TrollStore helper also
  did not produce a launchable XCUITest runner. The helper returned
  `install_exit=175` after `ldid: Unsupported Mach-O type`, and the device app
  registry still returned no installed app for
  `com.facebook.WebDriverAgentRunner.xctrunner`.
- `pymobiledevice3 developer wda launch com.apple.AppStore --xctrunner
  com.facebook.WebDriverAgentRunner.xctrunner` failed with
  `AppNotInstalledError: No app with bundle id com.facebook.WebDriverAgentRunner.xctrunner found`.
- Because no signed and launchable WDA runner exists on the device, the required
  element-tree workflow cannot currently click `获取` / `下载` / cloud buttons.

This attempt was blocked on provisioning or supplying a launchable WDA
runner. A valid element-tree route is to install a properly signed
`WebDriverAgentRunner.xctrunner` for this UDID using a full Xcode/developer-team
environment, or to attach to an already running WDA URL. Coordinate-only tapping
is not a substitute for claiming that this element-tree workflow passed.

### Authorized standalone App Store fallback on 2026-11-17

The user subsequently explicitly requested assistant-operated downloads. The
retained standalone `SDP_ALI_RESTORE_UI` helper executed on the current 12 mini
without modifying sensitive apps, their sandboxes, or RootHide configuration.
Fresh screenshots confirmed the exact native listing and cloud control;
foreground/unlocked checks and a stable title/control crop gated each tap.
Post-tap screenshots showed loading indicators for Taobao and Tmall, and the
user confirmed Taobao started downloading. This validates those download
requests, not final installation or WDA availability.

For this explicitly authorized fallback, current screenshot-derived input is
permitted only with the checks above. Fixed coordinates, blind input, target
app injection, and authentication/purchase automation remain forbidden. The
user requested switching to the next listing without waiting for completion.
See `docs/native-app-store-download.md` for the reusable procedure and limits.
The parameterized host controller is `native-app-store-control.py`, with Pillow
declared in `native-app-store-requirements.txt`. It has no embedded device
connection details or fixed screen dimensions. A human must review each current
listing/control; a tap is logged before dispatch and never automatically retried.
