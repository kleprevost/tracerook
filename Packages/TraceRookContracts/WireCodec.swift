import Foundation

/// Only the validated codec is a wire boundary; Codable alone is not validation.
public protocol IPCMessage: Codable, Sendable {
    static var wireKeys: Set<String> { get }
    static func validateWireShape(_ value: JSONValue) throws
    func validate() throws
}

extension IPCMessage {
    public static func validateWireShape(_ value: JSONValue) throws {
        guard case .object(let object) = value, Set(object.keys) == wireKeys else {
            throw TraceRookError.malformedInput
        }
    }
}

public enum WireLimits {
    public static let packetBytes = TraceRookVersion.maxInputBytes
    public static let replyBytes = 16_384
    public static let stringBytes = 65_536
    public static let objectMembers = 1_024
    public static let arrayElements = 2_048
    public static let decodeMilliseconds = 100
}

/// One packet only: network-order UInt32 size followed by bounded UTF-8 JSON.
/// Stream reads, peer authentication and request deduplication belong to the service.
public enum WireCodec {
    public static func encode<T: IPCMessage>(_ message: T, maximumBytes: Int = WireLimits.packetBytes) throws -> Data {
        let payload = try encodePayload(message, maximumBytes: maximumBytes)
        let size = UInt32(payload.count)
        var framed = Data([UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
        framed.append(payload)
        return framed
    }

    /// Validated unframed JSON for an HTTP boundary. Uses the same duplicate-key
    /// scanner and bounds as IPC; an HTTP body must not carry the IPC prefix.
    public static func encodePayload<T: IPCMessage>(_ message: T, maximumBytes: Int = WireLimits.packetBytes) throws -> Data {
        try message.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payload = try encoder.encode(message)
        let checked = try inspect(payload, maximumBytes: maximumBytes, deadline: ContinuousClock().now.advanced(by: .milliseconds(WireLimits.decodeMilliseconds)))
        try T.validateWireShape(checked)
        return payload
    }

    public static func decode<T: IPCMessage>(_ type: T.Type, frame: Data, maximumBytes: Int = WireLimits.packetBytes,
                                              deadline: ContinuousClock.Instant? = nil) throws -> T {
        let localDeadline = deadline ?? ContinuousClock().now.advanced(by: .milliseconds(WireLimits.decodeMilliseconds))
        try checkDeadline(localDeadline)
        guard frame.count >= 4 else { throw TraceRookError.malformedInput }
        let prefix = frame.prefix(4)
        let count = prefix.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard maximumBytes > 0, maximumBytes <= WireLimits.packetBytes, count <= maximumBytes else { throw TraceRookError.oversizedInput }
        guard count > 0, frame.count == Int(count) + 4 else { throw TraceRookError.malformedInput }
        return try decodePayload(type, payload: Data(frame.dropFirst(4)), maximumBytes: maximumBytes, deadline: localDeadline)
    }

    public static func decodePayload<T: IPCMessage>(_ type: T.Type, payload: Data, maximumBytes: Int = WireLimits.packetBytes,
                                                     deadline: ContinuousClock.Instant? = nil) throws -> T {
        let localDeadline = deadline ?? ContinuousClock().now.advanced(by: .milliseconds(WireLimits.decodeMilliseconds))
        let shape = try inspect(payload, maximumBytes: maximumBytes, deadline: localDeadline)
        try T.validateWireShape(shape)
        let message: T
        do { message = try JSONDecoder().decode(type, from: payload) }
        catch { throw TraceRookError.malformedInput }
        try checkDeadline(localDeadline)
        try message.validate()
        try checkDeadline(localDeadline)
        return message
    }

    public static func decodeReply(frame: Data, matching requestID: UUID, deadline: ContinuousClock.Instant? = nil) throws -> HookReplyV2 {
        let reply = try decode(HookReplyV2.self, frame: frame, maximumBytes: WireLimits.replyBytes, deadline: deadline)
        guard reply.requestID == requestID else { throw TraceRookError.wrongBinding }
        return reply
    }

    private static func inspect(_ data: Data, maximumBytes: Int, deadline: ContinuousClock.Instant) throws -> JSONValue {
        try checkDeadline(deadline)
        guard maximumBytes > 0, maximumBytes <= WireLimits.packetBytes, data.count <= maximumBytes else { throw TraceRookError.oversizedInput }
        guard String(data: data, encoding: .utf8) != nil else { throw TraceRookError.malformedInput }
        var scanner = StrictJSONScanner(bytes: Array(data), deadline: deadline)
        try scanner.scan()
        try checkDeadline(deadline)
        let value = try JSONValue.decodeBounded(data)
        try checkDeadline(deadline)
        return value
    }

    fileprivate static func checkDeadline(_ deadline: ContinuousClock.Instant) throws {
        guard ContinuousClock().now < deadline else { throw TraceRookError.timeout }
    }
}

/// Preflight before Foundation decoding loses duplicate keys. No user input is
/// included in errors. Bounds cover encoded string bytes, including escapes.
private struct StrictJSONScanner {
    let bytes: [UInt8]
    let deadline: ContinuousClock.Instant
    var index = 0

    mutating func scan() throws {
        try value(depth: 0)
        whitespace()
        guard index == bytes.count else { throw TraceRookError.malformedInput }
    }

    mutating func value(depth: Int) throws {
        try WireCodec.checkDeadline(deadline)
        whitespace()
        guard index < bytes.count else { throw TraceRookError.malformedInput }
        switch bytes[index] {
        case 123, 91:
            guard depth < TraceRookVersion.maxNestingDepth else { throw TraceRookError.excessiveNesting }
            if bytes[index] == 123 { try object(depth: depth + 1) }
            else { try array(depth: depth + 1) }
        case 34: _ = try string(decodeKey: false)
        default:
            let start = index
            while index < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[index]) {
                index += 1
                if index % 1_024 == 0 { try WireCodec.checkDeadline(deadline) }
            }
            guard index > start else { throw TraceRookError.malformedInput }
            // Literal/number grammar and exact Decimal limits are checked by JSONValue.
        }
    }

    mutating func object(depth: Int) throws {
        index += 1; whitespace()
        if consume(125) { return }
        var keys: Set<String> = []
        while true {
            whitespace()
            let key = try string(decodeKey: true)
            guard keys.insert(key).inserted else { throw TraceRookError.malformedInput }
            guard keys.count <= WireLimits.objectMembers else { throw TraceRookError.oversizedInput }
            whitespace()
            guard consume(58) else { throw TraceRookError.malformedInput }
            try value(depth: depth); whitespace()
            if consume(125) { return }
            guard consume(44) else { throw TraceRookError.malformedInput }
        }
    }

    mutating func array(depth: Int) throws {
        index += 1; whitespace()
        if consume(93) { return }
        var count = 0
        while true {
            count += 1
            guard count <= WireLimits.arrayElements else { throw TraceRookError.oversizedInput }
            try value(depth: depth); whitespace()
            if consume(93) { return }
            guard consume(44) else { throw TraceRookError.malformedInput }
        }
    }

    mutating func string(decodeKey: Bool) throws -> String {
        let start = index
        guard consume(34) else { throw TraceRookError.malformedInput }
        let contentStart = index
        while index < bytes.count {
            guard index - contentStart <= WireLimits.stringBytes else { throw TraceRookError.oversizedInput }
            if index % 1_024 == 0 { try WireCodec.checkDeadline(deadline) }
            let byte = bytes[index]; index += 1
            if byte == 34 {
                guard index - contentStart - 1 <= WireLimits.stringBytes else { throw TraceRookError.oversizedInput }
                if !decodeKey { return "" }
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<index])) }
                catch { throw TraceRookError.malformedInput }
            }
            guard byte >= 32 else { throw TraceRookError.malformedInput }
            if byte == 92 {
                guard index < bytes.count else { throw TraceRookError.malformedInput }
                let escape = bytes[index]; index += 1
                if escape == 117 {
                    guard bytes.count - index >= 4, bytes[index..<index + 4].allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { throw TraceRookError.malformedInput }
                    index += 4
                } else if ![34, 47, 92, 98, 102, 110, 114, 116].contains(escape) {
                    throw TraceRookError.malformedInput
                }
            }
        }
        throw TraceRookError.malformedInput
    }

    mutating func whitespace() {
        while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
    }
    mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1; return true
    }
}
