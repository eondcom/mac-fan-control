import Foundation
import Darwin

/// 프로세스 하나의 CPU·메모리
struct ProcSample: Codable, Hashable, Identifiable {
    let pid: Int32
    let name: String
    /// %CPU — 코어 하나가 100%라서 여러 코어를 쓰면 100을 넘는다.
    let cpu: Double
    /// 실제 메모리 (MB)
    let memMB: Int
    var id: Int32 { pid }
}

/// 한 번 잰 시스템 상태
struct PerfSample {
    let date: Date
    /// 전체 CPU 사용률 0...100
    let cpuBusy: Double
    /// 1 정상 · 2 경고 · 4 위험
    let memoryPressure: Int
    let swapUsedMB: Int
    /// 100 미만이면 발열·전원 때문에 CPU 속도가 깎인 상태
    let speedLimit: Int?
    let top: [ProcSample]
}

/// 느려진 순간 하나 — 이어지는 동안은 한 건으로 묶는다.
struct SlowEvent: Codable, Identifiable {
    var id = UUID()
    let start: Date
    var end: Date
    var reasons: Set<SlowReason>
    var peakCPU: Double
    var minSpeedLimit: Int?
    var peakSwapMB: Int
    /// 그동안 CPU를 가장 많이 쓴 프로세스 (이름별 최고값)
    var culprits: [ProcSample]
}

enum SlowReason: String, Codable, CaseIterable {
    case cpu, throttle, memory, swap, crash

    var label: String {
        switch self {
        case .cpu:      return tr("CPU 과부하")
        case .throttle: return tr("속도 제한")
        case .memory:   return tr("메모리 부족")
        case .swap:     return tr("스왑 급증")
        case .crash:    return tr("앱 충돌")
        }
    }
}

enum PerfService {

    // MARK: CPU 전체 — 직전 측정과의 차이로 계산

    private static var lastTicks: (busy: UInt64, total: UInt64)?

    static func cpuBusy() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let user = UInt64(info.cpu_ticks.0), sys = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2), nice = UInt64(info.cpu_ticks.3)
        let busy = user + sys + nice, total = busy + idle
        defer { lastTicks = (busy, total) }
        guard let last = lastTicks, total > last.total else { return 0 }
        return Double(busy - last.busy) / Double(total - last.total) * 100
    }

    // MARK: 메모리

    static func memoryPressure() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return Int(level)
    }

    static func swapUsedMB() -> Int {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int(usage.xsu_used / 1_048_576)
    }

    // MARK: 속도 제한

    static func speedLimit() -> Int? {
        let out = Shell.run("/usr/bin/pmset", ["-g", "therm"])
        guard let r = out.range(of: #"CPU_Speed_Limit\s*=\s*(\d+)"#, options: .regularExpression) else { return nil }
        let v = Int(out[r].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
        lastSpeedLimit = v
        return v
    }

    /// 마지막으로 읽은 속도 제한 — 화면에서 매번 pmset을 띄우지 않도록
    private static var lastSpeedLimit: Int?
    static var speedLimitCached: Int? {
        if lastSpeedLimit == nil { _ = speedLimit() }
        return lastSpeedLimit
    }

    // MARK: 프로세스

    static func topProcesses(_ n: Int = 5) -> [ProcSample] {
        let out = Shell.run("/bin/ps", ["-Ac", "-r", "-o", "pid=,pcpu=,rss=,comm="])
        var result: [ProcSample] = []
        for line in out.split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count == 4, let pid = Int32(f[0]), let cpu = Double(f[1]), let rss = Int(f[2]) else { continue }
            let name = f[3].trimmingCharacters(in: .whitespaces)
            // ps 자신은 잴 때마다 잡히므로 뺀다.
            if name == "ps" { continue }
            result.append(ProcSample(pid: pid, name: name, cpu: cpu, memMB: rss / 1024))
            if result.count == n { break }
        }
        return result
    }

    static func sample() -> PerfSample {
        PerfSample(date: Date(), cpuBusy: cpuBusy(), memoryPressure: memoryPressure(),
                   swapUsedMB: swapUsedMB(), speedLimit: speedLimit(), top: topProcesses())
    }
}

// MARK: - 성능 모니터링 상태

@MainActor
final class PerfMonitor: ObservableObject {

