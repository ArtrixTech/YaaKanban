import CryptoKit
import Foundation

/// Codex runs a hook from `hooks.json` only after the user trusts it in `/hooks`. Trust is stored in
/// `config.toml` as `[hooks.state."<hooks.json path>:<event>:<group>:<handler>"]` with
/// `trusted_hash`, a hash of the hook's normalized definition, and `enabled`. This mirrors
/// codex-rs `hooks/src/engine/discovery.rs` so the app can tell which of our hooks still wait.
enum CodexTrust {
    enum State: Equatable { case trusted, modified, untrusted, disabled }

    /// Codex's snake_case event labels; events it does not know are not run at all.
    static let labels: [String: String] = [
        "PreToolUse": "pre_tool_use", "PermissionRequest": "permission_request", "PostToolUse": "post_tool_use",
        "SessionStart": "session_start", "SessionEnd": "session_end", "UserPromptSubmit": "user_prompt_submit",
        "SubagentStart": "subagent_start", "SubagentStop": "subagent_stop", "Stop": "stop",
        "Interrupt": "interrupt", "PreCompact": "pre_compact", "PostCompact": "post_compact",
    ]

    /// Whether `config.toml` turns the hooks feature off, which stops every hook regardless of trust.
    static func hooksOff(home: URL) -> Bool {
        featureDisabled(Installer.read(home.appendingPathComponent(".codex/config.toml")) ?? "")
    }

    /// The state of each of our hooks in `hooks.json`, keyed by event name.
    static func states(home: URL) -> [(event: String, state: State)] {
        let hooksFile = home.appendingPathComponent(".codex/hooks.json")
        guard let root = try? JSONFile.load(hooksFile).root, let hooks = root["hooks"] as? [String: Any] else { return [] }
        let config = Installer.read(home.appendingPathComponent(".codex/config.toml")) ?? ""
        let saved = readState(config)
        var out: [(String, State)] = []
        for (event, groups) in hooks.sorted(by: { $0.key < $1.key }) {
            guard let label = labels[event], let groups = groups as? [[String: Any]] else { continue }
            for (g, group) in groups.enumerated() {
                for (h, handler) in (group["hooks"] as? [[String: Any]] ?? []).enumerated() {
                    guard HookCommand.isOurs(handler["command"] as? String ?? "") else { continue }
                    let key = "\(hooksFile.path):\(label):\(g):\(h)"
                    let entry = saved[key]
                    let state: State
                    if entry?.enabled == false { state = .disabled }
                    else if let trusted = entry?.trustedHash {
                        state = trusted == hash(label: label, matcher: group["matcher"] as? String, handler: handler) ? .trusted : .modified
                    } else { state = .untrusted }
                    out.append((event, state))
                }
            }
        }
        return out
    }

    /// `sha256:` of the compact, key-sorted JSON of `{event_name, matcher?, hooks: [handler]}`.
    static func hash(label: String, matcher: String?, handler: [String: Any]) -> String {
        var h: [String: Any] = ["type": "command", "command": handler["command"] as? String ?? "",
                                "async": handler["async"] as? Bool ?? false]
        let timeout = handler["timeout"] as? Int
        // Codex bounds the hooks that run while it shuts down.
        h["timeout"] = label == "session_end" || label == "interrupt" ? min(max(timeout ?? 1, 1), 3) : max(timeout ?? 600, 1)
        if let s = handler["statusMessage"] as? String { h["statusMessage"] = s }
        if let limit = handler["additionalContextLimit"] as? Int, limit != 2500,
           ["pre_tool_use", "post_tool_use", "session_start", "user_prompt_submit", "subagent_start"].contains(label) {
            h["additionalContextLimit"] = limit
        }
        var identity: [String: Any] = ["event_name": label, "hooks": [h]]
        // A matcher means nothing to these events, so Codex leaves it out.
        if let matcher, label != "user_prompt_submit", label != "stop" { identity["matcher"] = matcher }
        let data = try! JSONSerialization.data(withJSONObject: identity, options: [.sortedKeys, .withoutEscapingSlashes])
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// `[hooks.state."key"]` tables in `config.toml`, the only form Codex writes.
    static func readState(_ toml: String) -> [String: (trustedHash: String?, enabled: Bool?)] {
        var out: [String: (trustedHash: String?, enabled: Bool?)] = [:]
        var current: String?
        for raw in toml.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                current = nil
                let prefix = "[hooks.state.\""
                // The header may carry a trailing comment: `[hooks.state."k"] # note`.
                guard line.hasPrefix(prefix), let close = line.range(of: "\"]", options: .backwards),
                      line[close.upperBound...].trimmingCharacters(in: .whitespaces).first.map({ $0 == "#" }) ?? true
                else { continue }
                current = unescape(String(line[line.index(line.startIndex, offsetBy: prefix.count)..<close.lowerBound]))
                out[current!] = (nil, nil)
                continue
            }
            guard let key = current, let eq = line.firstIndex(of: "=") else { continue }
            let name = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if name == "trusted_hash", value.hasPrefix("\""), let end = value.dropFirst().firstIndex(of: "\"") {
                out[key]?.trustedHash = String(value[value.index(after: value.startIndex)..<end])
            } else if name == "enabled" {
                out[key]?.enabled = value.hasPrefix("true") ? true : value.hasPrefix("false") ? false : nil
            }
        }
        return out
    }

    /// `hooks = false` under `[features]` turns every hook off.
    static func featureDisabled(_ toml: String) -> Bool {
        var inFeatures = false
        for raw in toml.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inFeatures = line == "[features]"; continue }
            let compact = line.replacingOccurrences(of: " ", with: "")
            if inFeatures, compact.hasPrefix("hooks=false") || compact.hasPrefix("codex_hooks=false") { return true }
            if compact.hasPrefix("features.hooks=false") || compact.hasPrefix("features.codex_hooks=false") { return true }
        }
        return false
    }

    private static func unescape(_ s: String) -> String {
        var out = "", escaped = false
        for c in s {
            if escaped { out.append(c); escaped = false } else if c == "\\" { escaped = true } else { out.append(c) }
        }
        return out
    }
}
