import Foundation

/// 속도 제한(스로틀)이 걸린 순간 하나 — 그때의 온도를 남겨 자동 절전 온도를 추천한다.
struct ThrottleRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    let start: Date
    var end: Date
    /// 속도 제한이 시작된 순간의 CPU 온도
    let startTemp: Double
    /// 시작 직전 1분 동안의 최고 온도
    let peakBefore: Double
    var minSpeed: Int
    /// 시작 순간 팬 rpm, 그리고 이 앱이 팬을 제어하던 중이었는지 (시스템 자동이면 false)
    var fanRPM: Int?
    var fanControlled: Bool?

    /// 시작 순간 이 온도 이상이면 열 때문으로 본다. 아래면 전원·배터리 쪽.
    /// 직전 최고 온도는 참고용 — 1분 전에 뜨거웠다 식은 뒤 걸린 전원 스로틀을 열로 잘못 세지 않도록 기준에서 뺀다.
    static let thermalTemp = 80.0
    var isThermal: Bool { startTemp >= Self.thermalTemp }
}

/// 자동 절전 추천값
struct GuardRecommendation: Equatable {
    let on: Int
    let off: Int
    /// 근거가 된 열 스로틀 수
    let basis: Int
    /// 그 스로틀들의 시작 온도 중 가장 낮은 값과 가운데 값
    let lowest: Int
    let median: Int
}

/// 2초마다 속도·온도를 받아 스로틀 시작·끝을 기록한다(최근 100건, UserDefaults).
@MainActor
final class ThrottleLog: ObservableObject {
    @Published private(set) var records: [ThrottleRecord] = []

    static let keep = 100
    /// 추천에 필요한 최소 열 스로틀 수
    static let minBasis = 3
    private static let key = "throttle_log"

    private var current: ThrottleRecord?
    /// 최근 1분 온도 (2초 간격 30개)
    private var recentTemps: [Double] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([ThrottleRecord].self, from: data) {
            records = list
        }
    }

    func step(speed: Int?, temp: Double?, fanRPM: Int? = nil, fanControlled: Bool = false) {
        if let t = temp {
            recentTemps.append(t)
            if recentTemps.count > 30 { recentTemps.removeFirst(recentTemps.count - 30) }
        }
        let now = Date()
        guard let s = speed else { return }
        if s < 100 {
            if var c = current {
                c.end = now
                c.minSpeed = min(c.minSpeed, s)
                current = c
                replace(c)
            } else if let t = temp {
                let r = ThrottleRecord(start: now, end: now, startTemp: t,
                                       peakBefore: recentTemps.max() ?? t, minSpeed: s,
                                       fanRPM: fanRPM, fanControlled: fanControlled)
                current = r
                records.insert(r, at: 0)
                if records.count > Self.keep { records.removeLast(records.count - Self.keep) }
                save()
            }
        } else if current != nil {
            current = nil
            save()
        }
    }

    private func replace(_ r: ThrottleRecord) {
        if let i = records.firstIndex(where: { $0.id == r.id }) { records[i] = r }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    func clear() {
        records.removeAll()
        current = nil
        save()
    }

    var thermalCount: Int { records.filter(\.isThermal).count }
    var powerCount: Int { records.count - thermalCount }

    /// 팬을 낮게 제어하다 속도 제한이 걸린 rpm 중 가장 높은 값 + 300 — 이 아래로 내리면 깎이는 선.
    /// CPU 온도가 정상이어도 전원부·하판 센서가 뜨거워져 깎이는 경우가 있어 온도 대신 rpm 으로 본다.
    var fanRecommendation: (rpm: Int, basis: Int, highest: Int)? {
        let rpms = records.filter { $0.fanControlled == true }.compactMap(\.fanRPM)
        guard let highest = rpms.max() else { return nil }
        return ((highest + 300 + 99) / 100 * 100, rpms.count, highest)
    }

    /// 열 스로틀 시작 온도의 하위 20% 지점에서 3°C 낮춘 값 — 대부분의 스로틀보다 먼저 켜지도록.
    var recommendation: GuardRecommendation? {
        let temps = records.filter(\.isThermal).map(\.startTemp).sorted()
        guard temps.count >= Self.minBasis else { return nil }
        let p20 = temps[Int(Double(temps.count - 1) * 0.2)]
        let on = min(max(Int(p20.rounded()) - 3, 75), 95)
        let off = min(max(on - 15, 55), 85)
        return GuardRecommendation(on: on, off: off, basis: temps.count,
                                   lowest: Int(temps.first!.rounded()),
                                   median: Int(temps[temps.count / 2].rounded()))
    }
}
