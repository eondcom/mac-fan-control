import SwiftUI

/// SMC 재설정 순서 — 앱에서 할 수 없어 순서를 보여주고 종료까지 이어 준다.
struct SMCStepsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var confirmShutdown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SMC 재설정 방법")
                .font(EU.font(16, .bold))
            Text(tr(Platform.isAppleSilicon ? "Apple Silicon 맥은 따로 SMC 재설정 방법이 없습니다. 완전히 껐다가 켜면 같은 효과입니다."
                    : Maintenance.hasT2 ? "이 맥은 T2 칩 모델입니다. 앱으로는 할 수 없고, 맥을 끈 상태에서 버튼으로 합니다."
                                        : "앱으로는 할 수 없고, 맥을 끈 상태에서 버튼으로 합니다."))
                .font(EU.font(12))
                .foregroundStyle(EU.fg3)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(Maintenance.smcSteps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(i + 1)")
                            .font(EU.font(12, .bold))
                            .foregroundStyle(EU.fg4)
                            .frame(width: EU.z(14))
                        Text(step)
                            .font(EU.font(12.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text(tr(Platform.hasSpeedLimit
                    ? "이 안내는 종료하면 사라지니 휴대폰으로 찍어 두거나 순서를 기억해 두세요. 켠 뒤 성능 탭에서 CPU 속도가 100% 로 돌아왔는지 확인하세요."
                    : "이 안내는 종료하면 사라지니 휴대폰으로 찍어 두거나 순서를 기억해 두세요."))
                .font(EU.font(11.5))
                .foregroundStyle(EU.fg4)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(tr("닫기")) { dismiss() }
                    .buttonStyle(.eu(.light, small: true))
                Button(tr("지금 종료")) { confirmShutdown = true }
                    .buttonStyle(.eu(.solid, small: true))
            }
        }
        .padding(24)
        .frame(width: EU.z(440))
        .confirmationDialog(tr("맥을 종료할까요?"), isPresented: $confirmShutdown, titleVisibility: .visible) {
            Button(tr("종료"), role: .destructive) { Maintenance.shutDown() }
        } message: {
            Text("열린 앱에 저장하지 않은 작업이 있으면 먼저 저장하세요.")
        }
    }
}

/// 재시작 · SMC 재설정 방법 — 속도 제한 알림과 진단 카드에서 같이 쓴다.
struct ThrottleActions: View {
    @State private var showSMC = false
    @State private var confirmRestart = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                confirmRestart = true
            } label: {
                Label("재시작", systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.eu(.solid, small: true))
            Button {
                showSMC = true
            } label: {
                Label("SMC 재설정 방법", systemImage: "cpu")
            }
            .buttonStyle(.eu(.light, small: true))
        }
        .sheet(isPresented: $showSMC) { SMCStepsSheet() }
        .confirmationDialog(tr("맥을 재시작할까요?"), isPresented: $confirmRestart, titleVisibility: .visible) {
            Button(tr("재시작"), role: .destructive) { Maintenance.restart() }
        } message: {
            Text("완전히 다시 켜면 꼬인 전원 관리 상태가 풀리는 경우가 많습니다. 저장하지 않은 작업은 먼저 저장하세요.")
        }
    }
}

/// 대시보드 — 온도는 정상인데 속도가 깎였을 때
struct PowerThrottleBanner: View {
    let speed: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "bolt.trianglebadge.exclamationmark.fill")
                Text(trf("CPU 속도가 %d%%로 제한돼 있습니다", speed))
                    .font(EU.font(13, .semibold))
            }
            Text("온도는 정상이라 열 때문이 아닙니다. 전원 관리 상태가 꼬였거나 배터리·충전기 쪽 원인입니다. 재시작이나 SMC 재설정으로 풀리는 경우가 많고, 계속되면 성능 탭의 속도 저하 진단을 보세요.")
                .font(EU.font(12))
                .fixedSize(horizontal: false, vertical: true)
            ThrottleActions()
        }
        .foregroundStyle(EU.warningFg)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EU.warningFlat, in: RoundedRectangle(cornerRadius: EU.rCard, style: .continuous))
    }
}

