import Foundation

/// 팬 쓰기는 root 권한이 필요하다 — 번들에 든 헬퍼(macfan-smc)를 한 번 설치해 두고 그걸로 쓴다.
enum FanHelper {
    static let installedPath = "/Library/PrivilegedHelperTools/com.eond.macfancontrol.smc"
    /// Helper/main.swift의 helperVersion과 같아야 한다.
    static let expectedVersion = "4"
    /// 이미 설치된 헬퍼로 충분한 버전 — v4는 Apple Silicon 팬 잠금 해제 대기만 더했으므로 Intel은 v3도 쓴다.
    static let minimumVersion = Platform.isAppleSilicon ? 4 : 3

    /// 마지막 팬 쓰기 결과 — 진단 정보용 (명령, 종료 코드, 시각)
    private(set) static var lastWrite: (command: String, status: Int32, date: Date)?
    private static let lock = NSLock()

    private static func record(_ command: String, _ status: Int32) -> Bool {
        lock.lock(); lastWrite = (command, status, Date()); lock.unlock()
        return status == 0
    }

    static var lastWriteSnapshot: (command: String, status: Int32, date: Date)? {
        lock.lock(); defer { lock.unlock() }
        return lastWrite
    }

    enum Status { case ready, missing, outdated }

    static var bundledURL: URL? {
        Bundle.main.url(forAuxiliaryExecutable: "macfan-smc")
    }

    /// 한 번 확인되면 다시 묻지 않는다 (쓰기마다 version을 실행하지 않도록).
    private static var verified = false

    static var isReady: Bool { verified || status() == .ready }

    static func status() -> Status {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: installedPath) else { return .missing }
        let owner = (attrs[.ownerAccountID] as? NSNumber)?.intValue
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        guard owner == 0, perms & 0o4000 != 0 else { return .outdated }
        let v = Shell.run(installedPath, ["version"]).trimmingCharacters(in: .whitespacesAndNewlines)
        verified = (Int(v) ?? 0) >= minimumVersion
        return verified ? .ready : .outdated
    }

    /// 관리자 암호를 한 번 묻고 root:wheel 4755로 설치
    static func install() -> Bool {
        guard let src = bundledURL?.path else { return false }
        let q = { (p: String) in "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let cmd = [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp -f \(q(src)) \(q(installedPath))",
            "chown root:wheel \(q(installedPath))",
            "chmod 4755 \(q(installedPath))",
        ].joined(separator: " && ")
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return Shell.runReturningStatus("/usr/bin/osascript", ["-e", script]) == 0 && status() == .ready
    }

    @discardableResult
    static func setFanSpeed(rpm: Int) -> Bool {
        record("set \(rpm)", Shell.runReturningStatus(installedPath, ["set", String(rpm)]))
    }

    /// 저전력 모드 — 헬퍼가 있으면 암호 없이 바꾼다.
    static func setLowPower(_ on: Bool) -> Bool {
        Shell.runReturningStatus(installedPath, ["lowpower", on ? "1" : "0"]) == 0
    }

    @discardableResult
    static func resetAuto() -> Bool {
        record("auto", Shell.runReturningStatus(installedPath, ["auto"]))
    }
}
