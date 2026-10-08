import Foundation
import AppKit

/// 문제 해결 — NVRAM 초기화, 전원 설정 기본값, 재시작, SMC 재설정 안내
///
/// SMC 재설정은 소프트웨어로 할 수 없다(전원을 끈 상태에서 키 조합으로 T2/SMC 에 전원을 다시 넣는 절차).
/// 그래서 순서만 보여주고, 재시작·종료까지 앱에서 이어 준다.
/// NVRAM·pmset 초기화는 드물고 되돌릴 수 없어 도우미 대신 매번 관리자 암호를 묻는다.
enum Maintenance {

    /// 관리자 암호를 묻고 실행 — 취소하면 false
    private static func runAsAdmin(_ cmd: String) -> Bool {
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return Shell.runReturningStatus("/usr/bin/osascript", ["-e", script]) == 0
    }

    /// 저장된 시동 디스크·화면·음량 등 초기화 — 다음 부팅부터 적용
    static func resetNVRAM() -> Bool { runAsAdmin("/usr/sbin/nvram -c") }

    /// 잠자기·디스플레이 끄기 등 pmset 설정을 기본값으로 (저전력 모드도 꺼진다)
    static func restorePowerDefaults() -> Bool { runAsAdmin("/usr/bin/pmset -a restoredefaults") }

    /// loginwindow 에 재시작·종료 요청 — 열린 앱에 저장을 묻는 일반 재시작과 같다.
    static func restart() { sendToLoginWindow("rrst") }
    static func shutDown() { sendToLoginWindow("rsdn") }

    private static func sendToLoginWindow(_ code: String) {
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"loginwindow\" to «event aevt\(code)»")?.executeAndReturnError(&err)
    }

    // MARK: SMC 재설정 순서

    /// T2 칩이 있는 인텔 맥 (2018~2020)
    static let hasT2: Bool = {
        let prefixes = ["MacBookPro15,", "MacBookPro16,", "MacBookAir8,", "MacBookAir9,", "Macmini8,", "iMac20,", "iMacPro1,", "MacPro7,"]
        return !Platform.isAppleSilicon && prefixes.contains { Platform.model.hasPrefix($0) }
    }()

    static var smcSteps: [String] {
        // Apple Silicon 은 SMC 재설정 키 조합이 없다 — 완전히 껐다 켜면 같은 효과
        if Platform.isAppleSilicon {
            return [tr("맥을 종료합니다."),
                    tr("데스크톱 맥은 전원 케이블을 뽑습니다. 노트북은 그대로 둡니다."),
                    tr("30초 기다렸다가 (케이블을 다시 꽂고) 켭니다.")]
        }
        if hasT2 {
            return [tr("1차 — 맥을 종료하고, 전원 버튼을 10초 누른 뒤 떼고, 몇 초 뒤 켭니다."),
                    tr("그래도 안 되면 — 종료한 뒤 오른쪽 Shift + 왼쪽 Option + 왼쪽 Control 을 7초 누릅니다."),
                    tr("세 키를 누른 채 전원 버튼도 7초 더 누릅니다."),
                    tr("모두 떼고 몇 초 기다렸다가 켭니다.")]
        }
        return [tr("맥을 종료합니다."),
                tr("왼쪽 Shift + 왼쪽 Control + 왼쪽 Option 과 전원 버튼을 함께 10초 누릅니다."),
                tr("모두 떼고 전원 버튼을 눌러 켭니다.")]
    }
}
