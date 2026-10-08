import Foundation

/// 자주 쓰는 SMC 키 상수.
enum SMCKeys {
    // 온도 (Intel) — Apple Silicon은 AppleSiliconSensors 가 키 목록에서 찾는다.
    static let cpuTempCandidates = ["TC0P", "TC0D", "TC0H", "TCXC", "Ts0S"]
    static let gpuTemp     = "TG0P"
    static let batteryTemp = "TB0T"

    // 팬 0 (메인 팬)
    static let fan0Current = "F0Ac"
    static let fan0Min     = "F0Mn"
    static let fan0Max     = "F0Mx"
    static let fan0Mode    = "F0Md"  // 0=자동, 1=수동
    static let fan0Target  = "F0Tg"

    // 팬 1 (있을 경우)
    static let fan1Mode    = "F1Md"
    static let fan1Target  = "F1Tg"

    // 팬 개수
    static let fanCount    = "FNum"
}

/// Apple Silicon 온도 키 — 칩(M1~M4)마다 이름이 달라 SMC 키 목록을 한 번 훑어 고른다.
///   CPU: Tp·Te (성능·효율 코어), M3 계열은 Tf0·Tf4
///   GPU: Tg, M3 계열은 Tf1·Tf2
enum AppleSiliconSensors {
    struct Keys { var cpu: [String]; var gpu: [String] }

    static let keys: Keys = discover()

    static let validRange = 10.0...130.0

    private static func discover() -> Keys {
        let flt = SMC.shared.allKeys().filter { k in
            k.hasPrefix("T") && SMC.shared.read(k).map { $0.dataType.trimmingCharacters(in: .whitespaces) == "flt" } == true
        }
        func pick(_ prefixes: [String]) -> [String] {
            flt.filter { k in prefixes.contains { k.hasPrefix($0) } }
               .filter { SMC.shared.read($0)?.asDouble.map(validRange.contains) == true }
        }
        var cpu = pick(["Tp", "Te"])
        if cpu.isEmpty { cpu = pick(["Tf0", "Tf4"]) }
        var gpu = pick(["Tg"])
        if gpu.isEmpty { gpu = pick(["Tf1", "Tf2"]) }
        return Keys(cpu: cpu, gpu: gpu)
    }

    /// 코어 평균 — 코어 하나가 튀어도 팬이 출렁이지 않게
    static func average(_ keys: [String]) -> Double? {
        let v = keys.compactMap { SMC.shared.read($0)?.asDouble }.filter(validRange.contains)
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }
}
