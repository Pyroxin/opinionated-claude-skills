# Core Foundation and C Interop

<cf_interop_scope>
Read this when Swift code bridges to a C or Core Foundation API: an imported signature hands you an `Unmanaged<T>`, you need a C function pointer, or a function you need is absent from the Swift module map and must be resolved at runtime. It covers the ownership rule that decides whether a bridged value leaks or is over-released, the `Unmanaged` API that expresses that rule in Swift, container lifetimes, and the mechanics and risks of calling C functions the importer doesn't expose. It assumes familiarity with ARC; the memory-management section of `SKILL.md` covers retain cycles and `weak`/`unowned`.
</cf_interop_scope>

## The Ownership Rule

<cf_ownership_rule>
Core Foundation encodes ownership in function names, and Apple's policy is stated in three rules:[^cf-ownership]

> If you create an object (either directly or by making a copy of another object […]), you own it. If you get an object from somewhere else, you do not own it. […] If you are an owner of an object, you must relinquish ownership when you have finished using it.

The naming convention that carries this:
- **Create rule** — functions with "Create" or "Copy" in the name return an object you own and must release.
- **Get rule** — any other function (typically one with "Get" in the name) returns an object you do not own; Apple's wording is that you "cannot be certain of the object's life span," so retain it yourself if you need it to outlive the call.

**First check how Swift imported the function.** Apple's guidance is that "Core Foundation objects returned from annotated APIs are automatically memory-managed in Swift," and that only when "APIs that have not been annotated" are imported does the compiler hand you an `Unmanaged` value to convert yourself.[^cf-types] So an imported signature returning `CFArray` needs nothing from you; one returning `Unmanaged<CFArray>` needs the rule above, and the function name is how you decide which side of it applies.
</cf_ownership_rule>

## Expressing Ownership with `Unmanaged`

<unmanaged_api>
`Unmanaged` is "a type for propagating an unmanaged object reference. When you use this type, you become partially responsible for keeping the object alive."[^unmanaged] Swift hands you one where it lacks the ownership information to manage the reference itself. Convert it with the method that matches the ownership rule above:

