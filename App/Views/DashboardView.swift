import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "대시보드", subtitle: "온도·팬·전원 상태를 5초마다 갱신합니다") {
                Button {
                    state.refreshAll()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.eu(.bordered, small: true))
            }
            .padding(.bottom, 4)

            HStack(spacing: 12) {
                tempCard(title: "CPU",    icon: "cpu",              temp: state.thermal.cpuTemp)
                tempCard(title: "GPU",    icon: "square.stack.3d.up", temp: state.thermal.gpuTemp)
                tempCard(title: "배터리", icon: "battery.75",        temp: state.thermal.batteryTemp)
            }

            HStack(alignment: .top, spacing: 12) {
                fanCard()
                PowerModeCard()
            }
        }
    }

    // MARK: - temp card

    private func tempCard(title: String, icon: String, temp: Double?) -> some View {
        let level = TempLevel.from(temp)
        return EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: trf("%@ 온도", tr(title)), icon: icon) {
                    if let level { EUChip(text: level.label, tone: level.tone) }
                }
                if let t = temp {
                    EUStatValue(value: String(format: "%.1f", t), unit: "°C")
                } else {
                    EUStatValue(value: "N/A", color: EU.fg4)
                }
                EUBar(value: (temp ?? 0) / 100, tone: level?.tone == .neutral ? .primary : (level?.tone ?? .neutral))
            }
        }
    }

    // MARK: - fan card

    private func fanCard() -> some View {
        let t = state.thermal
        let ratio: Double = {
            guard let r = t.fanRPM, let mn = t.fanMin, let mx = t.fanMax, mx > mn else { return 0 }
            return Double(r - mn) / Double(mx - mn)
        }()

        return EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: "팬 상태", icon: "fan") {
                    EUChip(text: state.fanModeLabel,
                           tone: state.safetyOverride ? .warning : (state.fanMode == .zone ? .primary : .neutral))
                }
                HStack(alignment: .firstTextBaseline) {
                    EUStatValue(value: t.fanRPM.map { $0.formatted() } ?? "N/A",
                                unit: t.fanRPM == nil ? nil : "rpm",
                                color: t.fanRPM == nil ? EU.fg4 : EU.fg)
                    Spacer()
                    if let lv = FanLevel.from(t.fanRPM) {
                        Text(lv.label).font(EU.font(12, .medium)).foregroundStyle(EU.fg3)
                    }
                }
                EUBar(value: ratio)

                VStack(spacing: 0) {
                    EUInfoRow("최소", t.fanMin.map { "\($0.formatted()) rpm" } ?? "N/A")
                    EUDivider()
                    EUInfoRow("최대", t.fanMax.map { "\($0.formatted()) rpm" } ?? "N/A")
                }
            }
        }
    }
}

// MARK: - 전원 모드 카드 — 대시보드·배터리 탭 공용

struct PowerModeCard: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: "전원 모드", icon: "bolt") {
                    if state.power == .low { EUChip(text: "절전 중", tone: .success, icon: "leaf.fill") }
                }
                EUStatValue(value: state.power == .low ? "절전 모드" : "기본 모드", size: 22)

                EUSeg(selection: Binding(
                        get: { state.power },
                        set: { state.setPowerMode($0) }),
                      options: [(.low, "절전"), (.normal, "기본")],
                      fill: true)

                HStack(spacing: 5) {
                    Image(systemName: "lock.fill").font(.system(size: EU.z(9)))
                    Text("모드를 바꿀 때 시스템 암호를 묻습니다")
                }
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
            }
        }
    }
}
