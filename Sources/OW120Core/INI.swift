import Foundation

/// Preserves unrelated sections, comments and account/keybinding preferences.
public enum INI {
    public static func remove(_ text: String, section: String, keys: Set<String>) -> String {
        var inSection = false
        return text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").filter { line in
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("[") { inSection = clean == "[\(section)]"; return true }
            guard inSection, !clean.hasPrefix("#"), !clean.hasPrefix(";"), let equals = clean.firstIndex(of: "=") else { return true }
            let key = String(clean[..<equals]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return !keys.contains(key)
        }.joined(separator: "\n")
    }
    public static func merge(_ text: String, section: String, values: [String: String], quotedKeys: Bool = false) -> String {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        let header = "[\(section)]"
        if !lines.contains(where: { $0.trimmingCharacters(in: .whitespaces) == header }) { lines.append(contentsOf: ["", header]) }
        var inSection = false
        var seen = Set<String>()
        var output: [String] = []
        func formatted(_ key: String) -> String {
            let value = values[key]!.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\(quotedKeys ? "\"\(key)\"" : key) = \"\(value)\""
        }
        func appendMissing() { for key in values.keys.sorted() where !seen.contains(key) { output.append(formatted(key)); seen.insert(key) } }
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("[") && clean.hasSuffix("]") {
                if inSection { appendMissing() }
                inSection = clean == header
                output.append(line); continue
            }
            if inSection, !clean.hasPrefix(";"), !clean.hasPrefix("#"), let equal = clean.firstIndex(of: "=") {
                let key = String(clean[..<equal]).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if values[key] != nil {
                    if !seen.contains(key) { output.append(formatted(key)); seen.insert(key) }
                    continue
                }
            }
            output.append(line)
        }
        if inSection { appendMissing() }
        return output.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
}

/// Wine `user.reg` sections may have a trailing timestamp after the `]`.
public enum WineReg {
    public static func set(_ text: String, section: String, values: [String: String]) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var inSection = false
        var found = false
        var seen = Set<String>()
        var output: [String] = []
        func formatted(_ key: String) -> String {
            let value = values[key]!.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(key)\"=\"\(value)\""
        }
        func appendMissing() { for key in values.keys.sorted() where !seen.contains(key) { output.append(formatted(key)); seen.insert(key) } }
        for line in lines {
            let clean = line.trimmingCharacters(in: .whitespaces)
            if clean.hasPrefix("["), let close = clean.firstIndex(of: "]") {
                if inSection { appendMissing() }
                inSection = String(clean[clean.index(after: clean.startIndex)..<close]) == section
                if inSection { found = true; seen.removeAll() }
                output.append(line)
                continue
            }
            if inSection, clean.hasPrefix("\""), let equal = clean.firstIndex(of: "=") {
                let key = String(clean[..<equal]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                if values[key] != nil {
                    if !seen.contains(key) { output.append(formatted(key)); seen.insert(key) }
                    continue
                }
            }
            output.append(line)
        }
        if inSection { appendMissing() }
        if !found {
            output.append("")
            output.append("[\(section)]")
            seen.removeAll()
            appendMissing()
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n"
    }
}
