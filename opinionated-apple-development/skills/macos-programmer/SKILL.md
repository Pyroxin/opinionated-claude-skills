---
name: macos-programmer
description: macOS-specific development patterns, platform APIs, and decision frameworks. Use when developing Mac apps, macOS applications, Cocoa/AppKit code, or making SwiftUI vs AppKit decisions. Covers NSWindow management, NSDocument architecture, sandboxing, code signing, notarization, and macOS UI patterns. Applies to Mac Catalyst considerations.
---

# macOS Programming

<skill_scope skill="macos-programmer">
**Related skills:**
- `swift-programmer` — Swift language fundamentals and Swift 6 concurrency
- `software-engineer` — General software engineering principles and system architecture
- `test-driven-development` — Testing philosophy and practices

This skill covers macOS-specific development patterns, platform APIs, and decision frameworks. It applies when developing Mac apps, working with Cocoa/AppKit code, or making SwiftUI vs AppKit decisions.
</skill_scope>

## Core Philosophy

<core_philosophy>
**Hybrid by default.** Production Mac apps commonly combine SwiftUI and AppKit: SwiftUI for most view content, AppKit where the platform's window, text, and event systems are exposed only there. Where the line falls varies by app; the case studies in `<swiftui_vs_appkit_decision>` show teams landing at different points, and each macOS release moves some formerly AppKit-only capability into SwiftUI (see `<recent_changes>`). Treat AppKit fallback as expected work rather than a failure of SwiftUI, and re-check the boundary when the deployment target moves.

**Platform Identity:** macOS is not iOS with a bigger screen. Multiple windows, menu bars, keyboard navigation, document-based architecture, and precise window management are first-class citizens. Respect macOS conventions; don't port iOS patterns blindly.
</core_philosophy>

## SwiftUI vs AppKit: The Critical Decision Framework

<swiftui_vs_appkit_decision>
**The Ground Truth from Production Apps:**

SwiftUI maturity differs between iOS and macOS. Two 2023 accounts from Mac apps in development show the shape of the gap. Ghostty (then in private beta) rewrote its SwiftUI app and window lifecycle management in AppKit (+802/-239 lines) when non-native fullscreen, which requires subclassing `NSWindow`, proved impossible in pure SwiftUI; its views stayed SwiftUI.[^ghostty-devlog] Multi.app moved to SwiftUI but still needed "some access to NSEvents, text input, and tweaking the first responder that just aren't possible with pure SwiftUI," and wrote that SwiftUI bugs on older macOS left them "approaching the cusp of dropping support entirely" for those versions.[^multi-swiftui] Both are dated; re-read the boundary against the current release before applying them.

**Use SwiftUI When:**
- New apps targeting macOS 14+, simple-to-medium complexity
- Standard UI elements suffice (lists, forms, navigation)
- Cross-platform iOS/macOS with acceptable compromises
- Rapid prototyping where bugs are acceptable
- Team willing to bridge to AppKit with `NSViewRepresentable` where a control or behavior isn't available in SwiftUI
- Can require a recent macOS; each release fixes SwiftUI-on-Mac issues, so older deployment targets carry more workarounds

**Use AppKit When:**
- Complex text editing (code editors, word processors, NSTextView-dependent workflows)
- Large datasets where profiling on a Release build shows SwiftUI `List` falling behind `NSTableView`; measure on the current OS, since a macOS 26 change to `NavigationLink` "improves performance of many `NavigationLink`s in lazy containers like `List`"[^macos26-notes]
- Custom window management (non-standard fullscreen, window subclassing, utility panels)
- UI that must idle at near-zero CPU (verify with Instruments rather than assuming either framework)
- Behavior that has been stable in AppKit across the OS versions you support, where the SwiftUI equivalent has changed release to release (check release notes for the specific control)
- Professional tools (IDEs, DAWs, design apps, terminals) whose text, window, or event needs exceed SwiftUI's surface

**The Hybrid Shape (Common in Production):**

Ghostty's arrangement after its rewrite: AppKit owns the app and window lifecycle and SwiftUI supplies the views.[^ghostty-devlog] The bridging mechanisms are `NSHostingController` (SwiftUI inside AppKit) and `NSViewRepresentable` (AppKit inside SwiftUI).

<swiftui_limitations>
**SwiftUI Limitations on macOS (as of macOS 26; re-check each release):**
- Window subclassing is unavailable in pure SwiftUI; non-native fullscreen and similar behaviors need AppKit[^ghostty-devlog]
- Direct access to `NSEvent`, first-responder manipulation, and some text-input behavior is AppKit-only[^multi-swiftui]
- The menu bar cannot be customized to the degree AppKit allows
- `List` performance with large data sets can lag `NSTableView`; the gap is workload-dependent and narrowed in macOS 26, so measure rather than assume
- Memory growth relative to iOS for similar apps has been reported by developers; treat it as something to profile, not a settled property

Capabilities that have moved into SwiftUI recently, such as styled text editing with `AttributedString` and Find Bar control in `TextEditor` on macOS 26, are listed in `<recent_changes>`.
</swiftui_limitations>

**Decision Pattern:**
```
Production Mac App
├── AppKit: NSApplication, NSWindow, NSWindowController, NSDocument
├── SwiftUI: View content where appropriate
└── Bridge: NSHostingController, NSViewRepresentable
```
</swiftui_vs_appkit_decision>

