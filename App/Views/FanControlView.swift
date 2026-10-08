import SwiftUI

struct FanControlView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.eu) private var eu

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "팬 제어", subtitle: "구간을 고르거나 값을 바꾸면 바로 적용됩니다") {
                Button {
                    state.useSystemFan()
                } label: {
                    Label("자동으로 복구", systemImage: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.eu(.bordered, small: true))
                .disabled(state.fanMode == .system)
                .help("macOS가 다시 팬을 제어합니다")
            }
            .padding(.bottom, 4)

            if state.helperStatus != .ready {
                helperCard()
            }

            statusCard()

            if let b = state.boostZone, let until = state.boostUntil {
                BoostBanner(zone: b, base: state.fanZone, until: until) { state.cancelBoost() }
            }

            if state.safetyOverride {
                notice(icon: "exclamationmark.triangle.fill",
                       text: trf("%d°C를 넘어 시스템 자동에 맡겼습니다. %d°C 아래로 내려오면 구간 제어로 돌아옵니다.",
                                 Int(FanCurve.safetyTemp), Int(FanCurve.resumeTemp)))
            }

            HStack(spacing: 12) {
                ForEach(FanZone.allCases) { z in
                    ZoneCard(zone: z,
                             range: state.zoneRange(z),
                             selected: state.fanMode == .zone && state.activeZone == z,
                             dimmed: state.fanMode == .system,
                             customized: state.isZoneCustomized(z),
                             badge: state.fanMode != .zone || state.boostZone == nil ? nil
                                  : (z == state.boostZone ? "임시" : (z == state.fanZone ? "기본" : nil))) {
                        state.selectZone(z)
                    }
                }
            }

            ZoneEditor(zone: state.fanZone)

            BoostSettings()
            ThermalGuardSettings()
            // 부하 테스트는 CPU 속도 제한 값으로 판정한다 — Intel 전용
            if Platform.hasSpeedLimit {
                FanCalibrationCard(cal: state.calibrator)
            }

            Text("앱을 종료하면 팬은 시스템 자동으로 돌아갑니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
        }
    }

    // MARK: - 현재 상태

    private func statusCard() -> some View {
        let t = state.thermal
        let temp = max(t.cpuTemp ?? 0, t.gpuTemp ?? 0)
        let level = TempLevel.from(temp > 0 ? temp : nil)
        let showTarget = state.fanMode == .zone && !state.safetyOverride && state.fanTarget != nil
        return EUCard {
            HStack(spacing: 0) {
                stat("지금 속도", t.fanRPM.map { $0.formatted() } ?? "—", unit: "rpm", leading: 0)
                divider()
                stat("목표", showTarget ? state.fanTarget!.formatted() : "자동",
                     unit: showTarget ? "rpm" : nil, leading: 16)
                divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("온도").font(EU.font(12, .medium)).foregroundStyle(EU.fg3)
                        if let level { EUChip(text: level.label, tone: level.tone) }
                    }
                    EUStatValue(value: temp > 0 ? String(format: "%.0f", temp) : "—", unit: "°C", size: 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("제어").font(EU.font(12, .medium)).foregroundStyle(EU.fg3)
                    EUChip(text: state.fanModeLabel,
                           tone: state.safetyOverride ? .warning : (state.fanMode == .zone ? .primary : .neutral))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }
        }
    }

    private func stat(_ title: String, _ value: String, unit: String?, leading: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr(title)).font(EU.font(12, .medium)).foregroundStyle(EU.fg3)
            EUStatValue(value: value, unit: unit, size: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, leading)
    }

    private func divider() -> some View {
        Rectangle().fill(EU.line).frame(width: 1, height: 40)
    }

    private func helperCard() -> some View {
        EUCard {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield")
                    .font(.system(size: EU.z(18), weight: .semibold))
                    .foregroundStyle(EU.warningFg)
                    .frame(width: EU.z(40), height: EU.z(40))
                    .background(EU.warningFlat, in: RoundedRectangle(cornerRadius: EU.rRow + 2, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr(state.helperStatus == .outdated ? "팬 제어 도우미를 다시 설치해야 합니다" : "팬 제어 도우미가 필요합니다"))
                        .font(EU.font(13.5, .semibold))
                    Text("팬 속도를 바꾸려면 관리자 권한이 필요합니다. 처음 한 번만 암호를 묻습니다.")
                        .font(EU.font(12))
                        .foregroundStyle(EU.fg3)
                }
                Spacer()
                Button {
                    state.installHelper()
                } label: {
                    Text(tr(state.helperInstalling ? "설치 중…" : "설치"))
                }
                .buttonStyle(.eu(.solid))
                .disabled(state.helperInstalling)
            }
        }
    }

    private func notice(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: EU.z(12), weight: .semibold))
            Text(tr(text)).font(EU.font(12.5, .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(EU.warningFg)
        .padding(12)
        .background(EU.warningFlat, in: RoundedRectangle(cornerRadius: EU.rRow + 2, style: .continuous))
    }
}

