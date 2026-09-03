//===--- UniqueBox.swift --------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// Vendored from swift main: stdlib/public/core/UniqueBox.swift
// uSwift changes:
//   * availability annotations dropped (single fixed toolchain).
//   * `@export(implementation)` -> `@_alwaysEmitIntoClient`.
//   * `value` uses unsafeAddress/unsafeMutableAddress addressors instead of
//     upstream's `borrow`/`mutate` accessors, so that uSwift does not need the
//     BorrowAndMutateAccessors experimental feature enabled.
//   * `pointer._deallocate(capacity: 1)` -> `pointer.deallocate()`, which is
//     the API uSwift's UnsafeMutablePointer provides.
//   * span/mutableSpan use uSwift's internal Span initialiser spellings
//     (`Span(_unchecked: UnsafeRawPointer?, count:)` and
//     `MutableSpan(_unchecked: UnsafeMutableBufferPointer)`).
//   * `@_lifetime(...)` written as `@lifetime(...)`, matching uSwift.
//
// NOTE: this type heap-allocates. It is only useful on parts where malloc is
// available and affordable.
//
//===----------------------------------------------------------------------===//

/// A smart pointer type that uniquely owns an instance of `Value` on the heap.
@frozen
@safe
public struct UniqueBox<Value: ~Copyable>: ~Copyable {
  @usableFromInline
  let pointer: UnsafeMutablePointer<Value>

  /// Initializes a value of this unique box with the given initial value.
  ///
  /// - Parameter initialValue: The initial value to initialize the unique box
  ///                           with.
  @_alwaysEmitIntoClient
  @_transparent
  public init(_ initialValue: consuming Value) {
    // uSwift's allocate(capacity:) is failable, unlike upstream's: on a
    // microcontroller the allocation really can fail. Match the convention used
    // by _fallBackToHeapAllocation in TemporaryAllocation.swift.
    guard let allocation = unsafe UnsafeMutablePointer<Value>.allocate(
      capacity: 1
    ) else {
      fatalError()
    }
    unsafe pointer = allocation
    unsafe pointer.initialize(to: initialValue)
  }

  @_alwaysEmitIntoClient
  @_transparent
  deinit {
    unsafe pointer.deinitialize(count: 1)
    unsafe pointer.deallocate()
  }
}

extension UniqueBox: @unchecked Sendable where Value: Sendable & ~Copyable {}

extension UniqueBox where Value: ~Copyable {
  /// Dereferences the unique box allowing for in-place reads and writes to the
  /// stored `Value`.
  @_alwaysEmitIntoClient
  public var value: Value {
    @_transparent
    unsafeAddress {
      // uSwift's UnsafePointer(_:) from a raw pointer is failable; this is the
      // non-failing spelling, and the pointer is known non-nil here.
      unsafe UnsafePointer<Value>(knownNotNilRawPointer: pointer._rawValue)
    }

    @_transparent
    unsafeMutableAddress {
      unsafe pointer
    }
  }

  /// Consumes the unique box and returns the instance of `Value` that was
  /// within the box.
  @_alwaysEmitIntoClient
  @_transparent
  public consuming func consume() -> Value {
    let result = unsafe pointer.move()
    unsafe pointer.deallocate()
    discard self
    return result
  }
}

extension UniqueBox where Value: ~Copyable {
  /// A span over the single element stored in this box.
  ///
  /// - Complexity: O(1)
  @_alwaysEmitIntoClient
  public var span: Span<Value> {
    @lifetime(borrow self)
    @_transparent
    get {
      let s = unsafe Span<Value>(
        _unchecked: UnsafeRawPointer(pointer), count: 1
      )
      return unsafe _overrideLifetime(s, borrowing: self)
    }
  }

  /// A mutable span over the single element stored in this box.
  ///
  /// - Complexity: O(1)
  @_alwaysEmitIntoClient
  public var mutableSpan: MutableSpan<Value> {
    @lifetime(&self)
    @_transparent
    mutating get {
      let buffer = unsafe UnsafeMutableBufferPointer(start: pointer, count: 1)
      let s = unsafe MutableSpan<Value>(_unchecked: buffer)
      return unsafe _overrideLifetime(s, mutating: &self)
    }
  }
}

extension UniqueBox where Value: Copyable {
  /// Copies the value within the unique box and returns it in a new unique
  /// instance.
  @_alwaysEmitIntoClient
  public func clone() -> Self {
    UniqueBox(value)
  }
}
