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
                    EUChip(text: active?.label ?? tr("사용자 지정"), tone: active == nil ? .neutral : .primary)
                }
                HStack(spacing: 8) {
                    ForEach(UsageProfile.allCases) { p in
                        tile(p, selected: p == active)
                    }
                }
                Text(active?.summary ?? tr("팬이나 전원 모드를 직접 바꿔 사용자 지정 상태입니다. 모드를 고르면 한 번에 맞춰집니다."))
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func tile(_ p: UsageProfile, selected: Bool) -> some View {
        Button {
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
        .help(p.summary)
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
            Text(state.activeProfile?.summary ?? tr("사용자 지정"))
                .font(EU.font(11))
                .foregroundStyle(EU.fg3)
                .lineLimit(1)
        }
    }
}
