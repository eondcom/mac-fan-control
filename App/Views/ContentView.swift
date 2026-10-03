import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard, fan, battery, display, performance, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return tr("대시보드")
        case .fan:       return tr("팬 제어")
        case .battery:   return tr("배터리")
        case .display:   return tr("모니터")
        case .performance: return tr("성능")
        case .settings:  return tr("설정")
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .fan:       return "fan"
        case .battery:   return "battery.75"
        case .display:   return "display"
        case .performance: return "waveform.path.ecg"
        case .settings:  return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: AppTab
    /// 배율이 바뀌면 탭은 그대로 두고 안쪽만 다시 그린다.
    @AppStorage(UIZoom.key) private var zoom: Double = 1

    init(initialTab: AppTab = .dashboard) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(tab: $tab)
                .id(zoom)
            Rectangle().fill(EU.line).frame(width: 1)

            ScrollView {
                Group {
                    switch tab {
                    case .dashboard: DashboardView()
                    case .fan:       FanControlView()
                    case .battery:   BatteryView()
                    case .display:   DisplayView()
                    case .performance: PerformanceView()
                    case .settings:  SettingsView()
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 36)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .id(zoom)
            }
            .background(EU.appBg)
        }
        .background(EU.appBg)
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: .refreshEverything)) { _ in
            refreshEverything()
        }
    }

    @EnvironmentObject private var displays: DisplayState
    @EnvironmentObject private var perf: PerfMonitor

    private func refreshEverything() {
        state.refreshAll()
        displays.refresh()
        displays.refreshLinks()
        perf.refreshNow()
    }
}

// MARK: - 사이드바 (.eu-nav)

private struct Sidebar: View {
    @EnvironmentObject var state: AppState
    @Binding var tab: AppTab
    @Environment(\.eu) private var eu

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 신호등 버튼 자리
            Color.clear.frame(height: 40)

            HStack(spacing: 8) {
                Image(systemName: "fan.fill")
                    .font(.system(size: EU.z(13), weight: .bold))
                    .foregroundStyle(eu.onPrimary)
                    .frame(width: EU.z(26), height: EU.z(26))
                    .background(eu.primary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("맥북 팬 관리")
                        .font(EU.font(13, .bold))
                    Text("v\(ReleaseChecker.currentVersion())")
                        .font(EU.font(10.5, .medium))
                        .foregroundStyle(EU.fg4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 18)

            ForEach(AppTab.allCases) { t in
                NavItem(tab: t, selected: tab == t) { tab = t }
            }

            Spacer()

            Button {
                NotificationCenter.default.post(name: .refreshEverything, object: nil)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("전체 새로고침")
                    Spacer()
                    Text("⌘R").foregroundStyle(EU.fg4)
                }
            }
            .buttonStyle(.eu(.light, small: true, fill: true))

            DonateNavItem()
                .padding(.bottom, 6)

            // 하단 실시간 요약
            VStack(alignment: .leading, spacing: 6) {
                miniStat("CPU", state.thermal.cpuTemp.map { String(format: "%.0f°", $0) } ?? "—",
                         tone: TempLevel.from(state.thermal.cpuTemp)?.tone)
                miniStat("팬", state.thermal.fanRPM.map { "\($0.formatted())" } ?? "—", tone: nil)
            }
            .padding(12)
            .background(EU.c1, in: RoundedRectangle(cornerRadius: EU.rRow + 2, style: .continuous))

            if let r = state.latestRelease {
                let l = state.updateActionLabel
                Button {
                    state.installUpdate()
                } label: {
                    HStack(spacing: 6) {
                        if state.isInstallingUpdate {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: l.icon)
                        }
                        Text(l.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(EU.font(12, .semibold))
                    .foregroundStyle(eu.fg)
                    .frame(maxWidth: .infinity, minHeight: EU.z(30))
                    .background(eu.flat, in: RoundedRectangle(cornerRadius: EU.rRow, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(state.isInstallingUpdate)
                .help(trf("v%@을 내려받아 설치하고 다시 실행합니다", r.version))
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: EU.z(200))
        .frame(maxHeight: .infinity)
        .background(EU.chrome)
    }

    private func miniStat(_ key: String, _ value: String, tone: EUTone?) -> some View {
        HStack(spacing: 6) {
            EUDot(color: tone?.dotColor ?? EU.fg4)
            Text(tr(key)).foregroundStyle(EU.fg3)
            Spacer()
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
        .font(EU.font(12))
    }
}

private struct NavItem: View {
    let tab: AppTab
    let selected: Bool
    let action: () -> Void
    @Environment(\.eu) private var eu
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: EU.z(13), weight: .medium))
                    .frame(width: EU.z(18))
                Text(tab.title)
                    .font(EU.font(13, selected ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(selected ? eu.fg : (hovering ? EU.fg : EU.fg2))
            .padding(.horizontal, 10)
            .frame(height: EU.z(34))
            .background(
                selected ? eu.row : (hovering ? EU.hover : .clear),
                in: RoundedRectangle(cornerRadius: EU.rRow, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - 온도·팬 단계 → 뜻 있는 색

enum TempLevel {
    case stable, normal, caution, hot

    static func from(_ temp: Double?) -> TempLevel? {
        guard let t = temp else { return nil }
        if t < 60 { return .stable }
        if t < 75 { return .normal }
        if t < 85 { return .caution }
        return .hot
    }

    var tone: EUTone {
        switch self {
        case .stable:  return .success
        case .normal:  return .neutral
        case .caution: return .warning
        case .hot:     return .danger
        }
    }

    var label: String {
        switch self {
        case .stable:  return tr("안정")
        case .normal:  return tr("적정")
        case .caution: return tr("주의")
        case .hot:     return tr("위험")
        }
    }
}

enum FanLevel {
    case low, mid, high

    static func from(_ rpm: Int?) -> FanLevel? {
        guard let r = rpm else { return nil }
        if r < 2000 { return .low }
        if r < 4000 { return .mid }
        return .high
    }

    var label: String {
        switch self {
        case .low:  return tr("최소")
        case .mid:  return tr("기본")
        case .high: return tr("고속")
        }
    }
}

/// 사이드바 아래쪽 전체 새로고침 밑의 작은 후원 줄 — 탭이 아니라 후원 창을 띄운다.
private struct DonateNavItem: View {
    @Environment(\.openURL) private var openURL
    @State private var show = false
    @State private var hovering = false

    var body: some View {
        Button {
            show.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "heart")
                    .font(.system(size: EU.z(11), weight: .medium))
                    .frame(width: EU.z(18))
                Text("후원하기")
                    .font(EU.font(12))
                Spacer()
            }
            .foregroundStyle(hovering ? EU.fg2 : EU.fg4)
            .padding(.horizontal, 10)
            .frame(height: EU.z(28))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .popover(isPresented: $show, arrowEdge: .trailing) {
            VStack(spacing: 0) {
                KakaoPayQR(url: SettingsView.kakaoPayURL)
                EUDivider()
                Button {
                    openURL(SettingsView.payPalURL)
                } label: {
                    Label(tr("PayPal로 후원"), systemImage: "heart.fill")
                }
                .buttonStyle(.eu(.light, small: true))
                .padding(10)
            }
        }
    }
}
