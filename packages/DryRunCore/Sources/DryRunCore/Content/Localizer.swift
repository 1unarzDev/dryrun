import Foundation

public enum TranslationReviewState: String, Codable, Sendable, Hashable, Comparable {
    case reviewed, draft, missing
    private var rank: Int { switch self { case .reviewed: 0; case .draft: 1; case .missing: 2 } }
    public static func < (a: Self, b: Self) -> Bool { a.rank < b.rank }
}

public struct LocaleManifest: Codable, Sendable, Hashable {
    public struct Entry: Codable, Sendable, Hashable {
        public var code: String
        public var name: String
        public var nativeName: String
        public var domains: [String: TranslationReviewState]
        public var note: String?
    }
    public var schemaVersion: Int
    public var sourceLocale: String
    public var locales: [Entry]
    public func entry(_ code: String) -> Entry? { locales.first { $0.code == code } }
}

/// A resolved string plus everything a viewer needs to label it honestly.
public struct LocalizedText: Sendable, Hashable {
    public var key: String
    public var text: String
    public var requestedLocale: String
    /// The locale the text actually came from. Differs from `requestedLocale` on fallback.
    public var resolvedLocale: String
    public var reviewState: TranslationReviewState
    /// Key absent in every locale (a content bug; tests assert none are emitted).
    public var isMissing: Bool
    /// Template placeholders that had no value (a content/code bug, distinct from braces in user-entered values).
    public var unfilledPlaceholders: [String] = []
    public var isFallback: Bool { resolvedLocale != requestedLocale }
    /// Must the viewer/PDF show "Draft translation - language review pending"?
    public var needsDraftLabel: Bool { resolvedLocale != "en" && reviewState != .reviewed }
}

/// Resolves keys from versioned locale packs. Never silently shows English under another label:
/// fallback is reported on every `LocalizedText`.
public struct Localizer: Sendable {
    public let locale: String
    public let sourceLocale: String
    /// locale -> domain -> key -> text
    private let tables: [String: [String: [String: String]]]
    private let manifest: LocaleManifest?

    public init(locale: String, tables: [String: [String: [String: String]]], manifest: LocaleManifest?, sourceLocale: String = "en") {
        self.locale = locale; self.tables = tables; self.manifest = manifest; self.sourceLocale = sourceLocale
    }

    public func with(locale: String) -> Localizer {
        Localizer(locale: locale, tables: tables, manifest: manifest, sourceLocale: sourceLocale)
    }

    public var availableLocales: [String] { tables.keys.sorted() }

    public func text(_ key: String, _ values: [String: String] = [:]) -> LocalizedText {
        for candidate in [locale, sourceLocale] {
            guard let domains = tables[candidate] else { continue }
            for domain in domains.keys.sorted() {
                if let raw = domains[domain]?[key] {
                    return LocalizedText(key: key, text: Self.fill(raw, values), requestedLocale: locale,
                                         resolvedLocale: candidate, reviewState: reviewState(candidate, domain), isMissing: false,
                                         unfilledPlaceholders: Self.placeholders(in: raw).subtracting(values.keys).sorted())
                }
            }
        }
        return LocalizedText(key: key, text: key, requestedLocale: locale, resolvedLocale: sourceLocale,
                             reviewState: .missing, isMissing: true)
    }

    /// Convenience for UI code that only needs the string.
    public func callAsFunction(_ key: String, _ values: [String: String] = [:]) -> String { text(key, values).text }

    public func has(_ key: String, in locale: String) -> Bool {
        tables[locale]?.values.contains { $0[key] != nil } ?? false
    }

    public func reviewState(_ locale: String, _ domain: String) -> TranslationReviewState {
        if let state = manifest?.entry(locale)?.domains[domain] { return state }
        // Without a manifest entry nothing is considered reviewed.
        return tables[locale]?[domain] == nil ? .missing : .draft
    }

    public func allKeys(in locale: String) -> Set<String> {
        Set(tables[locale]?.values.flatMap { $0.keys } ?? [])
    }

    /// Replaces `{name}` placeholders in a single left-to-right pass, so substituted values (which may contain braces)
    /// are never re-expanded. Unknown placeholders are left visible rather than dropped.
    public static func fill(_ template: String, _ values: [String: String]) -> String {
        guard !values.isEmpty, template.contains("{") else { return template }
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            if template[i] == "{", let close = template[i...].firstIndex(of: "}") {
                let name = String(template[template.index(after: i)..<close])
                if let v = values[name], !name.contains("{") {
                    out += v
                    i = template.index(after: close)
                    continue
                }
            }
            out.append(template[i])
            i = template.index(after: i)
        }
        return out
    }

    public static func placeholders(in template: String) -> Set<String> {
        var result = Set<String>()
        var current: String?
        for ch in template {
            if ch == "{" { current = "" } else if ch == "}" { if let c = current, !c.isEmpty { result.insert(c) }; current = nil }
            else if current != nil { current!.append(ch) }
        }
        return result
    }
}
