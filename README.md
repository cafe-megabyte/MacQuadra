# MacQuadra 

MacQuadra is an iOS-focused fork of Basilisk II, tuned for running classic 68k Macintosh software on iPhone and iPad.

The repository still contains the original Basilisk II and SheepShaver source trees, but the active work in this fork is the iOS Basilisk II app in:

```text
BasiliskII/src/iOS
```

## What this fork adds

- Automatic emulator boot once a ROM and boot disk are available in the file system
- Play sound at startup decoded from ROM file
- Optional private ZIP download URLs for a ROM file and disk image with on-the-fly inflate
- Make copy before first use of a disk image + restore option in Drive settings, strictly using APFS copy-on-write
- Improved interactive custom screen sizing with different preset-options
- Zoom and pinch to enlarge and move the view
- New keyboard reveal gestures than don't interfere with the zoom gestures (from side edges with one finger or pencil)
- Dynamic screen sizes that are re-calculated on emulator start
- New defaults
- Higher max. RAM size (512 MB)
- On-screen keyboard for German
- German localization
- Version and build information exposed in the iOS Settings app
- App Icon for Light and Dark

## Legal note

This repository does not include a Macintosh ROM, Mac OS, or any Apple system software.

To use the emulator you need your own legally obtained Macintosh ROM image and a compatible classic Mac OS installation or disk image. Do not publish ROMs, system disks, or private download URLs in this repository.

## Requirements

- macOS with Xcode
- An Apple development team for device builds
- iOS/iPadOS 15.6 or later for the app target
- A compatible 68k Macintosh ROM file, usually `.rom`
- A bootable classic Mac OS disk image, for example `.img`, `.dsk`, `.hd`, or `.disk`

## Building

Open the iOS project in Xcode:

```sh
open BasiliskII/src/iOS/BasiliskII.xcodeproj
```

Then select the `BasiliskII` scheme and build for an iPhone or iPad device.

You will probably need to change the signing team and bundle identifier before installing the app on your own device.

## Configure private download for supplying ROM and disk image
For personal builds or private TestFlight distribution, you can configure private ZIP download URLs.

Copy the example file:

```sh
cp BasiliskII/src/iOS/BasiliskII/B2PrivateResourceURLs.example.h \
   BasiliskII/src/iOS/BasiliskII/B2PrivateResourceURLs.h
```

Then edit `B2PrivateResourceURLs.h`:

```objc
#define B2_PRIVATE_ROM_ZIP_URL @"https://example.com/private/rom.zip"
#define B2_PRIVATE_DISK_ZIP_URL @"https://example.com/private/system-disk.zip"
```

`B2PrivateResourceURLs.h` is ignored by git and must stay private.

Each ZIP archive must contain exactly one file: one ROM file or one disk image. ZIP archives with multiple files, folders, or encrypted entries are not supported. The ZIP file is deflated on-the-fly while being downloaded. When the download finishes, the file is ready to use!

## Repository background

Basilisk II is an open source 68k Macintosh emulator originally written by Christian Bauer and contributors. SheepShaver is also included in this repository as part of the inherited macemu source tree.

This fork keeps that history but focuses on a practical iOS app experience.

## License

Basilisk II is distributed under the GNU General Public License. See the license files in the original source tree for details.
