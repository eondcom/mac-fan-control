import SwiftUI

struct PerformanceView: View {
    @EnvironmentObject var perf: PerfMonitor
    @Environment(\.eu) private var eu

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "성능", subtitle: "느려지는 순간을 기록해 원인 앱을 찾습니다")
                .padding(.bottom, 4)

            switchCard
            SlowdownAdviceCard()

            if let s = perf.latest {
                statCards(s)
                HStack(alignment: .top, spacing: 12) {
                    TopAppsCard(title: "지금 CPU를 많이 쓰는 앱", icon: "list.number", apps: s.top, metric: .cpu)
                    TopAppsCard(title: "메모리를 많이 쓰는 앱", icon: "memorychip", apps: s.topMemory, metric: .memory)
                }
            }

            PerfHistoryView(events: perf.events, offenders: perf.offenders, enabled: perf.enabled) {
                perf.clear()
            }
            .equatable()

            Text("CPU 사용이 10초 넘게 70% 이상이거나, 속도 제한·메모리 부족·스왑 급증·앱 충돌이 생기면 그 순간의 상위 앱을 기록합니다. 기록은 24시간 보관합니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { perf.startLive() }
        .onDisappear { perf.stopLive() }
    }

    // MARK: 켜기

    private var switchCard: some View {
        EUCard(padding: 0) {
            VStack(spacing: 0) {
                EUListRow {
                    Toggle(isOn: $perf.enabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("백그라운드 기록")
                                .font(EU.font(13, .semibold))
                            Text("앱을 안 보고 있을 때도 5초마다 재서 느려진 순간을 남깁니다 (CPU 1% 미만)")
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
                EUDivider()
                EUListRow {
                    Toggle(isOn: $perf.lowerHogs) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CPU를 오래 쓰는 앱 우선순위 낮추기")
                            Text("한 앱이 1분 넘게 CPU 50% 이상을 쓰면 그 앱을 뒤로 미뤄 다른 작업을 먼저 돌립니다. 지금 쓰는 앱은 건드리지 않습니다")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                    }
                    .toggleStyle(.eu)
                    .padding(.vertical, 8)
                }
                ForEach(perf.lowered.sorted { $0.key < $1.key }, id: \.key) { pid, name in
                    EUDivider()
                    EUListRow {
                        HStack(spacing: 8) {
                            Image(systemName: "tortoise")
                                .foregroundStyle(EU.fg3)
                            Text(name)
                                .font(EU.font(12.5, .medium))
                                .lineLimit(1)
                            Text("우선순위 낮춤")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                            Spacer()
                            Button(tr("되돌리기")) { perf.restore(pid) }
                                .buttonStyle(.eu(.light, small: true))
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .font(EU.font(13))
        }
    }

    // MARK: 지금 상태

    private func statCards(_ s: PerfSample) -> some View {
        HStack(alignment: .top, spacing: 12) {
            CPUUsageCard(sample: s)
            MemoryUsageCard(sample: s)
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: tr(Platform.hasSpeedLimit ? "CPU 속도" : "열 상태"), icon: "speedometer")
                    if !Platform.hasSpeedLimit {
                        let t = Platform.thermalState
                        EUStatValue(value: Platform.thermalStateLabel(t),
                                    color: Platform.isThermalThrottling ? EU.dangerFg : EU.fg)
                        Text(Platform.isThermalThrottling ? "발열 때문에 느려짐" : "macOS가 판단한 발열 단계")
                            .font(EU.font(12))
                            .foregroundStyle(EU.fg3)
                    } else if let l = s.speedLimit {
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
}

// MARK: - CPU·메모리 카드 — 대시보드·성능 탭 공용

struct CPUUsageCard: View {
    let sample: PerfSample

    var body: some View {
        EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: "CPU 사용", icon: "cpu")
                EUStatValue(value: String(format: "%.0f", sample.cpuBusy), unit: "%")
                EUBar(value: sample.cpuBusy / 100,
                      tone: sample.cpuBusy >= PerfMonitor.busyThreshold ? .danger : .primary)
                Text(ProcessInfo.processInfo.activeProcessorCount.description + tr("코어"))
                    .font(EU.font(12))
                    .foregroundStyle(EU.fg3)
            }
        }
    }
}

struct MemoryUsageCard: View {
    let sample: PerfSample

    var body: some View {
        EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: "메모리", icon: "memorychip") {
                    EUChip(text: pressureText(sample.memoryPressure), tone: pressureTone(sample.memoryPressure))
                }
                if let m = sample.memory {
                    EUStatValue(value: String(format: "%.1f", Double(m.usedMB) / 1024),
                                unit: String(format: "/ %.0f GB", (Double(m.totalMB) / 1024).rounded()))
                    EUBar(value: m.usedRatio, tone: sample.memoryPressure >= 2 ? .danger : .primary)
                    Text(trf("앱 %@ · 압축 %@ · 캐시 %@ · 스왑 %@",
                             perfSize(m.appMB), perfSize(m.compressedMB), perfSize(m.cachedMB), perfSize(sample.swapUsedMB)))
                        .font(EU.font(12))
                        .foregroundStyle(EU.fg3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    EUStatValue(value: "N/A", color: EU.fg4)
                }
            }
        }
    }

    private func pressureText(_ level: Int) -> String {
        switch level {
        case 4:  return tr("위험")
        case 2:  return tr("부족")
        default: return tr("여유")
        }
    }

    private func pressureTone(_ level: Int) -> EUTone {
        switch level {
        case 4:  return .danger
        case 2:  return .warning
        default: return .success
        }
    }
}

/// 많이 쓰는 앱 순위 — CPU 순 또는 메모리 순
struct TopAppsCard: View {
    enum Metric { case cpu, memory }

    let title: String
    let icon: String
    let apps: [ProcSample]
    let metric: Metric
    var limit = 5

    var body: some View {
        EUCard {
            VStack(alignment: .leading, spacing: 10) {
                EUCardHeader(title: title, icon: icon)
                let top = apps.prefix(limit)
                let maxMem = Double(top.map(\.memMB).max() ?? 1)
                ForEach(Array(top)) { p in
                    HStack(spacing: 10) {
                        Text(p.name)
                            .font(EU.font(12.5, .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: EU.z(120), alignment: .leading)
                        switch metric {
                        case .cpu:
                            EUBar(value: min(p.cpu, 100) / 100,
                                  tone: p.cpu >= PerfMonitor.hogThreshold ? .warning : .neutral)
                            Text(String(format: "%.0f%%", p.cpu))
                                .font(EU.font(12.5, .semibold))
                                .monospacedDigit()
                                .frame(width: EU.z(56), alignment: .trailing)
                        case .memory:
                            EUBar(value: Double(p.memMB) / max(maxMem, 1), tone: .neutral)
                            Text(perfSize(p.memMB))
                                .font(EU.font(12.5, .semibold))
                                .monospacedDigit()
                                .frame(width: EU.z(56), alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

/// MB를 읽기 좋게 — 1GB 넘으면 GB로
func perfSize(_ v: Int) -> String {
    v >= 1024 ? String(format: "%.1fGB", Double(v) / 1024) : "\(v)MB"
}

/// 자주 원인·느려진 순간 — 기록이 바뀔 때만 다시 그린다 (.equatable()).
private struct PerfHistoryView: View, Equatable {
    let events: [SlowEvent]
    let offenders: [PerfMonitor.Offender]
    let enabled: Bool
    let onClear: () -> Void

    static func == (a: Self, b: Self) -> Bool {
        a.events == b.events && a.offenders == b.offenders && a.enabled == b.enabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            offendersCard
            eventsCard
        }
    }

    // MARK: 자주 원인

    @ViewBuilder
    private var offendersCard: some View {
        let list = offenders.prefix(5)
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
                    if !events.isEmpty {
                        Button(tr("기록 지우기")) { onClear() }
                            .buttonStyle(.eu(.light, small: true))
                    }
                }
                if events.isEmpty {
                    Text(enabled ? "아직 느려진 순간이 없습니다" : "백그라운드 기록을 켜면 기록이 시작됩니다")
                        .font(EU.font(12.5))
                        .foregroundStyle(EU.fg3)
                        .padding(.vertical, 6)
                } else {
                    ForEach(events.prefix(30)) { e in
                        eventRow(e)
                        if e.id != events.prefix(30).last?.id { EUDivider() }
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

    /// 줄마다 만들면 무거우므로 하나를 같이 쓴다.
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func timeRange(_ e: SlowEvent) -> String {
        let f = Self.timeFormat
        let secs = Int(e.end.timeIntervalSince(e.start))
        if secs < 5 { return f.string(from: e.start) }
        let dur = secs >= 60 ? trf("%d분", secs / 60) : trf("%d초", secs)
        return "\(f.string(from: e.start)) · \(dur)"
    }
}
