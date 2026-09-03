//===--- FullyInhabited.swift ---------------------------------------------===//
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
// Vendored from swift main: stdlib/public/core/FullyInhabited.swift
// uSwift changes:
//   * availability annotations dropped (single fixed toolchain).
//   * `@export(implementation)` -> `@_alwaysEmitIntoClient`, matching the
//     convention used elsewhere in uSwift.
//   * `_precondition` called without a message: uSwift's `_precondition` takes
//     only a condition, so messages are not carried into flash.
//   * Upstream declares the conformances in the .gyb sources for the integer
//     and floating point types. uSwift has no gyb step, so the conformances
//     for the types uSwift actually defines are collected at the bottom of
//     this file instead.
//
//===----------------------------------------------------------------------===//

/// A protocol for types whose memory can safely be read as individual raw bytes.
///
/// A type can conform to ConvertibleToBytes if its memory representation
/// includes no padding. The sum of the size of its stored properties must be
/// equal to its stride.
@_marker public protocol ConvertibleToBytes: Copyable {}

/// A protocol for types that can safely be constructed from raw bytes.
///
/// Every bit pattern of the type's size must be a valid instance, and the
/// type's memory representation must include no padding.
@_marker public protocol ConvertibleFromBytes: BitwiseCopyable {}

/// A type whose every bit pattern is a valid value, and whose memory
/// representation contains no padding.
public typealias FullyInhabited = ConvertibleToBytes & ConvertibleFromBytes

/// Reinterprets the bytes of `original` as an instance of `type`.
///
/// The two types must have the same size. Unlike
/// `unsafeBitCast(_:to:)` this is a safe operation, because the
/// `ConvertibleToBytes` and `ConvertibleFromBytes` constraints guarantee that
/// every bit pattern involved is valid and that neither layout has padding.
@_alwaysEmitIntoClient
@_transparent
public func bitCast<T, U>(
  _ original: T, to type: U.Type
) -> U where T: ConvertibleToBytes, U: ConvertibleFromBytes {
  _precondition(MemoryLayout<T>.size == MemoryLayout<U>.size)
  return Builtin.reinterpretCast(original)
}

//===----------------------------------------------------------------------===//
// uSwift-local conformances.
//
// Upstream attaches these in IntegerTypes.swift.gyb, FloatingPointTypes.swift.gyb
// and Bool.swift. They are gathered here so that vendoring this file does not
// require touching uSwift's hand-maintained integer and floating point sources.
// Pointer, Range and SIMD conformances are deliberately not included; add them
// if and when they are wanted.
//===----------------------------------------------------------------------===//

extension Bool: ConvertibleToBytes {}

extension Int: ConvertibleToBytes, ConvertibleFromBytes {}
extension Int8: ConvertibleToBytes, ConvertibleFromBytes {}
extension Int16: ConvertibleToBytes, ConvertibleFromBytes {}
extension Int32: ConvertibleToBytes, ConvertibleFromBytes {}
extension Int64: ConvertibleToBytes, ConvertibleFromBytes {}

extension UInt: ConvertibleToBytes, ConvertibleFromBytes {}
extension UInt8: ConvertibleToBytes, ConvertibleFromBytes {}
extension UInt16: ConvertibleToBytes, ConvertibleFromBytes {}
extension UInt32: ConvertibleToBytes, ConvertibleFromBytes {}
extension UInt64: ConvertibleToBytes, ConvertibleFromBytes {}

// Note: floating point types are ConvertibleToBytes but NOT
// ConvertibleFromBytes upstream, because not every bit pattern is a distinct
// valid value (NaN payloads).
extension Float: ConvertibleToBytes {}
extension Float16: ConvertibleToBytes {}
