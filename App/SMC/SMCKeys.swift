import Foundation

/// 자주 쓰는 SMC 키 상수.
enum SMCKeys {
    // 온도
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
