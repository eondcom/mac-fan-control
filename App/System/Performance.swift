import Foundation
import Darwin
import IOKit.pwr_mgt
import AppKit

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

/// 메모리 사용량 — 활성 상태 보기와 같은 셈법 (MB)
struct MemoryUsage {
    let totalMB: Int
    /// 앱 메모리 + 고정 + 압축
    let usedMB: Int
    let appMB: Int
    let wiredMB: Int
    let compressedMB: Int
    /// 파일 캐시 — 필요하면 바로 비워지므로 사용량에 넣지 않는다.
    let cachedMB: Int

    var usedRatio: Double { totalMB > 0 ? Double(usedMB) / Double(totalMB) : 0 }
}

/// 한 번 잰 시스템 상태
struct PerfSample {
    let date: Date
    /// 전체 CPU 사용률 0...100
    let cpuBusy: Double
    /// 1 정상 · 2 경고 · 4 위험
    let memoryPressure: Int
    let memory: MemoryUsage?
    let swapUsedMB: Int
    /// 100 미만이면 발열·전원 때문에 CPU 속도가 깎인 상태
    let speedLimit: Int?
    let top: [ProcSample]
    /// 메모리를 많이 쓰는 순
    let topMemory: [ProcSample]
}

/// 느려진 순간 하나 — 이어지는 동안은 한 건으로 묶는다.
struct SlowEvent: Codable, Identifiable, Equatable {
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

    private static let meter = CPULoadMeter()

    static func cpuBusy() -> Double { meter.sample() }
}

/// 직전 측정과의 차이로 CPU 사용률을 잰다 — 쓰는 곳마다 따로 두어야 간격이 섞이지 않는다.
final class CPULoadMeter: @unchecked Sendable {
    private var lastTicks: (busy: UInt64, total: UInt64)?
    private let lock = NSLock()

    /// 0...100
    func sample() -> Double {
        lock.lock(); defer { lock.unlock() }
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
}

extension PerfService {

    // MARK: 메모리

    static func memoryPressure() -> Int {
        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
        return Int(level)
    }

    static func memoryUsage() -> MemoryUsage? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        func mb(_ pages: UInt64) -> Int { Int(pages * page / 1_048_576) }
        let purgeable = UInt64(info.purgeable_count)
        let app = mb(UInt64(info.internal_page_count) - min(purgeable, UInt64(info.internal_page_count)))
        let wired = mb(UInt64(info.wire_count))
        let compressed = mb(UInt64(info.compressor_page_count))
        return MemoryUsage(totalMB: Int(ProcessInfo.processInfo.physicalMemory / 1_048_576),
                           usedMB: app + wired + compressed, appMB: app, wiredMB: wired,
                           compressedMB: compressed,
                           cachedMB: mb(UInt64(info.external_page_count) + purgeable))
    }

    static func swapUsedMB() -> Int {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return 0 }
        return Int(usage.xsu_used / 1_048_576)
    }

    // MARK: 속도 제한

    /// pmset -g therm과 같은 값 — 프로세스를 띄우지 않고 IOKit으로 읽는다.
    static func speedLimit() -> Int? {
        var dict: Unmanaged<CFDictionary>?
        guard IOPMCopyCPUPowerStatus(&dict) == kIOReturnSuccess,
              let d = dict?.takeRetainedValue() as? [String: Any] else { return nil }
        let v = d[kIOPMCPUPowerLimitProcessorSpeedKey] as? Int
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

    /// ps 한 번으로 CPU 순·메모리 순을 같이 뽑는다.
    static func topProcesses(_ n: Int = 5) -> (cpu: [ProcSample], memory: [ProcSample]) {
        let out = Shell.run("/bin/ps", ["-Ac", "-o", "pid=,pcpu=,rss=,comm="])
        var all: [ProcSample] = []
        for line in out.split(separator: "\n") {
            let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard f.count == 4, let pid = Int32(f[0]), let cpu = Double(f[1]), let rss = Int(f[2]) else { continue }
            let name = f[3].trimmingCharacters(in: .whitespaces)
            // ps 자신은 잴 때마다 잡히므로 뺀다.
            if name == "ps" { continue }
            all.append(ProcSample(pid: pid, name: name, cpu: cpu, memMB: rss / 1024))
        }
        return (Array(all.sorted { $0.cpu > $1.cpu }.prefix(n)),
                Array(all.sorted { $0.memMB > $1.memMB }.prefix(n)))
    }

    static func sample() -> PerfSample {
        let top = topProcesses()
        return PerfSample(date: Date(), cpuBusy: cpuBusy(), memoryPressure: memoryPressure(),
                          memory: memoryUsage(), swapUsedMB: swapUsedMB(), speedLimit: speedLimit(),
                          top: top.cpu, topMemory: top.memory)
    }
}

