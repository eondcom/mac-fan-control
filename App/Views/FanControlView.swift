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
