import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("메뉴바 표시") {
                Toggle("CPU 온도 표시", isOn: $state.mbShowTemp)
                Toggle("팬 속도 표시",  isOn: $state.mbShowFan)
            }

            Section("실행") {
                Toggle("시작 시 메뉴바로 숨기기", isOn: $state.startHidden)
                LabeledContent("자동 실행") {
                    Text("시스템 설정 → 사용자 → 로그인 항목에서 추가")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("정보") {
                LabeledContent("버전", value: "v\(ReleaseChecker.currentVersion())")
                if let r = state.latestRelease {
                    Link(destination: r.tagURL) {
                        Label("새 버전 v\(r.version) 다운로드", systemImage: "arrow.down.circle")
                    }
                }
                Button {
                    Task { await state.checkUpdate() }
                } label: {
                    Label("업데이트 확인", systemImage: "arrow.clockwise")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