// MARK: - 구간 카드

private struct ZoneCard: View {
    let zone: FanZone
    let range: ClosedRange<Int>
    let selected: Bool
    let dimmed: Bool
    let customized: Bool
    var badge: String? = nil
    let action: () -> Void

    @Environment(\.eu) private var eu
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: zone.icon)
                        .font(.system(size: EU.z(14), weight: .semibold))
                        .foregroundStyle(selected ? eu.fg : EU.fg3)
                    Text(zone.label)
                        .font(EU.font(15, .bold))
                        .foregroundStyle(selected ? eu.fg : EU.fg)
                    Spacer()
                    if let badge {
                        EUChip(text: badge, tone: badge == "임시" ? .warning : .neutral)
                    }
                    if selected {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(eu.primary)
                    } else if customized && badge == nil {
                        EUChip(text: "조정됨")
                    }
                }
                Text("\(range.lowerBound.formatted()) – \(range.upperBound.formatted()) rpm")
                    .font(EU.font(12.5, .semibold))
                    .foregroundStyle(EU.fg2)
                    .monospacedDigit()
                Text(zone.hint)
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(selected ? eu.row : (hovering ? EU.c2 : EU.c1),
                        in: RoundedRectangle(cornerRadius: EU.rCard, style: .continuous))
            .opacity(dimmed && !hovering ? 0.7 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: - 선택한 구간 설정

private struct ZoneEditor: View {
    let zone: FanZone
    @EnvironmentObject var state: AppState

    var body: some View {
        let range = state.zoneRange(zone)
        let hw = state.hardwareRange

        EUCard(padding: 20) {
            VStack(alignment: .leading, spacing: 16) {
                EUCardHeader(title: trf("%@ 구간 설정", zone.label), icon: "slider.horizontal.3") {
                    Button {
                        state.resetZone(zone)
                    } label: {
                        Label("기본값으로", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.eu(.light, small: true))
                    .disabled(!state.isZoneCustomized(zone))
                }

                // 고정 여부
                Toggle(isOn: Binding(get: { state.fanFixed }, set: { state.setFanFixed($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("이 값으로 고정").font(EU.font(13, .semibold))
                        Text(tr(state.fanFixed
                             ? "온도와 상관없이 아래 값으로 돌립니다"
                             : "끄면 온도에 따라 하한~상한 사이에서 자동으로 움직입니다"))
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.fg3)
                    }
                }
                .toggleStyle(.eu)

                // 상한 또는 고정값
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(tr(state.fanFixed ? "고정값" : "상한"))
                            .font(EU.font(12, .medium))
                            .foregroundStyle(EU.fg3)
                        Spacer()
                        EUStatValue(value: state.zoneValue.formatted(), unit: "rpm", size: 24)
                    }
                    EUSlider(value: Binding(get: { state.zoneValue }, set: { state.setZoneValue($0) }),
                             bounds: range, step: 50, marker: state.thermal.fanRPM)
                    scale(range)
                    if !state.fanFixed {
                        Text(trf("%1$d°C 이하 → %2$@ rpm  ·  %3$d°C 이상 → %4$@ rpm", Int(FanCurve.coolTemp), range.lowerBound.formatted(), Int(FanCurve.warmTemp), state.zoneCap(zone).formatted()))
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.fg4)
                    }
                }

                EUDivider()

                // 구간 범위
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("구간 범위")
                            .font(EU.font(12, .medium))
                            .foregroundStyle(EU.fg3)
                        Spacer()
                        Text("\(range.lowerBound.formatted()) – \(range.upperBound.formatted()) rpm")
                            .font(EU.font(13, .semibold))
                            .monospacedDigit()
                    }
                    EURangeSlider(
                        lower: Binding(get: { range.lowerBound },
                                       set: { state.setZoneBounds(zone, lower: $0, upper: range.upperBound) }),
                        upper: Binding(get: { range.upperBound },
                                       set: { state.setZoneBounds(zone, lower: range.lowerBound, upper: $0) }),
                        bounds: hw, step: 100, minGap: 100)
                    scale(hw)
                    Text(trf("기본 %@ – %@ rpm", zone.baseRange.lowerBound.formatted(), zone.baseRange.upperBound.formatted()))
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg4)
                }
            }
        }
    }

    private func scale(_ r: ClosedRange<Int>) -> some View {
        HStack {
            Text(r.lowerBound.formatted())
            Spacer()
            Text(r.upperBound.formatted())
        }
        .font(EU.font(11))
        .foregroundStyle(EU.fg4)
        .monospacedDigit()
    }
}

