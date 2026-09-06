# Swift Scripting Mechanics

<scripting_reference_scope>
Read this when writing or debugging a single-file Swift script: choosing a shebang, handling arguments, keeping the script runnable on Linux, or deciding when the script has outgrown the `swift` interpreter. The decision to use Swift for a script at all, the shebang to use by default, and the script-mode entry-point rules are in the `<scripting>` section of `SKILL.md`; this file holds the mechanics behind them.
</scripting_reference_scope>

## Shebangs

<scripting_shebangs>
The language-mode flag is policy and the launcher is mechanics; every variant below keeps `-swift-version 6`, because a shebang that drops it runs the script in the Swift 5 language mode (see `<scripting_essentials>` in `SKILL.md`).

**Default, cross-platform**: `#!/usr/bin/env -S swift -swift-version 6`. `env` resolves `swift` from `PATH` on macOS and Linux, and `-S` splits the rest of the line into separate arguments. `env -S` is supported on modern macOS, where BSD `env` documents `-S`,[^scripting-env-macos] and on Linux with GNU coreutils ≥ 8.30.[^scripting-coreutils-8-30] Avoid `xcrun` in portable shebangs; it is an Apple developer-tool resolver for SDK/toolchain-aware command execution, not a general cross-platform launcher.[^scripting-xcrun]

**When `env` lacks `-S`** (minimal or older systems): `#!/usr/bin/env swift` alone works but loses the flag, so invoke the script through a wrapper shell script whose body is `exec swift -swift-version 6 "$(dirname "$0")/script.swift" "$@"`, or pass the flag explicitly at every invocation.

**Xcode Build Phase scripts** (macOS-only by definition): a documented Swift Forums workaround uses `#!/usr/bin/xcrun --sdk macosx swift` so the script resolves against the macOS SDK — write it as `#!/usr/bin/xcrun --sdk macosx swift -swift-version 6` to keep the language mode (observed working on macOS 26 with Swift 6.3.2); a build phase can otherwise pick up the wrong SDK (e.g., iOS) from the build environment's `SDKROOT`.[^scripting-xcode-build] That multi-argument shebang works because macOS splits shebang arguments; Linux passes everything after the interpreter as a single argument, which is why the portable form above goes through `env -S`.
</scripting_shebangs>

## Arguments and Invocation

<scripting_invocation>
**Access arguments via `CommandLine.arguments`**; element 0 is the script path, and the script's own arguments follow it.[^scripting-commandline] `swift-argument-parser` is an SPM dependency, so it is available to SPM executables (or through `swift-sh`, below), not to a plain single-file script.

**Name scripts with a `.swift` extension or invoke them by path.** A bare extensionless name is treated as a subcommand lookup (`swift foo` searches for `swift-foo`); `swift ./foo` and shebang execution run the file.
</scripting_invocation>

## Platform Compatibility

<scripting_platform_compat>
| Framework | macOS | Linux |
|-----------|-------|-------|
| Foundation | Yes | Yes, via `swift-corelibs-foundation` — parity is best-effort, and `URLSession`/XML APIs need separate `import FoundationNetworking` / `import FoundationXML`[^scripting-foundation-linux] |
| AppKit | Yes | No |
| SwiftUI | Yes | No (no first-party Linux support) |

Guard platform-specific imports with conditional compilation:
```swift
#if canImport(AppKit)
import AppKit
#endif
```

Do not assume a Linux host has Swift installed; install the toolchain or use an official container image when Swift is required.[^scripting-swift-install-linux] On macOS, `/usr/bin/swift` is a stub that requires Xcode or the Command Line Tools behind it.
</scripting_platform_compat>

## Compilation Behavior and Growth

<scripting_compilation>
`swift script.swift` compiles the file on every invocation (the driver runs `-frontend -interpret` each time, observed with `swift -v` on Swift 6.3.2) and leaves no reusable artifact — convenient for direct execution, not a distribution format. When invocation latency matters, benchmark direct execution against a compiled SPM executable and simpler scripting languages on the target machine.

**When a script grows beyond what the standard library and platform frameworks can handle alone, convert it into a Swift Package Manager executable** rather than reaching for scripting tooling. SPM gives you dependency resolution, builds, tests, and distribution; the cost over a single-file script is small for anything non-trivial.

For the narrow case where a single-file script genuinely needs an external SPM dependency, the community tool `swift-sh`[^scripting-swift-sh] wraps SPM behind a shebang and caches the build. It introduces a dependency on every reader of the script having `swift-sh` installed, so reserve it for personal scripts on machines you control — not for anything you'd hand to a teammate or check into a shared repository.
</scripting_compilation>

## Sources

<sources>
[^scripting-xcrun]: Apple Inc. *xcrun(1) Manual Page*. Public mirror maintained by Keith Smiley. Retrieved May 8, 2026 from https://keith.github.io/xcode-man-pages/xcrun.1.html

[^scripting-xcode-build]: Swift Forums. 2020. *Swift build fails inside Xcode build script*. Retrieved May 8, 2026 from https://forums.swift.org/t/swift-build-fails-inside-xcode-build-script/35127

[^scripting-coreutils-8-30]: Pádraig Brady. 2018. *coreutils-8.30 released [stable]*. GNU info-gnu mailing list archive. Retrieved May 8, 2026 from https://lists.gnu.org/archive/html/info-gnu/2018-07/msg00001.html

[^scripting-env-macos]: Apple Inc. *env(1) macOS Manual Page*. Verified locally with `man env` on macOS 26.3.1; public mirror retrieved June 14, 2026 from https://ss64.com/mac/env.html

[^scripting-commandline]: Apple Inc. *CommandLine.arguments*. Swift Standard Library Documentation. Retrieved May 8, 2026 from https://developer.apple.com/documentation/swift/commandline/arguments

[^scripting-foundation-linux]: Swift Project. *swiftlang/swift-corelibs-foundation*. GitHub. Retrieved May 8, 2026 from https://github.com/swiftlang/swift-corelibs-foundation

[^scripting-swift-install-linux]: Swift Project. 2026. *Install Swift - Linux*. Swift.org. Retrieved June 21, 2026 from https://www.swift.org/install/linux/

[^scripting-swift-sh]: Max Howell. *mxcl/swift-sh: Easily script with third-party Swift dependencies*. GitHub. Retrieved May 8, 2026 from https://github.com/mxcl/swift-sh
</sources>
