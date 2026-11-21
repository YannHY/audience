import Foundation

/// Keeps fields from web/Electron backups, including formats not edited by this version.
public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public var object: [String: JSONValue] { if case .object(let v) = self { v } else { [:] } }
    public var array: [JSONValue] { if case .array(let v) = self { v } else { [] } }
    public var string: String { if case .string(let v) = self { v } else { "" } }
    public var int: Int { if case .number(let v) = self, v.isFinite, v < Double(Int.max), v > Double(Int.min) { Int(v) } else { Int(string) ?? 0 } }
    public var double: Double { if case .number(let v) = self { v } else { Double(string) ?? 0 } }
    public var bool: Bool {
        switch self {
        case .bool(let v): v
        case .number(let v): v != 0
        case .string(let v): ["true", "1"].contains(v.lowercased())
        default: false
        }
    }
    public subscript(_ key: String) -> JSONValue { object[key] ?? .null }
}

public extension String {
    var unformattedText: String {
        replacingOccurrences(of: "<br\\s*/?>|</(?:p|div|li)>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .decodingHTMLEntities
    }
    /// Decodes named and numeric entities (&#39;, &#x27;, &rsquo;…) in one pass, so "&amp;#39;" stays "&#39;".
    var decodingHTMLEntities: String {
        guard contains("&") else { return self }
        var result = "", rest = self[...]
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let tail = rest[amp...]
            if let semicolon = tail.prefix(12).firstIndex(of: ";"),
               let decoded = Self.entity(tail[tail.index(after: amp)..<semicolon]) {
                result += decoded
                rest = tail[tail.index(after: semicolon)...]
            } else {
                result += "&"
                rest = tail.dropFirst()
            }
        }
        return result + rest
    }
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "rsquo": "\u{2019}", "lsquo": "\u{2018}", "rdquo": "\u{201D}", "ldquo": "\u{201C}",
        "laquo": "\u{00AB}", "raquo": "\u{00BB}", "hellip": "\u{2026}", "ndash": "\u{2013}", "mdash": "\u{2014}",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "agrave": "à", "acirc": "â", "ccedil": "ç",
        "ocirc": "ô", "ucirc": "û", "ugrave": "ù", "icirc": "î", "iuml": "ï", "euml": "ë", "oelig": "œ",
        "Eacute": "É", "Agrave": "À", "Ccedil": "Ç", "deg": "°", "times": "×", "divide": "÷"
    ]
    private static func entity(_ name: Substring) -> String? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst(), radix: 10).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[String(name)]
    }
    var plainText: String { unformattedText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }
}
