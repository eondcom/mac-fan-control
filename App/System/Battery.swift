import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo {
    var cycleCount: Int?
    var capacityPercent: Int?
    var condition: String?
    var timeRemaining: String?
    var isCharging: Bool
    var isCharged: Bool
    /// 연결된 어댑터(또는 USB-C 모니터)의 정격 전력
    var adapterWatts: Int?
    /// 배터리에 드나드는 전력 — 양수면 충전, 음수면 방전
    var batteryWatts: Double?
}

enum BatteryService {

    /// 한 번에 가져오는 전체 정보 (느림, 60s마다).
    static func full() -> BatteryInfo {
        var info = BatteryInfo(isCharging: false, isCharged: false)

        let sp = Shell.run("/usr/sbin/system_profiler", ["SPPowerDataType"])
        if let m = matchFirst(sp, pattern: #"Cycle Count:\s*(\d+)"#) {
            info.cycleCount = Int(m)
        }
        if let m = matchFirst(sp, pattern: #"Maximum Capacity:\s*(\d+)\s*%"#) {
            info.capacityPercent = Int(m)
        } else {
            // Sequoia 폴백 — ioreg
            let ir = Shell.run("/usr/sbin/ioreg", ["-r", "-c", "AppleSmartBattery"])
            if let maxStr = matchFirst(ir, pattern: #""MaxCapacity"\s*=\s*(\d+)"#),
               let desStr = matchFirst(ir, pattern: #""DesignCapacity"\s*=\s*(\d+)"#),
               let maxV = Int(maxStr), let desV = Int(desStr), desV > 0 {
                info.capacityPercent = Int((Double(maxV) / Double(desV) * 100).rounded())
            }
        }
        if let cond = matchFirst(sp, pattern: #"Condition:\s*(\S[\w ]*)"#) {
            info.condition = cond.trimmingCharacters(in: .whitespaces)
        }

        let st = quickStatus()
        info.isCharging     = st.isCharging
        info.isCharged      = st.isCharged
        info.timeRemaining  = st.timeRemaining
        info.adapterWatts   = st.adapterWatts
        info.batteryWatts   = st.batteryWatts
        return info
    }

    struct QuickStatus {
        var isCharging: Bool
        var isCharged: Bool
        var timeRemaining: String?
        var adapterWatts: Int?
        var batteryWatts: Double?
        var raw: String
    }

    /// 빠른 폴링용 — 1초마다 호출 가능.
    static func quickStatus() -> QuickStatus {
        let out = Shell.run("/usr/bin/pmset", ["-g", "batt"])
        let onAC = out.contains("AC Power")
        var statusWord = ""
        if let m = matchFirst(out, pattern: #"\d+%;\s*([\w ]+?)\s*;"#) {
            statusWord = m.lowercased()
        }
        let charging = onAC && !statusWord.contains("discharging")
        let charged  = onAC && (statusWord.contains("charged") || statusWord.contains("finishing"))

        var remain: String? = nil
        if let r = matchFirst(out, pattern: #"(\d+:\d+)\s+remaining"#),
           r != "0:00", r != "(no estimate)" {
            remain = r
        }
        return QuickStatus(isCharging: charging,
                           isCharged: charged,
                           timeRemaining: remain,
                           adapterWatts: onAC ? adapterWatts() : nil,
                           batteryWatts: batteryWatts(),
                           raw: out)
    }

    // MARK: - 전력

    static func adapterWatts() -> Int? {
        guard let d = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else { return nil }
        return (d[kIOPSPowerAdapterWattsKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
    }

    /// 배터리 전압 × 전류 (W)
    static func batteryWatts() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        func prop(_ key: String) -> Int? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int
        }
        guard let mv = prop("Voltage"), let raw = prop("Amperage") else { return nil }
        // 방전 전류는 음수지만 부호 없는 64비트로 올 때가 있다.
        let ma = Int64(truncatingIfNeeded: raw)
        return Double(mv) * Double(ma) / 1_000_000
    }

    // MARK: - regex helper

    private static func matchFirst(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges >= 2 else { return nil }
        guard let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}
