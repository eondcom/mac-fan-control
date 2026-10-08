import Foundation

/// 이 맥의 하드웨어 — Intel·Apple Silicon에 따라 온도 키·속도 제한·SMC 재설정이 다르다.
enum Platform {

    /// Rosetta로 돌아도 실제 칩을 본다.
    static let isAppleSilicon: Bool = sysctlInt("hw.optional.arm64") == 1

    /// Intel 빌드가 Apple Silicon에서 Rosetta로 도는 중
    static let isTranslated: Bool = sysctlInt("sysctl.proc_translated") == 1

    /// 예: MacBookPro16,1 · Mac14,3
    static let model: String = sysctlString("hw.model") ?? "?"

    /// 예: Intel(R) Core(TM) i7-9750H · Apple M2
    static let chip: String = sysctlString("machdep.cpu.brand_string") ?? (isAppleSilicon ? "Apple Silicon" : "Intel")

    /// Intel만 pmset -g therm 의 CPU 속도 제한 값을 준다.
    static var hasSpeedLimit: Bool { !isAppleSilicon }

    /// Apple Silicon에서 속도 제한 대신 쓰는 macOS 열 상태 — 높음 이상이면 성능을 줄이고 있다.
    static var thermalState: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }

    static var isThermalThrottling: Bool {
        thermalState == .serious || thermalState == .critical
    }

    static func thermalStateLabel(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal:  return tr("정상")
        case .fair:     return tr("약간 높음")
        case .serious:  return tr("높음")
        case .critical: return tr("위험")
        @unknown default: return "?"
        }
    }

    private static func sysctlInt(_ name: String) -> Int32? {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? v : nil
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
