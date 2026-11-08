# Camera roll transfer helper

Derived from `../photos-edited-original-restore/PhotosEditedOriginalRestore.m`.
Creates only the explicitly planned asset through PhotoKit. It does not inject
apps, directly write the Photos database, transcode media, or delete originals.

An import plan supplies `primary`, optional `pairedVideo`, exact SHA-256 and
byte counts, original filenames, Apple-reference `creationDate` / `addedDate`,
media kind/subtype and optional coordinates. `albumIdentifier` is optional;
without it the new asset belongs to the camera roll only.

RootHide database namespace is resolved at runtime. `inspect` must confirm
Photos authorization and `setAddedDate:` availability before writes. Save a
consistent target database/WAL snapshot on both Mac and device, check duplicate
resources, and verify one Live Photo before the remaining authorized imports.

The creation receipt is persisted immediately after a successful PhotoKit
transaction, before observing the new asset. Failure or observation timeout
preserves this receipt and asset: do not reimport or delete automatically.
`finish-existing PLAN UUID` is only for the exact receipt-matched asset created
by this operation. Verification reads original resource data through PhotoKit,
computes streaming hashes without duplicating large videos, checks filename,
size, dates, location, media subtype and Live Photo pairing.

Build:

```sh
xcrun clang -target arm64-apple-ios16.0 \
  -isysroot "$HOME/theos/sdks/iPhoneOS16.5.sdk" \
  -fobjc-arc -O2 -Wall -Wextra -Wno-deprecated-declarations \
  -framework Foundation -framework Photos -framework CoreLocation -lsqlite3 \
  PhotosCameraRollTransfer.m -o /tmp/PhotosCameraRollTransfer
ldid -Sentitlements.plist /tmp/PhotosCameraRollTransfer
```

Commands: `inspect`, `import-one PLAN`, `verify RECEIPT`,
`finish-existing PLAN UUID`, optional `create-album TITLE RECEIPT`.

The original added timestamp is private iOS API behavior: verify runtime and
persisted database readback on every target version. No full-library ordering
changes occur. PhotoKit/hash readback is not a visual UI or iCloud sync test.

## Bounded bulk restore

`import-batch PLAN` accepts 1-24 explicit assets and a fresh expected personal
asset count. Primary photos/RAW, primary videos, and Live Photo paired MOVs are
created in a single transaction. `batch-receipt.json` is saved before observing
or updating created assets. `finish-batch RECEIPT` updates only those receipt
identities, then `verify-batch RECEIPT` reads original bytes and checks metadata.
A failure must stop automatic creation: retain the receipt and inspect it.

`restore_bulk.py --operation DIR` uses a prebuilt `bulk-config.json` and
`bulk-plans.json`. It hashes source files, snapshots target SQLite plus WAL,
checks the existing sample identities, then overlaps at most a bounded number
of staging batches with sequential PhotoKit writes. Each batch contains at
most 24 assets and normally 320 MiB; an individual large video may exceed this
byte target. It does not transcode or compress media. Successfully verified
batch staging files may be deleted, but library originals and source backups
are never deleted. Each landed batch has local receipts, a progress file and
per-resource verification. A failure stops the workflow and prevents blind
restart when `completed-assets.json` already exists.

A RAW uniform type identifier is supplied when recorded in the source DB.
System-derived screenshot, burst, and slow-motion subtypes can be recreated
differently by PhotoKit; `allowSystemDerivedSubtype` permits this only for the
explicit source subtypes and records `sourceKindSubtype` plus
`kindSubtypePreserved`. This is not proof of preserving an editing recipe or
burst-group membership. Original bytes, capture time, added time, location,
Live Photo pairing, and explicit favorite flags remain the recovery checks.
The final audit reports any system-derived subtype differences rather than
claiming complete behavioral equality.
