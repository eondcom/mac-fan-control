import Foundation

/// 모든 코어에 계산 부하를 거는 스레드들 — 측정 동안만
final class CPUBurner: @unchecked Sendable {
    private let lock = NSLock()
    private var running = false

    var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        lock.unlock()
        for _ in 0..<ProcessInfo.processInfo.activeProcessorCount {
            let t = Thread { [weak self] in
                var x = 1.0001
                while self?.isRunning == true {
                    for _ in 0..<200_000 { x = (x * 1.0000001).squareRoot() + 0.5 }
                }
                _ = x
            }
            t.qualityOfService = .userInitiated
            t.start()
        }
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
    }
}

/// 팬·전원 부하 테스트 — 부하를 건 채 ① 팬 최대에서 깎이는지(깎이면 전원 원인) ② 팬을 단계적으로 내리며 깎이는 rpm 을 찾는다.
/// 2026-10-04 이 맥(15" 2018)에서 직접 돌려 본 결과: 팬 6000rpm·70°C 에서도 부하 10초 만에 90% 로 깎임 → 전원·배터리 원인.
@MainActor
final class FanCalibrator: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// 팬 최대 + 부하 — 여기서 깎이면 팬과 무관
        case maxCheck
        case stepping
        case finished
    }

    struct Result: Codable, Equatable {
        let date: Date
        /// 속도 제한이 걸린 rpm — nil 이면 최저 rpm 까지 괜찮았다
        let throttleRPM: Int?
        /// 추천 하한
        let recommended: Int
        /// 팬 최대에서도 깎였다 — 팬과 무관한 전원 원인
        let powerLimited: Bool
        /// 온도 안전선에 닿아 멈춤
        let hitTempLimit: Bool
        let maxTemp: Double
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var targetRPM: Int?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var stepRemaining: TimeInterval = 0
    @Published private(set) var lastSpeed: Int?
    @Published private(set) var lastTemp: Double?
    @Published private(set) var message: String?
    @Published private(set) var result: Result? {
        didSet {
            if let r = result, let d = try? JSONEncoder().encode(r) { UserDefaults.standard.set(d, forKey: Self.key) }
        }
    }

    static let startRPM = 4500
    static let stepRPM = 300
    static let maxCheck: TimeInterval = 30
    static let hold: TimeInterval = 40
    static let tempLimit = 95.0
    static let margin = 300
    private static let key = "fan_calibration"

    private let burner = CPUBurner()
    private var timer: Timer?
    private var started = Date()
    private var stepStarted = Date()
    private var lowSince: Date?
    private var maxTemp = 0.0
    private var range: ClosedRange<Int> = 2000...6000
    private weak var state: AppState?

    var isRunning: Bool { phase == .maxCheck || phase == .stepping }

    init() {
        if let d = UserDefaults.standard.data(forKey: Self.key),
           let r = try? JSONDecoder().decode(Result.self, from: d) {
            result = r
        }
    }

    /// 측정 전에 막아야 할 것 — 없으면 nil
    func blocker(_ s: AppState) -> String? {
        if !FanHelper.isReady { return tr("팬 제어 도우미를 먼저 설치하세요") }
        if s.battery.adapterWatts == nil { return tr("충전기를 연결하세요 — 배터리로는 원래 속도가 깎일 수 있어 결과가 틀립니다") }
        if s.power == .low { return tr("전원 모드를 '기본'으로 바꾸세요 — 절전 모드는 일부러 속도를 낮춥니다") }
        return nil
    }

    func start(_ s: AppState) {
        guard !isRunning, blocker(s) == nil else { return }
        state = s
        range = s.hardwareRange
        maxTemp = 0
        message = nil
        lowSince = nil
        s.beginCalibration()
        burner.start()
        started = Date()
        stepStarted = started
        phase = .maxCheck
        setFan(range.upperBound)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func cancel() {
        guard isRunning else { return }
        // 지난 결과는 그대로 둔다.
        finish(nil, note: tr("측정을 취소했습니다"))
    }

    private func setFan(_ rpm: Int) {
        targetRPM = rpm
        Task.detached { Thermal.setFanSpeed(rpm: rpm) }
    }

    private func tick() {
        guard isRunning, let s = state else { return }
        let now = Date()
        elapsed = now.timeIntervalSince(started)
        let speed = PerfService.speedLimit()
        let temp = s.thermal.cpuTemp
        lastSpeed = speed
        lastTemp = temp
        if let t = temp { maxTemp = max(maxTemp, t) }

        // 안전선 — 바로 멈추고 지금 rpm 을 한계로 본다
        if let t = temp, t >= Self.tempLimit {
            finish(makeResult(throttleAt: targetRPM, hitTemp: true), note: nil)
            return
        }

        // 속도 제한이 4초 이어지면 그 rpm 이 한계
        if let sp = speed, sp < 100 {
            let since = lowSince ?? now
            lowSince = since
            if now.timeIntervalSince(since) >= 4 {
                if phase == .maxCheck {
                    finish(Result(date: now, throttleRPM: nil, recommended: range.lowerBound, powerLimited: true,
                                  hitTempLimit: false, maxTemp: maxTemp), note: nil)
                } else {
                    finish(makeResult(throttleAt: targetRPM, hitTemp: false), note: nil)
                }
                return
            }
        } else {
            lowSince = nil
        }

        let length = phase == .maxCheck ? Self.maxCheck : Self.hold
        stepRemaining = max(0, length - now.timeIntervalSince(stepStarted))
        guard stepRemaining == 0 else { return }

        // 다음 단계 — 팬 최대 확인이 끝나면 4500 부터, 그다음은 300 씩
        let current = targetRPM ?? range.upperBound
        let next: Int
        if phase == .maxCheck {
            phase = .stepping
            next = min(Self.startRPM, range.upperBound)
        } else if current <= range.lowerBound {
            finish(makeResult(throttleAt: nil, hitTemp: false), note: nil)
            return
        } else {
            next = max(current - Self.stepRPM, range.lowerBound)
        }
        stepStarted = now
        lowSince = nil
        setFan(next)
    }

    private func makeResult(throttleAt rpm: Int?, hitTemp: Bool) -> Result {
        let rec: Int
        if let rpm {
            rec = min((rpm + Self.margin + 99) / 100 * 100, range.upperBound)
        } else {
            rec = range.lowerBound
        }
        return Result(date: Date(), throttleRPM: rpm, recommended: rec, powerLimited: false,
                      hitTempLimit: hitTemp, maxTemp: maxTemp)
    }

    private func finish(_ r: Result?, note: String?) {
        timer?.invalidate()
        timer = nil
        burner.stop()
        state?.endCalibration()
        phase = r == nil ? .idle : .finished
        targetRPM = nil
        message = note
        if let r { result = r }
    }

    /// 앱이 꺼질 때 — 부하를 남기지 않는다
    func emergencyStop() {
        burner.stop()
        timer?.invalidate()
    }
}
