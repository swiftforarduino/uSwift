# uSwift 6.5 sync notes

Branch `uSwift-6.5-sync`. Nothing is committed. Companion document:
`VENDORED.md`, which records where the vendored files came from and the local
conventions that must be preserved.

Upstream reference: `swiftlang/swift` `origin/main` @ `871a239941f` (2026-08-31).

## The one thing that actually breaks

`CoreOperators.swift` had 17 operator declarations using the old "operator
designated types" syntax, e.g.

```swift
infix operator  << : BitwiseShiftPrecedence, BinaryInteger
infix operator   + : AdditionPrecedence, AdditiveArithmetic
```

That form has been removed from the compiler. It produced **68 parse errors**,
which cascade into hundreds of downstream failures, so uSwift as it stood did not
compile against a current toolchain at all. The trailing designated types are now
stripped, matching upstream's `Policy.swift` (`infix operator <<: BitwiseShiftPrecedence`).

This is the highest-value change on the branch and is independent of everything
else here.

## Taken from upstream

**New files** (all three added to `ALL_SWIFT_SOURCES_SHARED` in `Makefile`):

- `ByteOrder.swift` — `ByteOrder` enum with `.native`. Useful for wire formats and
  register images.
- `FullyInhabited.swift` — the `ConvertibleToBytes` / `ConvertibleFromBytes`
  marker protocols, the `FullyInhabited` typealias, and safe `bitCast(_:to:)`.
  Upstream attaches the conformances in `.gyb` sources; since uSwift has no gyb
  step, conformances for the types uSwift actually defines (`Bool`, all the sized
  integers, `Int`/`UInt`, `Float`, `Float16`) are collected at the bottom of the
  file. Pointer, `Range` and SIMD conformances are deliberately not included.
- `UniqueBox.swift` — uniquely-owning heap box. **This one heap-allocates**, so it
  is only useful where malloc is affordable; drop it from the `Makefile` list if
  that is not wanted. Adapted to use addressors rather than upstream's
  `borrow`/`mutate` accessors, so no new experimental feature is required.

**`InlineArray.swift`**

