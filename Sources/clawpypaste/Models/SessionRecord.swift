import Foundation

// Minimal Codable shapes for the records we care about in session.jsonl.
// Records we don't care about (mode, permission-mode, ai-title, etc.) fall
// through SessionRecord.other and are ignored by the extractor.

struct SessionRecord: Decodable {
    let type: String
    let timestamp: Date?
    let message: Message?
    let uuid: String?
    let parentUuid: String?

    struct Message: Decodable {
        let role: String?
        let content: ContentField?
    }

    enum ContentField: Decodable {
        case text(String)
        case parts([ContentPart])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                self = .text(s)
            } else if let parts = try? c.decode([ContentPart].self) {
                self = .parts(parts)
            } else {
                self = .parts([])
            }
        }
    }

    struct ContentPart: Decodable {
        let type: String
        let text: String?
        let thinking: String?
        let name: String?               // tool_use name
        let input: AnyJSON?             // tool_use input (heterogeneous)
        let toolUseId: String?
        let content: ToolResultContent? // tool_result content
        let isError: Bool?

        enum CodingKeys: String, CodingKey {
            case type, text, thinking, name, input, content
            case toolUseId = "tool_use_id"
            case isError = "is_error"
        }
    }

    // tool_result.content is either a string or an array of parts.
    enum ToolResultContent: Decodable {
        case text(String)
        case parts([ContentPart])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                self = .text(s)
            } else if let parts = try? c.decode([ContentPart].self) {
                self = .parts(parts)
            } else {
                self = .text("")
            }
        }

        var asString: String {
            switch self {
            case .text(let s): return s
            case .parts(let parts):
                return parts.compactMap { $0.text }.joined(separator: "\n")
            }
        }
    }
}

// Loose JSON for tool_use inputs whose schema varies by tool.
enum AnyJSON: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: AnyJSON])
    case array([AnyJSON])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self)   { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([String: AnyJSON].self) { self = .object(v); return }
        if let v = try? c.decode([AnyJSON].self) { self = .array(v); return }
        self = .null
    }

    var stringValue: String? {
        if case .string(let s) = self { return s } else { return nil }
    }

    subscript(key: String) -> AnyJSON? {
        if case .object(let dict) = self { return dict[key] } else { return nil }
    }
}