/// 설정 → 문제 해결
struct TroubleshootRows: View {
    @State private var confirmNVRAM = false
    @State private var confirmPower = false
    @State private var showSMC = false
    @State private var askRestart = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            row(title: "NVRAM 초기화 후 재시작",
                detail: "시동 디스크·화면 해상도·음량 같은 저장 설정을 지웁니다. 외장 모니터가 안 잡히거나 시동이 이상할 때. 관리자 암호를 묻습니다.",
                button: "초기화") { confirmNVRAM = true }
            EUDivider()
            row(title: "전원 설정 기본값 복원",
                detail: "잠자기·디스플레이 끄기 시간 등 전원 설정(pmset)을 처음 상태로 돌립니다. 저전력 모드도 꺼집니다. 관리자 암호를 묻습니다.",
                button: "복원") { confirmPower = true }
            EUDivider()
            row(title: "SMC 재설정",
                detail: "팬·전원·속도 제한이 이상할 때. 앱으로는 할 수 없어 순서를 보여줍니다.",
                button: "방법 보기") { showSMC = true }
            if let m = message {
                EUDivider()
                EUListRow {
                    Text(m)
                        .font(EU.font(12))
                        .foregroundStyle(EU.fg3)
                        .padding(.vertical, 8)
                }
            }
        }
        .sheet(isPresented: $showSMC) { SMCStepsSheet() }
        .confirmationDialog(tr("NVRAM 을 초기화할까요?"), isPresented: $confirmNVRAM, titleVisibility: .visible) {
            Button(tr("초기화"), role: .destructive) {
                Task.detached {
                    let ok = Maintenance.resetNVRAM()
                    await MainActor.run {
                        message = ok ? tr("NVRAM 을 초기화했습니다. 재시작하면 적용됩니다.") : tr("초기화하지 않았습니다 (취소했거나 실패).")
                        if ok { askRestart = true }
                    }
                }
            }
        } message: {
            Text("되돌릴 수 없습니다. 시동 디스크를 바꿔 썼다면 다시 골라야 할 수 있습니다.")
        }
        .confirmationDialog(tr("전원 설정을 기본값으로 돌릴까요?"), isPresented: $confirmPower, titleVisibility: .visible) {
            Button(tr("복원"), role: .destructive) {
                Task.detached {
                    let ok = Maintenance.restorePowerDefaults()
                    await MainActor.run {
                        message = ok ? tr("전원 설정을 기본값으로 돌렸습니다.") : tr("복원하지 않았습니다 (취소했거나 실패).")
                    }
                }
            }
        } message: {
            Text("되돌릴 수 없습니다. 직접 바꿔 둔 잠자기 시간 등은 다시 설정해야 합니다.")
        }
        .confirmationDialog(tr("지금 재시작할까요?"), isPresented: $askRestart, titleVisibility: .visible) {
            Button(tr("재시작"), role: .destructive) { Maintenance.restart() }
            Button(tr("나중에"), role: .cancel) {}
        }
    }

    private func row(title: String, detail: String, button: String, action: @escaping () -> Void) -> some View {
        EUListRow {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr(title))
                    Text(tr(detail))
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(tr(button), action: action)
                    .buttonStyle(.eu(.light, small: true))
            }
            .padding(.vertical, 8)
        }
    }
}

/// 진단 정보 복사 — 칩·센서·팬 키를 텍스트로 모아 개발자에게 보낸다.
struct DiagnosticsRow: View {
    @EnvironmentObject var state: AppState
    @State private var working = false
    @State private var copied = false

    var body: some View {
        EUListRow {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("진단 정보 복사")
                    Text(trf("칩·온도 센서·팬 상태를 복사합니다. 문제를 알릴 때 붙여 넣어 주세요. (%@ · %@)",
                             Platform.chip, Platform.model))
                        .font(EU.font(11.5))
                        .foregroundStyle(EU.fg3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if copied {
                    EUChip(text: "복사됨", tone: .success, icon: "checkmark")
                }
                Button {
                    working = true
                    let mode = state.fanMode.rawValue
                    let target = state.fanTarget
                    Task.detached {
                        let text = Diagnostics.report(fanMode: mode, fanTarget: target)
                        await MainActor.run {
                            Diagnostics.copyToPasteboard(text)
                            working = false
                            copied = true
                        }
                    }
                } label: {
                    if working {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("복사")
                    }
                }
                .buttonStyle(.eu(.light, small: true))
                .disabled(working)
            }
            .padding(.vertical, 8)
        }
    }
}