- `span` / `mutableSpan` now use the unchecked `Span` initialiser (upstream
  #90002). `count` is a value generic and cannot be negative, so the precondition
  in `_unsafeStart` was dead weight in flash.
- Added the `ConvertibleToBytes` / `ConvertibleFromBytes` conformances.

**`TemporaryAllocation.swift`**

- Converted to **typed throws** throughout (both public entry points and the
  three internal helpers), matching upstream. This is the most valuable item
  after the operator fix: with `rethrows` a throwing body goes through an
  existential `Error`, and uSwift has no error-box runtime. As upstream does, the
  closures passed to the internal helpers are explicitly annotated
  `{ (pointer: Builtin.RawPointer) throws(E) -> R in }`, otherwise inference
  defaults the thrown type to `any Error` and the file does not compile.
- Stack deallocation moved back to `defer` (upstream reverted to this once the
  SIL verifier stopped objecting), replacing the duplicated `stackDealloc` on the
  do/catch paths.

**`Span.swift`**

- Added upstream's additive `internal init(_unchecked: UnsafePointer<Element>, count:)`
  overload, so call sites holding a typed pointer need not launder it through
  `UnsafeRawPointer`.
- Added `init(viewing: RawSpan)` constrained on `ConvertibleFromBytes`, which is
  upstream's new name for uSwift's existing `init(_bytes:)`. The old spelling is
  kept, so nothing breaks.

**`RawSpan.swift`**

- Added safe byte access ported from upstream: `subscript(_ byteOffset:)`,
  `subscript(unchecked byteOffset:)`, `_checkIndex`, and
  `load<T: ConvertibleFromBytes>(fromByteOffset:as:)` — the checked counterpart to
  the existing `unsafeLoad`. Safe because `ConvertibleFromBytes` guarantees every
  bit pattern is valid.
- Added `isTriviallyIdentical(to:)` (SE-0494's name) **alongside** the existing
  `isIdentical(to:)` rather than replacing it.

**`MutableRawSpan.swift`**

- The same safe `load<T: ConvertibleFromBytes>` plus `_checkIndex`.

**`experimental-features.txt`**

Trimmed from 19 flags to 5. `MoveOnlyTypes` is no longer a feature the compiler
knows; ten others (`MoveOnly`, `NoncopyableGenerics`, `NonescapableTypes`,
`BitwiseCopyable`, `BorrowingSwitch`, `ConformanceSuppression`,
`MemorySafetyAttributes`, `TypedThrows`, `BuiltinEmplaceTypedThrows`,
`MoveOnlyPartialConsumption`) are now `BASELINE_LANGUAGE_FEATURE`, i.e. always on;
and three (`InoutLifetimeDependence`, `LifetimeDependenceMutableAccessors`,
`NonescapableAccessorOnTrivial`) are `LANGUAGE_FEATURE` entries that exist for
`#if $Feature` checks and were never enableable by flag. Retained:
`LifetimeDependence`, `Lifetimes`, `AddressableParameters`, `AddressableTypes`,
`ExistentialAny`. This is tidy-up, not a fix — the compiler silently ignores
unknown experimental features, so the old list was noisy rather than broken.

## Deliberately NOT taken

The Span family was **not** wholesale refreshed. uSwift's copies are pre-6.3 plus
the systematic local edits listed in `VENDORED.md`, and a 3-way merge against
upstream produces 17–30 conflicts per file whose "resolution" would mostly mean
reverting those edits — reintroducing precondition message strings, the
`extracting`/deprecated-alias churn, `@export(implementation)` and
`@_originallyDefinedIn(... SwiftCompatibilitySpan ...)`. Of the upstream delta,
roughly half is doc comments and most of the remainder is annotation churn: for
`Span.swift`, 581 changed lines reduce to about 159 lines of real code change.

Specific items left for a session with a working AVR build:

1. **`Builtin.gepProjection` element addressing** (upstream, June 2026). Changes
   `_unsafeAddressOfElement` to return `Builtin.RawPointer` and uses
   `Builtin.gepProjection_Word` under `#if $BuiltinGepProjection`, touching every
   subscript addressor. Plausibly a code-size win on AVR, but it is the highest
   risk item to do blind.
2. **`borrow` / `mutate` accessors** replacing `unsafeAddress` /
   `unsafeMutableAddress` in `Span` and `InlineArray`. Needs the
   `BorrowAndMutateAccessors` experimental feature enabling.
3. **API removals**: upstream removed `Span`'s subscript get accessors and
   retyped several constraints from `BitwiseCopyable` to `ConvertibleToBytes`.
   Source-breaking for S4A libraries and user sketches, so not done unilaterally.
4. **`MutableSpan` / `MutableRawSpan` byte views**: `bytes`, `mutableBytes`,
   `init(mutating: inout MutableRawSpan)`, `init(mutableBytes:)`, `_reborrowed`.
5. **`Iterable` conformances** on `InlineArray`, `Span` and `MutableSpan` — would
   require vendoring `BorrowingSequence.swift` first.
6. **`_isWellAligned()`** on the buffer pointer types, which upstream now uses in
   place of inline alignment arithmetic.

Also not touched, per instruction: keypaths, and anything about `-O0` codegen.

## Verification performed

No AVR toolchain was used and nothing was linked or run. What was done:

- Every touched file parses (`swift-frontend -frontend -parse`).
- Whole-module type-check of the real AVR source list (the `Makefile` list plus
  the arch files), with `uSwiftShims` initialised — see `VENDORED.md` for the exact
  command. Result: **no new errors introduced**, and the two `CoreOperators.swift`
  parse errors eliminated. Confirmed by stashing the branch and re-running
  identically for a baseline.
- Remaining errors in that configuration are 8 "cannot find ... in scope"
  diagnostics for `swift_slowAlloc`, `float_to_int16/32/64` and
  `_byteFromProgmem` / `_intFromProgmem` / `_dwordFromProgmem` /
  `_floatFromProgmem`. These are C shim symbols that need the avr-libc and libgcc
  include paths the real Makefile passes; they are present in the baseline too.

## What to check first on a real build

1. `InlineArray: ConvertibleFromBytes` relies on conditional `BitwiseCopyable`
   inference through `Builtin.FixedArray`. It type-checks here, but it is the one
   conformance worth eyeballing in generated code.
2. `UniqueBox` uses `discard self` in `consume()`, which is not used anywhere else
   in uSwift.
3. The typed-throws conversion in `TemporaryAllocation.swift` changes public
   signatures (`rethrows` to `throws(E)`). Callers should be unaffected, but it is
   worth a smoke test of anything that passes a throwing closure.
4. `ByteOrder.native` uses `#if _endian(big)` / `#elseif _endian(little)`, and
   `#error`s if neither is defined. Confirm the AVR target defines one.
