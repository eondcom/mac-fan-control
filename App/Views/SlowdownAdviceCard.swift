import SwiftUI

/// 속도 저하 진단 — 지금 해당하는 원인과 없애는 방법
struct SlowdownAdviceCard: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var perf: PerfMonitor
    @State private var showAll = false

    var body: some View {
        let throttles = perf.events.filter { $0.reasons.contains(.throttle) }.count
        let causes = SlowdownAdvice.causes(battery: state.battery, power: state.power,
                                           speedLimit: perf.latest?.speedLimit ?? PerfService.speedLimitCached,
                                           throttleEvents: throttles)
        let active = causes.filter(\.active)
        let shown = showAll ? causes : active

        EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: "속도 저하 진단", icon: "stethoscope") {
                    if active.isEmpty {
                        EUChip(text: "문제 없음", tone: .success, icon: "checkmark")
                    } else {
                        EUChip(text: trf("원인 %d개", active.count), tone: .warning)
                    }
                }
                if shown.isEmpty {
                    Text("지금은 속도를 떨어뜨릴 만한 원인이 보이지 않습니다.")
                        .font(EU.font(12.5))
                        .foregroundStyle(EU.fg3)
                }
                ForEach(shown) { c in
                    causeRow(c)
                    if c.id != shown.last?.id { EUDivider() }
                }
                Button(showAll ? tr("해당하는 것만 보기") : tr("모든 원인과 해결 방법 보기")) {
                    showAll.toggle()
                }
                .buttonStyle(.eu(.light, small: true))
            }
        }
    }

    private func causeRow(_ c: SlowdownCause) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: c.active ? "exclamationmark.triangle.fill" : "checkmark.circle")
                    .foregroundStyle(c.active ? EU.warningFg : EU.fg4)
                Text(c.title)
                    .font(EU.font(13, .semibold))
            }
            Text(c.detail)
                .font(EU.font(12))
                .foregroundStyle(EU.fg3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(c.fixes, id: \.self) { f in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("→").foregroundStyle(EU.fg4)
                        Text(f).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(EU.font(12))
                }
            }
            if c.kind == .throttle && c.active {
                ThrottleActions()
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 2)
    }
}
