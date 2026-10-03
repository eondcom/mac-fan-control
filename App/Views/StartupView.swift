import SwiftUI
import AppKit

/// 시작 프로그램 — 로그인 항목과 백그라운드 항목(launchd)을 경로와 함께 보여주고 끄기·켜기·삭제
struct StartupView: View {
    @StateObject private var startup = StartupState()
    @EnvironmentObject var state: AppState
    @State private var pendingDelete: LaunchItem?
    @State private var pendingLoginRemove: LoginItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            EUPageHeader(title: "시작 프로그램", subtitle: "로그인하거나 맥이 켜질 때 실행되는 프로그램") {
                HStack(spacing: 6) {
                    Button {
                        NSWorkspace.shared.open(StartupService.settingsURL)
                    } label: {
                        Label("시스템 설정", systemImage: "gearshape")
                    }
                    .buttonStyle(.eu(.light, small: true))
                    Button {
                        startup.refresh()
                    } label: {
                        Label("새로고침", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.eu(.bordered, small: true))
                }
            }
            .padding(.bottom, 4)

            if let e = startup.lastError {
                Text(e)
                    .font(EU.font(12))
                    .foregroundStyle(EU.dangerFg)
            }

            loginCard

            ForEach(LaunchScope.allCases) { scope in
                launchCard(scope)
            }

            Text("끈 항목은 다시 로그인하거나 재부팅해도 실행되지 않고, 켜면 바로 다시 실행됩니다. 삭제는 내 계정 항목만 할 수 있고 파일은 휴지통으로 갑니다. 시스템 설정에서 끈 항목은 여기서 켜짐으로 보일 수 있습니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { startup.refresh() }
        .confirmationDialog(trf("%@을(를) 삭제할까요?", pendingDelete?.displayName ?? ""),
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible) {
            Button(tr("휴지통으로 이동"), role: .destructive) {
                if let i = pendingDelete { startup.delete(i) }
                pendingDelete = nil
            }
        } message: {
            Text(pendingDelete?.plist.path ?? "")
        }
        .confirmationDialog(trf("%@을(를) 로그인 항목에서 뺄까요?", pendingLoginRemove?.name ?? ""),
                            isPresented: Binding(get: { pendingLoginRemove != nil }, set: { if !$0 { pendingLoginRemove = nil } }),
                            titleVisibility: .visible) {
            Button(tr("빼기"), role: .destructive) {
                if let i = pendingLoginRemove { startup.removeLoginItem(i) }
                pendingLoginRemove = nil
            }
        }
    }

    // MARK: 로그인 항목

    private var loginCard: some View {
        EUCard {
            VStack(alignment: .leading, spacing: 10) {
                EUCardHeader(title: "로그인 시 열기", icon: "person.crop.circle.badge.checkmark") {
                    EUChip(text: "\(startup.loginItems.count)")
                }
                Text("로그인하면 바로 열리는 앱 — 윈도우의 시작프로그램과 같습니다")
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                if let e = startup.loginError {
                    Text(e).font(EU.font(12)).foregroundStyle(EU.warningFg)
                        .fixedSize(horizontal: false, vertical: true)
                } else if startup.loginItems.isEmpty {
                    Text(startup.loading ? "불러오는 중…" : "없음")
                        .font(EU.font(12.5)).foregroundStyle(EU.fg3)
                }
                ForEach(startup.loginItems) { item in
                    HStack(spacing: 10) {
                        appIcon(item.path.map(URL.init(fileURLWithPath:)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(EU.font(12.5, .semibold))
                            Text(item.path ?? tr("경로 없음 — 앱이 지워졌을 수 있습니다"))
                                .font(EU.font(11))
                                .foregroundStyle(item.path == nil ? EU.warningFg : EU.fg3)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if let p = item.path {
                            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.eu(.light, small: true))
                            .help("Finder에서 보기")
                        }
                        Button(tr("빼기")) { pendingLoginRemove = item }
                            .buttonStyle(.eu(.light, small: true))
                    }
                }
            }
        }
    }

    // MARK: 백그라운드 항목

    private func launchCard(_ scope: LaunchScope) -> some View {
        let items = startup.items(scope)
        return EUCard {
            VStack(alignment: .leading, spacing: 10) {
                EUCardHeader(title: scope.title, icon: scope == .daemon ? "gearshape.2" : "clock.arrow.circlepath") {
                    EUChip(text: "\(items.count)")
                }
                Text(scope.caption)
                    .font(EU.font(11.5))
                    .foregroundStyle(EU.fg3)
                if scope == .daemon && state.helperStatus != .ready {
                    Text("끄기·켜기는 팬 제어 도우미가 처리합니다 — 팬 제어 탭에서 도우미를 설치하세요")
                        .font(EU.font(11.5)).foregroundStyle(EU.warningFg)
                }
                if items.isEmpty {
                    Text(startup.loading ? "불러오는 중…" : "없음")
                        .font(EU.font(12.5)).foregroundStyle(EU.fg3)
                }
                ForEach(items) { item in
                    if item.id != items.first?.id { EUDivider() }
                    launchRow(item)
                }
            }
        }
    }

    private func launchRow(_ item: LaunchItem) -> some View {
        HStack(alignment: .top, spacing: 10) {
            appIcon(item.appURL)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(EU.font(12.5, .semibold))
                        .foregroundStyle(item.disabled ? EU.fg3 : EU.fg)
                        .lineLimit(1)
                    if item.isEmpty {
                        EUChip(text: "빈 파일 · 실행 안 됨", tone: .neutral)
                    } else if item.disabled {
                        EUChip(text: "꺼짐", tone: .neutral)
                    } else if item.loaded {
                        EUChip(text: "활성", tone: .success)
                    }
                    if item.keepAlive { EUChip(text: "항상 유지", tone: .info) }
                    if item.runAtLoad { EUChip(text: "시작 시 실행", tone: .primary) }
                }
                Text(item.isEmpty ? tr("내용이 비어 있어 launchd 가 무시합니다") : item.label)
                    .font(EU.font(11)).foregroundStyle(EU.fg3)
                    .lineLimit(1).truncationMode(.middle)
                if let p = item.command {
                    Text(p)
                        .font(EU.font(11)).foregroundStyle(EU.fg4)
                        .lineLimit(1).truncationMode(.middle)
                        .help(p)
                }
            }
            Spacer(minLength: 8)
            Button { NSWorkspace.shared.activateFileViewerSelecting([item.plist]) } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.eu(.light, small: true))
            .help(trf("Finder에서 보기 — %@", item.plist.path))
            if !item.isEmpty {
                Button(item.disabled ? tr("켜기") : tr("끄기")) { startup.toggle(item) }
                    .buttonStyle(.eu(item.disabled ? .flat : .light, small: true))
            }
            if item.scope.canDelete {
                Button(tr("삭제")) { pendingDelete = item }
                    .buttonStyle(.eu(.light, small: true))
            }
        }
        .padding(.vertical, 2)
    }

    private func appIcon(_ url: URL?) -> some View {
        Group {
            if let u = url, FileManager.default.fileExists(atPath: u.path) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: u.path))
                    .resizable()
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: EU.z(14)))
                    .foregroundStyle(EU.fg3)
            }
        }
        .frame(width: EU.z(26), height: EU.z(26))
    }
}
