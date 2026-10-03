import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showDonate = false
    @Environment(\.openURL) private var openURL
    @Environment(\.eu) private var eu

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 머리
            HStack(spacing: 8) {
                Image(systemName: "fan.fill")
                    .font(.system(size: EU.z(11), weight: .bold))
                    .foregroundStyle(eu.onPrimary)
                    .frame(width: EU.z(22), height: EU.z(22))
                    .background(eu.primary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text("맥북 팬 관리")
                    .font(EU.font(13, .bold))
                Spacer()
                Text("v\(ReleaseChecker.currentVersion())")
                    .font(EU.font(11, .medium))
                    .foregroundStyle(EU.fg4)
            }

            // 온도 3칸
            HStack(spacing: 6) {
                tempTile("CPU",    state.thermal.cpuTemp)
                tempTile("GPU",    state.thermal.gpuTemp)
                tempTile("배터리", state.thermal.batteryTemp)
            }

            // 팬 빠른 전환 — 고르면 바로 적용
            EUSeg(selection: Binding(
                    get: { state.fanMode == .system ? "auto" : state.fanZone.rawValue },
                    set: { v in
                        if let z = FanZone(rawValue: v) { state.selectZone(z) } else { state.useSystemFan() }
                    }),
                  options: [("auto", "자동")] + FanZone.allCases.map { ($0.rawValue, $0.label) },
                  fill: true)

            if let b = state.boostZone, let until = state.boostUntil {
                HStack(spacing: 6) {
                    Image(systemName: "thermometer.sun.fill")
                    (Text(trf("%@ 임시", b.label)) + Text(" · ") + Text(until, style: .relative) + Text(" ") + Text(tr("남음")))
                        .lineLimit(1)
                    Spacer()
                    Button("되돌리기") { state.cancelBoost() }
                        .buttonStyle(.eu(.light, small: true))
                }
                .font(EU.font(12, .semibold))
                .foregroundStyle(EU.warningFg)
                .padding(.leading, 10)
                .padding(.vertical, 2)
                .background(EU.warningFlat, in: RoundedRectangle(cornerRadius: EU.rRow, style: .continuous))
            }

            // 팬·전원
            VStack(spacing: 0) {
                EUInfoRow(label: "팬") {
                    Text(state.thermal.fanRPM.map { "\($0.formatted()) rpm" } ?? "—")
                        .monospacedDigit()
                }
                EUDivider()
                EUInfoRow(label: "팬 제어") {
                    EUChip(text: state.fanModeLabel,
                           tone: state.safetyOverride ? .warning : (state.fanMode == .zone ? .primary : .neutral))
                }
                EUDivider()
                EUInfoRow(label: "전원") {
                    EUChip(text: state.power == .low ? "절전" : "기본",
                           tone: state.power == .low ? .success : .neutral)
                }
            }
            .padding(.horizontal, 12)
            .background(EU.c1, in: RoundedRectangle(cornerRadius: EU.rRow + 2, style: .continuous))

            if let r = state.latestRelease {
                let l = state.updateActionLabel
                Button {
                    state.installUpdate()
                } label: {
                    Label(l.title, systemImage: l.icon)
                }
                .buttonStyle(.eu(.flat, small: true, fill: true))
                .disabled(state.isInstallingUpdate)
                .help(trf("v%@을 내려받아 설치하고 다시 실행합니다", r.version))
            }

            HStack(spacing: 6) {
                Button {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("대시보드 열기", systemImage: "macwindow")
                }
                .buttonStyle(.eu(.solid, small: true, fill: true))

                Button {
                    state.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.eu(.neutral, small: true))
                .help("새로고침")

                // 후원 — 카카오페이 QR과 PayPal (영어 화면을 쓰는 한국 사용자도 있으므로 언어와 무관)
                Button {
                    showDonate.toggle()
                } label: {
                    Image(systemName: "heart")
                }
                .buttonStyle(.eu(.neutral, small: true))
                .help(tr("후원"))
                .popover(isPresented: $showDonate, arrowEdge: .bottom) {
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

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.eu(.dangerFlat, small: true))
                .help("종료")
            }
        }
        .padding(12)
        .background(EU.appBg)
    }

    private func tempTile(_ key: String, _ temp: Double?) -> some View {
        let level = TempLevel.from(temp)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                EUDot(color: level?.tone.dotColor ?? EU.fg4)
                Text(tr(key))
                    .font(EU.font(11, .medium))
                    .foregroundStyle(EU.fg3)
            }
            Text(temp.map { String(format: "%.0f°", $0) } ?? "—")
                .font(EU.font(18, .bold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(EU.c1, in: RoundedRectangle(cornerRadius: EU.rRow + 2, style: .continuous))
    }
}
