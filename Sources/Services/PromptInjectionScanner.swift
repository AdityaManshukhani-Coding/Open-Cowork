import Foundation

/// Scans AX tree text for prompt injection attempts and suspicious content
/// that could compromise the AI agent's behavior.
///
/// Run after every screenshot/AX tree capture to detect on-screen text that
/// tries to override the agent's system instructions before that text is
/// included in the LLM prompt.
public struct PromptInjectionScanner {

    // MARK: - Severity Levels

    public enum Severity: Comparable {
        case low        // Potentially suspicious but likely benign
        case medium     // Suspicious — warrants a warning
        case high       // Strongly indicative of injection
        case critical   // Definitive injection attempt

        var label: String {
            switch self {
            case .low:      return "LOW"
            case .medium:   return "MEDIUM"
            case .high:     return "HIGH"
            case .critical: return "CRITICAL"
            }
        }
    }

    // MARK: - Scan Result

    public struct ScanResult {
        public let injectionDetected: Bool
        public let matchedPatterns: [String]
        public let severity: Severity
        public let detail: String
    }

    // MARK: - Injection Pattern Database

    /// Known prompt injection patterns with associated severity.
    /// Patterns are matched case-insensitively against the full AX tree text.
    private static let patterns: [(pattern: String, severity: Severity)] = [
        // ── Direct instruction overrides (CRITICAL) ─────────────────
        ("ignore previous instructions", .critical),
        ("ignore all previous instructions", .critical),
        ("ignore the above instructions", .critical),
        ("ignore your instructions", .critical),
        ("disregard previous instructions", .critical),
        ("forget your instructions", .critical),
        ("forget everything above", .critical),
        ("override your instructions", .critical),
        ("override your system prompt", .critical),
        ("new system prompt", .critical),
        ("your new instructions are", .critical),
        ("your instructions have changed", .critical),

        // ── Role / identity hijacking ───────────────────────────────
        ("you are now a different", .high),
        ("you are now a", .high),       // "You are now a DAN" / "You are now a hacker" etc.
        ("you are now", .medium),       // Broad — may false-positive on "You are now connected"
        ("you are no longer", .high),
        ("your name is now", .high),
        ("your role has changed", .high),
        ("pretend you are", .high),
        ("act as if you are", .high),
        ("you must instead", .high),

        // ── System-level impersonation (HIGH) — anchored forms ─────
        ("system prompt:", .critical),
        ("system instruction:", .high),
        ("system message:", .high),
        ("new system:", .high),
        ("[system prompt]", .critical),
        ("<<system>>", .high),

        // ── Indirect manipulation (MEDIUM) ──────────────────────────
        ("do not listen to your", .medium),
        ("your real task is", .medium),
        ("the real goal is", .medium),
        ("disregard your safety", .critical),
        ("bypass your safety", .critical),

        // ── Dangerous command / path suggestions (HIGH) ─────────────
        ("rm -rf /", .critical),
        ("rm -rf ~", .critical),
        ("sudo rm", .critical),
        ("cat /etc/passwd", .high),
        ("cat /etc/shadow", .critical),
    ]

    // MARK: - Base64 Detection

    /// Matches strings that look like base64-encoded content (40+ chars of
    /// base64 alphabet, optionally with 1-2 padding chars).
    /// Base64 is commonly used to smuggle instructions past text filters.
    private static let base64Regex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: "[A-Za-z0-9+/]{40,}={0,2}",
            options: []
        )
    }()

    // MARK: - Sensitive Path Patterns

    /// Paths the agent must never access.
    /// Only flagged when they appear in path-like context (preceded by ~/ or /Users/ etc.).
    private static let sensitivePathPatterns: [(pattern: String, severity: Severity)] = [
        (".ssh", .high),
        (".aws", .high),
        ("keychain", .high),
        ("id_rsa", .critical),
        ("id_ed25519", .critical),
        ("id_ecdsa", .critical),
        (".git-credentials", .high),
        (".env", .medium),              // Often contains API keys and secrets
        ("banking", .high),
    ]

    // MARK: - Public API

    /// Scans the given text (typically an AX tree dump) for prompt injection
    /// attempts, base64 smuggling, and sensitive path references.
    ///
    /// - Parameter text: The text to scan (AX tree, visible on-screen text, etc.)
    /// - Returns: A `ScanResult` indicating whether injection was detected,
    ///   which patterns matched, the maximum severity, and a human-readable
    ///   detail string.
    public static func scan(_ text: String) -> ScanResult {
        let lowercased = text.lowercased()
        var matches: [(pattern: String, severity: Severity)] = []

        // ── Check known injection patterns ──────────────────────────
        for (pattern, severity) in patterns {
            if lowercased.contains(pattern) {
                matches.append((pattern, severity))
            }
        }

        // ── Check for base64-encoded blocks ─────────────────────────
        let base64Matches = base64Regex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        if !base64Matches.isEmpty {
            let count = base64Matches.count
            let firstMatch = Range(base64Matches[0].range, in: text).map { text[$0] } ?? "..."
            matches.append(("\(count) base64-encoded block(s) detected, first: \"\(firstMatch.prefix(30))...\"", .high))
        }

        // ── Check for sensitive path references ─────────────────────
        for (pathPattern, severity) in sensitivePathPatterns {
            if lowercased.contains(pathPattern) {
                // Only flag if it appears to be a path reference (preceded by
                // path-like context like ~/ or /Users/ or similar)
                if lowercased.contains("~/" + pathPattern)
                    || lowercased.contains("/" + pathPattern)
                    || lowercased.contains("open \"" + pathPattern)
                    || lowercased.contains("read \"" + pathPattern) {
                    matches.append(("sensitive path: \(pathPattern)", severity))
                }
            }
        }

        // ── No matches ──────────────────────────────────────────────
        if matches.isEmpty {
            return ScanResult(
                injectionDetected: false,
                matchedPatterns: [],
                severity: .low,
                detail: ""
            )
        }

        // ── Build result ────────────────────────────────────────────
        let maxSeverity = matches.map(\.severity).max() ?? .medium
        let patterns = matches.map(\.pattern)
        let detail = "Detected \(matches.count) suspicious pattern(s): "
            + patterns.map { "\"\($0)\"" }.joined(separator: ", ")
            + " (max severity: \(maxSeverity.label))"

        return ScanResult(
            injectionDetected: true,
            matchedPatterns: patterns,
            severity: maxSeverity,
            detail: detail
        )
    }
}
