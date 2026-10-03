import Foundation

/// 느려지는 원인 하나 — 지금 해당하는지와 없애는 방법
struct SlowdownCause: Identifiable {
    enum Kind: String { case battery, charger, lowPower, throttle, leftPort, cooling }
    let kind: Kind
    /// 지금 이 원인에 해당하는가
    let active: Bool
    let title: String
    let detail: String
    let fixes: [String]
    var id: String { kind.rawValue }
}

enum SlowdownAdvice {

    /// 배터리가 이 아래로 낮아지면 macOS가 성능을 보수적으로 관리할 수 있다.
    static let weakBattery = 80

    /// 모델별 권장 충전기 — 15·16인치 인텔 맥북 프로는 87W 이상
    static let recommendedWatts: Int = {
        let model = sysctlString("hw.model") ?? ""
        let big = ["MacBookPro11,4", "MacBookPro11,5", "MacBookPro13,3", "MacBookPro14,3",
                   "MacBookPro15,1", "MacBookPro15,3", "MacBookPro16,1", "MacBookPro16,4"]
        return big.contains(model) ? 87 : 61
    }()

    /// 2016~2019 인텔 맥북 프로 — 왼쪽 포트 충전 발열 문제가 알려진 모델
    static let hasLeftPortIssue: Bool = {
        let model = sysctlString("hw.model") ?? ""
        return ["MacBookPro13,", "MacBookPro14,", "MacBookPro15,", "MacBookPro16,"].contains { model.hasPrefix($0) }
    }()

    static func causes(battery: BatteryInfo, power: PowerMode, speedLimit: Int?, throttleEvents: Int) -> [SlowdownCause] {
        var list: [SlowdownCause] = []
        let need = recommendedWatts

        let cap = battery.capacityPercent
        let serviceFlag = ["Service Recommended", "Replace Soon", "Replace Now", "Poor"].contains(battery.condition ?? "")
        list.append(SlowdownCause(
            kind: .battery,
            active: (cap.map { $0 < weakBattery } ?? false) || serviceFlag,
            title: tr("배터리 건강도"),
            detail: trf("건강도가 %d%% 아래로 낮아지거나 '점검 권장'이 뜨면, 배터리가 순간 전력을 받쳐 주지 못해 CPU 속도가 깎일 수 있습니다.", weakBattery),
            fixes: [tr("배터리 교체 — 가장 확실한 해결입니다"),
                    tr("교체 전까지는 권장 출력 이상의 충전기를 꽂고 쓰세요")]))

        if let w = battery.adapterWatts {
            list.append(SlowdownCause(
                kind: .charger,
                // 애플 87W 어댑터는 86W로 보고되므로 몇 W 여유를 둔다.
                active: w + 3 < need,
                title: tr("충전기 출력"),
                detail: trf("지금 %dW로 들어옵니다. 이 맥은 %dW 이상을 권장합니다. 부족하면 무거운 작업에서 속도가 깎이고 배터리가 줄어듭니다.", w, need),
                fixes: [trf("%dW 이상 충전기 사용", need),
                        tr("모니터 USB-C로 충전하면 케이블이 5A(100W)인지 확인 — 3A 케이블은 60W까지만 전달합니다"),
                        tr("충전기가 여러 개면 맥은 가장 센 것 하나만 씁니다")]))
        }

        list.append(SlowdownCause(
            kind: .lowPower,
            active: power == .low && battery.adapterWatts != nil,
            title: tr("절전 모드"),
            detail: tr("절전 모드는 일부러 CPU 속도를 낮춥니다. 충전 중에는 켤 필요가 없습니다."),
            fixes: [tr("전원 모드를 '기본'으로")]))

        if hasLeftPortIssue {
            list.append(SlowdownCause(
                kind: .leftPort,
                active: false,
                title: tr("충전 포트 위치"),
                detail: tr("이 모델은 왼쪽 포트로 충전하면 전원부가 데워져 팬이 빨라지고 CPU 속도가 깎이는 경우가 많습니다."),
                fixes: [tr("충전기는 오른쪽 포트에, 모니터·주변기기는 왼쪽에")]))
        }

        list.append(SlowdownCause(
            kind: .throttle,
            active: (speedLimit.map { $0 < 100 } ?? false) || throttleEvents > 0,
            title: tr("CPU 속도 제한"),
            detail: speedLimit.map { trf("지금 CPU 속도 %d%% · 최근 24시간 제한 %d번. 하드웨어 보호용이라 강제로 끌 수 없고, 원인을 없애야 풀립니다.", $0, throttleEvents) }
                ?? tr("하드웨어 보호용이라 강제로 끌 수 없고, 원인을 없애야 풀립니다."),
            fixes: [tr("온도가 정상인데 깎였다면 — 완전히 종료했다가 켜기, 그래도 안 되면 SMC 재설정"),
                    tr("위의 배터리·충전기·포트 항목부터 확인"),
                    tr("성능 탭 모니터링을 켜 두고 하루 뒤 기록을 비교")]))

        list.append(SlowdownCause(
            kind: .cooling,
            active: false,
            title: tr("내부 먼지·써멀"),
            detail: tr("오래 쓴 맥은 방열판 먼지와 굳은 써멀 때문에 같은 작업에도 더 뜨거워지고 팬이 시끄러워집니다."),
            fixes: [tr("수리점에서 내부 청소 + 써멀 재도포 (배터리 교체 때 함께 요청)"),
                    tr("거치대로 바닥 공기 흐름 확보")]))

        // 해당하는 원인을 위로
        return list.filter(\.active) + list.filter { !$0.active }
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
