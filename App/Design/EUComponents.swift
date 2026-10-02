import SwiftUI

// EOND UI App 부품의 SwiftUI 판 — Card · Btn · Chip · Bar · Seg · Switch · InfoRow

// MARK: - Card (.eu-card)

struct EUCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(EU.c1, in: RoundedRectangle(cornerRadius: EU.rCard, style: .continuous))
            .shadow(color: EU.shadow, radius: 1.5, y: 1)
    }
}

/// 카드 머리 — 작은 회색 제목 + 오른쪽 부속(칩 등)
struct EUCardHeader<Trailing: View>: View {
    let title: String
    var icon: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: EU.z(11), weight: .semibold))
                    .foregroundStyle(EU.fg4)
            }
            Text(tr(title))
                .font(EU.font(12, .medium))
                .foregroundStyle(EU.fg3)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension EUCardHeader where Trailing == EmptyView {
    init(title: String, icon: String? = nil) {
        self.init(title: title, icon: icon) { EmptyView() }
    }
}

// MARK: - Button (.eu-btn)

enum EUBtnKind {
    /// 화면마다 1~2개, 주 동작만
    case solid
    case flat
    case bordered
    case light
    case neutral
    case dangerFlat
    case successFlat
}

struct EUButtonStyle: ButtonStyle {
    var kind: EUBtnKind = .neutral
    var small = false
    var fill = false

    @Environment(\.eu) private var eu
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        EUButtonBody(configuration: configuration, kind: kind, small: small, fill: fill,
                     eu: eu, isEnabled: isEnabled)
    }
}

private struct EUButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: EUBtnKind
    let small: Bool
    let fill: Bool
    let eu: EUPalette
    let isEnabled: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(EU.font(small ? 12 : 13, kind == .bordered || kind == .light ? .medium : .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, small ? 12 : 16)
            .frame(maxWidth: fill ? .infinity : nil)
            .frame(minHeight: EU.z(small ? 28 : 36))
            .background(background, in: RoundedRectangle(cornerRadius: small ? 8 : EU.rBtn, style: .continuous))
            .overlay {
                if kind == .bordered {
                    RoundedRectangle(cornerRadius: small ? 8 : EU.rBtn, style: .continuous)
                        .strokeBorder(EU.c4, lineWidth: 1.5)
                }
            }
            .brightness(hovering && kind != .bordered && kind != .light ? 0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .solid:       return eu.onPrimary
        case .flat:        return eu.fg
        case .bordered:    return EU.fg
        case .light:       return hovering ? EU.fg : EU.fg2
        case .neutral:     return EU.fg
        case .dangerFlat:  return EU.dangerFg
        case .successFlat: return EU.successFg
        }
    }

    private var background: Color {
        switch kind {
        case .solid:       return eu.primary
        case .flat:        return eu.flat
        case .bordered:    return hovering ? EU.hover : .clear
        case .light:       return hovering ? EU.hover : .clear
        case .neutral:     return EU.c2
        case .dangerFlat:  return EU.dangerFlat
        case .successFlat: return EU.successFlat
        }
    }
}

extension ButtonStyle where Self == EUButtonStyle {
    static func eu(_ kind: EUBtnKind = .neutral, small: Bool = false, fill: Bool = false) -> EUButtonStyle {
        EUButtonStyle(kind: kind, small: small, fill: fill)
    }
}

// MARK: - Chip (.eu-chip)

enum EUTone {
    case neutral, primary, success, warning, danger, info
}

struct EUChip: View {
    let text: String
    var tone: EUTone = .neutral
    var icon: String? = nil
    @Environment(\.eu) private var eu

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.system(size: EU.z(9), weight: .bold))
            }
            Text(tr(text))
        }
        .font(EU.font(11.5, .semibold))
        .foregroundStyle(colors.fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(colors.bg, in: Capsule())
    }

    private var colors: (bg: Color, fg: Color) {
        switch tone {
        case .neutral: return (EU.c2, EU.fg3)
        case .primary: return (eu.flat, eu.fg)
        case .success: return (EU.successFlat, EU.successFg)
        case .warning: return (EU.warningFlat, EU.warningFg)
        case .danger:  return (EU.dangerFlat, EU.dangerFg)
        case .info:    return (EU.infoFlat, EU.infoFg)
        }
    }
}

