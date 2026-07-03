# macpad

macpad is a native macOS AppKit plain-text editor. It uses Cocoa/AppKit directly: no Electron, no Wine, no Windows compatibility wrapper.

## Requirements

- macOS 11 or later
- Xcode Command Line Tools (`clang`, `make`)

Install the command line tools if needed:

```sh
xcode-select --install
```

## Build

```sh
make
```

This creates:

```text
build/macpad.app
```

## Run

```sh
make run
```

Or open the app directly:

```sh
open build/macpad.app
```

## Clean

```sh
make clean
```

## macOS Features

- Native AppKit menu bar and document window
- Multiple document windows
- Native macOS Window menu for minimizing, zooming, focusing, and bringing windows forward
- Plain-text editing with `NSTextView`
- New, Open, Save, Save As, Close, Quit
- Native open/save panels
- Native printing and page setup
- Undo, redo, cut, copy, paste, delete, select all
- Native find and replace panel
- Go To Line
- Time/date insertion
- Word wrap toggle
- Font panel integration
- Status bar with line, column, and total line count
- Optional line number ruler
- Drag-and-drop opening for files
- BOM-aware text loading and saving for UTF-8, UTF-16LE, UTF-16BE, and Windows-1252 fallback

## Project Layout

- `macos/MacpadApp.m` - native AppKit application source
- `macos/Info.plist` - macOS bundle metadata and document type registration
- `macos/macpad.entitlements` - sandbox entitlements for local signed builds
- `macos/Assets/macpad.icns` - bundled macOS app icon
- `macos/Assets/macpad-icon-source.png` - generated source artwork for the icon
- `Makefile` - macOS build
- `LICENSE` - BSD 3-Clause License, copied into the app bundle resources at build time

## License

This project remains under the BSD 3-Clause License. Source redistributions retain the copyright notice and license text in `LICENSE`; binary app bundles include a copy at `Contents/Resources/LICENSE`, and the app exposes the same notice from `Help > License`.
