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
                .frame(width: 280)
                .onAppear { state.startTimers() }
        } label: {
            MenuBarLabel()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)

        // 대시보드 — 메뉴바에서 "대시보드 열기"로 호출.
        Window("맥북 팬 관리", id: "dashboard") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}

/// 메뉴바 좌측 라벨 — 온도/팬 토글에 따라 표시.
struct MenuBarLabel: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let parts = labelParts()
        Text(parts.isEmpty ? "🖥️" : parts.joined(separator: "  "))
    }

    private func labelParts() -> [String] {
        var parts: [String] = []
        if state.mbShowTemp {
            if let t = state.thermal.cpuTemp {
                parts.append(String(format: "🌡️%.1f°C", t))
            } else {
                parts.append("🌡️—")
            }
        }
        if state.mbShowFan {
            if let r = state.thermal.fanRPM {
                parts.append("🌀\(r)")
            } else {
                parts.append("🌀—")
            }
        }
        return parts
    }
}
