---
name: swift-programmer
description: Swift-specific idioms, tooling, and philosophy for both application development and command-line scripting. Use when working with Swift code, including Swift scripts. Emphasizes protocol-oriented programming, value semantics, strict concurrency (Swift 6+), and compile-time safety guarantees.
---

# Swift Programming

<skill_scope skill="swift-programmer">
**Related skills:**
- `software-engineer` — Core design principles and system architecture
- `macos-programmer` — macOS-specific patterns when building Mac apps
- `test-driven-development` — Testing philosophy and practices
- `functional-programmer` — Functional paradigm principles (Swift supports FP)
- `fish-shell-scripting` — Shell-scripting alternative when Swift's framework access isn't needed

This skill covers Swift-specific idioms, tooling, and philosophy for both application development and command-line scripting. It emphasizes protocol-oriented programming, value semantics, strict concurrency (Swift 6+), and compile-time safety guarantees.
</skill_scope>

## Core Philosophy

<core_philosophy>
This section states the defaults this skill applies when writing Swift; the sections that follow give the judgment frameworks for the cases where a default doesn't fit.

**Let the compiler carry the safety argument.** Swift 6 adds compile-time data-race safety to memory safety, so design so that the checker can prove the code correct rather than suppressing its diagnostics; the working model for that — isolation domains rather than threads — is developed in `<concurrency_fundamentals>`.

**Prefer** protocol composition over inheritance, value semantics over reference semantics, and static dispatch over dynamic dispatch.

**Version targeting**: Use the latest Swift version available. For internal apps, target only the current version. For open-source libraries, support at most the current version and one or two prior ones.
</core_philosophy>

## Swift 6 Concurrency

<concurrency_fundamentals>
**Think in isolation domains, not threads.** Each domain — a task, an actor, or a global actor such as the main actor — executes serially with exclusive access to its state, and every piece of mutable state belongs to exactly one domain at a time. An `await` marks a possible suspension point: the task may give up its thread there, and on resumption it may run on a different thread but always in the same isolation domain. Write the code after an `await` to tolerate suspension without depending on it having happened. The compiler reasons about logical isolation, not physical threading, so design for the former.

**Prefer structured concurrency.** Child tasks (`async let`, `TaskGroup`) inherit their parent's priority and cancellation and cannot outlive it. SE-0304 frames unstructured tasks — both `Task { }` and `Task.detached` — as the escape valve for work "whose lifetime is not bound to the creating task, for example in order to fire-and-forget some operation or to initiate asynchronous work from synchronous code."[^se-0304] The two differ in what they inherit: `Task.detached` inherits no actor isolation, priority, or task-local values, whereas `Task { }` inherits all three.[^tspl] Use `Task { }` for unstructured work that should keep its context, and `Task.detached` only when independence from that context is the point.

**Approachable Concurrency (opt-in, Swift 6.2+)**[^approachable-concurrency]: a configuration pairing SE-0461's caller's-actor default for `nonisolated async` functions[^se-0461] with SE-0466's default `@MainActor` inference.[^se-0466] Under it, unannotated code is inferred `@MainActor` and a `nonisolated async` function runs on whichever actor called it, so code that doesn't opt into parallelism runs sequentially and most data-race errors for naturally sequential code disappear. Parallelism still enters where you ask for it — `@concurrent`, `Task.detached`, a custom `actor`, or a concurrent API — and only the unannotated and `nonisolated async` cases change; explicitly isolated code behaves as before. Apple states that main-actor mode "is enabled by default for new app projects created with Xcode 26";[^wwdc25-268] existing targets and bare `-swift-version 6` builds do not enable it, and `swift package init` generates a manifest with the Swift 6 language mode but neither setting (observed with Swift 6.3.2; check the generated `Package.swift` on your toolchain). Check the target's settings before assuming either execution behavior.
</concurrency_fundamentals>

### Choosing an Isolation Strategy

<isolation_decision>
Apple's own guidance sets the default: the main actor is "the most common way to protect global state," annotating a whole class `@MainActor` is common "especially in a project that doesn't have a lot of concurrent tasks," and default main-actor isolation is "recommended for apps, scripts, and other executable targets."[^apple-concurrency-updates] Reach for a custom `actor` when state is genuinely shared by concurrent work that runs off the main actor. The following table covers the common situations; it is not a complete list:

