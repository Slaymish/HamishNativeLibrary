import Foundation

public enum InterchangeError: Error, LocalizedError, Sendable {
    case invalid(String)
    case stalePreview
    public var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .stalePreview: "Data changed since this preview. Refresh it before applying."
        }
    }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

/// A deliberately small schema DSL, not a general JSON Schema interpreter.
/// Objects always reject unknown fields, including nested objects.
public indirect enum PayloadSchema: Sendable {
    case object(properties: [String: PayloadSchema], required: Set<String>)
    case array(items: PayloadSchema, maximum: Int)
    case string(maximum: Int, choices: Set<String>? = nil)
    case integer(minimum: Int, maximum: Int)
    case boolean
    case nullable(PayloadSchema)

    func validateDefinition(depth: Int = 0) throws {
        guard depth <= 32 else { throw InterchangeError.invalid("Schema is nested too deeply.") }
        switch self {
        case let .object(properties, required):
            guard required.isSubset(of: Set(properties.keys)) else { throw InterchangeError.invalid("Schema requires an undefined property.") }
            for schema in properties.values { try schema.validateDefinition(depth: depth + 1) }
        case let .array(items, maximum):
            guard maximum >= 0 else { throw InterchangeError.invalid("Invalid array limit.") }
            try items.validateDefinition(depth: depth + 1)
        case let .string(maximum, choices):
            guard maximum >= 0, choices?.allSatisfy({ $0.count <= maximum }) ?? true else { throw InterchangeError.invalid("Invalid string limit.") }
        case let .integer(minimum, maximum):
            guard minimum <= maximum else { throw InterchangeError.invalid("Invalid integer range.") }
        case .boolean: break
        case let .nullable(schema): try schema.validateDefinition(depth: depth + 1)
        }
    }

    public func validate(_ value: JSONValue, path: String = "$", depth: Int = 0) throws {
        guard depth <= 32 else { throw InterchangeError.invalid("JSON is nested too deeply.") }
        func fail() throws -> Never { throw InterchangeError.invalid("Invalid value at \(path).") }
        switch (self, value) {
        case let (.object(properties, required), .object(object)):
            guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: Set(properties.keys)) else {
                throw InterchangeError.invalid("Missing or unknown fields at \(path).")
            }
            for (key, value) in object {
                try properties[key]!.validate(value, path: path + "." + key, depth: depth + 1)
            }
        case let (.array(items, maximum), .array(values)):
            guard values.count <= maximum else { try fail() }
            for (index, value) in values.enumerated() {
                try items.validate(value, path: "\(path)[\(index)]", depth: depth + 1)
            }
        case let (.string(maximum, choices), .string(text)):
            guard text.count <= maximum, choices == nil || choices!.contains(text) else { try fail() }
        case let (.integer(minimum, maximum), .number(number)):
            guard number.isFinite, number.rounded() == number,
                  number >= Double(minimum), number <= Double(maximum) else { try fail() }
        case (.boolean, .bool): break
        case (.nullable, .null): break
        case let (.nullable(schema), _): try schema.validate(value, path: path, depth: depth + 1)
        default: try fail()
        }
    }

    public var jsonSchema: JSONValue {
        switch self {
        case let .object(properties, required):
            return .object(["type": .string("object"), "additionalProperties": .bool(false),
                "properties": .object(properties.mapValues(\.jsonSchema)),
                "required": .array(required.sorted().map(JSONValue.string))])
        case let .array(items, maximum):
            return .object(["type": .string("array"), "items": items.jsonSchema, "maxItems": .number(Double(maximum))])
        case let .string(maximum, choices):
            var object: [String: JSONValue] = ["type": .string("string"), "maxLength": .number(Double(maximum))]
            if let choices { object["enum"] = .array(choices.sorted().map(JSONValue.string)) }
            return .object(object)
        case let .integer(minimum, maximum):
            return .object(["type": .string("integer"), "minimum": .number(Double(minimum)), "maximum": .number(Double(maximum))])
        case .boolean: return .object(["type": .string("boolean")])
        case let .nullable(schema): return .object(["anyOf": .array([schema.jsonSchema, .object(["type": .string("null")])])])
        }
    }
}
