import Foundation

enum PowerMode: String {
    case low
    case normal
}

enum PowerModeService {

    static func current() -> PowerMode {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? .low : .normal
    }

    /// 헬퍼가 설치돼 있으면 암호 없이, 없으면 관리자 권한을 물어 pmset 적용.
    static func set(_ mode: PowerMode) -> Bool {
        if FanHelper.isReady, FanHelper.setLowPower(mode == .low) { return true }
        let value = (mode == .low) ? "1" : "0"
        let cmd = "pmset lowpowermode \(value)"
        let escaped = cmd.replacingOccurrences(of: "\\", with: "\\\\")
                         .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        let result = Shell.runReturningStatus("/usr/bin/osascript", ["-e", script])
        return result == 0
    }
}

// MARK: - Shell helper

enum Shell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String]) -> String {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return ""
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func runReturningStatus(_ launchPath: String, _ args: [String]) -> Int32 {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = args
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
        } catch {
            return -1
        }
        task.waitUntilExit()
        return task.terminationStatus
    }
}