| Situation | Use | Why |
|-----------|-----|-----|
| UI state, SwiftUI observable models | `@MainActor` class (with `@Observable`) | SwiftUI reads state on the main actor; Apple DTS guidance is that view models "make sense … main-actor bound"[^dts-798211] |
| Mostly single-threaded target (app, script, tool) | `-default-isolation MainActor` (Xcode: Default Actor Isolation) | Infers `@MainActor` project-wide, with concurrency encapsulated where you opt in[^apple-concurrency-updates] |
| Mutable state shared by parallel workers | `actor` | A custom serialization domain; callers pay an `await` |
| Global or static mutable state | `@MainActor` on the declaration or its type, or `let` of a `Sendable` type | SE-0412 requires every global to be actor-isolated or immutable-and-`Sendable`[^se-0412] |
| No mutable shared state | `struct`, or a `final` class with only `let` properties | Nothing to isolate |
| CPU-bound work that must not stall an actor | `@concurrent` async function | Runs on the concurrent pool and frees the actor (see `<offloading_with_concurrent>`) |

Prefer `@MainActor` over a custom actor for anything SwiftUI observes: views run on the main actor and would need an `await` to read a custom actor's state, which is exactly the friction main-actor isolation removes.
</isolation_decision>

### Actor Re-entrancy

<actor_reentrancy>
Actors are re-entrant. SE-0306 states that "actor-isolated state can change across an await when an interleaved task mutates that state, meaning that developers must be sure not to break invariants across an await."[^se-0306] Apple's guidance for designing around this:[^wwdc21-10133] perform mutation of actor state within synchronous code, restore consistency before every `await`, and re-check any assumption about actor or global state after the `await` resumes.

```swift
actor OrderQueue {
    var pending: [Order] = []
    var inFlight: Set<Order.ID> = []

    func processNext() async {
        guard let order = pending.first(where: { !inFlight.contains($0.id) }) else { return }
        inFlight.insert(order.id)               // claim before suspending: a second caller cannot pick the same order
        await perform(order)                    // other tasks may run here and mutate `pending`
        inFlight.remove(order.id)
        if let i = pending.firstIndex(where: { $0.id == order.id }) {
            pending.remove(at: i)               // re-validate: `pending` may have changed across the await
        }                                       // claim, and check-and-remove, each contain no `await`, so neither can be interleaved
    }
}
```

The claim is what prevents duplicate work: without `inFlight`, two callers suspended in `perform` would both have read the same first element. Keep actor methods synchronous where you can and compose async wrappers around them; a synchronous actor method cannot be interleaved.
</actor_reentrancy>

### @MainActor Guarantees

<mainactor_guarantees>
`@MainActor` guarantees main-thread execution for async functions unconditionally, and for synchronous functions only when they are called from a main-actor context. Calling a synchronous `@MainActor` function from a synchronous nonisolated context is a compile-time error in both language modes (diagnostic `ActorIsolatedCall`); the fixes are to isolate the caller to the main actor or to wrap the call in `Task { @MainActor in … }`.[^apple-diagnostics] Where the two modes differ is at `@preconcurrency` boundaries, e.g., a `@MainActor` type conforming to a `@preconcurrency` protocol: the Swift 5 language mode warns ("this is an error in the Swift 6 language mode", diagnostic `ConformanceIsolation`) and the callback can arrive off the main thread at run time, while the Swift 6 language mode rejects the conformance (compiler output observed with Swift 6.3.2; the bundled `conformance-isolation.md` describes the fix, not the mode difference).[^apple-diagnostics] SE-0423 offers a third option: put `@preconcurrency` on the conformance itself (`final class C: @preconcurrency P`), which the Swift 6 language mode accepts and enforces at run time — a requirement called off the actor "will result in a runtime error that halts program execution."[^se-0423] Use it for protocols whose off-actor calls would be a bug in the caller, not as a way to silence the diagnostic.

Two Swift 6.2 additions reduce how much annotation main-actor code needs:
- **Isolated conformances** — a conformance that needs main-actor state is written `extension Model: @MainActor Exportable`, and the compiler then permits its use only from main-actor contexts.[^apple-concurrency-updates]
- **Default main-actor mode** — `-default-isolation MainActor` infers `@MainActor` on declarations project-wide; opt individual functions out with `nonisolated` or `@concurrent`.[^se-0466]

Mark a method `nonisolated` when it touches no main-actor state and must be callable from anywhere; the compiler enforces that it accesses no isolated state. In the Swift 6 language mode `Thread.isMainThread` is unavailable from async contexts — the compiler steers you toward `@MainActor` annotations rather than thread checks.
</mainactor_guarantees>

### Sendable

