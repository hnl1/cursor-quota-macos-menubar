import Foundation

enum JSONNode: Sendable {
    case object([String: JSONNode])
    case array([JSONNode])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
}

extension JSONNode: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONNode].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONNode].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    var object: [String: JSONNode]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value) where value == 0:
            return false
        case .number(let value) where value == 1:
            return true
        case .string(let raw):
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value) where value.isFinite:
            return value
        case .string(let raw):
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(trimmed), value.isFinite else { return nil }
            return value
        default:
            return nil
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return String(value)
        default:
            return nil
        }
    }

    func value(forNormalized aliases: [String]) -> JSONNode? {
        guard let object else { return nil }
        var normalized: [String: JSONNode] = [:]
        for (key, value) in object {
            normalized[key.normalizedJSONKey] = value
        }
        for alias in aliases {
            if let value = normalized[alias] {
                return value
            }
        }
        return nil
    }

    func firstNumber(for aliases: [String]) -> Double? {
        value(forNormalized: aliases)?.numberValue
    }

    func firstBool(for aliases: [String]) -> Bool? {
        value(forNormalized: aliases)?.boolValue
    }

    func firstDate(for aliases: [String]) -> Date? {
        guard let node = value(forNormalized: aliases) else { return nil }
        if let number = node.numberValue {
            return DateParser.date(fromUnixMagnitude: number)
        }
        if let text = node.stringValue {
            return DateParser.date(from: text)
        }
        return nil
    }

    func unwrappedCandidates(depth: Int = 0) -> [JSONNode] {
        var nodes = [self]
        guard depth < 3, let object else { return nodes }
        let wrappers: Set<String> = [
            "data", "result", "response", "currentperiodusage", "individualusage"
        ]
        for (key, value) in object where wrappers.contains(key.normalizedJSONKey) {
            nodes.append(contentsOf: value.unwrappedCandidates(depth: depth + 1))
        }
        return nodes
    }
}

enum DateParser {
    static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Double(trimmed) {
            return date(fromUnixMagnitude: number)
        }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: trimmed) {
            return date
        }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: trimmed)
    }

    static func date(fromUnixMagnitude value: Double) -> Date? {
        guard value.isFinite else { return nil }
        let magnitude = abs(value)
        let seconds: Double
        switch magnitude {
        case 100_000_000_000_000_000...:
            seconds = value / 1_000_000_000
        case 100_000_000_000_000...:
            seconds = value / 1_000_000
        case 100_000_000_000...:
            seconds = value / 1_000
        default:
            seconds = value
        }
        let date = Date(timeIntervalSince1970: seconds)
        return date.timeIntervalSinceReferenceDate.isFinite ? date : nil
    }
}

extension String {
    var normalizedJSONKey: String {
        String(lowercased().filter { $0.isLetter || $0.isNumber })
    }
}
