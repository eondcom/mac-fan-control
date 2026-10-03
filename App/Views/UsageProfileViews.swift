import SwiftUI

/// 대시보드 — 사용 모드 네 칸
struct UsageProfileCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.eu) private var eu

    var body: some View {
        let active = state.activeProfile
        EUCard {
            VStack(alignment: .leading, spacing: 12) {
                EUCardHeader(title: "사용 모드", icon: "slider.horizontal.3") {
                    EUChip(text: active?.label ?? tr("변경됨"), tone: active == nil ? .neutral : .primary)
                }
                HStack(spacing: 8) {
                    ForEach(UsageProfile.allCases) { p in
                        tile(p, selected: p == active)
                    }
                }
                Text(description(active))
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                    .fixedSize(horizontal: false, vertical: true)
                if active == nil {
                    Button {
                        state.saveCustomProfile()
                    } label: {
                        Label("지금 설정을 내 설정으로 저장", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.eu(.light, small: true))
                }
            }
        }
    }

    private func description(_ active: UsageProfile?) -> String {
        switch active {
        case .custom?:
            return trf("내 설정 — %@", state.customProfile?.summary ?? "")
        case let p?:
            return p.summary
        case nil:
            return tr("팬이나 전원을 직접 바꿨습니다. 다른 모드로 넘어가면 지금 상태가 '내 설정'으로 저장돼 언제든 돌아올 수 있습니다.")
        }
    }

    private func tile(_ p: UsageProfile, selected: Bool) -> some View {
        let disabled = p == .custom && state.customProfile == nil
        return Button {
            state.applyProfile(p)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: p.icon)
                    .font(.system(size: EU.z(18), weight: .semibold))
                Text(p.label)
                    .font(EU.font(12.5, .semibold))
            }
            .foregroundStyle(selected ? eu.onPrimary : EU.fg)
            .frame(maxWidth: .infinity, minHeight: EU.z(64))
            .background(selected ? eu.primary : EU.c2, in: RoundedRectangle(cornerRadius: EU.rRow, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .help(disabled ? tr("팬이나 전원을 직접 맞추면 '내 설정'으로 저장됩니다") : p.summary)
    }
}

/// 메뉴바 — 한 줄 빠른 전환
struct UsageProfileSeg: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            EUSeg(selection: Binding(
                    get: { state.activeProfile?.rawValue ?? "custom" },
                    set: { v in if let p = UsageProfile(rawValue: v) { state.applyProfile(p) } }),
                  options: UsageProfile.allCases.map { ($0.rawValue, $0.shortLabel) },
                  fill: true)
            Text(state.activeProfile.map { $0 == .custom ? (state.customProfile?.summary ?? $0.summary) : $0.summary } ?? tr("변경됨 — 다른 모드로 가면 내 설정에 저장"))
                .font(EU.font(11))
                .foregroundStyle(EU.fg3)
                .lineLimit(1)
        }
    }
}
