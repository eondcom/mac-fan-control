import Foundation

/// 사용 모드 — 팬 값을 하나하나 고르는 대신 "어떻게 쓰고 싶은지"를 고르면 전원 모드·팬·관련 기능을 한 번에 맞춘다.
///
/// 2026-10-04 측정(12코어 60초): 기본 모드 처리량 3302 · 속도 제한 평균 75% · 73.8°C,
/// 저전력 모드 2351(−29%) · 제한 없음 · 67.7°C → 조용함은 저전력, 성능은 기본 모드.
enum UsageProfile: String, CaseIterable, Identifiable {
    case quiet, balanced, performance, system
    /// 사용자가 직접 맞춘 설정 — 저장해 두고 돌아온다
    case custom

    var id: String { rawValue }
    /// 정해진 값이 있는 모드 (custom 제외)
    static let presets: [UsageProfile] = [.quiet, .balanced, .performance, .system]

    var label: String {
        switch self {
        case .quiet:       return tr("조용함")
        case .balanced:    return tr("균형")
        case .performance: return tr("성능")
        case .system:      return tr("시스템 기본")
        case .custom:      return tr("내 설정")
        }
    }

    /// 메뉴바 한 줄에 들어가게
    var shortLabel: String { self == .system ? "macOS" : label }

    var icon: String {
        switch self {
        case .quiet:       return "moon.zzz"
        case .balanced:    return "scale.3d"
        case .performance: return "bolt.fill"
        case .system:      return "apple.logo"
        case .custom:      return "person.crop.circle"
        }
    }

    var summary: String {
        switch self {
        case .quiet:       return tr("브라우저·터미널·문서 — 저전력 모드, 저음 팬")
        case .balanced:    return tr("평소 — 기본 모드, 일반 팬, 뜨거우면 자동 절전")
        case .performance: return tr("빌드·영상 — 기본 모드, 고속 팬")
        case .system:      return tr("macOS 에 맡김 — 앱이 팬을 건드리지 않음")
        case .custom:      return tr("직접 맞춰 둔 설정으로 돌아갑니다")
        }
    }

    // 모드별 설정
    var power: PowerMode { self == .quiet ? .low : .normal }
    /// nil 이면 시스템 자동 팬
    var zone: FanZone? {
        switch self {
        case .quiet:       return .quiet
        case .balanced:    return .normal
        case .performance: return .high
        case .system, .custom: return nil
        }
    }
    /// 갑자기 팬이 커지지 않도록 조용함에선 끈다.
    var preemptFan: Bool { self == .balanced || self == .performance }
    /// 이미 저전력이거나 성능을 원하면 끈다.
    var thermalGuard: Bool { self == .balanced }
    var lowerHogs: Bool { self == .quiet || self == .balanced }
}

/// "내 설정" — 사용자가 직접 맞춘 전원·팬·기능 값
struct CustomProfile: Codable, Equatable {
    var power: String
    var fanSystem: Bool
    var zone: String
    var fixed: Bool
    var preemptFan: Bool
    var guardEnabled: Bool
    var guardOn: Int
    var guardOff: Int
    var lowerHogs: Bool

    /// 요약 — 화면에 보여줄 한 줄
    var summary: String {
        let p = power == PowerMode.low.rawValue ? tr("저전력") : tr("기본")
        let fan = fanSystem ? tr("macOS 자동 팬") : trf("%@ 팬%@", FanZone(rawValue: zone)?.label ?? zone, fixed ? tr(" 고정") : "")
        return trf("%@ 모드 · %@", p, fan)
    }
}

extension Notification.Name {
    /// 사용 모드가 정한 "원인 앱 낮추기" 값 — PerfMonitor 가 받는다.
    static let usageProfileLowerHogs = Notification.Name("usageProfileLowerHogs")
}

extension AppState {

    private static let customKey = "custom_profile"

