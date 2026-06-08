import Foundation

enum PowerMode: String {
    case low
    case normal
}

enum PowerModeService {

    static func current() -> PowerMode {
        let out = Shell.run("/usr/bin/pmset", ["-g"])
        if let range = out.range(of: #"lowpowermode\s+(\d)"#, options: .regularExpression) {
            let match = String(out[range])
            if match.contains("1") { return .low }
        }
        return .normal
    }

    /// 관리자 권한 요청 (osascript) 후 pmset 적용.
    static func set(_ mode: PowerMode) -> Bool {
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
