import Foundation
import os

/// The languages Dustpan speaks. English is the source; every other language is a table in
/// `Translations.swift` keyed by the English text.
public enum Language: String, CaseIterable, Sendable, Identifiable {
    case english = "en"
    case turkish = "tr"

    public var id: String { rawValue }

    /// The language's name in that language, for pickers.
    public var nativeName: String {
        switch self {
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }

    /// The first of the user's preferred languages that Dustpan speaks, else English.
    public static var system: Language {
        // Read the global setting: an app-level override would otherwise hide what "system" means.
        let global = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleLanguages"] as? [String]
        return matching(global ?? Locale.preferredLanguages) ?? .english
    }

    /// The first language in `codes` (like `tr-TR` or `en`) that Dustpan speaks.
    public static func matching(_ codes: [String]) -> Language? {
        for code in codes {
            let base = code.split(separator: "-").first.map(String.init)?.lowercased() ?? code
            if let language = Language(rawValue: base) { return language }
        }
        return nil
    }
}

public enum Localization {
    private static let current = OSAllocatedUnfairLock(initialState: Language.system)

    /// The language `L(_:)` translates into. Set once at launch, or when the user picks another one.
    public static var language: Language {
        get { current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    /// `key` in `language`. Falls back to the English key when a translation is missing.
    public static func translate(_ key: String, to language: Language = language) -> String {
        switch language {
        case .english: key
        case .turkish: Translations.turkish[key] ?? key
        }
    }

    /// Upper-cases with the language's rules, so Turkish "incele" becomes "İNCELE" and not "INCELE".
    public static func uppercased(_ text: String, in language: Language = language) -> String {
        text.uppercased(with: language.locale)
    }

    public static func lowercased(_ text: String, in language: Language = language) -> String {
        text.lowercased(with: language.locale)
    }

    /// Translates `key` and fills its `%@` placeholders.
    public static func format(_ key: String, _ arguments: [String], in language: Language = language) -> String {
        String(format: translate(key, to: language), arguments: arguments.map { $0 as CVarArg })
    }
}

/// Translates English UI text into the current language.
public func L(_ key: String) -> String {
    Localization.translate(key)
}

/// Translates a format string whose placeholders are all `%@` (or positional `%1$@`), then fills them in.
public func L(_ key: String, _ arguments: String...) -> String {
    Localization.format(key, arguments)
}