    var customProfile: CustomProfile? {
        guard let d = UserDefaults.standard.data(forKey: Self.customKey) else { return nil }
        return try? JSONDecoder().decode(CustomProfile.self, from: d)
    }

    /// 지금 설정 그대로
    var currentSnapshot: CustomProfile {
        CustomProfile(power: power.rawValue, fanSystem: fanMode == .system, zone: fanZone.rawValue, fixed: fanFixed,
                      preemptFan: preemptFan, guardEnabled: guardEnabled, guardOn: guardOnTemp, guardOff: guardOffTemp,
                      lowerHogs: UserDefaults.standard.bool(forKey: "perf_lower_hogs"))
    }

    /// 지금 설정을 "내 설정"으로
    func saveCustomProfile() {
        guard let d = try? JSONEncoder().encode(currentSnapshot) else { return }
        UserDefaults.standard.set(d, forKey: Self.customKey)
        UserDefaults.standard.set(UsageProfile.custom.rawValue, forKey: "usage_profile")
        objectWillChange.send()
    }

    /// 모드를 고르면 한 번에 적용 — 과열 안전장치·고온 상향은 모든 모드에서 그대로 둔다.
    /// 직접 맞춘 상태(어느 모드와도 안 맞음)에서 넘어가면 그 상태를 "내 설정"으로 먼저 저장한다.
    func applyProfile(_ p: UsageProfile) {
        if activeProfile == nil { saveCustomProfile() }
        if p == .custom {
            applyCustom()
            return
        }
        if power != p.power { setPowerMode(p.power) }
        if let z = p.zone {
            fanFixed = false
            selectZone(z)
        } else {
            useSystemFan()
        }
        preemptFan = p.preemptFan
        if guardEnabled != p.thermalGuard { setGuardEnabled(p.thermalGuard) }
        NotificationCenter.default.post(name: .usageProfileLowerHogs, object: p.lowerHogs)
        UserDefaults.standard.set(p.rawValue, forKey: "usage_profile")
        objectWillChange.send()
    }

    private func applyCustom() {
        guard let c = customProfile else { return }
        let mode = PowerMode(rawValue: c.power) ?? .normal
        if power != mode { setPowerMode(mode) }
        if c.fanSystem {
            useSystemFan()
        } else {
            fanFixed = c.fixed
            selectZone(FanZone(rawValue: c.zone) ?? .normal)
        }
        preemptFan = c.preemptFan
        guardOnTemp = c.guardOn
        guardOffTemp = c.guardOff
        if guardEnabled != c.guardEnabled { setGuardEnabled(c.guardEnabled) }
        NotificationCenter.default.post(name: .usageProfileLowerHogs, object: c.lowerHogs)
        UserDefaults.standard.set(UsageProfile.custom.rawValue, forKey: "usage_profile")
        objectWillChange.send()
    }

    /// 지금 설정과 맞는 모드 — 어느 것과도 안 맞으면 nil(변경됨)
    var activeProfile: UsageProfile? {
        guard let raw = UserDefaults.standard.string(forKey: "usage_profile"),
              let p = UsageProfile(rawValue: raw) else { return nil }
        if p == .custom {
            guard let c = customProfile else { return nil }
            let now = currentSnapshot
            // 원인 앱 낮추기는 성능 탭에서 따로 바꿀 수 있어 비교에서 뺀다.
            return now.power == c.power && now.fanSystem == c.fanSystem && (c.fanSystem || (now.zone == c.zone && now.fixed == c.fixed))
                && now.preemptFan == c.preemptFan && now.guardEnabled == c.guardEnabled ? .custom : nil
        }
        let fanMatches: Bool = {
            if let z = p.zone { return fanMode == .zone && fanZone == z && !fanFixed }
            return fanMode == .system
        }()
        guard power == p.power, fanMatches, guardEnabled == p.thermalGuard else { return nil }
        if p.zone != nil, preemptFan != p.preemptFan { return nil }
        return p
    }
}