<sendable_rules>
`Sendable` marks a type as safe to share across isolation domains. The following kinds qualify (Apple's `Sendable` documentation states the requirements[^apple-sendable]):
- value types whose stored properties are all `Sendable`;
- `final` classes whose stored properties are all immutable and `Sendable`, with no superclass other than `NSObject`;
- actors, implicitly;
- functions and closures marked `@Sendable`, which may capture only `Sendable` values and no mutable variables.

Implicit conformance is narrow: Apple's `Sendable` documentation grants it to structures and enumerations that qualify and are either frozen or non-public and not `@usableFromInline`, and SE-0316 grants it to any non-protocol type annotated with a global actor (e.g., a `@MainActor` class),[^se-0316] with SE-0434's qualifications: a global-actor-isolated subclass of a non-`Sendable` superclass is not `Sendable`, and a global-actor-isolated closure may capture non-`Sendable` values even though it is `@Sendable`, because it can never run concurrently with itself.[^se-0434] Other classes, and public non-frozen value types without global-actor isolation, declare the conformance explicitly. A `@Sendable` closure that needs a mutable variable's current value captures it by value in the capture list (`{ [count] in … }`).[^apple-diagnostics]

**Escape hatches, in order of preference.** The migration guide's rule is that "if a type isn't already thread-safe, attempting to make it Sendable should not be your first approach";[^migration-common-problems] reach for an actor or `@MainActor` first. When a type genuinely does its own synchronization, prefer a form the compiler can check: `Mutex` from the `Synchronization` module is itself `Sendable`,[^se-0433] so a `final` class whose state lives entirely in `let` `Mutex` properties conforms to `Sendable` with checking intact. Reserve `@unchecked Sendable` for synchronization the compiler cannot see (e.g., a lock guarding a `var`), and document the invariant it relies on. For a single variable guarded by an external lock or queue, `nonisolated(unsafe)` opts that one declaration out of checking; the guide restricts it to cases where "you are carefully guarding all access to the variable with an external synchronization mechanism."[^migration-common-problems]
</sendable_rules>

### Region-Based Isolation and `sending`

<region_isolation>
Region-based isolation (SE-0414) lets a non-`Sendable` value cross an isolation boundary when the compiler can prove that the value's isolation region — the value and everything it may alias — is not used by the sending side while the receiver may still be using it: a value sent into an actor's persistent state is unusable by the sender from then on, whereas one passed as an ordinary (non-`sending`) parameter to a `nonisolated` async function becomes usable again when that call returns;[^se-0414] a `sending` parameter permits the callee to transfer the value onward, so the caller cannot use it after the call regardless of return; that modifier (SE-0430) is how an API states the transfer explicitly in its signature.[^se-0430] Use `sending` when an API hands ownership of a non-`Sendable` object across actors and you want the transfer checked rather than forced through a `Sendable` conformance. The diagnostics `sending-risks-data-race.md` and `sending-closure-risks-data-race.md` explain the failure cases.[^apple-diagnostics]
</region_isolation>

### Offloading Work with `@concurrent`

<offloading_with_concurrent>
Under `NonisolatedNonsendingByDefault`, a `nonisolated async` function runs on whichever actor called it; `@concurrent` marks a function that "must *always* switch off of an actor to run."[^apple-nonisolated-nonsending] The Approachable Concurrency vision frames the decision as the last stage of a progression — start on the main actor, and "when the programmer is ready to embrace concurrency to get better performance, they can explicitly offload work from the main actor to the cooperative thread pool."[^approachable-concurrency]

Apple's recipe for offloading a function:[^apple-concurrency-updates] add `@concurrent` to the function (which makes that function `nonisolated`), make it `async` if it isn't already, and `await` it at call sites; Apple's worked example also marks the enclosing type `nonisolated`, but do that only when none of the type's members need actor isolation, because SE-0461 permits `@concurrent` methods inside actors and `@MainActor` types.[^se-0461] Apply it to CPU-intensive work (e.g., image or video processing, large parses) that would otherwise stall the calling actor; I/O that suspends rather than blocks gains nothing from it, unless the same function also does substantial synchronous work after the `await` (e.g., decoding a large response), in which case that work is what you offload. Before the feature is enabled, `nonisolated(nonsending)` gives an individual function the caller's-actor behavior, and the migration flag `-enable-upcoming-feature NonisolatedNonsendingByDefault:migrate` adds `@concurrent` to existing nonisolated async functions so their semantics don't change silently.[^apple-nonisolated-nonsending]
</offloading_with_concurrent>

### Migrating to Strict Concurrency

<migration_diagnostics>
Migrate incrementally. The migration guide describes moving "towards the Swift 6 language mode … in stages," introducing concurrency features gradually and addressing problems as they surface,[^migration-incremental] with `@preconcurrency import` as the staging tool for dependencies that have not migrated (it suppresses or downgrades to warnings the `Sendable` diagnostics that involve that module's types, depending on the case and language mode).[^se-0337] Xcode bundles a document for each strict-concurrency diagnostic under `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/share/doc/swift/diagnostics/`;[^apple-diagnostics] read the matching file when an error appears. The following are the ones that come up most, not a complete list:

| Diagnostic (document) | Typical fix |
|-----------------------|-------------|
| `actor-isolated-call.md` | Isolate the caller to the actor, or `Task { @MainActor in … }` |
| `mutable-global-variable.md` | Make it `let` of a `Sendable` type, or isolate it with `@MainActor` |
| `sendable-closure-captures.md` | Capture by value (`[x]`), isolate the captured type, or as a last resort `nonisolated(unsafe)` |
| `explicit-sendable-annotations.md` | Add the conformance a public type needs, or restructure the type |
| `conformance-isolation.md`, `isolated-conformances.md` | Declare the conformance `@MainActor` when it needs main-actor state |
| `preconcurrency-import.md` | Stage an unmigrated dependency with `@preconcurrency import` |
| `nonisolated-nonsending-by-default.md` | Decide per function: caller's actor (the default) or `@concurrent` |

The `:migrate` variant of an upcoming-feature flag adds fix-its that preserve existing behavior while you adopt the feature.[^apple-nonisolated-nonsending]
</migration_diagnostics>

## Protocol-Oriented Programming

<protocol_oriented>
**Core principle**: "Don't start with a class, start with a protocol."[^abrahams-pop]

**When to use protocols**:
- Multiple types share behavior without sharing state
- Value types need to participate
- Multiple conformance needed (Swift = single inheritance for classes)
- Retroactive conformance to types you don't own

**When to use classes**:
- Need stored property inheritance
- Need to call `super` implementations
- Working with UIKit/AppKit (forced)
- Identity matters more than equality

**Protocol extensions = mixins**: Default implementations enable code reuse without inheritance.

**Anti-pattern from OOP**: Treating protocols as "interfaces" with no default implementations. This recreates OOP hierarchy problems.

**Dispatch rule**: a method declared only in a protocol extension is statically dispatched on the compile-time type; a method that is also a protocol requirement is dynamically dispatched to the conforming type's implementation. Declare a requirement whenever conformers are expected to override.
</protocol_oriented>

## Value vs Reference Types

<value_vs_reference>
**Apple's guidance**: "Use structures by default." Apple's two stated reasons to use a class are Objective-C interoperability and needing "to control the identity of the data you're modeling"; its example identity cases are file handles, network connections, and shared hardware intermediaries.[^value-semantics]

**Decision tree**:
```
Need identity semantics (object lifetime matters)? → class
Need shared mutable state? → class, or an actor when that state crosses isolation domains
Subclassing an Objective-C framework class, or passing data to an Objective-C API? → class
Need stored property inheritance? → class
Everything else → struct
```

**Performance**: a value type whose stored properties are themselves reference-free needs no heap allocation or reference counting of its own, and small ones pass in registers, so do not choose a class on the assumption that pointer semantics are cheaper; a large value, or one holding references, pays copying or retain/release costs that the optimizer may or may not remove.

**Know what a stored class reference does to a value type**: copies of the struct share that object, so the field has reference semantics unless the type implements copy-on-write (the standard library's technique for its collections), and each copy retains it (the optimizer removes some retain/release pairs, but design as if it didn't). Keep value types free of inner references where the field's semantics don't call for sharing; use copy-on-write when they need a shared buffer with value semantics.
</value_vs_reference>

## Error Handling

<error_handling>
| Mechanism | Use When |
|-----------|----------|
| `throws` | Recoverable errors with context |
| `Result<T, E>` | Async callbacks, deferred handling |
| `Optional` | Simple absence, no error details needed |

**Swift 6 typed throws**:
```swift
enum FileError: Error { case notFound, unreadable(any Error) }

func loadFile(_ path: String) throws(FileError) -> Data {
    guard fileExists(path) else { throw .notFound }
    do { return try Data(contentsOf: URL(fileURLWithPath: path)) }
    catch { throw .unreadable(error) }        // a typed-throws body cannot propagate `any Error` unchanged
}
// Caller: error is FileError, not 'any Error'
```
</error_handling>

## Tooling

<tooling>
**SwiftLint + SwiftFormat**: run both in CI and fail the build on violations, so the standard is enforced by the pipeline rather than remembered in review.
- SwiftLint: code smells, complexity, naming, and architecture rules
- SwiftFormat: all formatting (e.g., indentation, spacing, wrapping)

**Swift Package Manager**: Three-layer architecture (Core ← Domain ← Features). Unidirectional dependencies.

**Testing**: Prefer Swift Testing for new unit tests (native async, `#expect` macro, parameterized tests). Apple's guidance is to "continue using XCTest for any tests which use UI automation APIs like XCUIApplication or use performance testing APIs like XCTMetric as these are not supported in Swift Testing."[^wwdc24-10179]

**Documentation**: document every public API with DocC, using `​``Symbol``​` links, and state algorithmic complexity when it is not O(1).

**Configuration files**: See local .swiftlint.yml and .swiftformat in projects for standard configs.
</tooling>

## Swift Scripting

<scripting>
Use Swift for shell scripting when a script needs what Swift uniquely offers — on macOS, that is direct calls into Foundation, AppKit, and other platform frameworks from a command-line tool without a full app project. Compared to Python or Ruby, Swift trades startup latency for type safety and direct framework access.

### Choosing Swift for a Script

<scripting_decision>
| Context | Choose | Why |
|---------|--------|-----|
| Need Foundation, AppKit, or other Apple framework APIs | Swift | Calls platform APIs directly; no bridge or wrapper layer |
| Hot path; script invoked frequently | Compiled SPM executable, or Python/Ruby | `swift script.swift` compiles on every run (the driver invokes `-frontend -interpret` each time; observed with `swift -v` on Swift 6.3.2) |
| Must assume only common Unix tools are present | Bash/Python | Swift requires an installed toolchain on Linux hosts[^scripting-swift-install-linux] |
| Complex data, type safety matters | Swift | Compile-time guarantees over runtime tests |
</scripting_decision>

### Script Essentials

<scripting_essentials>
**Start every script with `#!/usr/bin/env -S swift -swift-version 6`.** Language modes are opt-in — Apple's `error-in-future-swift-version.md` states that code "will not build with the new language mode until you set that language mode in your build settings"[^apple-diagnostics] — so plain `swift script.swift` runs in the Swift 5 language mode and silently lacks the strict data-race checking described in `<concurrency_fundamentals>` until `-swift-version 6` is passed.

**Write top-level statements.** Top-level code is the script's entry point, and it supports `await` directly — call async APIs in straight-line code rather than wrapping them in semaphores or run-loop spins, and reserve `RunLoop.main.run()` for callback- and notification-based APIs that never complete. `@main` is forbidden in a file that allows top-level statements, which is what the `swift` interpreter compiles; an explicit `@main` entry point requires compiling, via `swiftc -parse-as-library` or an SPM executable target.[^scripting-main-forbidden] (The interpreter rejects `-parse-as-library`; observed with Swift 6.3.2.)

**Convert to an SPM executable when a script needs a dependency or a test**, rather than reaching for scripting tooling.

For shebang variants (Xcode build phases, systems whose `env` lacks `-S`), argument handling, Linux compatibility of Foundation and the platform frameworks, recompile-per-run latency, and the narrow case for `swift-sh`, read `references/swift-scripting.md`.
</scripting_essentials>
</scripting>

## Common Mistakes from Other Languages

<common_mistakes>
The following are the recurring mistakes by background; the list is not complete.

<from_java_and_csharp>
- **Classes for everything**: default to structs; reserve classes for identity or shared mutable state (see `<value_vs_reference>`)
- **Deep inheritance hierarchies**: compose protocols with default implementations instead
</from_java_and_csharp>

<from_python_and_javascript>
- **`Any` as an escape from typing**: use generics and protocols; `Any` discards the compile-time guarantees that are the point of writing Swift
</from_python_and_javascript>

<from_c_and_cpp>
- **Reaching for `UnsafePointer` in ordinary code**: let ARC manage lifetimes and break cycles with `weak`/`unowned`; unsafe and `Unmanaged` pointers belong at C and Core Foundation boundaries, where they are the correct tool (see `references/core-foundation-interop.md`)
</from_c_and_cpp>

<from_rust>
- **Re-creating ownership discipline by hand**: trust ARC and copy-on-write; use `sending` where isolation transfer is the actual problem (see `<region_isolation>`); `consuming` and `borrowing` are ownership modifiers (SE-0377) with their own uses, e.g., for non-copyable types, and are not a concurrency tool
</from_rust>

<from_objective_c>
- **`NSString`, `NSArray`, `NSDictionary` in Swift code**: use the native types and bridge only at Objective-C API boundaries
</from_objective_c>
</common_mistakes>

## Memory Management Gotchas

<memory_gotchas>
**Retain cycles**: Parent ↔ child, closures capturing self, delegate patterns

**Closure capture lists**:
```swift
{ [weak self] in
    guard let self else { return }
    // Use self
}
```

**Weak vs Unowned**:
- `weak`: Optional, auto-nil when deallocated (safe)
- `unowned`: not cleared on deallocation (traps if accessed afterwards); may be optional, in which case you keep it valid yourself[^tspl]

**Rule**: Prefer `weak` unless the referenced object is guaranteed to outlive the reference.

**Core Foundation and C boundaries**: when an imported signature returns `Unmanaged<T>`, Swift lacks the ownership annotation and you must apply the Create/Copy-versus-Get rule yourself; getting it backwards over-releases or leaks. Read `references/core-foundation-interop.md` before writing that conversion, and for `@convention(c)`, `dlsym`, and container lifetimes.
</memory_gotchas>

## API Design Core Principles

<api_design>
**Apple's three pillars**[^api-guidelines]:
1. **Clarity at point of use** (most important)
2. **Clarity over brevity**
3. **Document every declaration**

**Naming**:
- No side-effects → noun phrases: `x.distance(to: y)`
- With side-effects → imperative verbs: `x.sort()`
- Mutating/non-mutating pairs: `sort()`/`sorted()`, `append(_:)`/`appending(_:)`
- Factory methods start with "make": `makeIterator()`

**Access control**: Default to `private`, use `internal` for module-wide, `public`/`open` only for framework APIs.

**Source**: https://www.swift.org/documentation/api-design-guidelines/
</api_design>

## Recent Changes

<recent_changes>
**Baseline: February 2025.** This section assumes trained knowledge of Swift through that date — the reliable-knowledge cutoff of Claude Haiku 4.5, the oldest among the current Claude models[^claude-models] — and lists what has changed since: additions, behavior changes, and what the language or its community is moving away from. Treat anything older as known, and read the sources in `<local_docs>` when a feature's details matter. Move the baseline forward when the model lineup changes, and drop entries that fall behind it.

**Additions**, by release:
- **Swift 6.1** (March 31, 2025)[^swift-61]: `nonisolated` on types and extensions to prevent `@MainActor` inference; inferred child-task result types for `withTaskGroup`; `@implementation` for supplying Swift implementations of Objective-C declarations; trailing commas in more positions (e.g., tuples, parameter lists, capture lists); package traits; Swift Testing's `TestScoping` trait protocol (ST-0007) and `#expect(throws:)` returning the caught error (ST-0006).
- **Swift 6.2** (September 15, 2025)[^swift-62]: the concurrency changes developed in `<concurrency_fundamentals>` and `<offloading_with_concurrent>` (default main-actor isolation, caller's-actor `nonisolated async` as an upcoming feature, `@concurrent`); `InlineArray` and `Span`; opt-in strict memory safety that flags unsafe constructs; the `Subprocess` package for launching processes with Swift concurrency; a typed `NotificationCenter` API and the `Observations` async sequence; Swift Testing exit tests and attachments; and migration tooling for upcoming features (the `:migrate` flag variant[^apple-nonisolated-nonsending]).
- **Swift 6.3** (March 24, 2026)[^swift-63]: `@c` to "expose Swift functions and enums to C code"; module selectors to "specify which imported module Swift should look in for an API"; and performance-control attributes giving library authors "finer-grained control over compiler optimizations for clients of their APIs." Read the release post before using any of the three.
- **Swift 6.4** (next release; Embedded Swift improvements have been announced for it).[^swift-aug-2026] Accepted for a future release and not yet tied to a version: SE-0516 `Iterable` and SE-0544 (mutation and consumption in non-copyable `deinit`s).[^swift-aug-2026] Check the swift.org blog for what has landed.

**Behavior changes, deprecations, and things being moved away from:**
- **`nonisolated async` execution semantics** changed under SE-0461: with `NonisolatedNonsendingByDefault` enabled, such a function runs on the caller's actor instead of the concurrent pool. Code written to the old semantics needs `@concurrent` to keep offloading; see `<offloading_with_concurrent>`.[^se-0461]
- **Swift 6.3.2 concurrency regression** (Xcode 26.5 known issue): a closure with explicit captures passed to a `nonisolated(nonsending)` parameter has its isolation inferred from the parent context rather than set to `nonisolated(nonsending)`, and an actor-hop fix in 6.3.2 made the difference observable, so synchronous code after the `await` can run off the main actor. Apple's workarounds are to drop the explicit capture list or to use a local function declared `nonisolated(nonsending)`. Affects projects with `NonisolatedNonsendingByDefault` enabled.[^xcode-26-5]
- **`@_cdecl` is superseded.** SE-0495 (Swift 6.3) "aims to formalize and extend the long experimental `@_cdecl`" as `@c`; use `@c` in new code. Switching an existing declaration is an ABI break because `@_cdecl` emits two symbols, so leave shipped ABI alone.[^se-0495]
- **Community style guides**: the Kodeco Swift style guide has had no commits since April 2025 (checked September 2026; see `<resources>`). That establishes inactivity, not abandonment or a community move away; read the guide as a snapshot of conventions as of April 2025.
</recent_changes>

## Respecting Third-Party Codebases

<third_party>
When contributing to a codebase you don't own, its conventions take precedence over this skill's preferences:
- Follow the existing style even where it conflicts with the guidance here
- Keep to the project's supported Swift version; don't introduce newer language features
- Follow CONTRIBUTING.md exactly
- Match the existing formatting
- Keep each PR focused on one change
</third_party>

## Local Documentation Resources

<local_docs>
**Xcode bundles Markdown documentation written for its own intelligence features; read it directly:**

**Swift Diagnostic Docs** (one file per compiler diagnostic):
- Path: `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/share/doc/swift/diagnostics/`
- Files: `sendable-closure-captures.md`, `actor-isolated-call.md`, and some forty others (46 in Xcode 26)
- Use when: a Swift 6 concurrency error names a diagnostic; the file explains the cause and the sanctioned fixes

**Framework and Language Guides**:
- Path: `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/`
- Files: `Swift-Concurrency-Updates.md`, `Swift-InlineArray-Span.md`, and framework guides (e.g., SwiftUI, AppKit, Foundation updates)
- Use when: working with Swift 6.2+ language features or the frameworks those guides cover

**The Swift Programming Language Book**:
- Online: https://docs.swift.org/swift-book/
- Source (Markdown): https://github.com/swiftlang/swift-book/tree/main/TSPL.docc
- Use when: Need authoritative language reference
</local_docs>

## Authoritative Resources

<resources>
**Official Documentation (readable)**:
- Swift.org: https://www.swift.org/
- Swift Evolution: https://www.swift.org/swift-evolution/
- API Guidelines: https://www.swift.org/documentation/api-design-guidelines/
- Swift Book (Markdown): https://github.com/swiftlang/swift-book/tree/main/TSPL.docc
- DocC: https://www.swift.org/documentation/docc/
- Apple Developer Docs: https://developer.apple.com/documentation/

**Tooling**:
- SwiftLint: https://github.com/realm/SwiftLint
- SwiftFormat: https://github.com/nicklockwood/SwiftFormat
- Swift Testing: https://github.com/swiftlang/swift-testing

**Scripting**:
- swift-argument-parser: https://github.com/apple/swift-argument-parser
- swift-sh (personal scripts only; introduces external dependency): https://github.com/mxcl/swift-sh

**Style Guides**:
- Google: https://google.github.io/swift/
- Kodeco: https://github.com/kodecocodes/swift-style-guide (no commits since April 2025, as of September 2026)
</resources>

## Sources

<sources>
[^abrahams-pop]: Dave Abrahams. 2015. Protocol-Oriented Programming in Swift (Session 408). WWDC 2015. https://developer.apple.com/videos/play/wwdc2015/408/

[^api-guidelines]: Apple Inc. Swift API Design Guidelines. https://www.swift.org/documentation/api-design-guidelines/

[^value-semantics]: Apple Inc. Choosing Between Structures and Classes. Swift Documentation. Retrieved September 4, 2026 from https://developer.apple.com/documentation/swift/choosing-between-structures-and-classes

[^approachable-concurrency]: Swift Project. 2025. Approachable Concurrency Vision Document. Swift Evolution. https://github.com/swiftlang/swift-evolution/blob/main/visions/approachable-concurrency.md

[^se-0414]: Michael Gottesman, et al. 2024. SE-0414: Region-based Isolation. Swift Evolution. https://github.com/swiftlang/swift-evolution/blob/main/proposals/0414-region-based-isolation.md

[^se-0430]: Michael Gottesman, et al. 2024. SE-0430: `sending` parameter and result values. Swift Evolution. https://github.com/swiftlang/swift-evolution/blob/main/proposals/0430-transferring-parameters-and-results.md

[^se-0461]: Holly Borla, et al. 2025. SE-0461: Run nonisolated async functions on the caller's actor by default. Swift Evolution. https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md

[^se-0466]: Holly Borla and Doug Gregor. 2025. SE-0466: Control default actor isolation inference. Swift Evolution. Retrieved August 31, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md

[^swift-61]: Holly Borla. 2025. Swift 6.1 Released (March 31, 2025). Swift.org Blog. Retrieved September 5, 2026 from https://www.swift.org/blog/swift-6.1-released/

[^swift-62]: Holly Borla. 2025. Swift 6.2 Released (September 15, 2025). Swift.org Blog. Retrieved September 5, 2026 from https://www.swift.org/blog/swift-6.2-released/

[^se-0495]: Alexis Laferrière. 2025. SE-0495: C compatible functions and enums. Swift Evolution; status "Implemented (Swift 6.3)". Retrieved September 5, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0495-cdecl.md

[^swift-63]: Holly Borla and Joe Heck. 2026. Swift 6.3 Released (March 24, 2026). Swift.org Blog. Retrieved September 5, 2026 from https://www.swift.org/blog/swift-6.3-released/

[^swift-aug-2026]: Simon Leeb and Dave Lester. 2026. What's new in Swift: August 2026 Edition (September 4, 2026). Swift.org Blog. Retrieved September 5, 2026 from https://www.swift.org/blog/whats-new-in-swift-august-2026/

[^xcode-26-5]: Apple Inc. 2026. Xcode 26.5 Release Notes, section "Swift > Known Issues" (issue 176582055). Retrieved September 5, 2026 from https://developer.apple.com/documentation/xcode-release-notes/xcode-26_5-release-notes

[^claude-models]: Anthropic. 2026. Models overview, "Compare models" table, row "Reliable knowledge cutoff." Claude API Documentation. Retrieved September 5, 2026 from https://platform.claude.com/docs/en/models/overview

[^tspl]: Apple Inc. and Swift Project Authors. 2014–2025. The Swift Programming Language. https://docs.swift.org/swift-book/

[^scripting-main-forbidden]: Swift Forums. 2023. *@main in a single Swift file?* Retrieved May 8, 2026 from https://forums.swift.org/t/main-in-a-single-swift-file/63079

[^scripting-swift-install-linux]: Swift Project. 2026. *Install Swift - Linux*. Swift.org. Retrieved June 21, 2026 from https://www.swift.org/install/linux/

[^se-0304]: John McCall, Joe Groff, Doug Gregor, and Konrad Malawski. 2021. SE-0304: Structured Concurrency. Swift Evolution. Retrieved September 1, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md

[^se-0306]: John McCall, Doug Gregor, Konrad Malawski, and Chris Lattner. 2021. SE-0306: Actors. Swift Evolution. Retrieved September 1, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md

[^se-0316]: John McCall and Doug Gregor. 2021. SE-0316: Global actors, section "Using global actors on a type." Swift Evolution. Retrieved September 5, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0316-global-actors.md

[^apple-sendable]: Apple Inc. Sendable, sections "Sendable Structures and Enumerations" and "Sendable Classes." Swift Standard Library Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/swift/sendable

[^se-0433]: Alejandro Alonso. 2024. SE-0433: Synchronous Mutual Exclusion Lock, section "Interactions with Swift Concurrency." Swift Evolution. Retrieved September 5, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0433-mutex.md

[^se-0337]: Doug Gregor and Becca Royal-Gordon. 2022. SE-0337: Incremental migration to concurrency checking. Swift Evolution. Retrieved September 5, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0337-support-incremental-migration-to-concurrency-checking.md

[^se-0423]: Holly Borla and Pavel Yaskevich. 2024. SE-0423: Dynamic actor isolation enforcement from non-strict-concurrency contexts. Swift Evolution. Retrieved September 5, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0423-dynamic-actor-isolation.md

[^se-0434]: Sima Nerush, Matt Massicotte, and Holly Borla. 2024. SE-0434: Usability of global-actor-isolated types. Swift Evolution. Retrieved September 5, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0434-global-actor-isolated-types-usability.md

[^se-0412]: John McCall and Sophia Poirier. 2023. SE-0412: Strict Concurrency for Global Variables. Swift Evolution. Retrieved September 1, 2026 from https://github.com/swiftlang/swift-evolution/blob/main/proposals/0412-strict-concurrency-for-global-variables.md

[^wwdc25-268]: Apple Inc. 2025. Embracing Swift concurrency (WWDC25 session 268), session transcript. Retrieved September 4, 2026 from https://developer.apple.com/videos/play/wwdc2025/268/

[^wwdc24-10179]: Apple Inc. 2024. Meet Swift Testing (WWDC24 session 10179), session transcript. Retrieved September 5, 2026 from https://developer.apple.com/videos/play/wwdc2024/10179/

[^wwdc21-10133]: Apple Inc. 2021. Protect mutable state with Swift actors (WWDC21 session 10133), session transcript. Retrieved September 1, 2026 from https://developer.apple.com/videos/play/wwdc2021/10133/

[^dts-798211]: Quinn "The Eskimo!" (Apple Developer Technical Support). 2025. Reply in "Should SwiftUI view models in Swift 6 be both @Observable and @MainActor?" Apple Developer Forums thread 798211, August 2025. Retrieved September 1, 2026 from https://developer.apple.com/forums/thread/798211

[^migration-incremental]: Swift Project. Swift Migration Guide: Incremental Adoption. Retrieved September 1, 2026 from https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/IncrementalAdoption.md

[^migration-common-problems]: Swift Project. Swift Migration Guide: CommonProblems.md. Retrieved September 1, 2026 from https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/CommonProblems.md

[^apple-concurrency-updates]: Apple Inc. 2025. Concurrent programming updates in Swift 6.2. Bundled with Xcode 26 at `/Applications/Xcode.app/Contents/PlugIns/IDEIntelligenceChat.framework/Versions/A/Resources/AdditionalDocumentation/Swift-Concurrency-Updates.md`

[^apple-diagnostics]: Apple Inc. Swift compiler diagnostic documentation. Bundled with Xcode 26 at `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/share/doc/swift/diagnostics/`

[^apple-nonisolated-nonsending]: Apple Inc. nonisolated(nonsending) by Default (NonisolatedNonsendingByDefault). Bundled with Xcode 26 at `/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/share/doc/swift/diagnostics/nonisolated-nonsending-by-default.md`
</sources>
