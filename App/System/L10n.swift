import Foundation

/// 앱 언어 — 시스템을 따르거나 한국어·영어로 고정
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ko, en
    var id: String { rawValue }

    /// 언어 이름은 각자 자기 말로 보여준다.
    var label: String {
        switch self {
        case .system: return tr("시스템")
        case .ko:     return "한국어"
        case .en:     return "English"
        }
    }
}

/// 원문(한국어)을 키로 쓰고 영어는 en.lproj/Localizable.strings에서 찾는다.
enum L10n {
    static var language: AppLanguage {
        UserDefaults.standard.string(forKey: "app_language").flatMap(AppLanguage.init) ?? .system
    }

    /// 실제로 쓰는 언어 코드 — 시스템이 한국어가 아니면 영어
    static var resolved: String {
        switch language {
        case .ko: return "ko"
        case .en: return "en"
        case .system:
            return (Locale.preferredLanguages.first ?? "en").hasPrefix("ko") ? "ko" : "en"
        }
    }

    static var locale: Locale { Locale(identifier: resolved == "ko" ? "ko_KR" : "en_US") }

    private static let enBundle = Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))

    static func string(_ key: String) -> String {
        guard resolved == "en", let b = enBundle else { return key }
        return b.localizedString(forKey: key, value: key, table: nil)
    }
}

func tr(_ key: String) -> String { L10n.string(key) }

func trf(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.string(key), locale: L10n.locale, arguments: args)
}
