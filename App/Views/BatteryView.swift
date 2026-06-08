import SwiftUI

struct BatteryView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            HStack(spacing: 12) {
                card(title: "충전 횟수",
                     value: state.battery.cycleCount.map { "\($0)회" } ?? "N/A",
                     color: cycleColor(state.battery.cycleCount),
                     accent: .yellow)
                card(title: "건강도",
                     value: state.battery.capacityPercent.map { "\($0) %" } ?? "N/A",
                     color: capacityColor(state.battery.capacityPercent),
                     accent: .green)
                card(title: "잔여 시간",
                     value: remainingText(),
                     color: remainingColor(),
                     accent: .blue,
                     small: true)
                card(title: "상태",
                     value: conditionText(state.battery.condition),
                     color: conditionColor(state.battery.condition),
                     accent: .orange)
            }

            Spacer()
        }
        .padding()
    }

    private func card(title: String, value: String, color: Color, accent: Color, small: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(accent)
            Text(value)
                .font(.system(size: small ? 14 : 22, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(small ? 2 : 1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cycleColor(_ cycle: Int?) -> Color {
        guard let c = cycle else { return .secondary }
        if c > 800 { return .red }
        if c > 500 { return .yellow }
        return .green
    }

    private func capacityColor(_ cap: Int?) -> Color {
        guard let c = cap else { return .secondary }
        if c < 60 { return .red }
        if c < 80 { return .yellow }
        return .green
    }

    private func remainingText() -> String {
        if state.battery.isCharged { return "⚡ 완충" }
        if state.battery.isCharging {
            if let t = state.battery.timeRemaining { return "⚡ 충전 중\n\(t) 후 완충" }
            return "⚡ 충전 중"
        }
        if let t = state.battery.timeRemaining { return "🔋 방전 중\n\(t) 남음" }
        return "🔋 방전 중"
    }

    private func remainingColor() -> Color {
        if state.battery.isCharged { return .green }
        if state.battery.isCharging { return .blue }
        return state.battery.timeRemaining != nil ? .green : .secondary
    }

    private func conditionText(_ c: String?) -> String {
        guard let c = c else { return "N/A" }
        let map: [String: String] = [
            "Normal": "정상", "Good": "양호", "Fair": "보통",
            "Poor": "나쁨", "Replace Soon": "교체 권장",
            "Replace Now": "교체 필요", "Service Recommended": "점검 권장",
        ]
        return map[c] ?? c
    }

    private func conditionColor(_ c: String?) -> Color {
        guard let c = c else { return .secondary }
        if ["Replace Now", "Replace Soon"].contains(c) { return .red }
        if ["Poor", "Fair", "Service Recommended"].contains(c) { return .yellow }
        return .green
    }
}
