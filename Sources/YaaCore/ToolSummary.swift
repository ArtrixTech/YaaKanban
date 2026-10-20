import Foundation

/// One-line, human-readable summary of a tool call input, agent-agnostic.
public enum ToolSummary {
    public static let maxLength = 120

    public static func summarize(tool: String, input: JSONValue) -> String {
        let raw = full(tool: tool, input: input)
        let oneLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = oneLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > maxLength ? String(trimmed.prefix(maxLength - 1)) + "…" : trimmed
    }

    /// The untruncated text a summary is cut from.
    public static func full(tool: String, input: JSONValue) -> String {
        pick(tool: tool.lowercased(), input: input) ?? firstString(input) ?? ""
    }

    /// Full text when the summary hides part of it, for approval prompts.
    public static func detail(tool: String, input: JSONValue) -> String? {
        let f = full(tool: tool, input: input).trimmingCharacters(in: .whitespacesAndNewlines)
        return f == summarize(tool: tool, input: input) ? nil : f
    }

    private static func pick(tool: String, input: JSONValue) -> String? {
        func s(_ keys: String...) -> String? {
            for k in keys { if let v = input[k]?.string, !v.isEmpty { return v } }
            return nil
        }
        switch tool {
        case "bash", "shell", "exec_command", "local_shell", "run_terminal_cmd", "shell_command":
            if let parts = input["command"]?.array {
                return parts.compactMap(\.string).joined(separator: " ")
            }
            return s("command", "cmd")
        case "apply_patch":
            let patch = s("input", "patch") ?? input.string ?? ""
            for line in patch.split(separator: "\n") {
                for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(marker) {
                    return String(line.dropFirst(marker.count))
                }
            }
            return nil
        case "read", "write", "edit", "multiedit", "notebookedit", "view", "create", "str_replace", "delete_file":
            return s("file_path", "filePath", "path", "target_file", "notebook_path").map(shortPath)
        case "grep", "glob", "search", "codebase_search", "grep_search", "find":
            return s("pattern", "query", "glob")
        case "webfetch", "fetch":
            return s("url")
        case "websearch", "web_search":
            return s("query")
        case "task", "agent":
            return s("description", "prompt")
        case "todowrite":
            return "update todos"
        default:
            return s("command", "cmd", "file_path", "path", "url", "query", "pattern", "description")
        }
    }

    private static func firstString(_ input: JSONValue) -> String? {
        guard let o = input.object else { return input.string }
        for k in o.keys.sorted() { if let v = o[k]?.string, !v.isEmpty { return v } }
        return nil
    }

    static func shortPath(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}