## Platform Differences from iOS (Critical for iOS Developers)

<platform_differences>

**Coordinate Systems:**
- iOS origin: top-left, Y increases downward
- macOS (unflipped `NSView`) origin: bottom-left, Y increases upward
- Override `isFlipped` to return `true` for iOS-style coordinates
- Drawing into a flipped context without compensating can draw images upside down; check the drawing API's handling of flipped contexts

**Layer Backing:**
- iOS views are layer-backed by default
- macOS views are not layer-backed unless the view or an ancestor sets `wantsLayer = true`
- Layer-backed views enable GPU compositing but cost memory; a layer-backed view's subviews become layer-backed too
- Enable it for animation and compositing effects; leave static content unbacked unless profiling shows a benefit

**Windows vs Views:**
- macOS users expect multiple windows, resizing, minimize/maximize
- NSWindow is critical—not a passive container like UIWindow
- Window management patterns (tabs, fullscreen, spaces) are first-class
- Custom window behaviors require AppKit (SwiftUI limitations)

**Text System:**
- NSTextView/TextKit vastly more powerful than UITextView
- Rulers, find/replace, grammar checking built-in
- TextKit 2 shipped in macOS 12 and became the default for all text controls, `NSTextView` included, in macOS 13;[^wwdc22-10090] touching `textView.layoutManager` switches that view to TextKit 1 compatibility mode ("if you explicitly call the `layoutManager` property on a text view or text container, the framework reverts to a compatibility mode")[^textkit-compat]
- When a view needs TextKit 1 (a reproduced TextKit 2 regression, or code that depends on `NSLayoutManager` during a migration), select it when creating the view rather than by triggering the fallback later, which discards the TextKit 2 layout; macOS 26 continues to extend TextKit 2 (e.g., `includesTextListMarkers`)[^macos26-notes]

**Background Colors:**
- Many NSView subclasses use `drawsBackground` property
- Not universal `backgroundColor` like iOS
- Check class documentation for correct property

**Mouse vs Touch:**
- AppKit hover effects need tracking areas (`updateTrackingAreas()`); SwiftUI views use `.onHover`
- Right-click context menus are standard expectation
- Mouse tracking differs from touch gesture handling
- `NSEvent` provides precise cursor position and modifier keys
</platform_differences>

## Window Management Mastery

<window_management>

**NSWindow Lifecycle (10.13 SDK Change):**

`isReleasedWhenClosed` defaults to `true` for `NSWindow` (`false` for `NSPanel`) and "is ignored for windows owned by window controllers";[^released-when-closed] for a window your own code owns and references, set it to `false`, or closing the window over-releases it under ARC.

AppKit's release notes state the current rule: "If your application is linked on macOS 10.13 SDK or later, NSWindows that are ordered-in will be strongly referenced by AppKit, until they are explicitly ordered-out or closed."[^appkit-rn-window] The condition is the SDK the app is linked against, not its deployment target; an app built against an older SDK keeps the old behavior even when running on newer macOS.

**Window Style and Collection Behavior:**

Style masks combine but have limitations:
- A borderless window "can't become key or main, unless the value of `canBecomeKey` or `canBecomeMain` is `true`" (subclass and override)[^stylemask-borderless]
- "Changing the style mask may cause the view hierarchy to be rebuilt,"[^stylemask] so avoid changing it mid-animation or mid-fullscreen-transition
- `fullSizeContentView` "opts in to layer-backing"[^stylemask-fullsize]

Collection behavior controls Spaces/Exposé/fullscreen:
- `.canJoinAllSpaces`: Visible on all spaces (like menu bar)
- `.moveToActiveSpace`: "When the window becomes active, move it to the active space instead of switching spaces"[^collection-behavior]
- `.fullScreenPrimary`: Can be fullscreen window
- `.fullScreenAuxiliary`: Shown with fullscreen window
- `.stationary`: Unaffected by Exposé, visible on desktop

**Pattern for an overlay that appears on every space:**
```swift
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
```
Collection behavior governs Spaces and Exposé membership, not stacking order or fullscreen coexistence; set the window level separately and test with a fullscreen app and Stage Manager before relying on it.

**Multi-Window Document Architecture:**
```
NSDocumentController (singleton)
    ↓ manages
NSDocument instances (one per document)
    ↓ manages
NSWindowController instances (one per window)
```

**Modern Document Best Practice:**
```swift
override class var autosavesInPlace: Bool { true }
```

Enables autosave in place and the system's version browsing and storage. Asynchronous saving is a separate opt-in (`canAsynchronouslyWrite(to:ofType:for:)`), and the document must still unblock user interaction itself.
</window_management>

## Responder Chain and Menu Validation

<responder_chain>

**The Complete Action Message Responder Chain:**

1. Start with the first responder in the key window
2. Try every `nextResponder` in that chain, then the key window itself
3. Try the key window's delegate, then its `NSDocument` (if different from the delegate)
4. Repeat for the main window, if it is a different window
5. `NSApplication` tries to respond
6. `NSApplication.delegate`
7. In a document-based app, the `NSDocumentController` (which does not inherit from `NSResponder`)[^event-architecture]

**Critical Insight:** App delegate is NOT part of nextResponder chain—you can never reach it through iteration. It's used as a fallback when current key window's responder chain returns nil.