| The C function's name says | Take the value with | Because |
|----------------------------|---------------------|---------|
| Create / Copy (you own it) | `takeRetainedValue()` | It "consumes an unbalanced retain" — you are "responsible for releasing the result"[^unmanaged] |
| Get (you don't own it) | `takeUnretainedValue()` | It converts "without consuming an unbalanced retain" — you are "not responsible for releasing the result"[^unmanaged] |

Getting this backwards is the characteristic bug: `takeRetainedValue()` on a Get result over-releases and crashes later, and `takeUnretainedValue()` on a Create/Copy result leaks.

Going the other direction — handing a Swift object to C — the choice follows the receiving API's argument contract, not the naming rule: a parameter documented as consumed (+1) takes `passRetained`, one documented as borrowed (+0) takes `passUnretained`. `passRetained(_:)` "creates an unmanaged reference with an unbalanced retain" and the object "will leak if nothing eventually balances the retain"; `passUnretained(_:)` is for "passing a reference to an API which Swift does not know the ownership rules for," with no retain added.[^unmanaged]
</unmanaged_api>

## Container Lifetimes

<container_lifetime>
A pointer pulled out of a CF collection — for example, `CFArrayGetValueAtIndex` or the buffer filled by `CFSetGetValues` — is a Get-rule value: you do not own it. For a collection created with the standard callbacks (`kCFTypeArrayCallBacks` and the like) the container retains its elements, so keeping the container alive keeps them alive; wrapping the work in `withExtendedLifetime(container) { … }` makes that intent explicit and stops ARC from releasing the container after its last visible use. Two conditions void that reasoning: a collection created with custom callbacks whose `retain` is `NULL` holds unretained pointers, so the container's lifetime says nothing about the elements';[^cf-array] and a mutable collection can drop an element while it stays alive. If either can apply, hold your own managed reference to the element — `Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()` and keep the result alive — rather than relying on the container. That conversion is valid only when the pointer designates a live CF object, which a custom-callback collection does not guarantee (its values may be arbitrary pointers); `CFRetain` itself is unavailable from Swift ("Core Foundation objects are automatically memory managed").
</container_lifetime>

## C Function Pointers and Unexposed Symbols

<c_function_pointers>
The `@convention(c)` attribute on a function type "indicates a C function reference. The function value carries no context and uses the C calling convention."[^tspl-attributes] Declare a typealias per C signature and pass it wherever a C API expects a function pointer.

When a function is absent from the Swift module map (a private or unannotated symbol in a framework you must talk to), resolve it at runtime and cast it to that typealias:

```swift
typealias CopyThingFn = @convention(c) (CFDictionary) -> Unmanaged<CFTypeRef>?

let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "FrameworkCopyThing")   // RTLD_DEFAULT
let copyThing = sym.map { unsafeBitCast($0, to: CopyThingFn.self) }
```

Constraints that follow from doing this:
- **Reproduce the C signature exactly.** `unsafeBitCast` performs no checking. A typealias with the wrong arity makes the callee read arguments from registers you never set — an undocumented options parameter declared as no-arguments, for example, dereferences garbage and crashes inside the framework.
- **Pass what the callee expects, not what is convenient.** A function that dereferences an argument without a nil check crashes on `nil`, and an empty container is not automatically a request for defaults: an unannotated function may require particular keys or values. Establish the argument contract from the header, documentation, or disassembly before calling, and treat a crash on a plausible-looking argument as evidence that you haven't.
- **Resolve lazily and fail cleanly.** Treat every `dlsym` result as optional; a missing symbol should produce a distinct error path (for example, a dedicated exit code), never a crash. Private symbols can vanish or change shape in any OS release.
- **Prefer the imported API when one exists.** Reach for `dlsym` only for symbols the module map doesn't expose, and note the dependency on private API where the code declares the typealias.
</c_function_pointers>

## Type-Checking CF Values

<cf_type_checks>
Check a `CFTypeRef`'s dynamic type with `CFGetTypeID` against `CFArrayGetTypeID()`, `CFSetGetTypeID()`, and the like; after that check, convert with `unsafeDowncast(value, to: CFArray.self)`. The Swift compiler rejects `as?` for these conversions ("conditional downcast to CoreFoundation type … will always succeed"), and `as!` compiles silently while performing no check (observed with Swift 6.3.2), so the type-ID test followed by `unsafeDowncast` is the honest form — the test is where the safety lives.
</cf_type_checks>

## Sources

<sources>
[^cf-ownership]: Apple Inc. 2009. Ownership Policy. In *Memory Management Programming Guide for Core Foundation* (archived; last updated October 21, 2009). Retrieved September 1, 2026 from https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFMemoryMgmt/Concepts/Ownership.html

[^cf-types]: Apple Inc. Working with Core Foundation Types, sections "Use Memory Managed Objects" and "Convert Unmanaged Objects to Memory-Managed Objects." Swift Documentation. Retrieved September 5, 2026 from https://developer.apple.com/documentation/swift/working-with-core-foundation-types

[^cf-array]: Swift Project. `CFArray.h`, documentation of the `callBacks` parameter of `CFArrayCreate` ("The retain field may be NULL, in which case the CFArray will do nothing to add a retain to the contained values"). swift-corelibs-foundation source. Retrieved September 5, 2026 from https://github.com/swiftlang/swift-corelibs-foundation/blob/main/Sources/CoreFoundation/include/CFArray.h

[^unmanaged]: Swift Project. `Unmanaged` documentation comments, Swift standard library source (`stdlib/public/core/Unmanaged.swift`). Retrieved September 1, 2026 from https://github.com/swiftlang/swift/blob/main/stdlib/public/core/Unmanaged.swift

[^tspl-attributes]: Apple Inc. and Swift Project Authors. Attributes. In *The Swift Programming Language* (source: `TSPL.docc/ReferenceManual/Attributes.md`). Retrieved September 1, 2026 from https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/ReferenceManual/Attributes.md
</sources>
