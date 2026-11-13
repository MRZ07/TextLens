<img src="Resources/AppIcon.png" width="128" height="128" alt="TextLens app icon">

# TextLens

Copy text from anywhere on your screen. Select a region, recognize it offline with Apple Vision, and paste it into any app.

**macOS 14+ · Apple Silicon · Signed and notarized downloads**

## Install

### Homebrew

```sh
brew tap MRZ07/textlens https://github.com/MRZ07/TextLens
brew trust --cask MRZ07/textlens/textlens
brew install --cask MRZ07/textlens/textlens
```

Homebrew manages the installation, but does not install app updates in the background. To get a newer release:

```sh
brew upgrade --cask MRZ07/textlens/textlens
```

This upgrades only TextLens. Future releases need a higher version number; if the same version is replaced, use `brew reinstall --cask MRZ07/textlens/textlens` instead.

### Download

**[Download signed and notarized TextLens for macOS (.zip)](https://github.com/MRZ07/TextLens/releases/download/v0.1.0/TextLens-0.1.0.zip)**

Unzip the download, drag **TextLens.app** into **Applications**, then launch it. This release is distributed as a ZIP; all versions are listed under [Releases](https://github.com/MRZ07/TextLens/releases).

## Use

1. Click the menu bar icon and choose **Capture text**, or press **⌘⌥⇧T**.
2. Drag over the text you want to copy.
3. Paste. Recognized text is copied automatically.

Normal capture preserves line breaks. Choose **Capture text without line breaks**, or press **⌘⌥⇧L**, to join the recognized lines into a single line.

Change or clear each shortcut independently in **Settings → Shortcuts**. The current combinations appear beside their capture commands in the menu. The menu also opens searchable **Capture history**, **Settings**, and **About TextLens**. Closing those windows leaves the app running; use **Quit TextLens** to exit.

**Settings → General** controls automatic clipboard copying, success notifications, and notification sound. All three are enabled by default. With auto-copy off, use the Copy button in Capture History. Notifications show a preview of the recognized text and may be visible on the lock screen. macOS permission is required; Focus and system notification settings may suppress banners or sound. Disabling notifications also prevents their sound.

TextLens asks once whether it should **start when you log in**. Nothing is enabled before you agree. Change this later in **Settings → General → Startup**. If macOS requires approval, the app links to Login Items settings and shows the pending status instead of claiming startup is active.

## Features

- Offline, on-device text recognition with Apple Vision.
- Native screen-region selection and automatic clipboard copy.
- Two customizable global shortcuts: preserve line breaks or copy as a single line.
- Default-enabled auto-copy and success notifications with recognized-text previews.
- Optional notification sound and opt-in launch at login.
- Search and copy again from the newest 100 captures.
- History/privacy controls and a link to macOS screen-recording settings.

## Privacy and permissions

If macOS blocks a capture, allow TextLens in **System Settings → Privacy & Security → Screen & System Audio Recording**. Screenshots are temporary; only recognized text is saved in `~/Library/Application Support/TextLens/capture-history.json`. Nothing is uploaded for OCR. Clear saved text in Settings or Capture History.

**OCR limits:** this version uses Vision's accurate mode and language correction, but has no language picker or explicit language configuration. Recognition is biased toward English; other languages, small fonts, and handwriting may be less reliable.

## Build and release from source

Install Xcode Command Line Tools with Swift. Release builds are tested with Xcode 27.2.

```sh
swift test
./scripts/build-app.sh
open dist/TextLens.app
```

The local build is unsigned and includes the icon and SwiftPM resource bundles. To create a signed, notarized ZIP release, install a **Developer ID Application** identity and configure the `TextLensNotary` keychain profile, then run:

```sh
./scripts/package-release.sh
```

Use `TEXTLENS_VERSION` for a different version. The script prints the ZIP's SHA-256; update the Cask to match the published download. Homebrew upgrades are manual with `brew upgrade --cask MRZ07/textlens/textlens`; TextLens does not install a background updater.

## Credits and license

Inspired by [TRex](https://github.com/amebalabs/TRex); independently implemented and not affiliated with its authors. Global shortcuts use [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

There is currently no license file. Public visibility does not grant permission to reuse or redistribute the code or icon.