// MARK: - 성능 모니터링 상태

@MainActor
final class PerfMonitor: ObservableObject {

    /// 판정 기준
    static let busyThreshold = 70.0
    static let hogThreshold = 50.0
    static let swapJumpMB = 256

    /// 백그라운드 기록 — 꺼져 있어도 대시보드·성능 탭을 보는 동안은 잰다.
    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "perf_enabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "perf_enabled")
            if !enabled { resetRecording() }
            reschedule()
        }
    }
    /// 한 프로그램이 1분 넘게 CPU를 많이 쓰면 알림
    @Published var hogAlert: Bool = UserDefaults.standard.bool(forKey: "perf_hog_alert") {
        didSet {
            UserDefaults.standard.set(hogAlert, forKey: "perf_hog_alert")
            if hogAlert { Notifier.requestAuthorization() }
        }
    }

    /// CPU를 오래 쓰는 앱을 백그라운드 우선순위로 — 그 앱만 느려지고 나머지는 쾌적하게
    @Published var lowerHogs: Bool = UserDefaults.standard.bool(forKey: "perf_lower_hogs") {
        didSet {
            UserDefaults.standard.set(lowerHogs, forKey: "perf_lower_hogs")
            if !lowerHogs { restoreAll() }
            reschedule()
        }
    }
    /// 우선순위를 낮춘 앱 (pid → 이름)
    @Published private(set) var lowered: [Int32: String] = [:]
    /// 낮춘 앱이 CPU를 덜 쓰기 시작한 때
    private var loweredCoolSince: [Int32: Date] = [:]

    @Published private(set) var latest: PerfSample?
    @Published private(set) var events: [SlowEvent] = [] {
        didSet { if events != oldValue { offenders = Self.rank(events) } }
    }
    /// 자주 원인으로 잡힌 앱 — 기록이 바뀔 때만 다시 센다
    @Published private(set) var offenders: [Offender] = []

    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    /// 지금 CPU·메모리를 보여주는 화면 수
    private var viewers = 0
    /// CPU를 많이 쓰기 시작한 때 — 재는 간격이 바뀌어도 시간으로 판정한다.
    private var busySince: Date?
    private var lastSwapMB: Int?
    private var current: SlowEvent?
    /// 이름별로 CPU를 많이 쓰기 시작한 때와 마지막 알림 시각
    private var hogSince: [String: Date] = [:]
    private var hogNotified: [String: Date] = [:]

    /// 기록만 할 때는 5초, 화면에서 보고 있으면 2초
    private static let interval: TimeInterval = 5
    private static let liveInterval: TimeInterval = 2
    private static let keep: TimeInterval = 24 * 3600

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacFanControl", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("slow-events.json")
    }()

    init() {
        load()
        reschedule()
        // 사용 모드가 정한 원인 앱 낮추기 값
        NotificationCenter.default.addObserver(forName: .usageProfileLowerHogs, object: nil, queue: .main) { [weak self] n in
            guard let on = n.object as? Bool else { return }
            MainActor.assumeIsolated { if self?.lowerHogs != on { self?.lowerHogs = on } }
        }
        // 앱이 꺼져도 낮춘 우선순위가 남지 않게 되돌린다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restoreAll() }
        }
    }

    /// 화면이 나타날 때 부른다 — 사라질 때 stopLive()와 짝.
    func startLive() {
        viewers += 1
        reschedule()
    }

    func stopLive() {
        viewers = max(0, viewers - 1)
        reschedule()
    }

    /// 기록 중이거나 보는 화면이 있을 때만 타이머를 돌린다.
    private func reschedule() {
        let want: TimeInterval = viewers > 0 ? Self.liveInterval : (enabled || lowerHogs ? Self.interval : 0)
        guard want != timerInterval else { return }
        timer?.invalidate()
        timer = nil
        timerInterval = want
        guard want > 0 else { return }
        if latest == nil { _ = PerfService.cpuBusy() } // 기준점
        timer = Timer.scheduledTimer(withTimeInterval: want, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    private func resetRecording() {
        closeCurrent()
        busySince = nil
        lastSwapMB = nil
        hogSince.removeAll()
    }

    /// 재고 있으면 기다리지 않고 바로 한 번 잰다.
    func refreshNow() {
        if timer != nil { tick() }
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
        if lowerHogs || enabled { checkHogs(s) }
        guard enabled else { return }

        var reasons = Set<SlowReason>()
        busySince = s.cpuBusy >= Self.busyThreshold ? (busySince ?? s.date) : nil
        // 잠깐 튀는 건 빼고 10초 이상 이어질 때만
        if let since = busySince, s.date.timeIntervalSince(since) >= 10 { reasons.insert(.cpu) }
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
        checkLowered(s)
        let hot = Set(s.top.filter { $0.cpu >= Self.hogThreshold }.map(\.name))
        hogSince = hogSince.filter { hot.contains($0.key) }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for name in hot {
            let since = hogSince[name] ?? s.date
            hogSince[name] = since
            guard s.date.timeIntervalSince(since) >= 60 else { continue }
            if lowerHogs {
                for p in s.top where p.name == name && p.cpu >= Self.hogThreshold {
                    lower(p, front: front)
                }
            }
            guard hogAlert, enabled else { continue }
            if let last = hogNotified[name], Date().timeIntervalSince(last) < 1800 { continue }
            hogNotified[name] = Date()
            let cpu = s.top.first { $0.name == name }?.cpu ?? 0
            Notifier.post(id: "hog-\(name)", title: trf("%@이(가) CPU를 많이 쓰고 있습니다", name),
                          body: trf("1분 넘게 CPU %.0f%%를 쓰고 있습니다. 느려졌다면 이 앱을 확인해 보세요.", cpu))
        }
    }

    // MARK: 원인 앱 우선순위 낮추기

    private func lower(_ p: ProcSample, front: pid_t?) {
        // 지금 쓰고 있는 앱·이 앱 자신은 건드리지 않는다.
        guard lowered[p.pid] == nil, p.pid != front, p.pid != getpid() else { return }
        // 내 계정 프로세스만 바뀐다 — 시스템 프로세스는 실패하고 넘어간다.
        guard setpriority(PRIO_DARWIN_PROCESS, id_t(p.pid), PRIO_DARWIN_BG) == 0 else { return }
        lowered[p.pid] = p.name
        Notifier.post(id: "lower-\(p.name)", title: trf("%@의 우선순위를 낮췄습니다", p.name),
                      body: trf("1분 넘게 CPU %.0f%%를 써서 다른 앱이 먼저 돌도록 했습니다. 이 앱을 앞으로 가져오거나 CPU 사용이 줄면 되돌립니다.", p.cpu))
    }

    /// 낮춘 앱이 1분 넘게 조용하거나, 사용자가 앞으로 가져오면 되돌린다.
    private func checkLowered(_ s: PerfSample) {
        guard !lowered.isEmpty else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        for pid in Array(lowered.keys) {
            if kill(pid, 0) != 0 {
                lowered[pid] = nil
                loweredCoolSince[pid] = nil
                continue
            }
            if pid == front { restore(pid); continue }
            let busy = s.top.contains { $0.pid == pid && $0.cpu >= Self.hogThreshold }
            if busy {
                loweredCoolSince[pid] = nil
            } else {
                let since = loweredCoolSince[pid] ?? s.date
                loweredCoolSince[pid] = since
                if s.date.timeIntervalSince(since) >= 60 { restore(pid) }
            }
        }
    }

    func restore(_ pid: Int32) {
        setpriority(PRIO_DARWIN_PROCESS, id_t(pid), 0)
        lowered[pid] = nil
        loweredCoolSince[pid] = nil
    }

    func restoreAll() {
        for pid in Array(lowered.keys) { restore(pid) }
    }

    // MARK: 자주 원인으로 잡힌 앱

    struct Offender: Identifiable, Equatable {
        let name: String
        let count: Int
        let peakCPU: Double
        var id: String { name }
    }

    /// 느려진 순간마다 상위 3개 안에 든 횟수
    private static func rank(_ events: [SlowEvent]) -> [Offender] {
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
