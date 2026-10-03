import SwiftUI
import ServiceManagement
import CoreImage

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openURL) private var openURL
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var showKakaoQR = false
    static let kakaoPayURL = URL(string: "https://qr.kakaopay.com/Ej7jeAAOU")!
    static let payPalURL = URL(string: "https://paypal.me/eond")!

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
                        // 실제로 확인해서 최신일 때만
                        if case .upToDate = state.updateStatus, state.latestRelease == nil {
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trf("새 버전 v%@", r.version))
                                if case .failed(let msg) = state.installStatus {
                                    Text(msg).font(EU.font(11.5)).foregroundStyle(EU.dangerFg)
                                }
                            }
                            Spacer()
                            Button("릴리스 노트") { openURL(r.tagURL) }
                                .buttonStyle(.eu(.light, small: true))
                            UpdateButton()
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("업데이트")
                                updateStatusText
                            }
                            Spacer()
                            Button {
                                Task { await state.checkUpdate() }
                            } label: {
                                if state.updateStatus == .checking {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("확인 중")
                                    }
                                } else {
                                    Label("확인", systemImage: "arrow.clockwise")
                                }
                            }
                            .buttonStyle(.eu(.neutral, small: true))
                            .disabled(state.updateStatus == .checking)
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

            section("후원") {
                EUListRow {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("앱이 도움이 됐다면")
                            Text("광고 없이 무료로 유지하는 데 쓰입니다")
                                .font(EU.font(11.5))
                                .foregroundStyle(EU.fg3)
                        }
                        Spacer()
                        // 카카오페이 — PC에서는 휴대폰으로 찍도록 QR을 띄운다. 영어 화면을 쓰는 한국 사용자도 있어 항상 보인다.
                        Button {
                            showKakaoQR.toggle()
                        } label: {
                            Label(tr("카카오페이"), systemImage: "qrcode")
                        }
                        .buttonStyle(.eu(.flat, small: true))
                        .popover(isPresented: $showKakaoQR, arrowEdge: .bottom) {
                            KakaoPayQR(url: Self.kakaoPayURL)
                        }
                        Button {
                            openURL(Self.payPalURL)
                        } label: {
                            Label(tr("PayPal로 후원"), systemImage: "heart.fill")
                        }
                        .buttonStyle(.eu(.solid, small: true))
                    }
                    .padding(.vertical, 8)
                }
            }

            Text("© 2026 이온디(eond). 팬 속도 변경은 관리자 권한 도우미를 통해서만 이루어집니다.")
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
                .padding(.leading, 4)
        }
        .toggleStyle(.eu)
        .font(EU.font(13))
    }

    @ViewBuilder
    private var updateStatusText: some View {
        switch state.updateStatus {
        case .upToDate(let at):
            Text(trf("최신 버전입니다 · %@ 확인", at.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(L10n.locale))))
                .font(EU.font(11.5))
                .foregroundStyle(EU.successFg)
        case .failed:
            Text("확인하지 못했습니다 — 인터넷 연결을 확인하세요")
                .font(EU.font(11.5))
                .foregroundStyle(EU.dangerFg)
        case .idle, .checking:
            EmptyView()
        }
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

// MARK: - 카카오페이 송금 QR — PC에서는 휴대폰으로 찍어야 하므로 앱에서 바로 보여준다.

struct KakaoPayQR: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            Text("카카오페이로 후원")
                .font(EU.font(14, .bold))
            if let img = qrImage(url.absoluteString) {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: EU.z(200), height: EU.z(200))
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("휴대폰 카메라나 카카오톡으로 찍어 주세요")
                .font(EU.font(12))
                .foregroundStyle(EU.fg3)
            // PC에서 링크를 열면 "모바일에서 이용 가능"만 뜨므로 복사해 휴대폰으로 보내게 한다.
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                copied = true
            } label: {
                Label(copied ? tr("복사했습니다 — 카카오톡으로 보내세요") : tr("링크 복사"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.eu(copied ? .successFlat : .flat, small: true))
        }
        .padding(20)
    }

    private func qrImage(_ text: String) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

/// 새 버전 받기 → 바꿔 끼우기 → 다시 실행
private struct UpdateButton: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let busy = state.isInstallingUpdate
        Button {
            state.installUpdate()
        } label: {
            if busy {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(state.installStatus == .downloading ? "내려받는 중" : "설치 중")
                }
            } else {
                Label(UpdateInstaller.canReplaceCurrent ? "업데이트" : "다운로드", systemImage: "arrow.down.circle")
            }
        }
        .buttonStyle(.eu(.solid, small: true))
        .disabled(busy)
        .help("새 버전을 받아 설치하고 앱을 다시 실행합니다")
    }
}
