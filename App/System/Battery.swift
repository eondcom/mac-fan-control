import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
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
    }

    /// 빠른 폴링용 — pmset을 띄우지 않고 IOKit 전원 정보로 읽는다.
    static func quickStatus() -> QuickStatus {
        let watts = batteryWatts()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let d = list.lazy.compactMap({
                  IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
              }).first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType })
        else {
            return QuickStatus(isCharging: false, isCharged: false, timeRemaining: nil,
                               adapterWatts: adapterWatts(), batteryWatts: watts)
        }
        let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let charged = onAC && (d[kIOPSIsChargedKey] as? Bool ?? false)
        // 충전기에 꽂혀 있어도 전력이 모자라 배터리가 줄고 있으면 충전 중이 아니다.
        let draining = !(d[kIOPSIsChargingKey] as? Bool ?? false) && !charged && (watts ?? 0) < -0.5
        let minutes = (onAC ? d[kIOPSTimeToFullChargeKey] : d[kIOPSTimeToEmptyKey]) as? Int ?? -1
        return QuickStatus(isCharging: onAC && !draining,
                           isCharged: charged,
                           timeRemaining: minutes > 0 ? String(format: "%d:%02d", minutes / 60, minutes % 60) : nil,
                           adapterWatts: onAC ? adapterWatts() : nil,
                           batteryWatts: watts)
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
        // 0.5W 단위로 — 잔떨림마다 화면을 다시 그리지 않도록
        return (Double(mv) * Double(ma) / 1_000_000 * 2).rounded() / 2
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
