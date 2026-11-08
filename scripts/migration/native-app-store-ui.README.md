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
