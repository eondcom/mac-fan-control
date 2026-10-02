import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            EUPageHeader(title: "설정")

            section("화면") {
                EUListRow {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("화면 크기")
                            Text("⌘+ 확대 · ⌘- 축소 · ⌘0 기본")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                        Spacer()
                        Button { UIZoom.zoomOut() } label: { Image(systemName: "minus") }
                            .buttonStyle(.eu(.neutral, small: true))
                            .disabled(!UIZoom.canZoomOut)
                        Button { UIZoom.reset() } label: {
                            Text("\(Int((UIZoom.current * 100).rounded()))%")
                                .monospacedDigit()
                                .frame(minWidth: EU.z(40))
                        }
                        .buttonStyle(.eu(.light, small: true))
                        Button { UIZoom.zoomIn() } label: { Image(systemName: "plus") }
                            .buttonStyle(.eu(.neutral, small: true))
                            .disabled(!UIZoom.canZoomIn)
                    }
                }
                EUDivider()
                EUListRow {
                    HStack {
                        Text("언어")
                        Spacer()
                        EUSeg(selection: $state.language,
                              options: AppLanguage.allCases.map { ($0, $0.label) })
                    }
                }
                EUDivider()
                EUListRow {
                    HStack {
                        Text("테마")
                        Spacer()
                        EUSeg(selection: $state.themeMode,
                              options: EUThemeMode.allCases.map { ($0, $0.label) })
                    }
                }
                EUDivider()
                EUListRow {
                    HStack {
                        Text("메인 색")
                        Spacer()
                        HStack(spacing: 8) {
                            ForEach(EUAccent.allCases) { a in
                                accentSwatch(a)
                            }
                        }
                    }
                }
            }

            section("메뉴바 표시") {
                EUListRow {
                    Toggle(isOn: $state.mbShowIcon) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("팬 아이콘 표시")
                            HStack(spacing: 6) {
                                Text("구간마다 모양이 바뀝니다")
                                ForEach(["fan.badge.automatic"] + FanZone.allCases.map(\.icon), id: \.self) {
                                    Image(systemName: $0)
                                }
                            }
                            .font(EU.font(11.5))
                            .foregroundStyle(EU.fg3)
                        }
                    }
                }
                EUDivider()
                EUListRow {
                    Toggle(isOn: $state.mbShowThermo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("온도계 아이콘 표시")
                            Text("온도에 따라 눈금 높이가 바뀝니다")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                    }
                }
                EUDivider()
                EUListRow { Toggle("CPU 온도 표시", isOn: $state.mbShowTemp) }
                EUDivider()
                EUListRow { Toggle("팬 속도 표시", isOn: $state.mbShowFan) }
            }

            section("실행") {
                EUListRow { Toggle("시작 시 메뉴바로 숨기기", isOn: $state.startHidden) }
                EUDivider()
                EUListRow {
                    Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = !enabled
                            }
                        }
                }
            }

            section("정보") {
                EUListRow {
                    HStack {
                        Text("버전")
                        Spacer()
                        if state.latestRelease == nil {
                            EUChip(text: "최신", tone: .success, icon: "checkmark")
                        }
                        Text("v\(ReleaseChecker.currentVersion())")
                            .foregroundStyle(EU.fg3)
                            .monospacedDigit()
                    }
                }
                EUDivider()
                EUListRow {
                    HStack {
                        if let r = state.latestRelease {
                            Text(trf("새 버전 v%@", r.version))
                            Spacer()
                            Button {
                                openURL(r.tagURL)
                            } label: {
                                Label("다운로드", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.eu(.solid, small: true))
                        } else {
                            Text("업데이트")
                            Spacer()
                            Button {
                                Task { await state.checkUpdate() }
                            } label: {
                                Label("확인", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.eu(.neutral, small: true))
                        }
                    }
                }
                EUDivider()
                linkRow("만든 곳", tr("이온디 · eond.com"), url: "https://eond.com", icon: "globe")
                EUDivider()
                linkRow("문의", "eond@eond.com", url: "mailto:eond@eond.com", icon: "envelope")
                EUDivider()
                linkRow("소스 코드", "GitHub", url: "https://github.com/eondcom/mac-fan-control", icon: "chevron.left.forwardslash.chevron.right")
            }

            Text("© 2026 이온디(eond). 팬 속도 변경은 관리자 권한 도우미를 통해서만 이루어집니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
                .padding(.leading, 4)
        }
        .toggleStyle(.eu)
        .font(EU.font(13))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr(title))
                .font(EU.font(12, .semibold))
                .foregroundStyle(EU.fg3)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(EU.c1, in: RoundedRectangle(cornerRadius: EU.rCard, style: .continuous))
        }
    }

    private func linkRow(_ key: String, _ value: String, url: String, icon: String) -> some View {
        EUListRow {
            HStack {
                Text(tr(key))
                Spacer()
                Button {
                    if let u = URL(string: url) { openURL(u) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: icon).font(.system(size: EU.z(11), weight: .semibold))
                        Text(value)
                    }
                }
                .buttonStyle(.eu(.light, small: true))
                .help(url)
            }
        }
    }

    private func accentSwatch(_ a: EUAccent) -> some View {
        let on = state.accent == a
        return Button {
            state.accent = a
        } label: {
            Circle()
                .fill(a.palette.primary)
                .frame(width: EU.z(18), height: EU.z(18))
                .overlay(Circle().strokeBorder(EU.c4, lineWidth: a == .neutral ? 1 : 0))
                .padding(3)
                .overlay(Circle().strokeBorder(on ? EU.fg2 : .clear, lineWidth: 1.5))
                .help(a.label)
        }
        .buttonStyle(.plain)
    }
}