**NSViewController Integration (macOS 10.10+):**

Before 10.10, an `NSViewController` was not in the responder chain by default; code patched `nextResponder` by hand. From 10.10, AppKit inserts the view controller into the chain immediately after its view: "The view's nextResponder is then set to be the viewController, and viewController's nextResponder is set to be the previously saved nextResponder."[^appkit-rn-1010]

**Menu Validation Performance:**

NSMenu updates EVERY menu item on EVERY user event (mouse move, keypress). This is a performance killer for large menus.

How it works:
1. Determine item's target (explicit or via responder chain)
2. Check if target implements action method (if not, disable)
3. If target implements `validateMenuItem:` or `validateUserInterfaceItem:`, call it and use return value

**Optimization:**
- Disable auto-validation for static menus: `menu.autoenablesItems = false`
- Manually control `menuItem.isEnabled`
- A `nil` target routes the action and the validation query through the responder chain; set an explicit target only when you want to bypass that lookup
</responder_chain>

## SwiftUI Integration with AppKit

<swiftui_appkit_integration>

**NSHostingController (Essential Bridge Pattern):**
```swift
// Embedding SwiftUI in AppKit
let swiftUIView = MySwiftUIView()
let hostingController = NSHostingController(rootView: swiftUIView)

// macOS 13+ sizing control
hostingController.sizingOptions = [.intrinsicContentSize]
```

**NSViewRepresentable:**

`updateNSView` runs whenever SwiftUI updates this represented view, so guard assignments whose setter has side effects: assigning `NSTextView.string` resets the selection (observed on macOS 26; it does not post `textDidChange`). Propagate edits back to the binding through a `Coordinator`, or the bridge is one-way.

```swift
struct TextViewRepresentable: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: NSTextView, context: Context) {
        context.coordinator.text = $text     // keep the coordinator on the current binding
        if nsView.string != text {           // guard: assigning resets the selection
            nsView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string  // edits flow back to SwiftUI
        }
    }
}
```

**State Management with `@MainActor @Observable` (macOS 14+):**

Gotcha, toolchain-dependent: built with Xcode 26 or earlier, "A `State` property always instantiates its default value when SwiftUI instantiates the view," so Apple's guidance is to "avoid side effects and performance-intensive work when initializing the default value";[^swiftui-state] an `@Observable` model declared as `@State` in a frequently re-instantiated view is allocated on each instantiation. Built with Xcode 27 (beta 6 as of September 2026), `@State` is a macro and "objects held in state are only ever initialized one time, when the view is first created," which removes the cost but also rejects some initializer patterns that used to compile; read TN3211 before migrating.[^tn3211] For SwiftUI view state, keep the observable type on the main actor; see `swift-programmer` for the general `@MainActor @Observable` rule.

Solution for app-wide state: declare the main-actor observable model in the `App` struct, which SwiftUI instantiates once. Apple's alternative for a view-local model is to create it in a `.task` modifier, "which is called only once when the view first appears";[^swiftui-state] that is once per appearance of a given identity: it runs again if the view disappears and reappears, or if its identity changes, so guard the creation if it must happen once per state lifetime.
```swift
@MainActor
@Observable
class AppModel {
    // App state and actions.
}

@main
struct MyApp: App {
    @State private var appModel = AppModel() // Declare here
    var body: some Scene {
        WindowGroup {
            ContentView().environment(appModel)
        }
    }
}
```

**Multi-Window Management:**
```swift
// WindowGroup - Multiple instances
WindowGroup { ContentView() }

// Window - Single unique instance
Window("Stats", id: "stats") { StatsView() }

// UtilityWindow (macOS 15+) - Floating palette
UtilityWindow("Palette", id: "palette") { PaletteView() }
    .keyboardShortcut("u")
```

**Menu Bar & Commands:**
```swift
.commands {
    CommandMenu("Custom") {
        Button("Action") {}
            .keyboardShortcut("x", modifiers: [.command, .shift])
    }
}

// Focus values for multi-window menus
@FocusedValue(\.messageState) var messageState
```
</swiftui_appkit_integration>

## Sandboxing and File System Access

<sandboxing>

**Sandboxing Strategy:**
- Mac App Store: REQUIRED
- Direct Distribution: OPTIONAL but strongly recommended

**Access Methods:**
1. **User Selection** (NSOpenPanel/NSSavePanel): Immediate access
2. **Security-Scoped Bookmarks:** Persistent access across launches
3. **Container Access:** Automatic for `~/Library/Containers/{bundle-id}`

**Security-Scoped Bookmarks (Critical Pattern):**
```swift
// Save bookmark
let bookmarkData = try url.bookmarkData(options: .withSecurityScope)

// Restore and use
var isStale = false
let url = try URL(resolvingBookmarkData: bookmarkData,
                  options: .withSecurityScope,
                  bookmarkDataIsStale: &isStale)
guard url.startAccessingSecurityScopedResource() else {
    throw CocoaError(.fileReadNoPermission)
}
defer { url.stopAccessingSecurityScopedResource() }
if isStale {
    // Re-create and re-save the bookmark while access is active; creating one needs access to the file.
    let fresh = try url.bookmarkData(options: .withSecurityScope)
    save(fresh)
}
// Access file
```

