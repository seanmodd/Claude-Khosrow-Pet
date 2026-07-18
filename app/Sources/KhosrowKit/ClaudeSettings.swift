import Foundation

/// Idempotent injection and removal of the pet's hooks inside a Claude Code
/// `settings.json`, expressed as pure `JSONValue` transforms so the installer
/// and the tests share one algorithm.
///
/// Claude Code hook shape:
/// ```
/// { "hooks": { "<Event>": [ { "matcher": "<glob>",
///                             "hooks": [ { "type": "command", "command": "…" } ] } ] } }
/// ```
/// The installer never overwrites the file — it merges: existing keys and hooks
/// are preserved, and our own hooks are tagged so re-running refreshes rather
/// than duplicates them.
public enum ClaudeSettings {

    /// Substring embedded in every pet hook command so we can find/refresh/remove
    /// exactly our own entries and nothing else.
    public static let marker = "KHOSROW_PET_HOOK"

    public struct HookBinding {
        public let event: String
        public let matcher: String
        public let command: String
        public init(event: String, matcher: String, command: String) {
            self.event = event; self.matcher = matcher; self.command = command
        }
    }

    /// True if a single hook entry object is one of ours (command contains marker).
    static func isPetHookEntry(_ entry: JSONValue) -> Bool {
        (entry["command"]?.stringValue ?? "").contains(marker)
    }

    /// True if a matcher-group contains any pet hook entry.
    static func isPetGroup(_ group: JSONValue) -> Bool {
        (group["hooks"]?.arrayValue ?? []).contains(where: isPetHookEntry)
    }

    private static func hookEntry(command: String) -> JSONValue {
        .object(["type": .string("command"), "command": .string(command)])
    }

    private static func group(matcher: String, command: String) -> JSONValue {
        .object([
            "matcher": .string(matcher),
            "hooks": .array([hookEntry(command: command)]),
        ])
    }

    /// Merge our hooks into `settings`, preserving everything else. Idempotent:
    /// existing pet groups (by marker) are replaced, user groups are untouched.
    public static func installHooks(into settings: JSONValue,
                                    bindings: [HookBinding]) -> JSONValue {
        var root = settings.objectValue ?? [:]
        var hooks = root["hooks"]?.objectValue ?? [:]

        // Group our bindings by event.
        var byEvent: [String: [HookBinding]] = [:]
        for b in bindings { byEvent[b.event, default: []].append(b) }

        for (event, evBindings) in byEvent {
            var groups = hooks[event]?.arrayValue ?? []
            // Drop any of our previous groups for this event (refresh semantics).
            groups.removeAll(where: isPetGroup)
            // Append fresh pet groups.
            for b in evBindings {
                groups.append(group(matcher: b.matcher, command: b.command))
            }
            hooks[event] = .array(groups)
        }

        root["hooks"] = .object(hooks)
        return .object(root)
    }

    /// Remove every pet hook, leaving all other settings and hooks intact.
    /// Cleans up now-empty groups/events/`hooks` so the file returns to its
    /// original shape when nothing else uses hooks.
    public static func removeHooks(from settings: JSONValue) -> JSONValue {
        guard var root = settings.objectValue else { return settings }
        guard var hooks = root["hooks"]?.objectValue else { return settings }

        for (event, value) in hooks {
            guard var groups = value.arrayValue else { continue }
            groups.removeAll(where: isPetGroup)
            if groups.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = .array(groups)
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = .object(hooks)
        }
        return .object(root)
    }

    /// Count pet hook entries across all events (used by tests / dry-run output).
    public static func petHookCount(in settings: JSONValue) -> Int {
        guard let hooks = settings["hooks"]?.objectValue else { return 0 }
        var count = 0
        for (_, value) in hooks {
            for group in value.arrayValue ?? [] {
                for entry in group["hooks"]?.arrayValue ?? [] where isPetHookEntry(entry) {
                    count += 1
                }
            }
        }
        return count
    }
}
