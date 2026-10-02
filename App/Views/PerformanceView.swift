import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject var perf: PerfMonitor
    @Environment(\.eu) private var eu

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "성능", subtitle: "느려지는 순간을 기록해 원인 앱을 찾습니다")
                .padding(.bottom, 4)

            switchCard

            if perf.enabled, let s = perf.latest {
                statCards(s)
                nowCard(s)
            }

            offendersCard
            eventsCard

            Text("CPU 사용이 10초 넘게 70% 이상이거나, 속도 제한·메모리 부족·스왑 급증·앱 충돌이 생기면 그 순간의 상위 앱을 기록합니다. 기록은 24시간 보관합니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 켜기

    private var switchCard: some View {
        EUCard(padding: 0) {
            VStack(spacing: 0) {
                EUListRow {
                    Toggle(isOn: $perf.enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("모니터링 켜기")
                                .font(EU.font(13, .semibold))
                            Text("5초마다 가볍게 잽니다 (CPU 1% 미만)")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                    }
                    .toggleStyle(.eu)
                    .padding(.vertical, 10)
                }
                EUDivider()
                EUListRow {
                    Toggle(isOn: $perf.hogAlert) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CPU를 오래 쓰는 앱 알림")
                            Text("한 앱이 1분 넘게 CPU 50% 이상을 쓰면 알려줍니다")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                    }
                    .toggleStyle(.eu)
                    .disabled(!perf.enabled)
                    .padding(.vertical, 8)
                }
            }
            .font(EU.font(13))
        }
    }

    // MARK: 지금 상태

    private func statCards(_ s: PerfSample) -> some View {
        HStack(alignment: .top, spacing: 12) {
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: "CPU 사용", icon: "cpu")
                    EUStatValue(value: String(format: "%.0f", s.cpuBusy), unit: "%")
                    EUBar(value: s.cpuBusy / 100, tone: s.cpuBusy >= PerfMonitor.busyThreshold ? .danger : .primary)
                }
            }
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: "메모리", icon: "memorychip")
                    EUStatValue(value: pressureText(s.memoryPressure), size: 22,
                                color: s.memoryPressure >= 2 ? EU.dangerFg : EU.fg)
                    Text(trf("스왑 %@", mb(s.swapUsedMB)))
                        .font(EU.font(12))
                        .foregroundStyle(EU.fg3)
                }
            }
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: "CPU 속도", icon: "speedometer")
                    if let l = s.speedLimit {
                        EUStatValue(value: "\(l)", unit: "%", color: l < 100 ? EU.dangerFg : EU.fg)
                        Text(l < 100 ? "발열·전원 때문에 느려짐" : "제한 없음")
                            .font(EU.font(12))
                            .foregroundStyle(EU.fg3)
                    } else {
                        EUStatValue(value: "N/A", color: EU.fg4)
                    }
                }
            }
        }
    }

    private func nowCard(_ s: PerfSample) -> some View {
        EUCard {
            VStack(alignment: .leading, spacing: 10) {
                EUCardHeader(title: "지금 CPU를 많이 쓰는 앱", icon: "list.number")
                ForEach(s.top) { p in
                    procRow(p)
                }
            }
        }
    }

    private func procRow(_ p: ProcSample) -> some View {
        HStack(spacing: 10) {
            Text(p.name)
                .font(EU.font(12.5, .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: EU.z(180), alignment: .leading)
            EUBar(value: min(p.cpu, 100) / 100, tone: p.cpu >= PerfMonitor.hogThreshold ? .warning : .neutral)
            Text(String(format: "%.0f%%", p.cpu))
                .font(EU.font(12.5, .semibold))
                .monospacedDigit()
                .frame(width: EU.z(48), alignment: .trailing)
            Text(mb(p.memMB))
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg3)
                .monospacedDigit()
                .frame(width: EU.z(64), alignment: .trailing)
        }
    }

    // MARK: 자주 원인

    @ViewBuilder
    private var offendersCard: some View {
        let list = perf.offenders.prefix(5)
        if !list.isEmpty {
            EUCard {
                VStack(alignment: .leading, spacing: 10) {
                    EUCardHeader(title: "자주 원인으로 잡힌 앱", icon: "exclamationmark.triangle")
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, o in
                        HStack(spacing: 10) {
                            Text("\(i + 1)")
                                .font(EU.font(12, .bold))
                                .foregroundStyle(EU.fg4)
                                .frame(width: EU.z(16))
                            Text(o.name)
                                .font(EU.font(12.5, .semibold))
                                .lineLimit(1)
                            Spacer()
                            Text(trf("%d번", o.count))
                                .font(EU.font(12.5, .semibold))
                                .monospacedDigit()
                            Text(trf("최고 %.0f%%", o.peakCPU))
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                                .monospacedDigit()
                                .frame(width: EU.z(72), alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    // MARK: 느려진 순간

    private var eventsCard: some View {
        EUCard {
            VStack(alignment: .leading, spacing: 10) {
                EUCardHeader(title: "최근 24시간 느려진 순간", icon: "clock.arrow.circlepath") {
                    if !perf.events.isEmpty {
                        Button(tr("기록 지우기")) { perf.clear() }
                            .buttonStyle(.eu(.light, small: true))
                    }
                }
                if perf.events.isEmpty {
                    Text(perf.enabled ? "아직 느려진 순간이 없습니다" : "모니터링을 켜면 기록이 시작됩니다")
                        .font(EU.font(12.5))
                        .foregroundStyle(EU.fg3)
                        .padding(.vertical, 6)
                } else {
                    ForEach(perf.events.prefix(30)) { e in
                        eventRow(e)
                        if e.id != perf.events.prefix(30).last?.id { EUDivider() }
                    }
                }
            }
        }
    }

    private func eventRow(_ e: SlowEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(timeRange(e))
                    .font(EU.font(12.5, .semibold))
                    .monospacedDigit()
                ForEach(SlowReason.allCases.filter { e.reasons.contains($0) }, id: \.self) { r in
                    EUChip(text: r.label, tone: r == .cpu ? .warning : .danger)
                }
                Spacer()
                Text(trf("최고 CPU %.0f%%", e.peakCPU))
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                    .monospacedDigit()
            }
            if !e.culprits.isEmpty {
                Text(e.culprits.prefix(4).map { String(format: "%@ %.0f%%", $0.name, $0.cpu) }.joined(separator: " · "))
                    .font(EU.font(12))
                    .foregroundStyle(EU.fg2)
                    .lineLimit(2)
            }
            if let l = e.minSpeedLimit {
                Text(trf("CPU 속도 %d%%까지 제한", l))
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: 표기

    private func timeRange(_ e: SlowEvent) -> String {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.dateFormat = "HH:mm:ss"
        let secs = Int(e.end.timeIntervalSince(e.start))
        if secs < 5 { return f.string(from: e.start) }
        let dur = secs >= 60 ? trf("%d분", secs / 60) : trf("%d초", secs)
        return "\(f.string(from: e.start)) · \(dur)"
    }

    private func pressureText(_ level: Int) -> String {
        switch level {
        case 4:  return tr("위험")
        case 2:  return tr("부족")
        default: return tr("여유")
        }
    }

    private func mb(_ v: Int) -> String {
        v >= 1024 ? String(format: "%.1fGB", Double(v) / 1024) : "\(v)MB"
    }
}
