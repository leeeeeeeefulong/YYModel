//
//  YYModelPlatformConformances.swift
//  YYModel
//
//  Adopts the same platform protocols as Foundation's JSONDecoder / JSONEncoder,
//  so YYModelSwift is never "less than official" as a drop-in decoder.
//
//  Foundation's JSONDecoder conforms to: Copyable, Escapable, Sendable,
//  SendableMetatype, TopLevelDecoder (Combine), NetworkDecoder (Network).
//  YYJSONDecoder already satisfies Sendable (@unchecked) and the Copyable /
//  Escapable / SendableMetatype requirements by being a struct; the two
//  remaining conformances are declared here.
//
//  Both protocols require exactly `decode<T>(_:from:) throws -> T` (decoder) and
//  `encode<T>(_:) throws -> Data` (encoder) — YYJSONDecoder / YYJSONEncoder
//  already have those methods with matching signatures, so these are pure
//  declarations with no implementation cost.
//

import Foundation

// MARK: - Combine

#if canImport(Combine)
import Combine

/// Foundation's `JSONDecoder` is a `TopLevelDecoder`, so a Combine
/// `decode(type:decoder:)` operator accepts it. YYModelSwift matches that.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension YYJSONDecoder: TopLevelDecoder {
    public typealias Input = Data
}

/// Mirror of `TopLevelDecoder` on the encode side.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension YYJSONEncoder: TopLevelEncoder {
    public typealias Output = Data
}
#endif

// MARK: - Network

#if canImport(Network)
import Network

/// Foundation's `JSONDecoder` is a `NetworkDecoder` (iOS 26 / macOS 26).
/// The protocol only requires `decode<T>(_:from: Data)`, which already exists.
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
extension YYJSONDecoder: NetworkDecoder {}

/// Mirror of `NetworkDecoder` on the encode side.
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, *)
extension YYJSONEncoder: NetworkEncoder {}
#endif
