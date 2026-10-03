import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var perf: PerfMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "대시보드", subtitle: "온도·팬·CPU·메모리 상태를 실시간으로 보여줍니다") {
                Button {
                    state.refreshAll()
                    perf.refreshNow()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.eu(.bordered, small: true))
            }
            .padding(.bottom, 4)

            if let s = state.powerThrottle {
                PowerThrottleBanner(speed: s)
            }

            UsageProfileCard()

            HStack(spacing: 12) {
                tempCard(title: "CPU",    icon: "cpu",              temp: state.thermal.cpuTemp)
                tempCard(title: "GPU",    icon: "square.stack.3d.up", temp: state.thermal.gpuTemp)
                tempCard(title: "배터리", icon: "battery.75",        temp: state.thermal.batteryTemp)
            }

            if let s = perf.latest {
                HStack(alignment: .top, spacing: 12) {
                    CPUUsageCard(sample: s)
                    MemoryUsageCard(sample: s)
                }
                HStack(alignment: .top, spacing: 12) {
                    TopAppsCard(title: "CPU를 많이 쓰는 앱", icon: "list.number", apps: s.top, metric: .cpu, limit: 3)
                    TopAppsCard(title: "메모리를 많이 쓰는 앱", icon: "memorychip", apps: s.topMemory, metric: .memory, limit: 3)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                fanCard()
                PowerModeCard()
            }
        }
        .onAppear { perf.startLive() }
        .onDisappear { perf.stopLive() }
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