// MARK: - 고온 임시 상향

private struct BoostBanner: View {
    let zone: FanZone
    let base: FanZone
    let until: Date
    let revert: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let mins = max(Int(ceil(until.timeIntervalSince(ctx.date) / 60)), 0)
            HStack(spacing: 12) {
                Image(systemName: "thermometer.sun.fill")
                    .font(.system(size: EU.z(15), weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text(trf("온도가 높아 %@ 구간을 임시로 쓰는 중", zone.label))
                        .font(EU.font(13, .semibold))
                    Text(trf("%1$d분 뒤 기본 설정(%2$@)으로 돌아갑니다", mins, base.label))
                        .font(EU.font(12))
                        .opacity(0.85)
                }
                Spacer()
                Button("지금 되돌리기", action: revert)
                    .buttonStyle(.eu(.bordered, small: true))
            }
            .foregroundStyle(EU.warningFg)
            .padding(14)
            .background(EU.warningFlat, in: RoundedRectangle(cornerRadius: EU.rCard, style: .continuous))
        }
    }
}

private struct BoostSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        EUCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                EUCardHeader(title: "고온 자동 상향", icon: "thermometer.high")

                Toggle(isOn: $state.preemptFan) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("부하가 오르면 팬 미리 올리기").font(EU.font(13, .semibold))
                            if state.preemptFan && state.preemptLead > 0 && state.fanMode == .zone {
                                EUChip(text: "작동 중", tone: .primary)
                            }
                        }
                        Text("온도는 CPU 부하보다 몇 초 늦게 오릅니다. 부하가 50% 넘으면 미리 팬을 올려 온도 정점을 낮춥니다 (구간 상한은 넘지 않음)")
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.fg3)
                    }
                }
                .toggleStyle(.eu)

                EUDivider()

                Toggle(isOn: $state.throttleFanProtect) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("속도 제한이 걸리면 팬을 시스템에 맡기기").font(EU.font(13, .semibold))
                            if state.throttleOverride { EUChip(text: "작동 중", tone: .warning) }
                        }
                        Text(tr(Platform.hasSpeedLimit
                                ? "팬을 낮게 두면 CPU 온도가 정상이어도 전원부가 데워져 속도가 깎일 수 있습니다. 깎이면 4초 안에 macOS 자동 팬으로 넘기고, 1분 넘게 풀려 있으면 구간 제어로 돌아옵니다"
                                : "macOS 열 상태가 '높음' 이상이면 성능을 줄이고 있다는 뜻입니다. 4초 안에 macOS 자동 팬으로 넘기고, 1분 넘게 내려와 있으면 구간 제어로 돌아옵니다"))
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.fg3)
                    }
                }
                .toggleStyle(.eu)

                EUDivider()

                Toggle(isOn: Binding(get: { state.boostEnabled }, set: { state.setBoostEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("뜨거우면 다음 구간으로 1시간").font(EU.font(13, .semibold))
                        Text(trf("기준 온도가 %d초 넘게 이어지면 알림과 함께 한 구간 올리고, 1시간 뒤 기본 설정으로 되돌립니다", Int(FanCurve.boostSustain)))
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.fg3)
                    }
                }
                .toggleStyle(.eu)

                if state.boostEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("기준 온도").font(EU.font(12, .medium)).foregroundStyle(EU.fg3)
                            Spacer()
                            EUStatValue(value: "\(state.boostTemp)", unit: "°C", size: 22)
                        }
                        EUSlider(value: Binding(get: { state.boostTemp }, set: { state.boostTemp = $0 }),
                                 bounds: 70...88, step: 1)
                        HStack {
                            Text("70°C")
                            Spacer()
                            Text("88°C")
                        }
                        .font(EU.font(11))
                        .foregroundStyle(EU.fg4)
                    }
                }
            }
        }
    }
}

