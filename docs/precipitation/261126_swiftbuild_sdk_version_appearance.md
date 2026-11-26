# Swift 6.4 `swiftbuild` Stamps `sdk = minos (14.0)` and Triggers Legacy AppKit Colors

## Summary
Upgrading to macOS 27 Command Line Tools (Swift 6.4) switched `swift build` from the `native` engine to `swiftbuild`, which silently caused Mach-O binaries to record `LC_BUILD_VERSION sdk = 14.0` instead of `27.0`. On macOS 26/27, AppKit puts binaries linked against `< 26.0` into Sonoma compatibility mode, severely distorting `NSColor.windowBackgroundColor` and `NSColor.underPageBackgroundColor` even though no UI code changed.

## Content

### Symptom
Without any changes to `DesignSystem.swift` (`Fill.canvas`, `Fill.widget`, `WidgetSurface`), newly built local apps showed a dramatically altered appearance on macOS 27:

| Surface | `sdk 14.0` (broken `swiftbuild`) | `sdk 26.4` (v0.2.7) / `sdk 27.0` (fixed) |
| :--- | :--- | :--- |
| Dark canvas (`NSColor.windowBackgroundColor`) | `#323232` (50) | `#1E1E1E` (30) |
| Dark card (`Fill.widget`) | `#2A2A2A` (42) | `#2A2A2A` (42) |
| Light sidebar (`NSColor.underPageBackgroundColor`) | `#9F9F9F` (159) | `#F6F6F6` (246) |

Because the dark canvas jumped above the card fill (`#323232` > `#2A2A2A`), cards looked sunken into a light-grey background and the existing `WidgetSurface` drop shadow (`opacity: 0.25, radius: 14, y: 6`) became prominently visible around every card.

### Root Cause
1. Swift 6.4 changed `swift build`'s default build system from `native` (now deprecated) to `swiftbuild`.
2. When linking, `swiftbuild` invokes `swiftc -sdk <path>` without exporting `SDKROOT`.
3. `swiftc` forwards `--sysroot=<path>` (not `-isysroot <path>`) to Apple `clang` 21 as the linker driver.
4. Apple `clang` does not parse `SDKSettings.json` from `--sysroot`, so it falls back to `-platform_version macos <minos> <minos>` (`14.0.0 14.0.0`), stamping `sdk 14.0` into `LC_BUILD_VERSION`.
5. Additionally, macOS 27 Command Line Tools omit `SwiftUIMacros` (needed by `SwiftUI.@State`), and `swiftbuild` does not auto-create the directory passed to `-emit-localized-strings-path`.

### Diagnosis
Inspect the linked SDK directly on any built binary:
```sh
otool -l build/YaaKanban.app/Contents/MacOS/YaaKanban | grep -A 4 LC_BUILD_VERSION
```
Healthy builds on macOS 26/27 show `sdk 26.x` or `sdk 27.0`; broken `swiftbuild` builds show `sdk 14.0` (matching `Package.swift`'s `.macOS(.v14)`).

### Fix & Guardrails
1. **Prefer Xcode when installed** (`Makefile` and `scripts/bundle.sh`): when `DEVELOPER_DIR` is unset and `/Applications/Xcode.app/Contents/Developer` exists, export `DEVELOPER_DIR` so `SwiftUIMacros` and Xcode's `Testing.framework` are available. Scope CLT `TEST_FLAGS` to `CommandLineTools` only so Xcode's `swift test` doesn't mix in CLT's `Testing.framework`.
2. **Pass `-isysroot` to clang's linker driver**:
   ```sh
   SDK_PATH="$(xcrun --show-sdk-path)"
   swift build -Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc "$SDK_PATH"
   ```
   This works with the default `swiftbuild` engine without relying on deprecated `--build-system native` and restores `LC_BUILD_VERSION sdk 27.0` on both `YaaKanban` and `yaak`.
3. **Fail fast on regressions** (`scripts/bundle.sh` and `scripts/release.sh`): parse `LC_BUILD_VERSION` via `otool -l` for both `YaaKanban` and `yaak` and abort if any slice has `sdk < 26` or cannot be read.
4. **`make l10n` under `swiftbuild`**: pre-create `.build/l10n/strings` (`mkdir -p`) and pass its absolute path to `-emit-localized-strings-path`.
