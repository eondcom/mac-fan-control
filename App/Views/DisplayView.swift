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
                    displays.refreshLinks()
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

            if displays.displays.contains(where: { !$0.isBuiltin }) {
                externalCard
            }

            ForEach(displays.displays.filter { !$0.isDisabled }) { d in
                resolutionCard(d)
                colorCard(d)
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
                            .font(.system(size: EU.z(18)))
                            .foregroundStyle(b.isDisabled ? EU.fg4 : eu.fg)
                            .frame(width: EU.z(28))
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
                            Text("화면이 안 나오면 ⌃⌥⌘B — 내장 화면이 바로 켜집니다")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                    }
                    .toggleStyle(.eu)
                    .padding(.vertical, 8)
                }
                EUDivider()
                EUListRow {
                    warning
                        .padding(.vertical, 8)
                }
            }
            .font(EU.font(13))
        }
    }

    // MARK: 외장 모니터

    /// 화면을 연결한 채 꺼 두면(비공개 macOS 기능) 절전에서 깨어날 때 남은 화면까지 검게 남는 경우가 있다 — 2026-10-04 두 번 확인.
    private var warning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(EU.warningFg)
            Text("화면을 연결한 채 꺼 두면 절전에서 깨어날 때 화면이 안 켜질 수 있습니다. 그럴 땐 케이블을 뽑거나 ⌃⌥⌘B 를 누르세요. 충전만 하려면 모니터 전원 버튼으로 끄고 모니터 메뉴의 '대기 중 USB-C 전원 공급'을 켜 두는 쪽이 안전합니다")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var externalCard: some View {
        EUCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(displays.displays.filter { !$0.isBuiltin }) { d in
                    EUListRow {
                        HStack(spacing: 12) {
                            Image(systemName: d.isDisabled ? "display.trianglebadge.exclamationmark" : "display")
                                .font(.system(size: EU.z(18)))
                                .foregroundStyle(d.isDisabled ? EU.fg4 : EU.fg)
                                .frame(width: EU.z(28))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.name)
                                    .font(EU.font(13, .semibold))
                                Text(d.isDisabled ? tr("꺼짐 — 연결은 유지(충전은 그대로)") : tr("켜짐"))
                                    .font(EU.font(11.5))
                                    .foregroundStyle(EU.fg3)
                            }
                            Spacer()
                            if d.isDisabled {
                                Button(tr("켜기")) { displays.setExternal(d, enabled: true) }
                                    .buttonStyle(.eu(.flat, small: true))
                            } else {
                                Button(tr("끄기")) { displays.setExternal(d, enabled: false) }
                                    .buttonStyle(.eu(.light, small: true))
                                    .disabled(!DisplayService.canToggle)
                                    .help(tr("내장 화면을 먼저 켠 뒤 이 모니터를 끕니다"))
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    EUDivider()
                }
                EUListRow {
                    warning
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
                    if let link = displays.links[d.id], link != .builtin {
                        EUChip(text: link.label, tone: link.mayLimitColor ? .warning : .success, icon: "cable.connector")
                    }
                    if d.isMain { EUChip(text: "주 화면", tone: .primary) }
                    if let c = d.current {
                        EUChip(text: c.refresh > 0
                               ? "\(c.pixelWidth)×\(c.pixelHeight) · \(Int(c.refresh.rounded()))Hz"
                               : "\(c.pixelWidth)×\(c.pixelHeight)")
                    }
                }
                let showAll = expanded.contains(d.id)
                let hidden = d.modes.filter { isLowRes($0, in: d) }
                if displays.links[d.id]?.mayLimitColor == true {
                    Text("HDMI로 연결하면 맥이 TV처럼 색 범위를 줄여 보내 색이 연해질 수 있습니다. USB-C·DisplayPort 연결을 권장합니다.")
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.warningFg)
                        .fixedSize(horizontal: false, vertical: true)
                }
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

    // MARK: 색상 프로필

    @ViewBuilder
    private func colorCard(_ d: DisplayInfo) -> some View {
        if let entry = displays.profiles[d.id], !entry.candidates.isEmpty {
            let native = entry.candidates.first { $0.role == .native }?.profile
            let current = entry.current
            let fit = current.map { ColorProfileService.fit($0, native: native) } ?? .unknown

            EUCard {
                VStack(alignment: .leading, spacing: 12) {
                    EUCardHeader(title: trf("색상 프로필 · %@", d.name), icon: "paintpalette") {
                        fitChip(fit)
                    }
                    if let current {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trf("지금: %@", current.name))
                                .font(EU.font(13, .semibold))
                                .lineLimit(1)
                            Text(tr(fitText(fit)))
                                .font(EU.font(12))
                                .foregroundStyle(fit == .good ? EU.fg3 : EU.warningFg)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    VStack(spacing: 4) {
                        ForEach(entry.candidates) { c in
                            profileRow(c, display: d, current: current)
                        }
                    }
                    Text("모니터 자체 메뉴(OSD)의 색 모드와 맞추세요. 표준·기본 모드면 추천 프로필, sRGB 모드면 sRGB, DCI-P3 모드면 Display P3, Adobe RGB 모드면 Adobe RGB를 고릅니다.")
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func profileRow(_ c: ProfileCandidate, display d: DisplayInfo, current: ColorProfileInfo?) -> some View {
        let selected = current?.url.standardizedFileURL == c.profile.url.standardizedFileURL
        let gamut = c.profile.gamutArea.map { Int(($0 / ColorProfileService.sRGBArea * 100).rounded()) }

        return Button {
            if !selected { displays.applyProfile(c.profile, to: d) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? eu.primary : EU.fg4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.profile.name)
                        .font(EU.font(13, selected ? .semibold : .medium))
                        .lineLimit(1)
                    Text(tr(roleText(c.role)))
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg3)
                        .lineLimit(1)
                }
                Spacer()
                if let gamut {
                    Text(trf("색 영역 sRGB의 %d%%", gamut))
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg3)
                        .monospacedDigit()
                }
                if c.role == .native { EUChip(text: "추천", tone: .success) }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: EU.z(40))
            .background(selected ? eu.row : .clear,
                        in: RoundedRectangle(cornerRadius: EU.rRow, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func fitChip(_ fit: ProfileFit) -> some View {
        switch fit {
        case .good:       EUChip(text: "패널과 맞음", tone: .success, icon: "checkmark")
        case .tooNarrow:  EUChip(text: "과하게 진함", tone: .warning)
        case .tooWide:    EUChip(text: "색이 바램", tone: .warning)
        case .linear:     EUChip(text: "밋밋함", tone: .danger)
        case .notDisplay: EUChip(text: "모니터용 아님", tone: .danger)
        case .unknown:    EmptyView()
        }
    }

    private func fitText(_ fit: ProfileFit) -> String {
        switch fit {
        case .good:       return "패널의 실제 색 영역과 맞습니다."
        case .tooNarrow:  return "프로필이 패널보다 좁아서 밝은 색이 형광빛처럼 과하게 보일 수 있습니다."
        case .tooWide:    return "프로필이 패널보다 넓어서 색이 바래고 무미건조하게 보일 수 있습니다."
        case .linear:     return "선형(감마 1.0) 작업용 프로필이라 명암과 색이 밋밋하게 보입니다. 화면용으로는 맞지 않습니다."
        case .notDisplay: return "효과용·변환용 프로필이라 정확한 색이 나오지 않습니다."
        case .unknown:    return "패널 정보를 알 수 없어 비교하지 못했습니다."
        }
    }

    private func roleText(_ role: ProfileRole) -> String {
        switch role {
        case .native:    return "이 모니터가 알려준 패널 색으로 만든 프로필"
        case .sRGB:      return "모니터를 sRGB 모드로 둘 때 · 웹·문서"
        case .displayP3: return "모니터를 DCI-P3 모드로 둘 때 · 사진·영상"
        case .adobeRGB:  return "모니터를 Adobe RGB 모드로 둘 때 · 인쇄용 사진"
        case .other:     return "지금 적용된 프로필"
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
            .frame(height: EU.z(32))
            .background(selected ? eu.row : .clear,
                        in: RoundedRectangle(cornerRadius: EU.rRow, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