/// 스로틀 전 자동 절전 — 뜨거우면 저전력 모드로 터보를 막는다.
private struct ThermalGuardSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        EUCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                EUCardHeader(title: "스로틀 전 자동 절전", icon: "bolt.badge.clock") {
                    if state.guardActive { EUChip(text: "절전 중", tone: .success, icon: "leaf.fill") }
                }

                Toggle(isOn: Binding(get: { state.guardEnabled }, set: { state.setGuardEnabled($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("뜨거우면 저전력 모드로").font(EU.font(13, .semibold))
                        Text(trf("CPU가 켜는 온도 이상으로 %d초 이어지면 저전력 모드로 터보를 낮추고, 끄는 온도 아래로 %d분 식으면 되돌립니다",
                                 Int(AppState.guardSustain), Int(AppState.guardCooldown / 60)))
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.fg3)
                    }
                }
                .toggleStyle(.eu)

                if state.guardEnabled {
                    if state.helperStatus != .ready {
                        Text("팬 제어 도우미를 설치해야 암호 없이 자동으로 바뀝니다")
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.warningFg)
                    }
                    tempSlider(title: "켜는 온도", value: state.guardOnTemp, bounds: 75...95) {
                        state.setGuardTemps(on: $0)
                    }
                    tempSlider(title: "끄는 온도", value: state.guardOffTemp, bounds: 55...85) {
                        state.setGuardTemps(off: $0)
                    }
                }

                // 스로틀 기록은 CPU 속도 제한 값으로 쌓는다 — Intel 전용
                if Platform.hasSpeedLimit {
                    EUDivider()
                    ThrottleHistoryPanel(log: state.throttleLog)
                }
            }
        }
    }

    private func tempSlider(title: String, value: Int, bounds: ClosedRange<Int>,
                            set: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(tr(title)).font(EU.font(12, .medium)).foregroundStyle(EU.fg3)
                Spacer()
                EUStatValue(value: "\(value)", unit: "°C", size: 22)
            }
            EUSlider(value: Binding(get: { value }, set: set), bounds: bounds, step: 1)
            HStack {
                Text("\(bounds.lowerBound)°C")
                Spacer()
                Text("\(bounds.upperBound)°C")
            }
            .font(EU.font(11))
            .foregroundStyle(EU.fg4)
        }
    }
}

