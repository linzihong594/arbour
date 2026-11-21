import Foundation

/// Lightweight, zero-dependency Chinese/English localization helper driven by macOS system language
/// (with an optional `--lang en|zh` launch flag for deterministic testing).
enum L10n {
    static let isEnglish: Bool = {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--lang"), args.indices.contains(index + 1) {
            let override = args[index + 1].lowercased()
            if override.hasPrefix("en") { return true }
            if override.hasPrefix("zh") { return false }
        }
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return false
        }
        return !preferred.hasPrefix("zh")
    }()

    static var locale: Locale {
        Locale(identifier: isEnglish ? "en_US" : "zh_CN")
    }

    static func tr(_ zh: String, _ en: String) -> String {
        isEnglish ? en : zh
    }
}
