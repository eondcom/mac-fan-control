import SwiftUI

struct DisplayView: View {
    @EnvironmentObject var displays: DisplayState
    @Environment(\.eu) private var eu
    /// 낮은 해상도까지 펼친 화면
    @State private var expanded: Set<CGDirectDisplayID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "모니터", subtitle: "연결된 화면과 해상도, 그래픽 부하를 관리합니다") {
                Button {
                    displays.refresh()
                } label: {
                    Label(tr("새로고침"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.eu(.bordered, small: true))
            }
            .padding(.bottom, 4)

            loadCard

            if let b = displays.builtin {
                builtinCard(b)
            }

            ForEach(displays.displays.filter { !$0.isDisabled }) { d in
                resolutionCard(d)
            }

            if let err = displays.lastError {
                EUChip(text: err, tone: .danger, icon: "exclamationmark.triangle.fill")
            }

            Text("1배·2배 해상도는 패널 픽셀을 그대로 써서 가볍습니다. 그 사이 배율은 더 크게 그린 뒤 줄여서 보내므로 Intel 맥에서 그래픽 부하가 큽니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            displays.refresh()
            displays.startLoadMonitor()
        }
        .onDisappear { displays.stopLoadMonitor() }
    }

    // MARK: 그래픽 부하

    private var loadCard: some View {
        let active = displays.displays.filter { !$0.isDisabled }
        let pixels = active.reduce(0) { $0 + ($1.current.map { $0.pixelWidth * $0.pixelHeight } ?? 0) }
        let cpu = displays.windowServerCPU

        return HStack(alignment: .top, spacing: 12) {
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: "화면 그리기 CPU", icon: "cpu") {
                        if let cpu { EUChip(text: cpuLabel(cpu), tone: cpuTone(cpu)) }
                    }
                    EUStatValue(value: cpu.map { String(format: "%.0f", $0) } ?? "—", unit: "%")
                    EUBar(value: (cpu ?? 0) / 100, tone: cpu.map(cpuTone) ?? .neutral)
                    Text("코어 1개 기준 · 전체 CPU의 일부입니다")
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg4)
                }
            }
            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: "켜진 화면", icon: "display.2")
                    EUStatValue(value: "\(active.count)", unit: "개")
                    Text(trf("그리는 픽셀 %.1fM", Double(pixels) / 1_000_000))
                        .font(EU.font(12))
                        .foregroundStyle(EU.fg3)
                }
            }
        }
    }

    // WindowServer는 화면이 움직일 때마다 튀므로 코어 하나의 30% 정도까지는 평범하다.
    private func cpuTone(_ v: Double) -> EUTone {
        if v < 30 { return .success }
        if v < 60 { return .warning }
        return .danger
    }

    private func cpuLabel(_ v: Double) -> String {
        if v < 30 { return "가벼움" }
        if v < 60 { return "보통" }
        return "무거움"
    }

    // MARK: 내장 화면

    private func builtinCard(_ b: DisplayInfo) -> some View {
        let hasExternal = displays.displays.contains { !$0.isBuiltin && !$0.isDisabled }

        return EUCard(padding: 0) {
            VStack(spacing: 0) {
                EUListRow {
                    HStack(spacing: 12) {
                        Image(systemName: b.isDisabled ? "laptopcomputer.slash" : "laptopcomputer")
                            .font(.system(size: 18))
                            .foregroundStyle(b.isDisabled ? EU.fg4 : eu.fg)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("내장 화면")
                                .font(EU.font(13, .semibold))
                            Text(b.isDisabled ? "꺼짐 — 외장 모니터만 사용 중" : "켜짐")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                        Spacer()
                        if b.isDisabled {
                            Button(tr("켜기")) { displays.setBuiltin(enabled: true) }
                                .buttonStyle(.eu(.flat, small: true))
                        } else {
                            Button(tr("끄기")) { displays.setBuiltin(enabled: false) }
                                .buttonStyle(.eu(.solid, small: true))
                                .disabled(!hasExternal || !DisplayService.canToggle)
                        }
                    }
                    .padding(.vertical, 10)
                }
                EUDivider()
                EUListRow {
                    Toggle(isOn: $displays.autoBuiltinOff) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("외장 모니터 연결 시 자동으로 끄기")
                            Text("모니터를 뽑거나 앱을 끄면 내장 화면이 다시 켜집니다")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                    }
                    .toggleStyle(.eu)
                    .padding(.vertical, 8)
                }
            }
            .font(EU.font(13))
        }
    }

    // MARK: 해상도

    private func resolutionCard(_ d: DisplayInfo) -> some View {
        EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: d.name, icon: d.isBuiltin ? "laptopcomputer" : "display") {
                    if d.isMain { EUChip(text: "주 화면", tone: .primary) }
                    if let c = d.current {
                        EUChip(text: "\(c.pixelWidth)×\(c.pixelHeight) · \(Int(c.refresh.rounded()))Hz")
                    }
                }
                let showAll = expanded.contains(d.id)
                let hidden = d.modes.filter { isLowRes($0, in: d) }
                VStack(spacing: 4) {
                    ForEach(d.modes.filter { showAll || !isLowRes($0, in: d) }) { m in
                        modeRow(m, display: d)
                    }
                }
                if !hidden.isEmpty {
                    Button {
                        if showAll { expanded.remove(d.id) } else { expanded.insert(d.id) }
                    } label: {
                        Label(showAll ? tr("낮은 해상도 접기") : trf("낮은 해상도 %d개 더 보기", hidden.count),
                              systemImage: showAll ? "chevron.up" : "chevron.down")
                    }
                    .buttonStyle(.eu(.light, small: true))
                }
            }
        }
    }

    /// 흐린 해상도는 지금 쓰는 게 아니면 접어 둔다.
    private func isLowRes(_ m: DisplayModeInfo, in d: DisplayInfo) -> Bool {
        m.load(native: d.nativeWidth) == .blurry && d.current?.id != m.id
    }

    private func modeRow(_ m: DisplayModeInfo, display d: DisplayInfo) -> some View {
        let selected = d.current?.id == m.id
        let load = m.load(native: d.nativeWidth)

        return Button {
            if !selected { displays.setMode(m, on: d) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? eu.primary : EU.fg4)
                Text(m.label)
                    .font(EU.font(13, selected ? .semibold : .medium))
                    .monospacedDigit()
                Text(trf("글자 %d%%", m.scalePercent(native: d.nativeWidth)))
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                Spacer()
                switch load {
                case .light:  EUChip(text: "가벼움", tone: .success)
                case .heavy:  EUChip(text: "부하 큼", tone: .warning)
                case .blurry: EUChip(text: "흐림", tone: .neutral)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(selected ? eu.row : .clear,
                        in: RoundedRectangle(cornerRadius: EU.rRow, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