extension EUTone {
    /// 점·막대처럼 채워 그리는 색. 뜻이 없는 단계는 회색.
    var dotColor: Color {
        switch self {
        case .success: return EU.success
        case .warning: return EU.warning
        case .danger:  return EU.danger
        default:       return EU.fg4
        }
    }
}

/// 상태 점 (.eu-dot)
struct EUDot: View {
    var color: Color
    var body: some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }
}

// MARK: - Bar (.eu-bar)

struct EUBar: View {
    /// 0...1
    var value: Double
    var tone: EUTone = .primary
    var height: CGFloat = 5
    @Environment(\.eu) private var eu

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(EU.c3)
                Capsule()
                    .fill(fill)
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
                    .opacity(value > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: value)
    }

    private var fill: Color {
        switch tone {
        case .neutral: return EU.fg3
        case .primary: return eu.primary
        case .success: return EU.success
        case .warning: return EU.warning
        case .danger:  return EU.danger
        case .info:    return EU.infoFg
        }
    }
}

// MARK: - Segmented (.eu-seg)

struct EUSeg<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    var fill = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { opt in
                let on = opt.value == selection
                Button {
                    selection = opt.value
                } label: {
                    Text(tr(opt.label))
                        .font(EU.font(12.5, on ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(on ? EU.fg : EU.fg3)
                        .padding(.horizontal, fill ? 6 : 12)
                        .frame(maxWidth: fill ? .infinity : nil, minHeight: EU.z(28))
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(dark: 0x52525B, light: 0xFFFFFF))
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(EU.c2, in: RoundedRectangle(cornerRadius: EU.rBtn, style: .continuous))
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

// MARK: - Switch (.eu-switch)

struct EUSwitchStyle: ToggleStyle {
    @Environment(\.eu) private var eu

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? eu.primary : EU.trackOff)
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(configuration.isOn ? eu.onPrimary : .white)
                    .frame(width: 14, height: 14)
                    .padding(3)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
        .contentShape(Rectangle())
    }
}

extension ToggleStyle where Self == EUSwitchStyle {
    static var eu: EUSwitchStyle { EUSwitchStyle() }
}

// MARK: - Info rows (.eu-inforows)

struct EUInfoRow<Value: View>: View {
    let label: String
    @ViewBuilder var value: Value

    var body: some View {
        HStack {
            Text(tr(label))
                .font(EU.font(12.5))
                .foregroundStyle(EU.fg3)
            Spacer(minLength: 12)
            value
                .font(EU.font(12.5, .semibold))
                .foregroundStyle(EU.fg)
        }
        .padding(.vertical, 7)
    }
}

extension EUInfoRow where Value == Text {
    init(_ label: String, _ value: String) {
        self.init(label: label) { Text(tr(value)) }
    }
}

struct EUDivider: View {
    var body: some View {
        Rectangle().fill(EU.line).frame(height: 1)
    }
}

/// 설정형 목록 줄 (.eu-card--flush 안쪽 줄)
struct EUListRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 16)
            .frame(minHeight: EU.z(44))
    }
}

// MARK: - 큰 수치

struct EUStatValue: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 28
    var color: Color = EU.fg

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(tr(value))
                .font(EU.font(size, .bold))
                .monospacedDigit()
                .foregroundStyle(color)
            if let unit {
                Text(tr(unit))
                    .font(EU.font(size * 0.45, .semibold))
                    .foregroundStyle(EU.fg3)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// 페이지 머리 — 제목 + 설명 + 오른쪽 동작
struct EUPageHeader<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr(title))
                    .font(EU.font(20, .bold))
                    .foregroundStyle(EU.fg)
                if let subtitle {
                    Text(tr(subtitle))
                        .font(EU.font(12.5))
                        .foregroundStyle(EU.fg3)
                }
            }
            Spacer()
            actions
        }
    }
}

