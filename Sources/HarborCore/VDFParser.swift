import Foundation

public indirect enum VDFValue: Equatable {
    case string(String), object([String: VDFValue])
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var object: [String: VDFValue]? { if case .object(let value) = self { return value }; return nil }
    public subscript(_ key: String) -> VDFValue? {
        object?.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
    }
}

/// Minimal Valve text KeyValues parser. Never reads Steam account or ticket files.
public enum VDFParser {
    public static func parse(_ text: String) throws -> VDFValue {
        var lexer = Lexer(chars: Array(text))
        return .object(try lexer.object(nested: false, depth: 0))
    }
    private struct Lexer {
        var chars: [Character]; var index = 0
        mutating func skip() {
            while index < chars.count {
                if chars[index].isWhitespace || chars[index] == "\u{feff}" { index += 1; continue }
                if chars[index] == "/", index + 1 < chars.count, chars[index + 1] == "/" {
                    while index < chars.count && chars[index] != "\n" { index += 1 }
                    continue
                }
                break
            }
        }
        mutating func token() throws -> String? {
            skip(); guard index < chars.count else { return nil }
            let first = chars[index]; index += 1
            if first == "{" || first == "}" { return String(first) }
            if first == "\"" {
                var result = ""
                while index < chars.count {
                    let c = chars[index]; index += 1
                    if c == "\"" { return result }
                    if c == "\\", index < chars.count {
                        let next = chars[index]; index += 1
                        if next == "\\" || next == "\"" { result.append(next) }
                        else { result.append("\\"); result.append(next) }
                    } else { result.append(c) }
                }
                throw HarborError.invalid("Steam 配置中的引号未闭合。")
            }
            var result = String(first)
            while index < chars.count && !chars[index].isWhitespace && chars[index] != "{" && chars[index] != "}" {
                result.append(chars[index]); index += 1
            }
            return result
        }
        mutating func object(nested: Bool, depth: Int) throws -> [String: VDFValue] {
            guard depth < 32 else { throw HarborError.invalid("Steam 配置嵌套过深。") }
            var result: [String: VDFValue] = [:]
            while let key = try token() {
                if key == "}" {
                    guard nested else { throw HarborError.invalid("Steam 配置括号不匹配。") }; return result
                }
                guard key != "{", let value = try token(), value != "}" else { throw HarborError.invalid("Steam 配置缺少值。") }
                result[key] = value == "{" ? .object(try object(nested: true, depth: depth + 1)) : .string(value)
            }
            if nested { throw HarborError.invalid("Steam 配置未完整写入，请稍后刷新。") }
            return result
        }
    }
}
