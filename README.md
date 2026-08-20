# DuplicateFinder

Cross-platform duplicate finder for **photos, videos, and documents**. Detects
byte-identical files via streaming SHA-256, lets you bulk-select duplicates, and
deletes them safely to Trash / Recently Deleted.

- **macOS** app — scans your home directory, deletes to Finder Trash
- **iOS / iPadOS** app — scans your Photos library + any folder from Files app,
  deletes photos to Recently Deleted (30-day recovery) and files to the file
  provider's trash
- **CLI** (`dupefind`) — same core, scriptable, works without Xcode

## Repo layout

```
DuplicateFinder/
├── Package.swift                    Swift Package (macOS 14+, iOS 16+)
├── project.yml                      XcodeGen spec — regenerates the .xcodeproj
├── DuplicateFinder.xcodeproj/       Generated. Open this in Xcode.
├── Sources/
│   ├── DuplicateFinderCore/         Platform-agnostic library
│   │   ├── Models/                  MediaKind, FileEntry, ScanConfig, DuplicateGroup, ScanProgress
│   │   ├── Scanner/                 FileWalker, ContentHasher, PhotoAssetEnumerator (iOS)
│   │   ├── Grouping/                DuplicateGrouper (filesystem), PhotoLibraryGrouper (PhotoKit)
│   │   └── Deletion/                TrashDeleter, PhotoAssetDeleter (iOS)
│   ├── DuplicateFinderMac/          Mac SwiftUI app
│   ├── DuplicateFinderiOS/          iOS/iPadOS SwiftUI app (Photos + Files)
│   └── dupefind/                    CLI executable
├── Tests/DuplicateFinderCoreTests/  Swift Testing unit tests
└── scripts/
    ├── build-app.sh                 Wrap SwiftPM Mac binary in a .app bundle
    └── verify.sh                    End-to-end CLI smoke tests
```

## CLI (no Xcode required)

```bash
swift build -c release
.build/release/dupefind ~/Pictures ~/Downloads

# Filter to just photos and videos, skip tiny files
.build/release/dupefind --kinds photo,video --min-size 1024 ~/Movies

# Dry-run a delete plan (keeps newest copy per group)
.build/release/dupefind --trash keep-newest ~/Downloads

# Move duplicate extras to Trash (reversible from Finder)
.build/release/dupefind --trash keep-newest --confirm ~/Downloads
```

Policies: `keep-newest`, `keep-oldest`, `keep-first-path`.

## Regenerate the Xcode project

The `.xcodeproj` is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen        # one-time
xcodegen generate            # rebuilds DuplicateFinder.xcodeproj from project.yml
```

Rerun `xcodegen generate` any time you add a new source file or change target
settings.

## Run the Mac app

```bash
xcodegen generate
open DuplicateFinder.xcodeproj
```

In Xcode, select the **DuplicateFinderMac** scheme → ⌘R. First time only, in
*Signing & Capabilities* pick your Apple ID as the team. Grant Full Disk Access
in System Settings if you want to scan outside your home folder.

## Run on iPhone / iPad (free personal signing)

**One-time setup on your device:**

1. Update Xcode 26+ and iOS 16+ on the device.
2. Plug the iPhone/iPad into your Mac via USB.
3. On the device: **Settings → Privacy & Security → Developer Mode → On**, then
   restart. (Only appears after the device has been connected to Xcode once.)
4. In Xcode: **Settings → Accounts → +** and sign in with your Apple ID. This
   creates a free Personal Team certificate.

**Build & run:**

```bash
xcodegen generate
open DuplicateFinder.xcodeproj
```

1. In Xcode, select the **DuplicateFinderiOS** scheme.
2. Choose your connected device from the destination dropdown (top center).
3. Open the DuplicateFinderiOS target → *Signing & Capabilities* → pick your
   Personal Team.
4. ⌘R.

The first launch on the phone will error with "Untrusted Developer". Fix it once:
**Settings → General → VPN & Device Management → Developer App → trust your
Apple ID**. Then relaunch from the home screen.

**7-day certificate expiry:** free personal signing certs expire every 7 days.
To keep using the app, plug in the device and hit ⌘R again — Xcode resigns and
reinstalls in under a minute.

## What the iOS app does

Two tabs:

- **Photos** — scans your entire photo library (photos + videos) via PhotoKit.
  Requests read-write photo library access on first use. Deletion sends items
  to **Recently Deleted** in the Photos app (recoverable for 30 days).

- **Files** — you tap "Pick a folder", the iOS document picker opens (iCloud
  Drive, On My iPhone, Google Drive, Dropbox, whatever's installed). We scan
  only that folder tree. Deletion goes through `FileManager.trashItem` — the
  file provider decides recovery semantics (iCloud Drive: 30 days).

Both scans use the same two-pass SHA-256 dedupe as the Mac app. WhatsApp media
that's saved to Photos or exported to Files is fair game; media that lives
inside WhatsApp's private container isn't reachable to any third-party app on
iOS.

## Verification (Mac core)

```bash
./scripts/verify.sh
```

Builds `dupefind`, seeds a fixture tree with known duplicates and excluded
dirs (`.git/`, `Library/`), and checks 10 behaviors including per-file
SHA-256 correctness vs. `shasum -a 256` and exact group counts.

Unit tests (Swift Testing):

```bash
swift test
```

## Roadmap

- ✅ macOS CLI + SwiftUI app, exact SHA-256 dedupe, safe Trash delete
- ✅ iOS/iPadOS app with PhotoKit + Files picker
- ⏭ Perceptual hash (pHash) for near-duplicate photos (resized, re-encoded)
- ⏭ Live Photos and burst-mode awareness (group instead of dedupe)

## License

Licensed under the [Apache License, Version 2.0](LICENSE).