extension EUPageHeader where Actions == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Slider (.eu-range)

/// 손잡이 하나짜리 슬라이더 — 끄는 동안 값이 바로 바뀐다.
struct EUSlider: View {
    @Binding var value: Int
    let bounds: ClosedRange<Int>
    var step = 50
    /// 트랙 위에 겹쳐 보여줄 눈금 (예: 지금 실제 rpm)
    var marker: Int? = nil
    @Environment(\.eu) private var eu

    var body: some View {
        EUSliderTrack(bounds: bounds, marker: marker) { w in
            let x = EUSliderMath.position(value, in: bounds, width: w)
            Capsule().fill(eu.primary).frame(width: x, height: 5)
            EUThumb().offset(x: x - 8)
        } onDrag: { x, w in
            value = EUSliderMath.value(at: x, in: bounds, width: w, step: step)
        }
    }
}

/// 손잡이 두 개짜리 범위 슬라이더 — 가까운 손잡이를 움직인다.
struct EURangeSlider: View {
    @Binding var lower: Int
    @Binding var upper: Int
    let bounds: ClosedRange<Int>
    var step = 100
    var minGap = 100
    @Environment(\.eu) private var eu
    @State private var draggingUpper: Bool?

    var body: some View {
        EUSliderTrack(bounds: bounds, marker: nil) { w in
            let x0 = EUSliderMath.position(lower, in: bounds, width: w)
            let x1 = EUSliderMath.position(upper, in: bounds, width: w)
            Capsule().fill(eu.primary).frame(width: max(x1 - x0, 0), height: 5).offset(x: x0)
            EUThumb().offset(x: x0 - 8)
            EUThumb().offset(x: x1 - 8)
        } onDrag: { x, w in
            let v = EUSliderMath.value(at: x, in: bounds, width: w, step: step)
            let isUpper = draggingUpper ?? (abs(v - upper) < abs(v - lower) || (v == lower && v == upper && v > bounds.lowerBound))
            draggingUpper = isUpper
            if isUpper { upper = max(v, lower + minGap) } else { lower = min(v, upper - minGap) }
        } onEnd: {
            draggingUpper = nil
        }
    }
}

private struct EUThumb: View {
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 16, height: 16)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
    }
}

private struct EUSliderTrack<Content: View>: View {
    let bounds: ClosedRange<Int>
    let marker: Int?
    @ViewBuilder var content: (CGFloat) -> Content
    var onDrag: (CGFloat, CGFloat) -> Void
    var onEnd: () -> Void = {}

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(EU.c3).frame(height: 5)
                content(w)
                if let marker, bounds.contains(marker) {
                    Rectangle().fill(EU.fg3)
                        .frame(width: 2, height: 12)
                        .offset(x: EUSliderMath.position(marker, in: bounds, width: w) - 1)
                }
            }
            .frame(width: w, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { onDrag($0.location.x, w) }
                .onEnded { _ in onEnd() })
        }
        .frame(height: 22)
    }
}

private enum EUSliderMath {
    static func position(_ v: Int, in r: ClosedRange<Int>, width: CGFloat) -> CGFloat {
        let span = CGFloat(max(r.upperBound - r.lowerBound, 1))
        return CGFloat(min(max(v, r.lowerBound), r.upperBound) - r.lowerBound) / span * width
    }

    static func value(at x: CGFloat, in r: ClosedRange<Int>, width: CGFloat, step: Int) -> Int {
        let frac = min(max(x / max(width, 1), 0), 1)
        let raw = Double(r.lowerBound) + Double(frac) * Double(r.upperBound - r.lowerBound)
        let v = Int((raw / Double(step)).rounded()) * step
        return min(max(v, r.lowerBound), r.upperBound)
    }
}