**Rules:**
- Call `startAccessingSecurityScopedResource()` on the resolved URL, not the original
- Don't call it for `NSOpenPanel`/`NSSavePanel` URLs; the system starts access on those for you
- Balance every successful start with a stop; calls may nest, and access ends at the last balanced stop[^security-scoped]
- Leaking access consumes kernel resources until the app relaunches

**Entitlements to Know:**
- `com.apple.security.app-sandbox`: Enable App Sandbox
- `com.apple.security.files.user-selected.read-write`: User-selected files
- `com.apple.security.files.bookmarks.app-scope`: App-scoped bookmarks
- `com.apple.security.network.client`: Outgoing network connections
- `com.apple.security.network.server`: Incoming network connections
</sandboxing>

## Code Signing and Notarization

<code_signing>

**Process (checked against Apple's notarization documentation, September 2026):**

1. **Code Sign** each nested component first (frameworks, helpers, plug-ins), then the app, without `--deep`:
```bash
codesign --force --options runtime --timestamp \
  --entitlements App.entitlements \
  --sign "Developer ID Application: Your Name (TEAMID)" \
  App.app

codesign --verify --deep --strict --verbose=2 App.app   # --deep is for verification
```

2. **Create Archive:**
```bash
ditto -c -k --keepParent App.app App.zip
```

3. **Submit for Notarization** using a keychain profile created once with `notarytool store-credentials`:
```bash
xcrun notarytool submit App.zip --keychain-profile "notarytool-password" --wait
```

4. **Staple the ticket to the app, then re-package.** "While you can notarize a ZIP archive, you can't staple to it directly. Instead, run `stapler` against each item that you added to the archive. Then create a new ZIP file containing the stapled items for distribution."[^notarization-workflow]
```bash
xcrun stapler staple App.app
xcrun stapler validate App.app
ditto -c -k --keepParent App.app App.zip   # the distributed archive must contain the stapled app
```

**Rules:**
- Sign bottom-up in the bundle hierarchy; do not sign with `--deep` (`man codesign` marks it "DEPRECATED for signing as of macOS 13.0"), because it applies the outer entitlements and flags to nested code. `--deep` remains the right flag for `--verify`.
- `notarytool` replaced `altool`, which Apple stopped accepting on November 1, 2023; the `@keychain:` password syntax was `altool`'s, and `notarytool` uses `--keychain-profile` or a literal `--password`.
- macOS Sequoia removed the Control-click override for Gatekeeper; users must approve unsigned or un-notarized software in System Settings, so notarize anything distributed outside the App Store.[^sequoia-gatekeeper]

**Common Failures:**
- "Hardened runtime not enabled" → Add `--options runtime`
- "Invalid signature" → Re-sign with proper entitlements
</code_signing>

## Architecture Patterns

<architecture_patterns>
**For general architecture philosophy, see the `software-engineer` skill.** This section covers macOS-specific architectural considerations.

**Primary Patterns (Choose One):**

### MVC (Model-View-Controller)

**What it is:**
- Apple's classic pattern for AppKit development
- Model: Data and business logic
- View: UI components
- Controller: Coordinates between Model and View

**When to use:**
- AppKit-heavy applications
- Document-based apps (works naturally with NSDocument)
- Simple-to-medium complexity apps
- When following Apple's conventions makes sense

**Reality check:**
- Controllers tend to become large ("Massive View Controller")
- This is fine for many apps—just watch for controller bloat
- Treat a controller that has grown to several hundred lines as a signal to extract logic; the number is a rule of thumb, not a threshold

### MV (Model-View)

**What it is:**
- The pattern the cited author distills from Apple's SwiftUI sample code: no separate view-model layer[^mv-pattern]
- Model: Data and business logic
- View: SwiftUI views with @State for local state
- No separate ViewModel layer - views call model methods directly

**When to use:**
- Simple-to-medium SwiftUI applications
- Prototypes and MVPs
- Apps without complex testability requirements
- When MVVM feels like overkill

**Reality check:**
- SwiftUI's reactive binding means views often serve as their own view models[^mv-pattern]
- Minimal boilerplate
- Works until a model accumulates enough presentation logic that views become hard to test; then extract logic or move to MVVM

**Pattern:**
```swift
@MainActor
@Observable
class User {
    var name: String = ""
    var email: String = ""

    func save() {
        // Business logic here
    }
}

struct ProfileView: View {
    @State private var user = User()

    var body: some View {
        Form {
            TextField("Name", text: $user.name)
            Button("Save") { user.save() }
        }
    }
}
```

### MVVM (Model-View-ViewModel)

**What it is:**
- Model: Data and business logic
- View: SwiftUI views or AppKit views
- ViewModel: Presentation logic, formats data for View

**When to use:**
- SwiftUI applications needing testable presentation logic
- Multiple views display same data differently
- Need to separate view logic from view definition
- Models have grown too large in MV pattern

**Reality check:**
- Works beautifully with SwiftUI's reactive nature
- Less natural in pure AppKit (but still usable)
- ViewModels can also bloat—same solution as MVC (extract logic)
- Consider if you actually need it vs simpler MV pattern

### VIPER (View-Interactor-Presenter-Entity-Router)

**What it is:**
- Ultra-granular pattern splitting each screen into 5+ components
- View: Displays data
- Interactor: Business logic
- Presenter: Formats data for view
- Entity: Data models
- Router: Navigation

**When to use:**
- Rarely. Honest assessment: generally over-engineered
- Large enterprise apps with extreme testability requirements
- Teams that need architectural enforcement of separation
- Fits AppKit; in SwiftUI its Router layer duplicates state-driven navigation, and its Presenter's formatting can live in a view model or the model without a separate layer

**Reality check:**
- Massive boilerplate (5+ files per screen)
- Most sources say "only if you really need it"
- **In SwiftUI:** observation propagates model changes to views, so the Presenter's update plumbing disappears (its formatting logic moves into a view model or the model); the Router's routing becomes navigation state (`NavigationStack` with a `NavigationPath` held in an observable model), with navigation policy still yours to write
- **Don't force this pattern into SwiftUI** - you'll fight the framework constantly
- Consider carefully whether the complexity is justified even in AppKit

**Complementary Pattern (Add When Needed):**

### Coordinator Pattern

**What it is:**
- Handles navigation and screen flow
- Works **on top of** MVC or MVVM (not instead of)
- Removes navigation logic from view controllers/view models
- Common combinations: MVVM-C, MVC-C
- **Primarily an AppKit/UIKit pattern**

**When to add Coordinator:**
- Complex navigation in AppKit apps (many screens and flows)
- Deep linking (URLs open specific screens)
- Multiple entry points to same screen
- A/B testing different user flows
- Reusing view controllers in different contexts

**SwiftUI Reality:**
- **Don't force Coordinators into SwiftUI** - navigation is declarative and state-driven
- SwiftUI navigates through state: `NavigationStack` and `NavigationSplitView` driven by a `NavigationPath` or selection value, `.sheet()`, and on macOS separate `Window`/`WindowGroup` scenes (`.fullScreenCover()` is not available on macOS)
- Navigation policy can live in an observable model that owns the path; that is the SwiftUI counterpart of a coordinator

**Pattern (AppKit/UIKit):**
```
App uses MVC or MVVM for view/logic organization
     +
Coordinator manages navigation between screens
```

**Other Concerns:**

Patterns like Repository (data access), networking layers, and business logic extraction emerge on a case-by-case basis during actual project design. Don't prematurely abstract.
</architecture_patterns>

## Performance Optimization

<performance>

**Profiling with Instruments:**

Essential templates:
- **Time Profiler:** CPU usage, call stacks, bottlenecks; start here
- **Allocations:** Memory allocation patterns
- **Leaks:** Memory leak detection
- **Metal System Trace:** GPU performance

Best practices:
- Profile in Release mode (optimization critical)
- Profile on target hardware (older devices reveal issues)
- Use Signposts for precise measurement intervals

**Main Thread Optimization:**

Keep the main thread for UI updates and input handling. Blocking work moves off it; work that is already `async` and suspends (e.g., `URLSession` requests) can be initiated from the main actor without blocking it. Offload with `@concurrent` or a detached task (see `swift-programmer`):
- Data parsing and decoding of large responses
- Synchronous file I/O
- Complex calculations
- Image processing

**Layer-Backed View Optimization:**

A layer-backed view that draws with `draw(_:)` usually gets the redraw policy `NSViewLayerContentsRedrawDuringViewResize` (the SDK header: "Generally, the default value is NSViewLayerContentsRedrawOnSetNeedsDisplay if the view responds YES to -wantsUpdateLayer. Otherwise, the value is usually NSViewLayerContentsRedrawDuringViewResize"),[^nsview-header] which objc.io notes "might be detrimental to animation performance" because it triggers drawing on each frame of a resize.[^layer-redraw]

For views whose content doesn't depend on their size, change to:
```swift
view.layerContentsRedrawPolicy = .onSetNeedsDisplay
```
With this policy the view redraws only when you call `setNeedsDisplay`, so invalidation becomes your responsibility; content that depends on the view's size must invalidate on resize (or keep the default policy).

**When to Enable Layer-Backing:**
- Animating multiple views simultaneously
- Need smooth 60fps animations
- Want Core Animation features
- Creating effects requiring GPU acceleration

**Leave Layer-Backing Off When:**
- Static UI with no animation, where it buys nothing
- Memory is constrained; layers carry backing stores, though AppKit coalesces content where it can
- The view relies on precise, resolution-aware drawing that you have verified renders differently when backed
</performance>

## Testing Strategy

<testing>
**For general testing philosophy and TDD principles, see the `test-driven-development` skill.**

**Swift Testing vs XCTest:**

Swift Testing (Xcode 16+):
- Modern replacement using macros (`@Test`, `#expect`, `#require`)
- Better parallelization (in-process using Swift Concurrency)
- Works with structs/actors/classes, not just XCTestCase
- Use for: New unit tests in Swift 6/Xcode 16+ projects

XCTest:
- Apple's guidance: "continue using XCTest for any tests which use UI automation APIs like XCUIApplication or use performance testing APIs like XCTMetric as these are not supported in Swift Testing"[^wwdc24-10179]
- Necessary for Objective-C test code
- Use for: UI automation tests, performance tests, existing test suites

**Distribution:** put most coverage in unit tests of models and logic, integration tests where components meet (e.g., API clients), and UI tests only for the flows whose breakage would ship a broken app, because UI tests are the slowest and most brittle tier.

**Accessibility Testing:**

VoiceOver on macOS differs from iOS:
- Keyboard navigation primary (not touch)
- VoiceOver Utility for configuration
- Menu bar accessibility critical
- Multiple windows/spaces support

Testing workflow:
- Start VoiceOver: ⌘ + F5
- Navigate with Control + Option (VO keys)
- Verify all interactive elements are reachable and labeled (use the Accessibility Inspector in Xcode to audit)
</testing>

## Common Anti-Patterns

<anti_patterns>

### iOS Patterns Applied Incorrectly
- Assuming layer-backing is automatic
- Using UIKit coordinate conventions without override
- Treating NSWindow like UIWindow (passive container)
- Ignoring window management patterns
- Not implementing hover states (mouse tracking)
- Missing right-click context menus

### Web Developer Mistakes
- Expecting CSS-like layout flexibility (AppKit lays out with Auto Layout constraints; SwiftUI with its layout containers and modifiers)
- Fighting native controls instead of embracing system appearance
- Ignoring accessibility (VoiceOver is expected, not optional)
- Single-window mentality where users expect multiple windows (documents, inspectors, palettes); a single-window app is fine when its task is single-window
- Not using native file dialogs (NSOpenPanel/NSSavePanel)
- Ignoring keyboard shortcuts and menu bar conventions

### Linux/Cross-Platform Developer Mistakes
- Assuming POSIX conventions apply to GUI (Cocoa is not GTK/Qt)
- Fighting sandboxing instead of designing around it
- Ignoring Apple's signing/notarization requirements
- Persisting raw paths to files outside the container instead of security-scoped bookmarks (container-local paths need no bookmark)
- Not adapting to macOS HIG (menu bar, dock, system preferences)

### Windows Developer Mistakes
- Expecting registry-like global preferences (use UserDefaults, sandboxed)
- Assuming all file access is available (sandbox constraints)
- Window chrome expectations (unified title-and-toolbar is the macOS norm, though separate title bars remain available)
- Installation expectations (drag-to-Applications is the norm for apps; installer packages exist for software that needs privileged installation)

**Over-Engineering Simple Apps:**
- Using VIPER for simple CRUD apps
- Complex architectural patterns for prototypes
- Custom state management when an `@Observable` model in the environment suffices
- Premature abstraction before requirements are clear

**Ignoring macOS UI Conventions:**
- Not following macOS Human Interface Guidelines
- Poor keyboard shortcut support
- Ignoring standard menu bar conventions
- Misusing window management (minimize, zoom, full screen)
- Not respecting macOS-specific UI elements (toolbars, sidebars, split views)

### Premature SwiftUI Adoption
- Committing to 100% SwiftUI before checking that the app's window, text, and event needs are within SwiftUI's current surface (see `<swiftui_limitations>`)
- Ignoring AppKit when SwiftUI is insufficient
- Not budgeting for AppKit fallback code
- Assuming iOS SwiftUI code will work on macOS
</anti_patterns>

## Mac App Store vs Direct Distribution

<distribution>

**Mac App Store:**
- **Pros:** Apple handles distribution/updates, user trust, search visibility
- **Cons:** App Sandbox required; commission of 30%, reduced to 15% for developers in the App Store Small Business Program (developers with up to US$1 million in prior-year proceeds)[^small-business] and for auto-renewable subscriptions after a subscriber's first year;[^subscriptions] review delays; limited APIs

**Direct Distribution:**
- **Pros:** Greater API access, no commission, faster updates, custom pricing
- **Cons:** Must handle payments; Developer ID signing and notarization required for Gatekeeper to allow the app without the user granting an exception in System Settings; no built-in discoverability

**Tendency, not rule:** tools that need APIs the sandbox forbids, or their own licensing, go direct; apps that benefit from App Store discovery and trust go there. Many ship both.
</distribution>

## Decision Frameworks Summary

<decision_summary>

**SwiftUI vs AppKit:**
- Simple-medium apps targeting macOS 14+: SwiftUI
- Text editing beyond `TextEditor`'s surface, data sets where profiling shows `List` behind `NSTableView`, window behavior SwiftUI doesn't expose: AppKit for that part
- Behavior that must not change between OS releases: prefer the framework whose implementation of that behavior has been stable, which for windows, text, and events has usually been AppKit
- Professional tools: Hybrid (AppKit foundation, SwiftUI where appropriate)

**Architecture Pattern:**
- AppKit apps: MVC
- Simple SwiftUI apps: MV (Model-View)
- SwiftUI apps needing testability: MVVM
- Complex AppKit navigation (many screens, deep linking): Add a Coordinator; in SwiftUI, hold navigation state in an observable model instead
- Rarely: VIPER, and then in AppKit rather than SwiftUI (if you genuinely need that degree of separation)

**State Management:**
- View-local: @State
- Shared across views (macOS 14+): `@MainActor @Observable` models injected with `.environment(_:)` and read with `@Environment`; `@EnvironmentObject` pairs with the older `ObservableObject` protocol and is for code that still uses it
- Larger apps: several focused `@MainActor @Observable` types rather than one singleton

**Cross-Platform:**
- Substantial feature overlap with acceptable compromises: SwiftUI multiplatform
- Mac-specific interaction (multi-window, menus, keyboard) that a shared UI would flatten: separate platform UIs over shared business logic
- Complex apps: Hybrid (shared Swift Package for logic, platform UIs)
</decision_summary>

## Recent Changes

<recent_changes>
**Baseline: February 2025.** This section assumes trained knowledge of macOS development through that date — the reliable-knowledge cutoff of Claude Haiku 4.5, the oldest among the current Claude models[^claude-models] — and lists what has changed since that bears on this skill's guidance. Treat anything older (macOS 15 and Xcode 16 included) as known.

**Additions**, by release:
- **macOS 26 / Xcode 26** (September 2025): the Liquid Glass design, with `NSGlassEffectView` and `NSGlassEffectContainerView` in AppKit and matching SwiftUI APIs;[^liquid-glass-guide] styled text editing in SwiftUI with `AttributedString`,[^styled-text-guide] and Find Bar control in `TextEditor` (`findNavigator(isPresented:)`);[^macos26-notes] a SwiftUI `WebView` backed by an observable `WebPage`;[^webkit-guide] animated `Window` resizing from a SwiftUI transaction;[^macos26-notes] `NavigationLink` producing a single view in lazy containers, improving `List` performance;[^macos26-notes] an "Enhanced Security" helper-extension template for isolating untrusted-data handling.[^xcode26-notes] These move the SwiftUI/AppKit boundary in `<swiftui_vs_appkit_decision>`.
- **Xcode 27** (beta 6 as of September 2026): `@State` becomes a macro with lazy initial-value evaluation; see the gotcha in `<swiftui_appkit_integration>` and TN3211.[^tn3211]

**Behavior changes, deprecations, and things being moved away from:**
- **SceneKit is deprecated** "across all Apple platforms"; Apple recommends RealityKit for new projects.[^xcode26-notes]
- **`Text` concatenation with `+` is deprecated** in favor of `Text` interpolation, for localization correctness.[^macos26-notes]
- **Text writing direction** in `Text`, `TextEditor`, and `TextField` is now derived per paragraph from string content rather than layout direction on macOS 26.[^macos26-notes]
- **Instruments' SwiftUI template** replaced the View Body and View Properties instruments, which are deprecated but still available.[^xcode26-notes]
- **New app projects default to main-actor isolation** in Xcode 26; see `swift-programmer` for the concurrency consequences.
</recent_changes>

## Resources

<resources>

**Local Documentation:**
- Xcode diagnostic docs: `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/share/doc/swift/diagnostics/`
- Framework guides bundled with Xcode: `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/` (e.g., `AppKit-Implementing-Liquid-Glass-Design.md`, `SwiftUI-Styled-Text-Editing.md`, `SwiftUI-WebKit-Integration.md`)

**Apple Official:**
- AppKit Documentation: https://developer.apple.com/documentation/appkit
- macOS HIG: https://developer.apple.com/design/human-interface-guidelines/macos
- SwiftUI Documentation: https://developer.apple.com/documentation/swiftui

**Expert Blogs:**
- NSHipster: https://nshipster.com (Overlooked Cocoa/Swift bits)
- objc.io: https://www.objc.io (Advanced techniques, essential "AppKit for UIKit Developers" article)
- Mike Ash Friday Q&A: https://www.mikeash.com/pyblog/ (Deep low-level technical articles)
- Brent Simmons Inessential: https://inessential.com (Veteran Mac developer, NetNewsWire author)
- Use Your Loaf: https://useyourloaf.com (Practical guides, WWDC viewing guides)

**Books:**
- "macOS Apps Step by Step" (formerly "macOS by Tutorials"; v4.0, November 2025) by Sarah Reichelt (TrozWare) - covers macOS 26 and Xcode 26
- "Hacking with macOS" by Paul Hudson - 18 projects; paid, with a free sample
- "The Complete Friday Q&A" (Volumes I-III) by Mike Ash - Essential for Cocoa internals

**Open Source Examples:**
- Awesome Open Source Mac Apps: https://github.com/serhii-londar/open-source-mac-os-apps
- NetNewsWire: https://github.com/Ranchero-Software/NetNewsWire (Mature AppKit codebase)
- WWDC app (unofficial): https://github.com/insidegui/WWDC (Well-structured Mac app)

**Community:**
- Apple Developer Forums: https://developer.apple.com/forums/
- Stack Overflow (cocoa/appkit tags)
</resources>

## The Modern macOS Developer's Mindset

**Embrace Hybrid Solutions:** Well-regarded Mac apps blend SwiftUI and AppKit. Use each framework where it excels. Don't force SwiftUI where AppKit is superior.

**Leverage Platform Strengths:** macOS isn't iOS with a bigger screen. Multiple windows, menu bars, keyboard navigation, document architecture—these are first-class citizens. iOS developers transitioning to Mac: unlearn iOS assumptions.

**Test Relentlessly:** Swift Testing for unit tests, XCTest for UI automation. Profile with Instruments regularly. VoiceOver-test every release.

**Stay Pragmatic:** The perfect architecture that ships beats the theoretical ideal that doesn't. Balance theoretical purity with practical delivery. Ship working software, iterate based on real problems, refactor when justified by pain.

**Final Wisdom:** The best Mac apps feel like Mac apps. They embrace platform conventions, leverage macOS strengths, and don't feel like iPad apps in disguise. Build for Mac users, not iOS users with keyboards. Master the frameworks, respect the platform, ship great software.

## Sources

<sources>
[^ghostty-devlog]: Mitchell Hashimoto. 2023. Ghostty Devlog 002 (August 5, 2023). Retrieved September 5, 2026 from https://mitchellh.com/writing/ghostty-devlog-002

[^multi-swiftui]: Multi.app. 2023. Moving to SwiftUI from macOS Cocoa (April 5, 2023). Retrieved September 5, 2026 from https://multi.app/blog/moving-to-swiftui-from-macos-cocoa-or-ios-cocoa-touch

[^mv-pattern]: Mohammad Azam. 2022. SwiftUI Architecture — A Complete Guide to the MV Pattern Approach. https://betterprogramming.pub/swiftui-architecture-a-complete-guide-to-mv-pattern-approach-5f411eaaaf9e

[^layer-redraw]: objc.io. AppKit for UIKit Developers. Issue #14. https://www.objc.io/issues/14-mac/appkit-for-uikit-developers

[^swiftui-state]: Apple Inc. State. SwiftUI Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/swiftui/state

[^wwdc22-10090]: Apple Inc. 2022. What's new in TextKit and text views (WWDC22 session 10090), session transcript. Retrieved September 5, 2026 from https://developer.apple.com/videos/play/wwdc2022/10090/

[^released-when-closed]: Apple Inc. isReleasedWhenClosed. AppKit Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/appkit/nswindow/isreleasedwhenclosed

[^subscriptions]: Apple Inc. Offer auto-renewable subscriptions. App Store Connect Help. Retrieved September 5, 2026 from https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/

[^stylemask-borderless]: Apple Inc. NSWindow.StyleMask.borderless. AppKit Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/borderless

[^stylemask]: Apple Inc. styleMask. AppKit Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.property

[^stylemask-fullsize]: Apple Inc. NSWindow.StyleMask.fullSizeContentView. AppKit Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullsizecontentview

[^nsview-header]: Apple Inc. `NSView.h`, comment on `layerContentsRedrawPolicy`. macOS 26.5 SDK, `System/Library/Frameworks/AppKit.framework/Headers/NSView.h`.

[^appkit-rn-1010]: Apple Inc. AppKit Release Notes for OS X 10.10 (older notes), "NSViewController" section. Retrieved September 5, 2026 from https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKitOlderNotes/

[^textkit-compat]: Apple Inc. NSTextView, overview. AppKit Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/appkit/nstextview

[^appkit-rn-window]: Apple Inc. AppKit Release Notes for macOS 10.13, "NSWindow Lifecycle Changes." Retrieved September 5, 2026 from https://developer.apple.com/library/archive/releasenotes/AppKit/RN-AppKit/

[^collection-behavior]: Apple Inc. NSWindow.CollectionBehavior.moveToActiveSpace. AppKit Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/movetoactivespace

[^event-architecture]: Apple Inc. Event Architecture, "Action Messages" (responder chain of a document-based application). Cocoa Event Handling Guide (archived). Retrieved September 5, 2026 from https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/EventArchitecture/EventArchitecture.html

[^security-scoped]: Apple Inc. startAccessingSecurityScopedResource(). Foundation Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource()

[^notarization-workflow]: Apple Inc. Customizing the notarization workflow. Security Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/security/customizing-the-notarization-workflow

[^sequoia-gatekeeper]: Apple Inc. 2024. Updates to runtime protection in macOS Sequoia (August 6, 2024). Apple Developer News. Retrieved September 5, 2026 from https://developer.apple.com/news/?id=saqachfa

[^wwdc24-10179]: Apple Inc. 2024. Meet Swift Testing (WWDC24 session 10179), session transcript. Retrieved September 5, 2026 from https://developer.apple.com/videos/play/wwdc2024/10179/

[^small-business]: Apple Inc. App Store Small Business Program. Retrieved September 5, 2026 from https://developer.apple.com/app-store/small-business-program/

[^macos26-notes]: Apple Inc. 2025. macOS 26 Release Notes, SwiftUI and TextKit sections. Retrieved September 5, 2026 from https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes

[^xcode26-notes]: Apple Inc. 2025. Xcode 26 Release Notes (SceneKit deprecation 147454720; Instruments deprecations 148596828; Enhanced Security extension template 141308470). Retrieved September 5, 2026 from https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes

[^liquid-glass-guide]: Apple Inc. 2025. Implementing Liquid Glass Design in AppKit. Bundled with Xcode 26 at `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/AppKit-Implementing-Liquid-Glass-Design.md`

[^styled-text-guide]: Apple Inc. 2025. Styled Text Editing in SwiftUI. Bundled with Xcode 26 at `.../AdditionalDocumentation/SwiftUI-Styled-Text-Editing.md`

[^webkit-guide]: Apple Inc. 2025. SwiftUI WebKit Integration. Bundled with Xcode 26 at `.../AdditionalDocumentation/SwiftUI-WebKit-Integration.md`

[^claude-models]: Anthropic. 2026. Models overview, "Compare models" table, row "Reliable knowledge cutoff." Claude API Documentation. Retrieved September 5, 2026 from https://platform.claude.com/docs/en/models/overview

[^tn3211]: Apple Inc. 2026. TN3211: Resolving SwiftUI source incompatibilities for State and ContentBuilder, section "How @State evolved to support laziness." Apple Technotes. Retrieved September 5, 2026 from https://developer.apple.com/documentation/technotes/tn3211-resolving-swiftui-source-incompatibilities-for-state-and-contentbuilder
</sources>
