# Vendoring manifest

uSwift is largely a vendored copy of the Swift standard library, adapted for very
small microcontrollers. Until now there was no record of *which* upstream
revision each file came from, or of the systematic local edits applied to them.
Reconstructing that took a lot of forensic diffing, so it is written down here.

Upstream reference used for this pass: `swiftlang/swift` `origin/main` at
`871a239941f` (2026-08-31). Where "6.3 base" is mentioned it means
`2db0e8aea80` (2025-11-13), the point at which `release/6.3` and `main` diverge.
Note that `swift-6.3-RELEASE` is `aa782beb23b`, tagged 2026-03-20, so a file can
be "6.3 vintage" and still be older than commits dated 2025.

## Vintage of the vendored files

Measured as diff-line counts against upstream at the 6.3 base versus upstream
`main`; smaller means closer.

| file | vs 6.3 base | vs main | assessment |
| --- | --- | --- | --- |
| `Span.swift` | 136 | 679 | 6.3-vintage or slightly older |
| `RawSpan.swift` | 122 | 599 | 6.3-vintage or slightly older |
| `MutableSpan.swift` | 532 | 1292 | 6.3-vintage, heavily adapted |
| `MutableRawSpan.swift` | 334 | 1161 | 6.3-vintage, heavily adapted |
| `InlineArray.swift` | 163 | 279 | 6.3-vintage |
| `TemporaryAllocation.swift` | 170 | 276 | 6.3-vintage |

Some files are demonstrably **older** than the 6.3 base rather than merely
adapted: for example upstream had already renamed `Span._extracting(_:)` to
`extracting(_:)` (leaving a deprecated alias) by the 6.3 base, whereas uSwift
still has only `_extracting`.

## Systematic local adaptations

These are deliberate and should be preserved when vendoring anything new. A
mechanical 3-way merge with upstream will fight all of them.

1. **Preconditions carry no message.** uSwift's `_precondition` takes only a
   condition (`TopLevelFunctions.swift`), so upstream's
   `_precondition(cond, "message")` becomes `_precondition(cond)`. This keeps
   message literals out of flash.
2. **`@_alwaysEmitIntoClient`, not `@export(implementation)`.** Upstream migrated
   the stdlib to `@export(implementation)` in July 2026; uSwift uses
   `@_alwaysEmitIntoClient` (349 occurrences) and has none of the new spelling.
3. **`@lifetime(...)`, not `@_lifetime(...)`.** Both are accepted by the compiler
   (`DeclAttr.def` declares `lifetime` with `_lifetime` as an alias); uSwift uses
   the unprefixed form 138 times.
4. **Availability is largely vestigial.** uSwift carries `@available(SwiftStdlib
   6.2, *)` and `@available(SwiftCompatibilitySpan 5.0, *)` annotations inherited
   from upstream, and the build does not pass `-define-availability`, so
   `@_originallyDefinedIn(... SwiftCompatibilitySpan ...)` produces "unknown
   platform" warnings. New files vendored in this pass simply omit availability.
5. **Allocation is failable.** `UnsafeMutablePointer.allocate(capacity:)` and
   friends return optionals in uSwift, because malloc genuinely can fail on these
   parts. Upstream code that assumes non-optional allocation needs a
   `guard let ... else { fatalError() }`.
6. **Non-failable raw pointer conversion** is spelled
   `UnsafePointer(knownNotNilRawPointer:)`; the plain `UnsafePointer(_:)` from a
   raw pointer is failable.
7. **Types that simply do not exist here**, so upstream code referring to them
   must be dropped: `String`, `Character`, `Substring`, `Dictionary`,
   `OutputSpan`, `OutputRawSpan`, `Iterable`, `BorrowingSequence` /
   `BorrowingIterator`.
8. **Not every file on disk is built.** The build list is
   `ALL_SWIFT_SOURCES_SHARED` plus arch-specific files in `Makefile`;
   `SwiftifyImport.swift`, `UnsafeBufferPointerSlice.swift`, `AVRArrayBuffer.swift`
   and `Bitset.swift` are deliberately commented out. Anything vendored must be
   added to that list or it silently is not compiled.

## Files vendored or refreshed in the 6.5 sync

See `SYNC-NOTES-6.5.md` for what was taken, what was skipped, and why.

| file | upstream path | taken from |
| --- | --- | --- |
| `ByteOrder.swift` | `stdlib/public/core/ByteOrder.swift` | main @ `871a239941f` |
| `FullyInhabited.swift` | `stdlib/public/core/FullyInhabited.swift` | main @ `871a239941f` |
| `UniqueBox.swift` | `stdlib/public/core/UniqueBox.swift` | main @ `871a239941f` |
| `InlineArray.swift` | `stdlib/public/core/InlineArray.swift` | partial, main @ `871a239941f` |
| `TemporaryAllocation.swift` | `stdlib/public/core/TemporaryAllocation.swift` | partial, main @ `871a239941f` |
| `Span.swift` | `stdlib/public/core/Span/Span.swift` | partial, main @ `871a239941f` |
| `RawSpan.swift` | `stdlib/public/core/Span/RawSpan.swift` | partial, main @ `871a239941f` |
| `MutableRawSpan.swift` | `stdlib/public/core/Span/MutableRawSpan.swift` | partial, main @ `871a239941f` |

## How to compare a vendored file against upstream

`git show <rev>:<path>` misbehaves in the swift repo for some paths (it can
resolve to the commit rather than the blob). Use the blob directly:

```sh
cd /path/to/swift
blob() { git cat-file blob "$(git ls-tree "$1" --object-only -- "$2")"; }
blob origin/main stdlib/public/core/Span/Span.swift > /tmp/upstream_Span.swift
diff /tmp/upstream_Span.swift ~/Code/uSwift/Span.swift
```

## How to type-check uSwift without a full build

This does not need the AVR toolchain, only a built `swift-frontend`. It catches
everything except the C shim symbols (which need avr-libc include paths):

```sh
cd ~/Code/uSwift
git submodule update --init uSwiftShims          # needed once
swift-frontend -frontend -typecheck $(SOURCES) \
  -parse-stdlib -module-name Swift -target avr-none-none-elf -wmo \
  @experimental-features.txt -enable-experimental-feature Embedded \
  -I uSwiftShims -Xcc -I -Xcc uSwiftShims \
  -DFORCE_MAIN_SWIFT_ARRAYS -DAVR_LIBC_DEFINED_SWIFT
```

where `$(SOURCES)` is `ALL_SWIFT_SOURCES_SHARED` from `Makefile` plus
`Integer-16.swift IntegerMath-16.swift CTypes-16.swift Progmem.swift
EmbeddedRuntime.swift`. Expect only "cannot find ... in scope" errors for
`swift_slowAlloc`, `float_to_int*` and `_*FromProgmem`.
