import SwiftUI

@main
struct MacFanControlApp: App {

    @StateObject private var state = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        _ = SMC.shared.open()
    }

    var body: some Scene {
        // 메뉴바 패널 — 클릭 시 작은 SwiftUI 윈도우가 떠오름.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .frame(width: 300)
                .euTheme(state.themeMode, accent: state.accent)
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        // 대시보드 — 메뉴바에서 "대시보드 열기"로 호출.
        Window(tr("맥북 팬 관리"), id: "dashboard") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 820, minHeight: 560)
                .euTheme(state.themeMode, accent: state.accent)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// 메뉴바 라벨 — [구간 아이콘] [온도계]온도  rpm.
/// 메뉴바 항목은 Text 안의 이미지를 빼고 그리므로, 통째로 템플릿 이미지로 그려 넣는다.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Image(nsImage: renderLabel())
    }

    @MainActor
    private func renderLabel() -> NSImage {
        let r = ImageRenderer(content: content.foregroundStyle(.black))
        r.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = r.nsImage ?? NSImage(systemSymbolName: "fan", accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }

    private var content: some View {
        let showIcon = state.mbShowIcon || !(state.mbShowTemp || state.mbShowThermo || state.mbShowFan)
        return HStack(spacing: 6) {
            if showIcon {
                Image(systemName: state.menuBarSymbol)
                    .font(.system(size: 13, weight: .semibold))
            }
            if state.mbShowTemp || state.mbShowThermo {
                HStack(spacing: 2) {
                    if state.mbShowThermo {
                        Image(systemName: thermoSymbol(state.thermal.cpuTemp))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    if state.mbShowTemp {
                        Text(state.thermal.cpuTemp.map { String(format: "%.0f°", $0) } ?? "—°")
                    }
                }
            }
            if state.mbShowFan {
                Text(state.thermal.fanRPM.map { "\($0)rpm" } ?? "—rpm")
            }
        }
        .font(.system(size: 13, weight: .medium).monospacedDigit())
        .fixedSize()
        .frame(height: 18)
    }

    private func thermoSymbol(_ t: Double?) -> String {
        guard let t else { return "thermometer.medium" }
        if t < 60 { return "thermometer.low" }
        if t < 80 { return "thermometer.medium" }
        return "thermometer.high"
    }
}