/// 스로틀 기록과 추천 온도 — 실제로 속도 제한이 걸린 온도를 보고 켜는 온도를 맞춘다.
private struct ThrottleHistoryPanel: View {
    @ObservedObject var log: ThrottleLog
    @EnvironmentObject var state: AppState

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("스로틀 기록").font(EU.font(13, .semibold))
                EUChip(text: trf("열 %d · 전원 %d", log.thermalCount, log.powerCount))
                Spacer()
                if !log.records.isEmpty {
                    Button(tr("기록 지우기")) { log.clear() }
                        .buttonStyle(.eu(.light, small: true))
                }
            }

            if let f = log.fanRecommendation {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(trf("추천 팬 하한 — %@ rpm 이상", f.rpm.formatted()))
                            .font(EU.font(12.5, .semibold))
                        Spacer()
                        Button(tr("구간 하한에 적용")) { state.applyFanFloor(f.rpm) }
                            .buttonStyle(.eu(.solid, small: true))
                            .disabled(FanZone.allCases.allSatisfy { state.zoneRange($0).lowerBound >= f.rpm })
                    }
                    Text(trf("팬을 제어하다 속도 제한이 걸린 적 %d번, 그때 팬은 최고 %@ rpm 이었습니다. 300 rpm 여유를 두었습니다. 모든 구간의 하한을 이 값 이상으로 올립니다.",
                             f.basis, f.highest.formatted()))
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let r = log.recommendation {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(trf("추천 — 켜는 온도 %d°C · 끄는 온도 %d°C", r.on, r.off))
                            .font(EU.font(12.5, .semibold))
                        Spacer()
                        Button(tr("추천값 적용")) { state.applyGuardRecommendation() }
                            .buttonStyle(.eu(.solid, small: true))
                            .disabled(r.on == state.guardOnTemp && r.off == state.guardOffTemp)
                    }
                    Text(trf("열 때문인 스로틀 %d번 — 시작 온도 최저 %d°C, 가운데 %d°C. 대부분보다 먼저 켜지도록 하위 20%% 지점에서 3°C 낮췄습니다.",
                             r.basis, r.lowest, r.median))
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                    Toggle(isOn: $state.guardAutoRecommend) {
                        Text("새 기록이 쌓이면 추천값 자동 적용").font(EU.font(12))
                    }
                    .toggleStyle(.eu)
                }
            } else {
                Text(trf("열 때문인 스로틀이 %d번 쌓이면 그 온도를 보고 켜는 온도를 추천합니다 (지금 %d번). 이 기록은 v2.3.2부터 쌓입니다.",
                         ThrottleLog.minBasis, log.thermalCount))
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if log.powerCount > 0 {
                Text(trf("온도가 정상인데 걸린 스로틀 %d번은 전원·배터리 원인이라 자동 절전으로 막을 수 없습니다 — 성능 탭의 속도 저하 진단을 보세요.", log.powerCount))
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.warningFg)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(log.records.prefix(5)) { r in
                HStack(spacing: 8) {
                    Text(Self.timeFormat.string(from: r.start))
                        .font(EU.font(11.5)).monospacedDigit().foregroundStyle(EU.fg3)
                    EUChip(text: r.isThermal ? "열" : "전원", tone: r.isThermal ? .warning : .neutral)
                    Text(trf("시작 %.0f°C · 직전 최고 %.0f°C", r.startTemp, r.peakBefore))
                        .font(EU.font(11.5)).monospacedDigit()
                    if let rpm = r.fanRPM {
                        Text(trf("팬 %@ rpm%@", rpm.formatted(), r.fanControlled == true ? tr(" (앱 제어)") : ""))
                            .font(EU.font(11.5)).monospacedDigit()
                            .foregroundStyle(r.fanControlled == true ? EU.warningFg : EU.fg3)
                    }
                    Spacer()
                    Text(trf("최저 속도 %d%%", r.minSpeed))
                        .font(EU.font(11.5)).monospacedDigit().foregroundStyle(EU.fg3)
                }
            }
        }
    }
}

/// 팬·전원 부하 테스트 — 속도 제한이 팬 때문인지 전원 때문인지 가르고, 팬 때문이면 추천 하한을 구한다.
private struct FanCalibrationCard: View {
    @ObservedObject var cal: FanCalibrator
    @EnvironmentObject var state: AppState
    @State private var confirm = false