    /// 판정 기준
    static let busyThreshold = 70.0
    static let hogThreshold = 50.0
    static let swapJumpMB = 256

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "perf_enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "perf_enabled")
            enabled ? start() : stop()
        }
    }
    /// 한 프로그램이 1분 넘게 CPU를 많이 쓰면 알림
    @Published var hogAlert: Bool = UserDefaults.standard.bool(forKey: "perf_hog_alert") {
        didSet {
            UserDefaults.standard.set(hogAlert, forKey: "perf_hog_alert")
            if hogAlert { Notifier.requestAuthorization() }
        }
    }

    @Published private(set) var latest: PerfSample?
    @Published private(set) var events: [SlowEvent] = []

    private var timer: Timer?
    private var busyStreak = 0
    private var lastSwapMB: Int?
    private var current: SlowEvent?
    /// 이름별로 CPU를 많이 쓴 연속 횟수와 마지막 알림 시각
    private var hogStreak: [String: Int] = [:]
    private var hogNotified: [String: Date] = [:]

    private static let interval: TimeInterval = 5
    private static let keep: TimeInterval = 24 * 3600

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacFanControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("slow-events.json")
    }()

    init() {
        load()
        if enabled { start() }
    }

    func start() {
        stop()
        _ = PerfService.cpuBusy() // 기준점
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        closeCurrent()
        busyStreak = 0
        lastSwapMB = nil
        hogStreak.removeAll()
    }

    /// 모니터링 중이면 기다리지 않고 바로 한 번 잰다.
    func refreshNow() {
        if enabled { tick() }
    }

    func clear() {
        events.removeAll()
        current = nil
        save()
    }

    private func tick() {
        Task.detached {
            let s = PerfService.sample()
            await MainActor.run { [weak self] in self?.handle(s) }
        }
    }

    // MARK: 판정

    private func handle(_ s: PerfSample) {
        latest = s

        var reasons = Set<SlowReason>()
        busyStreak = s.cpuBusy >= Self.busyThreshold ? busyStreak + 1 : 0
        // 잠깐 튀는 건 빼고 10초 이상 이어질 때만
        if busyStreak >= 2 { reasons.insert(.cpu) }
        if let l = s.speedLimit, l < 100 { reasons.insert(.throttle) }
        if s.memoryPressure >= 2 { reasons.insert(.memory) }
        if let last = lastSwapMB, s.swapUsedMB - last >= Self.swapJumpMB { reasons.insert(.swap) }
        if s.top.contains(where: { $0.name == "ReportCrash" && $0.cpu >= 20 }) { reasons.insert(.crash) }
        lastSwapMB = s.swapUsedMB

        if reasons.isEmpty {
            closeCurrent()
        } else {
            record(s, reasons)
        }
        checkHogs(s)
    }

    private func record(_ s: PerfSample, _ reasons: Set<SlowReason>) {
        var e = current ?? SlowEvent(start: s.date, end: s.date, reasons: [], peakCPU: 0,
                                      minSpeedLimit: nil, peakSwapMB: 0, culprits: [])
        e.end = s.date
        e.reasons.formUnion(reasons)
        e.peakCPU = max(e.peakCPU, s.cpuBusy)
        if let l = s.speedLimit, l < 100 { e.minSpeedLimit = min(e.minSpeedLimit ?? 100, l) }
        e.peakSwapMB = max(e.peakSwapMB, s.swapUsedMB)

        var byName = Dictionary(e.culprits.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        for p in s.top where p.cpu >= 5 {
            if let old = byName[p.name], old.cpu >= p.cpu { continue }
            byName[p.name] = p
        }
        e.culprits = Array(byName.values.sorted { $0.cpu > $1.cpu }.prefix(5))

        current = e
        upsert(e)
    }

    private func closeCurrent() {
        guard current != nil else { return }
        current = nil
        save()
    }

    private func upsert(_ e: SlowEvent) {
        if let i = events.firstIndex(where: { $0.id == e.id }) {
            events[i] = e
        } else {
            events.insert(e, at: 0)
            prune()
            save()
        }
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Self.keep)
        events.removeAll { $0.end < cutoff }
    }

    // MARK: 오래 CPU를 쓰는 앱 알림

    private func checkHogs(_ s: PerfSample) {
        let hot = Set(s.top.filter { $0.cpu >= Self.hogThreshold }.map(\.name))
        hogStreak = hogStreak.filter { hot.contains($0.key) }
        for name in hot {
            let n = (hogStreak[name] ?? 0) + 1
            hogStreak[name] = n
            // 5초 × 12 = 1분
            guard hogAlert, n >= 12 else { continue }
            if let last = hogNotified[name], Date().timeIntervalSince(last) < 1800 { continue }
            hogNotified[name] = Date()
            let cpu = s.top.first { $0.name == name }?.cpu ?? 0
            Notifier.post(id: "hog-\(name)", title: trf("%@이(가) CPU를 많이 쓰고 있습니다", name),
                          body: trf("1분 넘게 CPU %.0f%%를 쓰고 있습니다. 느려졌다면 이 앱을 확인해 보세요.", cpu))
        }
    }

    // MARK: 자주 원인으로 잡힌 앱

    struct Offender: Identifiable {
        let name: String
        let count: Int
        let peakCPU: Double
        var id: String { name }
    }

    /// 느려진 순간마다 상위 3개 안에 든 횟수
    var offenders: [Offender] {
        var count: [String: Int] = [:]
        var peak: [String: Double] = [:]
        for e in events {
            for p in e.culprits.prefix(3) {
                count[p.name, default: 0] += 1
                peak[p.name] = max(peak[p.name] ?? 0, p.cpu)
            }
        }
        return count.map { Offender(name: $0.key, count: $0.value, peakCPU: peak[$0.key] ?? 0) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.peakCPU > $1.peakCPU }
    }

    // MARK: 저장

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([SlowEvent].self, from: data) else { return }
        events = list
        prune()
    }

    private func save() {
        prune()
        guard let data = try? JSONEncoder().encode(events) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
