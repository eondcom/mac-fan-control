import SwiftUI
import AppKit

// EOND UI App 0.2 토큰 — https://ui.eond.com/app-colors
// 원칙: 테두리 대신 밝기(바탕 → c1 카드 → c2 겹침 → c3 선택), 색은 토큰으로만.

extension Color {
    /// 다크/라이트 한 쌍. 창의 appearance를 따라 자동으로 바뀐다.
    init(dark: UInt32, light: UInt32, darkAlpha: Double = 1, lightAlpha: Double = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green:   CGFloat((hex >> 8) & 0xFF) / 255,
                  blue:    CGFloat(hex & 0xFF) / 255,
                  alpha:   alpha)
    }
}

enum EU {
    // 층
    static let appBg  = Color(dark: 0x000000, light: 0xF4F4F5)
    static let chrome = Color(dark: 0x000000, light: 0xFFFFFF)
    static let c1     = Color(dark: 0x18181B, light: 0xFFFFFF)
    static let c2     = Color(dark: 0x27272A, light: 0xF4F4F5)
    static let c3     = Color(dark: 0x3F3F46, light: 0xE4E4E7)
    static let c4     = Color(dark: 0x52525B, light: 0xD4D4D8)

    // 글자
    static let fg  = Color(dark: 0xECEDEE, light: 0x11181C)
    static let fg2 = Color(dark: 0xD4D4D8, light: 0x3F3F46)
    static let fg3 = Color(dark: 0xA1A1AA, light: 0x71717A)
    static let fg4 = Color(dark: 0x71717A, light: 0xA1A1AA)

    // 선·호버
    static let line  = Color(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.06, lightAlpha: 0.06)
    static let hover = Color(dark: 0xFFFFFF, light: 0x000000, darkAlpha: 0.05, lightAlpha: 0.04)
    static let shadow = Color(dark: 0x000000, light: 0x000000, darkAlpha: 0.5, lightAlpha: 0.06)
    static let trackOff = Color(dark: 0x3F3F46, light: 0xD4D4D8)

    // 뜻이 있는 색 — 초록 완료 · 노랑 다시 해야 함 · 빨강 삭제·실패
    static let success     = Color(dark: 0x17C964, light: 0x17C964)
    static let successFlat = Color(dark: 0x17C964, light: 0xE8FAF0, darkAlpha: 0.14)
    static let successFg   = Color(dark: 0x45D483, light: 0x0E793C)
    static let warning     = Color(dark: 0xF5A524, light: 0xF5A524)
    static let warningFlat = Color(dark: 0xF5A524, light: 0xFEF6E6, darkAlpha: 0.16)
    static let warningFg   = Color(dark: 0xF7B750, light: 0x936316)
    static let danger      = Color(dark: 0xF31260, light: 0xF31260)
    static let dangerFlat  = Color(dark: 0xF31260, light: 0xFEE7EF, darkAlpha: 0.16)
    static let dangerFg    = Color(dark: 0xF54180, light: 0xC20E4D)
    static let infoFlat    = Color(dark: 0x006FEE, light: 0xE6F1FE, darkAlpha: 0.18)
    static let infoFg      = Color(dark: 0x66AAF9, light: 0x005BC4)

    // 모서리
    static let rChip: CGFloat   = 7
    static let rRow: CGFloat    = 9
    static let rBtn: CGFloat    = 10
    static let rCard: CGFloat   = 14
    static let rDialog: CGFloat = 16

    // 글자 — Pretendard가 없으면 시스템 글꼴로 대체된다.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Pretendard Variable", size: size).weight(weight)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - 메인 색 (data-accent)

enum EUAccent: String, CaseIterable, Identifiable {
    case blue, neutral, red, orange
    var id: String { rawValue }

    var label: String {
        switch self {
        case .blue:    return tr("파랑")
        case .neutral: return tr("흰/검")
        case .red:     return tr("빨강")
        case .orange:  return tr("주황")
        }
    }

    var palette: EUPalette {
        switch self {
        case .blue:
            return EUPalette(
                primary:   Color(dark: 0x006FEE, light: 0x006FEE),
                flat:      Color(dark: 0x006FEE, light: 0xE6F1FE, darkAlpha: 0.18),
                row:       Color(dark: 0x006FEE, light: 0xE6F1FE, darkAlpha: 0.16),
                fg:        Color(dark: 0x338EF7, light: 0x005BC4),
                onPrimary: Color(dark: 0xFFFFFF, light: 0xFFFFFF))
        case .neutral:
            return EUPalette(
                primary:   Color(dark: 0xFAFAFA, light: 0x18181B),
                flat:      Color(dark: 0xFFFFFF, light: 0xE4E4E7, darkAlpha: 0.10),
                row:       Color(dark: 0xFFFFFF, light: 0xF4F4F5, darkAlpha: 0.08),
                fg:        Color(dark: 0xFAFAFA, light: 0x18181B),
                onPrimary: Color(dark: 0x09090B, light: 0xFFFFFF))
        case .red:
            return EUPalette(
                primary:   Color(dark: 0xDC2626, light: 0xDC2626),
                flat:      Color(dark: 0xEF4444, light: 0xFEE2E2, darkAlpha: 0.18),
                row:       Color(dark: 0xEF4444, light: 0xFEF2F2, darkAlpha: 0.14),
                fg:        Color(dark: 0xF87171, light: 0xB91C1C),
                onPrimary: Color(dark: 0xFFFFFF, light: 0xFFFFFF))
        case .orange:
            return EUPalette(
                primary:   Color(dark: 0xF97316, light: 0xC2410C),
                flat:      Color(dark: 0xF97316, light: 0xFFEDD5, darkAlpha: 0.18),
                row:       Color(dark: 0xF97316, light: 0xFFF7ED, darkAlpha: 0.14),
                fg:        Color(dark: 0xFB923C, light: 0xC2410C),
                onPrimary: Color(dark: 0x0A0A0A, light: 0xFFFFFF))
        }
    }
}

struct EUPalette {
    let primary: Color
    let flat: Color
    let row: Color
    let fg: Color
    let onPrimary: Color
}

// MARK: - 다크/라이트 (data-theme)

enum EUThemeMode: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark:   return tr("다크")
        case .light:  return tr("라이트")
        case .system: return tr("시스템")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }
}

private struct EUPaletteKey: EnvironmentKey {
    static let defaultValue = EUAccent.blue.palette
}

extension EnvironmentValues {
    var eu: EUPalette {
        get { self[EUPaletteKey.self] }
        set { self[EUPaletteKey.self] = newValue }
    }
}

extension View {
    /// 루트에 한 번 — 다크/라이트와 메인 색을 내려준다.
    func euTheme(_ mode: EUThemeMode, accent: EUAccent) -> some View {
        self
            .environment(\.eu, accent.palette)
            .preferredColorScheme(mode.colorScheme)
            .tint(accent.palette.primary)
            .font(EU.font(13))
            .foregroundStyle(EU.fg)
            .environment(\.locale, L10n.locale)
    }
}
