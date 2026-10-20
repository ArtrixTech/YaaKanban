# macOS Swift pitfalls without Xcode

## Summary
Traps hit while building a SwiftPM menu-bar app using only the Command Line Tools: test framework paths, `$HOME` handling in tests, process-stable hashing, and verifying UI without screen-recording permission.

## Content

### Swift Testing / XCTest under Command Line Tools
`import Testing` fails with only CLT installed. Pass the framework path and rpaths explicitly (see `Makefile` `TEST_FLAGS`):
`-Xswiftc -F/Library/Developer/CommandLineTools/Library/Developer/Frameworks`, plus `-Xlinker -rpath` for that directory and `.../CommandLineTools/Library/Developer/usr/lib`.

### `FileManager.homeDirectoryForCurrentUser` ignores `$HOME`
It resolves the home directory from the user database, so a test or `--dry-run` under a fake `HOME` still reads the real `~/.claude`. Route every home lookup through one helper that reads `ProcessInfo.environment["HOME"]` (`Paths.home`), and test installers against a temp HOME.

### `hashValue` is per-process
Swift seeds `Hasher` per process. When two processes must agree on an id (pre/post tool hooks run in separate `yaak` processes), use a deterministic hash such as FNV-1a.

### Plugin child processes
In Node/Bun plugins, firing one `spawn` per event lets later events overtake earlier ones. Chain sends on a promise and stamp a `ts`. Do not `unref()` the child if the host may exit before the chain drains.

### Verifying UI without screen recording
`screencapture` fails without the permission. Render each SwiftUI view into an offscreen `NSWindow` and call `cacheDisplay(in:to:)` (`yaak snapshot <dir>`). Caveats: the window background is not drawn (paint `windowBackgroundColor` in the view), and vibrancy (`NSVisualEffectView`: sidebars, search fields) renders blank or white. Give the layout ~2 s to settle first.

### Naming
A type named `Settings` shadows SwiftUI's `Settings` scene inside the app module. Use another name (`Preferences`).
