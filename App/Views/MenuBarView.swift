import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("맥북 팬 관리")
                    .font(.headline)
                Spacer()
                Text("v\(ReleaseChecker.currentVersion())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()

            statRow("CPU",   value: state.thermal.cpuTemp.map { tempLabel($0) } ?? "—")
            statRow("GPU",   value: state.thermal.gpuTemp.map { tempLabel($0) } ?? "—")
            statRow("배터리", value: state.thermal.batteryTemp.map { tempLabel($0) } ?? "—")
            statRow("팬",    value: state.thermal.fanRPM.map { "\($0) rpm" } ?? "—")
            statRow("전원",   value: state.power == .low ? "🌙 절전" : "⚡ 기본")

            if let r = state.latestRelease {
                Divider()
                Link(destination: r.tagURL) {
                    Label("v\(r.version) 업데이트 있음", systemImage: "arrow.down.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.blue)
                }
            }

            Divider()

            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("대시보드 열기", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Button {
                state.refreshAll()
            } label: {
                Label("새로고침", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("종료", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    @ViewBuilder
    private func statRow(_ key: String, value: String) -> some View {
        HStack {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .fontWeight(.medium)
            Spacer()
        }
        .font(.callout)
    }

    private func tempLabel(_ t: Double) -> String {
        String(format: "%.1f°C", t)
    }
}
