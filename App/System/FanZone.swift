import Foundation

/// 팬 제어 방식 — 시스템(SMC 자동) 또는 구간 제어
enum FanMode: String {
    case system, zone
}

/// 소음 기준 구간. MacBookPro15,3 체감 기준이며 실제 범위는 SMC 최소·최대로 잘린다.
enum FanZone: String, CaseIterable, Identifiable {
    case quiet, normal, high
    var id: String { rawValue }

    var label: String {
        switch self {
        case .quiet:  return tr("저음")
        case .normal: return tr("일반")
        case .high:   return tr("고속")
        }
    }

    var icon: String {
        switch self {
        case .quiet:  return "wind"
        case .normal: return "fan"
        case .high:   return "hurricane"
        }
    }

    var hint: String {
        switch self {
        case .quiet:  return tr("거의 안 들림")
        case .normal: return tr("가까이서 바람 소리")
        case .high:   return tr("확실히 들림")
        }
    }

    var baseRange: ClosedRange<Int> {
        switch self {
        case .quiet:  return 2200...2800
        case .normal: return 2800...3500
        case .high:   return 3500...6000
        }
    }

    /// 고온일 때 임시로 올라갈 구간
    var next: FanZone? {
        switch self {
        case .quiet:  return .normal
        case .normal: return .high
        case .high:   return nil
        }
    }

    /// 구간 자동의 기본 상한
    var defaultCap: Int { baseRange.upperBound }

    /// 구간 고정의 기본값
    var defaultFixed: Int {
        switch self {
        case .quiet:  return 2400
        case .normal: return 3000
        case .high:   return 4500
        }
    }
}

/// 구간 자동 곡선 — 온도에 따라 하한~상한 사이를 움직인다.
enum FanCurve {
    /// 이 온도 이하면 하한
    static let coolTemp = 50.0
    /// 이 온도 이상이면 상한
    static let warmTemp = 80.0
    /// 이 온도를 넘으면 시스템 자동에 넘긴다
    static let safetyTemp = 90.0
    /// 이 온도 아래로 내려오면 구간 제어로 돌아온다
    static let resumeTemp = 80.0

    /// 기준 온도가 이만큼 계속되면 다음 구간으로 임시 상향
    static let boostSustain: TimeInterval = 30
    /// 임시 상향 유지 시간
    static let boostDuration: TimeInterval = 60 * 60
    /// 기준 온도에서 이만큼 내려가야 "계속 뜨거움" 판정을 초기화한다
    static let boostHysteresis = 3.0

    /// 한 번에 올릴/내릴 수 있는 최대 폭 — 내릴 때를 느리게 해 소리가 출렁이지 않게
    static let maxStepUp = 400
    static let maxStepDown = 150

    static func target(temp: Double, lower: Int, cap: Int, previous: Int?) -> Int {
        let frac = min(max((temp - coolTemp) / (warmTemp - coolTemp), 0), 1)
        var rpm = Double(lower) + frac * Double(cap - lower)
        if let prev = previous.map(Double.init) {
            rpm = rpm > prev ? min(rpm, prev + Double(maxStepUp))
                             : max(rpm, prev - Double(maxStepDown))
        }
        let rounded = Int((rpm / 50).rounded()) * 50
        return min(max(rounded, lower), cap)
    }
}
