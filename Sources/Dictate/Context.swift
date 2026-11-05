import AppKit

/// What the cleanup model is told besides the transcript: where the text is going,
/// and terms the speaker uses that speech recognition tends to mishear.
struct Context {
    var app: String?
    var window: String?
    var field: String?

    /// Read when dictation ends, while focus is still where the text will be pasted.
    static func current() -> Context {
        var context = Context(app: NSWorkspace.shared.frontmostApplication?.localizedName)
        let system = AXUIElementCreateSystemWide()
        if let app = element(system, kAXFocusedApplicationAttribute),
           let window = element(app, kAXFocusedWindowAttribute) {
            context.window = string(window, kAXTitleAttribute)
        }
        if let focused = element(system, kAXFocusedUIElementAttribute) {
            let parts = [kAXRoleAttribute, kAXSubroleAttribute, kAXDescriptionAttribute,
                         kAXPlaceholderValueAttribute, kAXIdentifierAttribute]
                .compactMap { string(focused, $0) }
            if !parts.isEmpty { context.field = parts.joined(separator: ", ") }
        }
        return context
    }

    /// One term per line in ~/Library/Application Support/Dictate/words.txt; # starts a comment.
    /// Read on every dictation so edits apply without a restart.
    static func words() -> [String] {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dictate/words.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// The model's input: context and vocabulary first, then the transcript.
    func prompt(for transcript: String) -> String {
        var lines: [String] = []
        if let app { lines.append("App: \(app)") }
        if let window, !window.isEmpty { lines.append("Window: \(window)") }
        if let field { lines.append("Field: \(field)") }
        var prompt = ""
        if !lines.isEmpty { prompt += "<context>\n\(lines.joined(separator: "\n"))\n</context>\n" }
        let words = Self.words()
        if !words.isEmpty { prompt += "<vocabulary>\n\(words.joined(separator: "\n"))\n</vocabulary>\n" }
        return prompt + "<transcript>\n\(transcript)\n</transcript>"
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}