    var body: some View {
        EUCard(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: "팬·전원 부하 테스트", icon: "gauge.with.needle") {
                    if cal.isRunning { EUChip(text: "측정 중", tone: .warning) }
                }
                Text("CPU에 부하를 걸고 ① 팬 최대에서 속도가 깎이는지 보고(깎이면 전원·배터리 원인), ② 팬을 4,500 rpm 부터 300 rpm 씩 내리며 깎이는 지점을 찾아 추천 팬 하한을 계산합니다. 5~7분 걸리고 팬 소리가 커집니다.")
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                    .fixedSize(horizontal: false, vertical: true)

                if cal.isRunning {
                    progress
                } else {
                    if let b = cal.blocker(state) {
                        Text(b).font(EU.font(11.5)).foregroundStyle(EU.warningFg)
                    }
                    Button {
                        confirm = true
                    } label: {
                        Label(cal.result == nil ? "테스트 시작" : "다시 측정", systemImage: "play.fill")
                    }
                    .buttonStyle(.eu(.solid, small: true))
                    .disabled(cal.blocker(state) != nil)
                }

                if let m = cal.message {
                    Text(m).font(EU.font(11.5)).foregroundStyle(EU.fg3)
                }
                if let r = cal.result, !cal.isRunning {
                    EUDivider()
                    resultView(r)
                }
            }
        }
        .confirmationDialog(tr("부하 테스트를 시작할까요?"), isPresented: $confirm, titleVisibility: .visible) {
            Button(tr("시작")) { cal.start(state) }
        } message: {
            Text("5~7분 동안 CPU를 최대로 쓰고 팬이 크게 돕니다. 무거운 작업은 끝내고 시작하세요. 언제든 취소할 수 있고, CPU가 95°C에 닿으면 자동으로 멈춥니다.")
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(cal.phase == .maxCheck ? tr("① 팬 최대에서 확인") : tr("② 팬 단계적으로 낮추기"))
                    .font(EU.font(12.5, .semibold))
                Spacer()
                Button(tr("취소")) { cal.cancel() }
                    .buttonStyle(.eu(.light, small: true))
            }
            HStack(spacing: 14) {
                stat(tr("팬 목표"), cal.targetRPM.map { "\($0.formatted()) rpm" } ?? "—")
                stat(tr("CPU"), cal.lastTemp.map { String(format: "%.0f°C", $0) } ?? "—")
                stat(tr("CPU 속도"), cal.lastSpeed.map { "\($0)%" } ?? "—")
                stat(tr("다음 단계까지"), trf("%.0f초", cal.stepRemaining))
            }
            Text(trf("경과 %d분 %d초", Int(cal.elapsed) / 60, Int(cal.elapsed) % 60))
                .font(EU.font(11)).foregroundStyle(EU.fg4).monospacedDigit()
        }
    }

    private func stat(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(EU.font(11)).foregroundStyle(EU.fg3)
            Text(v).font(EU.font(13, .semibold)).monospacedDigit()
        }
    }

    @ViewBuilder
    private func resultView(_ r: FanCalibrator.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trf("마지막 측정 · %@", r.date.formatted(date: .abbreviated, time: .shortened)))
                .font(EU.font(11)).foregroundStyle(EU.fg4)
            if r.powerLimited {
                Text("전원·배터리 원인 — 팬과 무관합니다").font(EU.font(13, .semibold)).foregroundStyle(EU.warningFg)
                Text(trf("팬을 최대로 돌려도(최고 %.0f°C) 부하가 걸리자 속도가 깎였습니다. 팬 하한을 올려도 막을 수 없습니다. 배터리 건강도·충전기를 확인하세요 (성능 탭 → 속도 저하 진단).", r.maxTemp))
                    .font(EU.font(11.5)).foregroundStyle(EU.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let rpm = r.throttleRPM {
                HStack(alignment: .firstTextBaseline) {
                    Text(trf("추천 팬 하한 %@ rpm", r.recommended.formatted()))
                        .font(EU.font(13, .semibold))
                    Spacer()
                    Button(tr("구간 하한에 적용")) { state.applyFanFloor(r.recommended) }
                        .buttonStyle(.eu(.solid, small: true))
                        .disabled(FanZone.allCases.allSatisfy { state.zoneRange($0).lowerBound >= r.recommended })
                }
                Text(r.hitTempLimit
                     ? trf("%@ rpm 에서 CPU가 95°C에 닿아 멈췄습니다. 300 rpm 여유를 두었습니다.", rpm.formatted())
                     : trf("%@ rpm 에서 속도 제한이 걸렸습니다. 300 rpm 여유를 두었습니다.", rpm.formatted()))
                    .font(EU.font(11.5)).foregroundStyle(EU.fg3)
            } else {
                Text("최저 rpm 까지 속도 제한이 없었습니다 — 팬 하한 제한이 필요 없습니다")
                    .font(EU.font(13, .semibold)).foregroundStyle(EU.successFg)
            }
        }
    }
}
