import SwiftUI

struct BatteryView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.eu) private var eu

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "배터리", subtitle: "충전 상태와 건강도를 확인합니다")
                .padding(.bottom, 4)

            // 상태
            EUCard(padding: 20) {
                HStack(spacing: 18) {
                    Image(systemName: batterySymbol())
                        .font(.system(size: EU.z(30), weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(state.battery.isCharging ? eu.fg : EU.fg2)
                        .frame(width: EU.z(64), height: EU.z(64))
                        .background(state.battery.isCharging ? eu.flat : EU.c2,
                                    in: RoundedRectangle(cornerRadius: EU.rCard, style: .continuous))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(tr(chargingText()))
                                .font(EU.font(20, .bold))
                            chargeChip()
                        }
                        if let t = state.battery.timeRemaining {
                            Text(state.battery.isCharging ? trf("완충까지 %@", t) : trf("남은 시간 %@", t))
                                .font(EU.font(12.5))
                                .foregroundStyle(EU.fg3)
                        }
                    }
                    Spacer()
                    if let c = state.battery.condition {
                        EUChip(text: conditionText(c), tone: conditionTone(c), icon: "heart.fill")
                    }
                }
            }

            powerCards

            // 수치
            HStack(alignment: .top, spacing: 12) {
                EUCard {
                    VStack(alignment: .leading, spacing: 12) {
                        EUCardHeader(title: "배터리 건강도", icon: "heart")
                        if let cap = state.battery.capacityPercent {
                            EUStatValue(value: "\(cap)", unit: "%")
                            EUBar(value: Double(cap) / 100, tone: capacityTone(cap))
                        } else {
                            EUStatValue(value: "N/A", color: EU.fg4)
                        }
                    }
                }
                EUCard {
                    VStack(alignment: .leading, spacing: 12) {
                        EUCardHeader(title: "충전 횟수", icon: "arrow.triangle.2.circlepath")
                        if let n = state.battery.cycleCount {
                            EUStatValue(value: "\(n)", unit: "회")
                            EUBar(value: Double(n) / 1000, tone: n >= 1000 ? .warning : .neutral)
                        } else {
                            EUStatValue(value: "N/A", color: EU.fg4)
                        }
                    }
                }
                EUCard {
                    VStack(alignment: .leading, spacing: 12) {
                        let temp = state.thermal.batteryTemp
                        let level = TempLevel.from(temp)
                        EUCardHeader(title: "배터리 온도", icon: "thermometer.medium") {
                            if let level { EUChip(text: level.label, tone: level.tone) }
                        }
                        if let temp {
                            EUStatValue(value: String(format: "%.1f", temp), unit: "°C")
                            EUBar(value: temp / 60, tone: level?.tone == .neutral ? .primary : (level?.tone ?? .neutral))
                        } else {
                            EUStatValue(value: "N/A", color: EU.fg4)
                        }
                    }
                }
            }

            Text("충전 횟수 막대는 Apple 기준 1,000회를 100%로 봅니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
        }
    }

    // 전력 — 어댑터 정격과 배터리에 실제로 드나드는 전력

    private var powerCards: some View {
        let adapter = state.battery.adapterWatts
        let flow = state.battery.batteryWatts
        let charging = (flow ?? 0) > 0.3
        let draining = (flow ?? 0) < -0.3

        return HStack(alignment: .top, spacing: 12) {
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: "충전기", icon: "powerplug") {
                        if adapter != nil { EUChip(text: "연결됨", tone: .success) }
                    }
                    if let adapter {
                        EUStatValue(value: "\(adapter)", unit: "W")
                        Text("충전기·모니터가 줄 수 있는 최대 전력")
                            .font(EU.font(12))
                            .foregroundStyle(EU.fg3)
                    } else {
                        EUStatValue(value: "—", color: EU.fg4)
                        Text("연결 안 됨")
                            .font(EU.font(12))
                            .foregroundStyle(EU.fg3)
                    }
                }
            }
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: charging ? "배터리로 들어가는 전력" : "배터리 전력", icon: "bolt") {
                        if charging { EUChip(text: "충전", tone: .primary, icon: "arrow.down") }
                        else if draining { EUChip(text: "방전", tone: .warning, icon: "arrow.up") }
                    }
                    if let flow {
                        EUStatValue(value: String(format: "%.1f", abs(flow)), unit: "W",
                                    color: abs(flow) < 0.3 ? EU.fg4 : EU.fg)
                        Text(charging ? "지금 배터리에 충전되는 전력"
                             : draining ? "배터리에서 꺼내 쓰는 전력"
                             : "배터리를 쓰지도 채우지도 않는 중")
                            .font(EU.font(12))
                            .foregroundStyle(EU.fg3)
                    } else {
                        EUStatValue(value: "N/A", color: EU.fg4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chargeChip() -> some View {
        if state.battery.isCharged {
            EUChip(text: "완료", tone: .success, icon: "checkmark")
        } else if state.battery.isCharging {
            EUChip(text: "충전", tone: .primary, icon: "bolt.fill")
        }
    }

    private func batterySymbol() -> String {
        if state.battery.isCharged || state.battery.isCharging { return "battery.100.bolt" }
        guard let pct = state.battery.capacityPercent else { return "battery.0" }
        switch pct {
        case 76...100: return "battery.100"
        case 51...75:  return "battery.75"
        case 26...50:  return "battery.50"
        case 1...25:   return "battery.25"
        default:       return "battery.0"
        }
    }

    private func capacityTone(_ cap: Int) -> EUTone {
        if cap >= 80 { return .success }
        if cap >= 60 { return .warning }
        return .danger
    }

    private func chargingText() -> String {
        if state.battery.isCharged  { return "완충됨" }
        if state.battery.isCharging { return "충전 중" }
        return "배터리 사용 중"
    }

    private func conditionText(_ c: String) -> String {
        let map: [String: String] = [
            "Normal": "정상", "Good": "양호", "Fair": "보통",
            "Poor": "나쁨", "Replace Soon": "교체 권장",
            "Replace Now": "교체 필요", "Service Recommended": "점검 권장",
        ]
        return tr(map[c] ?? c)
    }

    private func conditionTone(_ c: String) -> EUTone {
        switch c {
        case "Normal", "Good":                          return .success
        case "Fair", "Replace Soon", "Service Recommended": return .warning
        case "Poor", "Replace Now":                     return .danger
        default:                                        return .neutral
        }
    }
}
