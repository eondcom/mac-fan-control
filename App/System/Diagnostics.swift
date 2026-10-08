import Foundation
import AppKit

/// 진단 정보 — 다른 맥(특히 Apple Silicon)에서 센서·팬 키가 어떻게 보이는지 복사해 보내 받는다.
/// 읽기만 하고 SMC 에 쓰지 않는다. 개발자가 읽는 용도라 번역하지 않는다.
enum Diagnostics {

    static func report(fanMode: String, fanTarget: Int?) -> String {
        var lines: [String] = []
        func add(_ s: String) { lines.append(s) }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        add("MacFanControl diagnostics — \(ISO8601DateFormatter().string(from: Date()))")
        add("app v\(ReleaseChecker.currentVersion()) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
        add("model \(Platform.model) · chip \(Platform.chip)")
        add("appleSilicon \(Platform.isAppleSilicon) · rosetta \(Platform.isTranslated)")

        add("")
        add("[SMC]")
        let opened = SMC.shared.open()
        let keys = opened ? SMC.shared.allKeys() : []
        add("open \(opened) · keys \(keys.count)")

        add("")
        add("[fans]")
        add("FNum \(describe("FNum")) · fanCount \(Thermal.fanCount)")
        add("Ftst \(describe("Ftst"))")
        for i in 0..<max(Thermal.fanCount, 1) {
            let fk = ["Ac", "Mn", "Mx", "Md", "md", "Tg"].map { "F\(i)\($0)" }
            add(fk.map { "\($0)=\(describe($0))" }.joined(separator: "  "))
        }
        add("fanMode \(fanMode) · target \(fanTarget.map(String.init) ?? "-")")

        add("")
        add("[temperature]")
        let t = Thermal.read()
        add("cpu \(fmt(t.cpuTemp)) · gpu \(fmt(t.gpuTemp)) · battery \(fmt(t.batteryTemp))")
        if Platform.isAppleSilicon {
            let k = AppleSiliconSensors.keys
            add("cpuKeys(\(k.cpu.count)) \(k.cpu.joined(separator: ","))")
            add("gpuKeys(\(k.gpu.count)) \(k.gpu.joined(separator: ","))")
            let cpuVals = k.cpu.compactMap { SMC.shared.read($0)?.asDouble }
            if let mx = cpuVals.max() { add("cpu max \(fmt(mx)) · min \(fmt(cpuVals.min()))") }
        }

        add("")
        add("[throttle]")
        add("speedLimit \(PerfService.speedLimit().map { "\($0)%" } ?? "n/a")")
        add("thermalState \(Platform.thermalStateLabel(Platform.thermalState)) (\(Platform.thermalState.rawValue))")
        add("lowPowerMode \(ProcessInfo.processInfo.isLowPowerModeEnabled)")

        add("")
        add("[helper]")
        add("status \(FanHelper.status())")
        if FileManager.default.fileExists(atPath: FanHelper.installedPath) {
            let v = Shell.run(FanHelper.installedPath, ["version"]).trimmingCharacters(in: .whitespacesAndNewlines)
            add("installed version \(v.isEmpty ? "?" : v) · bundled \(FanHelper.expectedVersion)")
        }
        if let w = FanHelper.lastWriteSnapshot {
            add("last write '\(w.command)' exit \(w.status) at \(ISO8601DateFormatter().string(from: w.date))")
        } else {
            add("last write -")
        }

        add("")
        add("[all T* keys]")
        for k in keys where k.hasPrefix("T") {
            add("\(k) \(describe(k))")
        }
        return lines.joined(separator: "\n")
    }

    static func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// 타입과 값 — 숫자로 못 읽으면 바이트 그대로
    private static func describe(_ key: String) -> String {
        guard let v = SMC.shared.read(key) else { return "-" }
        let type = v.dataType.trimmingCharacters(in: .whitespaces)
        if let d = v.asDouble { return "\(fmt(d))(\(type))" }
        return v.bytes.map { String(format: "%02x", $0) }.joined() + "(\(type))"
    }

    private static func fmt(_ v: Double?) -> String {
        guard let v else { return "-" }
        return String(format: "%.1f", v)
    }
}
