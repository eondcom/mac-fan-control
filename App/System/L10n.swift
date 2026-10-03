import Foundation

/// 앱 언어 — 시스템을 따르거나 한국어·영어·일본어로 고정
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ko, en, ja
    var id: String { rawValue }

    /// 언어 이름은 각자 자기 말로 보여준다.
    var label: String {
        switch self {
        case .system: return tr("시스템")
        case .ko:     return "한국어"
        case .en:     return "English"
        case .ja:     return "日本語"
        }
    }
}

/// 원문(한국어)을 키로 쓰고 영어·일본어는 en·ja.lproj/Localizable.strings에서 찾는다.
enum L10n {
    static var language: AppLanguage {
        UserDefaults.standard.string(forKey: "app_language").flatMap(AppLanguage.init) ?? .system
    }

    /// 실제로 쓰는 언어 코드 — 시스템이 한국어·일본어가 아니면 영어
    static var resolved: String {
        switch language {
        case .ko: return "ko"
        case .en: return "en"
        case .ja: return "ja"
        case .system:
            let first = Locale.preferredLanguages.first ?? "en"
            if first.hasPrefix("ko") { return "ko" }
            if first.hasPrefix("ja") { return "ja" }
            return "en"
        }
    }

    static var locale: Locale {
        switch resolved {
        case "ko": return Locale(identifier: "ko_KR")
        case "ja": return Locale(identifier: "ja_JP")
        default:   return Locale(identifier: "en_US")
        }
    }

    private static let bundles: [String: Bundle] = Dictionary(uniqueKeysWithValues: ["en", "ja"].compactMap { code in
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)).map { (code, $0) }
    })

    static func string(_ key: String) -> String {
        guard let b = bundles[resolved] else { return key }
        return b.localizedString(forKey: key, value: key, table: nil)
    }
}

func tr(_ key: String) -> String { L10n.string(key) }

func trf(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.string(key), locale: L10n.locale, arguments: args)
}
