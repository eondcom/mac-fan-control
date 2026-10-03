import Foundation
import Combine
import SwiftUI
import AppKit

@MainActor
final class AppState: ObservableObject {

    // 실시간 데이터
    @Published var thermal = ThermalReading(fanManual: false)
    @Published var power: PowerMode = .normal
    @Published var battery = BatteryInfo(isCharging: false, isCharged: false)

    // 사용자 설정 (UserDefaults)
    @AppStorage("mb_show_temp") var mbShowTemp: Bool = true
    @AppStorage("mb_show_fan")  var mbShowFan:  Bool = true
    /// 구간마다 모양이 바뀌는 팬 아이콘
    @AppStorage("mb_show_icon")   var mbShowIcon:   Bool = true
    /// 온도 앞 온도계 아이콘
    @AppStorage("mb_show_thermo") var mbShowThermo: Bool = false
    @AppStorage("start_hidden") var startHidden: Bool = false
    @AppStorage("eu_theme")     var themeMode: EUThemeMode = .dark
    @AppStorage("eu_accent")    var accent: EUAccent = .blue
    @AppStorage("app_language") var language: AppLanguage = .system

    // 팬 제어 설정
    @AppStorage("fan_mode")  var fanMode: FanMode = .system
    @AppStorage("fan_zone")  var fanZone: FanZone = .quiet
    @AppStorage("fan_fixed") var fanFixed: Bool = false
    /// 고온이 이어지면 다음 구간으로 1시간 임시 상향
    @AppStorage("boost_enabled") var boostEnabled: Bool = true
    @AppStorage("boost_temp")    var boostTemp: Int = 80
    /// CPU 부하가 오르면 온도보다 먼저 팬을 올린다 (구간 자동일 때)
    @AppStorage("preempt_fan")   var preemptFan: Bool = true
    /// 최근 CPU 사용률 (부드럽게) — 선제 팬 판단용
    @Published private(set) var cpuLoad: Double = 0
    /// 지금 부하 때문에 팬을 미리 올린 만큼 (°C 환산)
    @Published private(set) var preemptLead: Double = 0
    private let loadMeter = CPULoadMeter()

    /// 온도는 정상인데 CPU 속도가 깎인 상태 — 전원·배터리 원인 (값은 지금 속도 %)
    @Published private(set) var powerThrottle: Int?
    private var powerThrottleSince: Date?
    private var powerThrottleClearSince: Date?
    private var powerThrottleNotified = Date.distantPast
    static let powerThrottleLimit = 70
    static let powerThrottleSustain: TimeInterval = 60
    /// 구간별 상한(구간 자동) · 고정값(구간 고정)
    @Published private(set) var zoneCaps: [FanZone: Int] = [:]
    @Published private(set) var zoneFixedRPM: [FanZone: Int] = [:]
    /// 사용자가 조정한 구간 범위 (없으면 기본 범위)
    @Published private(set) var zoneBounds: [FanZone: ClosedRange<Int>] = [:]

    // 팬 제어 상태
    /// 마지막으로 SMC에 쓴 목표 rpm (구간 제어일 때만)
    @Published private(set) var fanTarget: Int?
    /// 과열로 시스템 자동에 넘겨둔 상태
    @Published private(set) var safetyOverride = false
    /// 임시 상향 중인 구간과 끝나는 시각 — fanZone(사용자 기본)은 그대로 둔다
    @Published private(set) var boostZone: FanZone?
    @Published private(set) var boostUntil: Date?
    private var hotSince: Date?

    // 스로틀 전 자동 절전 — 뜨거우면 저전력 모드로 터보를 막고, 식으면 되돌린다.
    @AppStorage("guard_enabled") var guardEnabled: Bool = false
    @AppStorage("guard_on_temp")  var guardOnTemp: Int = 85
    @AppStorage("guard_off_temp") var guardOffTemp: Int = 70
    /// 스로틀 기록으로 계산한 추천 온도를 자동으로 적용
    @AppStorage("guard_auto_recommend") var guardAutoRecommend: Bool = false
    /// 팬을 제어하다 속도 제한이 걸리면 바로 시스템 자동에 맡긴다.
    @AppStorage("throttle_fan_protect") var throttleFanProtect: Bool = true
    @Published private(set) var throttleOverride = false
    private var lastSpeed: Int?
    private var fanThrottleSince: Date?
    private var fanThrottleClearSince: Date?

    /// 팬·전원 부하 테스트 — 도는 동안 구간 제어·자동 절전·속도 제한 보호를 멈춘다.
    let calibrator = FanCalibrator()
    @Published private(set) var calibrating = false

    /// 스로틀이 걸린 순간의 온도 기록 — 추천값의 근거
    let throttleLog = ThrottleLog()
    /// 이 앱이 켠 저전력 모드 — 사용자가 직접 켠 건 되돌리지 않는다.
    @Published private(set) var guardActive = UserDefaults.standard.bool(forKey: "guard_active") {
        didSet { UserDefaults.standard.set(guardActive, forKey: "guard_active") }
    }
    private var guardHotSince: Date?
    private var guardCoolSince: Date?
    private var guardSwitching = false
    static let guardSustain: TimeInterval = 30
    static let guardCooldown: TimeInterval = 120
    /// 팬 쓰기용 root 헬퍼 상태
    @Published private(set) var helperStatus: FanHelper.Status = .ready
    @Published private(set) var helperInstalling = false

    // 업데이트
    @Published var latestRelease: ReleaseInfo?
    @Published private(set) var updateStatus: UpdateCheckStatus = .idle
    @Published private(set) var installStatus: UpdateInstallStatus = .idle

    private var timers: [Timer] = []
    private var pendingApply: DispatchWorkItem?
    private var lastApply = Date.distantPast
    /// SMC 쓰기는 한 줄로 — 빠르게 바꿔도 마지막 값이 마지막에 쓰이도록
    private let fanQueue = DispatchQueue(label: "com.eond.macfancontrol.fan")

    init() {
        let d = UserDefaults.standard
        for z in FanZone.allCases {
            zoneCaps[z]     = (d.object(forKey: "fan_cap_\(z.rawValue)") as? Int) ?? z.defaultCap
            zoneFixedRPM[z] = (d.object(forKey: "fan_fix_\(z.rawValue)") as? Int) ?? z.defaultFixed
            if let lo = d.object(forKey: "fan_lo_\(z.rawValue)") as? Int,
               let hi = d.object(forKey: "fan_hi_\(z.rawValue)") as? Int, lo < hi {
                zoneBounds[z] = lo...hi
            }
        }
        if let z = d.string(forKey: "boost_zone").flatMap(FanZone.init(rawValue:)),
           let until = d.object(forKey: "boost_until") as? Date, until > Date() {
            boostZone = z
            boostUntil = until
        }
        refreshAll()
        startTimers()
        checkHelper()
        if boostEnabled { Notifier.requestAuthorization() }

        // 앱 없이 팬이 낮게 고정된 채 남지 않도록 종료 시 시스템 자동으로 돌려둔다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.calibrator.emergencyStop() }
            Thermal.resetFanAuto()
        }

        // 시스템 설정·제어 센터에서 절전 모드를 바꿔도 바로 반영한다.
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            let mode = PowerModeService.current()
            Task { @MainActor in self?.powerChangedOutside(mode) }
        }

        if fanMode == .zone { scheduleApply() }
    }

    func startTimers() {
        stopTimers()
        // 구간 자동이 온도를 따라가도록 2초마다 읽는다.
        timers.append(Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshThermal() }
        })
        // pmset을 띄우므로 1초는 과하다 — 충전 상태는 5초면 충분하다.
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBatteryQuick() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBatteryFull() }
        })
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self?.checkUpdate()
        }
    }

    func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }

    // MARK: refresh

    func refreshAll() {
        refreshThermal()
        Task.detached { [weak self] in
            let mode = PowerModeService.current()
            guard let self else { return }
            await MainActor.run { if self.power != mode { self.power = mode } }
        }
        refreshBatteryFull()
    }

    func refreshThermal() {
        Task.detached { [weak self] in
            let t = Thermal.read().smoothed
            guard let self else { return }
            let load = self.loadMeter.sample()
            let speed = PerfService.speedLimit()
            await MainActor.run {
                // 같은 값을 다시 넣어도 모든 화면이 다시 그려지므로 바뀔 때만 넣는다.
                if self.thermal != t { self.thermal = t }
                // 한 번 튀는 건 반만 반영
                self.lastSpeed = speed
                let smoothed = self.cpuLoad * 0.5 + load * 0.5
                if abs(smoothed - self.cpuLoad) >= 1 { self.cpuLoad = smoothed }
                self.controlStep()
                self.guardStep()
                self.powerThrottleStep(speed: speed)
                self.throttleLog.step(speed: speed, temp: t.cpuTemp, fanRPM: t.fanRPM,
                                      fanControlled: self.fanMode == .zone && !self.safetyOverride && !self.throttleOverride)
                self.applyRecommendationIfAuto()
            }
        }
    }

    func refreshBatteryQuick() {
        Task.detached { [weak self] in
            let q = BatteryService.quickStatus()
            guard let self else { return }
            await MainActor.run {
                var b = self.battery
                b.isCharging    = q.isCharging
                b.isCharged     = q.isCharged
                b.timeRemaining = q.timeRemaining
                b.adapterWatts  = q.adapterWatts
                b.batteryWatts  = q.batteryWatts
                if b != self.battery { self.battery = b }
            }
        }
    }

    func refreshBatteryFull() {
        Task.detached { [weak self] in
            let info = BatteryService.full()
            guard let self else { return }
            await MainActor.run { if self.battery != info { self.battery = info } }
        }
    }

    // MARK: actions

    func setPowerMode(_ mode: PowerMode) {
        // 직접 고르면 자동 절전이 되돌리지 않는다.
        guardActive = false
        Task.detached { [weak self] in
            let ok = PowerModeService.set(mode)
            guard let self, ok else { return }
            await MainActor.run { self.power = mode }
        }
    }

    // MARK: fan helper

    func checkHelper() {
        Task {
            helperStatus = await Task.detached { FanHelper.status() }.value
        }
    }

    func installHelper() {
        helperInstalling = true
        Task {
            let s = await Task.detached { () -> FanHelper.Status in
                _ = FanHelper.install()
                return FanHelper.status()
            }.value
            helperInstalling = false
            helperStatus = s
            if s == .ready && fanMode == .zone { scheduleApply() }
        }
    }

    // MARK: fan control

    /// 하드웨어가 받는 범위 — SMC 최소(100 단위 올림) ~ 최대
    var hardwareRange: ClosedRange<Int> {
        let lo = thermal.fanMin.map { ($0 + 99) / 100 * 100 } ?? 2000
        let hi = thermal.fanMax ?? 6000
        return lo < hi ? lo...hi : 2000...6000
    }

    /// 구간의 실제 범위 — 사용자 범위(없으면 기본)를 하드웨어 범위로 자른다.
    func zoneRange(_ z: FanZone) -> ClosedRange<Int> {
        let hw = hardwareRange
        let base = zoneBounds[z] ?? z.baseRange
        let lo = min(max(base.lowerBound, hw.lowerBound), hw.upperBound - 100)
        let hi = max(min(base.upperBound, hw.upperBound), lo + 100)
        return lo...hi
    }

    func isZoneCustomized(_ z: FanZone) -> Bool {
        zoneBounds[z] != nil || zoneCaps[z] != z.defaultCap || zoneFixedRPM[z] != z.defaultFixed
    }

    /// 구간 범위 조정 — 최소 폭 100rpm
    func setZoneBounds(_ z: FanZone, lower: Int, upper: Int) {
        let hw = hardwareRange
        let lo = clamp(lower, to: hw.lowerBound...(hw.upperBound - 100))
        let hi = clamp(upper, to: (lo + 100)...hw.upperBound)
        zoneBounds[z] = lo...hi
        UserDefaults.standard.set(lo, forKey: "fan_lo_\(z.rawValue)")
        UserDefaults.standard.set(hi, forKey: "fan_hi_\(z.rawValue)")
        if z == fanZone {
            fanMode = .zone
            scheduleApply()
        }
    }

    /// 구간의 범위·상한·고정값을 기본값으로
    func resetZone(_ z: FanZone) {
        zoneBounds[z] = nil
        zoneCaps[z] = z.defaultCap
        zoneFixedRPM[z] = z.defaultFixed
        for k in ["lo", "hi", "cap", "fix"] {
            UserDefaults.standard.removeObject(forKey: "fan_\(k)_\(z.rawValue)")
        }
        if z == fanZone { scheduleApply() }
    }

    func zoneCap(_ z: FanZone) -> Int {
        clamp(zoneCaps[z] ?? z.defaultCap, to: zoneRange(z))
    }

    func zoneFixed(_ z: FanZone) -> Int {
        clamp(zoneFixedRPM[z] ?? z.defaultFixed, to: zoneRange(z))
    }

    /// 지금 슬라이더가 다루는 값 — 구간 자동이면 상한, 고정이면 고정값
    var zoneValue: Int { fanFixed ? zoneFixed(fanZone) : zoneCap(fanZone) }

    /// 지금 실제로 쓰는 구간 — 임시 상향 중이면 그 구간
    var activeZone: FanZone { boostZone ?? fanZone }

    /// 시스템 자동으로 복구 — macOS가 다시 팬을 제어한다.
    func useSystemFan() {
        fanMode = .system
        endBoost()
        pendingApply?.cancel()
        fanTarget = nil
        safetyOverride = false
        throttleOverride = false
        fanQueue.async { [weak self] in
            Thermal.resetFanAuto()
            Task { @MainActor in self?.refreshThermal() }
        }
    }

    func selectZone(_ z: FanZone) {
        if boostZone != nil { endBoost() }
        fanMode = .zone
        fanZone = z
        scheduleApply()
    }

    func setFanFixed(_ on: Bool) {
        fanMode = .zone
        fanFixed = on
        scheduleApply()
    }

    /// 슬라이더를 만지면 바로 들리도록 구간 제어로 전환한다.
    func setZoneValue(_ rpm: Int) {
        fanMode = .zone
        let v = clamp(rpm, to: zoneRange(fanZone))
        let key: String
        if fanFixed {
            zoneFixedRPM[fanZone] = v
            key = "fan_fix_\(fanZone.rawValue)"
        } else {
            zoneCaps[fanZone] = v
            key = "fan_cap_\(fanZone.rawValue)"
        }
        UserDefaults.standard.set(v, forKey: key)
        scheduleApply()
    }

    /// 적용 버튼 없이 바로 — 슬라이더를 끄는 동안 너무 자주 쓰지 않게 0.15초 묶는다.
    /// 슬라이더를 끄는 중에도 0.2초마다 적용하고, 손을 뗀 마지막 값도 놓치지 않는다.
    private func scheduleApply() {
        pendingApply?.cancel()
        let interval = 0.2
        let elapsed = Date().timeIntervalSince(lastApply)
        if elapsed >= interval {
            applyNow()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.applyNow() }
        }
        pendingApply = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (interval - elapsed), execute: work)
    }

    private func applyNow() {
        lastApply = Date()
        controlStep(force: true)
    }

    /// 2초마다(또는 설정이 바뀌면 바로) 목표 rpm을 계산해 SMC에 쓴다.
    func controlStep(force: Bool = false) {
        guard fanMode == .zone, !calibrating else { return }
        let temp = max(thermal.cpuTemp ?? 0, thermal.gpuTemp ?? 0)

        // 과열 안전장치
        if temp >= FanCurve.safetyTemp {
            if !safetyOverride {
                safetyOverride = true
                fanTarget = nil
                fanQueue.async { Thermal.resetFanAuto() }
            }
            return
        }
        if safetyOverride {
            guard temp <= FanCurve.resumeTemp else { return }
            safetyOverride = false
        }

        // 속도 제한 보호 — 팬이 낮아 깎이면 4초 안에 시스템 자동으로, 1분 넘게 풀려 있으면 돌아온다.
        if throttleFanProtect, let s = lastSpeed {
            let now = Date()
            if s < 100 {
                fanThrottleClearSince = nil
                let since = fanThrottleSince ?? now
                fanThrottleSince = since
                if !throttleOverride, now.timeIntervalSince(since) >= 4 {
                    throttleOverride = true
                    fanTarget = nil
                    fanQueue.async { Thermal.resetFanAuto() }
                    Notifier.post(id: "throttle-fan", title: tr("속도 제한이 걸려 팬을 시스템에 맡겼습니다"),
                                  body: trf("CPU 속도 %d%%. 속도가 1분 넘게 돌아오면 다시 구간 제어로 돌아옵니다. 자주 생기면 팬 제어 탭의 추천 하한을 적용하세요.", s))
                }
            } else {
                fanThrottleSince = nil
                if throttleOverride {
                    let since = fanThrottleClearSince ?? now
                    fanThrottleClearSince = since
                    guard now.timeIntervalSince(since) >= 60 else { return }
                    throttleOverride = false
                    fanThrottleClearSince = nil
                }
            }
            if throttleOverride { return }
        } else if throttleOverride {
            throttleOverride = false
        }

        let boosted = updateBoost(temp: temp)

        let zone = activeZone
        let range = zoneRange(zone)
        let desired: Int
        if fanFixed {
            desired = zoneFixed(zone)
        } else {
            // 구간을 바꾼 직후엔 이전 목표에 묶이지 않고 바로 새 구간으로 간다.
            let prev = fanTarget.flatMap { range.contains($0) ? $0 : nil }
            let lead = preemptFan ? FanCurve.leadTemp(load: cpuLoad) : 0
            if preemptLead != lead { preemptLead = lead }
            desired = FanCurve.target(temp: temp + lead, lower: range.lowerBound,
                                      cap: zoneCap(zone), previous: force || boosted ? nil : prev)
        }

        let changed = fanTarget.map { abs($0 - desired) >= 50 } ?? true
        guard force || boosted || changed || !thermal.fanManual else { return }
        fanTarget = desired
        fanQueue.async { Thermal.setFanSpeed(rpm: desired) }
    }

    /// 메뉴바·대시보드용 한 줄 설명
    var fanModeLabel: String {
        if fanMode == .system { return tr("시스템 자동") }
        if safetyOverride { return tr("과열 보호") }
        if throttleOverride { return tr("속도 제한 보호") }
        if let b = boostZone { return trf("%@ · 임시", b.label) }
        return fanFixed ? trf("%@ · 고정", fanZone.label) : trf("%@ · 자동", fanZone.label)
    }

    /// 메뉴바 팬 아이콘 — 지금 쓰는 구간(임시 상향 포함)에 따라
    var menuBarSymbol: String {
        if fanMode == .system { return "fan.badge.automatic" }
        if safetyOverride { return "exclamationmark.triangle.fill" }
        if throttleOverride { return "fan.badge.automatic" }
        return activeZone.icon
    }

    // MARK: 고온 임시 상향

    /// 만료·상향을 판단한다. 구간이 바뀌었으면 true.
    private func updateBoost(temp: Double) -> Bool {
        let now = Date()

        // 1시간이 지나면 사용자 기본 구간으로
        if let until = boostUntil, until <= now {
            endBoost()
            Notifier.post(id: "boost", title: tr("팬 구간을 되돌렸습니다"),
                          body: trf("임시 상향 1시간이 지나 기본 설정(%@)으로 돌아왔습니다.", fanZone.label))
            return true
        }

        guard boostEnabled, let next = activeZone.next else {
            hotSince = nil
            return false
        }

        let threshold = Double(boostTemp)
        if temp >= threshold {
            if hotSince == nil { hotSince = now }
        } else if temp < threshold - FanCurve.boostHysteresis {
            hotSince = nil
        }
        guard let since = hotSince, now.timeIntervalSince(since) >= FanCurve.boostSustain else {
            return false
        }

        // 다음 구간으로 1시간 — 더 올라가도 시간은 새로 1시간
        hotSince = nil
        boostZone = next
        boostUntil = now.addingTimeInterval(FanCurve.boostDuration)
        saveBoost()
        Notifier.post(id: "boost", title: trf("팬을 %@ 구간으로 올렸습니다", next.label),
                      body: trf("온도가 %.0f°C로 높아 1시간 동안 %@ 구간을 씁니다. 이후 %@ 구간으로 돌아갑니다.",
                                temp, next.label, fanZone.label))
        return true
    }

    /// 지금 되돌리기 — 사용자 기본 구간으로
    func cancelBoost() {
        guard boostZone != nil else { return }
        endBoost()
        scheduleApply()
    }

    private func endBoost() {
        boostZone = nil
        boostUntil = nil
        hotSince = nil
        saveBoost()
    }

    private func saveBoost() {
        let d = UserDefaults.standard
        d.set(boostZone?.rawValue, forKey: "boost_zone")
        d.set(boostUntil, forKey: "boost_until")
    }

    func setBoostEnabled(_ on: Bool) {
        boostEnabled = on
        if on { Notifier.requestAuthorization() } else { cancelBoost() }
    }

    // MARK: 온도와 무관한 속도 제한 감지

    /// CPU 가 80°C 아래인데 속도 제한이 70% 아래로 1분 이어지면 전원·배터리 원인으로 본다.
    private func powerThrottleStep(speed: Int?) {
        let now = Date()
        let cool = (thermal.cpuTemp ?? 0) < 80
        if let s = speed, s < Self.powerThrottleLimit, cool {
            powerThrottleClearSince = nil
            let since = powerThrottleSince ?? now
            powerThrottleSince = since
            guard now.timeIntervalSince(since) >= Self.powerThrottleSustain else { return }
            if powerThrottle != s { powerThrottle = s }
            if now.timeIntervalSince(powerThrottleNotified) >= 2 * 3600 {
                powerThrottleNotified = now
                Notifier.post(id: "power-throttle", title: trf("CPU 속도가 %d%%로 제한됐습니다", s),
                              body: tr("온도는 정상이라 전원·배터리 쪽 원인입니다. 완전히 종료했다가 켜거나 SMC 재설정을 해 보세요."))
            }
        } else {
            powerThrottleSince = nil
            guard powerThrottle != nil else { return }
            // 잠깐 풀린 것으로 끄지 않는다 — 30초 넘게 정상이어야 해제
            let since = powerThrottleClearSince ?? now
            powerThrottleClearSince = since
            if now.timeIntervalSince(since) >= 30 {
                powerThrottle = nil
                powerThrottleClearSince = nil
            }
        }
    }

    // MARK: 스로틀 전 자동 절전

    /// 2초마다 — CPU 온도가 켜는 온도 이상으로 30초 이어지면 저전력 모드, 끄는 온도 아래로 2분이면 되돌린다.
    private func guardStep() {
        guard guardEnabled, !guardSwitching, !calibrating, let temp = thermal.cpuTemp else {
            guardHotSince = nil
            guardCoolSince = nil
            return
        }
        let now = Date()
        if power == .normal {
            guardCoolSince = nil
            guardHotSince = temp >= Double(guardOnTemp) ? (guardHotSince ?? now) : nil
            guard let since = guardHotSince, now.timeIntervalSince(since) >= Self.guardSustain else { return }
            guardHotSince = nil
            switchPowerByGuard(.low, temp: temp)
        } else if guardActive {
            guardHotSince = nil
            guardCoolSince = temp < Double(guardOffTemp) ? (guardCoolSince ?? now) : nil
            guard let since = guardCoolSince, now.timeIntervalSince(since) >= Self.guardCooldown else { return }
            guardCoolSince = nil
            switchPowerByGuard(.normal, temp: temp)
        }
    }

    private func switchPowerByGuard(_ mode: PowerMode, temp: Double) {
        // 헬퍼가 없으면 매번 암호를 물어야 하므로 자동 전환하지 않는다.
        guard FanHelper.isReady else { return }
        guardSwitching = true
        Task.detached { [weak self] in
            let ok = FanHelper.setLowPower(mode == .low)
            await MainActor.run {
                guard let self else { return }
                self.guardSwitching = false
                guard ok else { return }
                self.power = mode
                self.guardActive = mode == .low
                if mode == .low {
                    Notifier.post(id: "guard", title: tr("저전력 모드로 전환했습니다"),
                                  body: trf("CPU가 %.0f°C로 뜨거워 속도 제한이 걸리기 전에 터보를 낮췄습니다. %d°C 아래로 식으면 되돌립니다.",
                                            temp, self.guardOffTemp))
                } else {
                    Notifier.post(id: "guard", title: tr("기본 모드로 되돌렸습니다"),
                                  body: trf("CPU가 %.0f°C로 식어 원래 성능으로 돌아왔습니다.", temp))
                }
            }
        }
    }

    /// 시스템 설정·제어 센터에서 바꾸면 사용자의 선택으로 본다.
    private func powerChangedOutside(_ mode: PowerMode) {
        guard power != mode else { return }
        power = mode
        if !guardSwitching { guardActive = false }
    }

    func setGuardEnabled(_ on: Bool) {
        guardEnabled = on
        if on {
            Notifier.requestAuthorization()
        } else if guardActive {
            // 끄면 자동으로 켠 저전력 모드도 되돌린다.
            guardActive = false
            setPowerMode(.normal)
        }
    }

    /// 끄는 온도는 켜는 온도보다 5°C 이상 낮게
    func beginCalibration() {
        calibrating = true
        fanTarget = nil
    }

    /// 끝나면 원래 팬 제어로 — 구간 제어면 다시 적용, 아니면 시스템 자동
    func endCalibration() {
        calibrating = false
        if fanMode == .zone {
            scheduleApply()
        } else {
            fanQueue.async { Thermal.resetFanAuto() }
        }
    }

    /// 추천 팬 하한을 모든 구간의 하한으로 — 이미 더 높은 구간은 그대로
    func applyFanFloor(_ rpm: Int) {
        // setZoneBounds 는 지금 구간이면 구간 제어로 바꾸므로 원래 모드를 지킨다.
        let mode = fanMode
        defer { fanMode = mode }
        for z in FanZone.allCases {
            let r = zoneRange(z)
            guard r.lowerBound < rpm else { continue }
            setZoneBounds(z, lower: rpm, upper: max(r.upperBound, rpm + 100))
        }
        if mode == .zone { scheduleApply() }
    }

    /// 추천값 적용 — 버튼 또는 자동
    func applyGuardRecommendation() {
        guard let r = throttleLog.recommendation else { return }
        guardOnTemp = r.on
        guardOffTemp = r.off
    }

    private func applyRecommendationIfAuto() {
        guard guardAutoRecommend, let r = throttleLog.recommendation,
              r.on != guardOnTemp || r.off != guardOffTemp else { return }
        applyGuardRecommendation()
    }

    func setGuardTemps(on: Int? = nil, off: Int? = nil) {
        if let on { guardOnTemp = on; guardOffTemp = min(guardOffTemp, on - 5) }
        if let off { guardOffTemp = min(off, guardOnTemp - 5) }
    }

    private func clamp(_ v: Int, to r: ClosedRange<Int>) -> Int {
        min(max(v, r.lowerBound), r.upperBound)
    }

    // MARK: update

    var isInstallingUpdate: Bool { installStatus == .downloading || installStatus == .installing }

    /// 메뉴바·사이드바 업데이트 버튼 — 진행 상태에 따라 문구가 바뀐다.
    var updateActionLabel: (title: String, icon: String) {
        switch installStatus {
        case .downloading: return (tr("내려받는 중…"), "arrow.down.circle")
        case .installing:  return (tr("설치 중…"), "arrow.triangle.2.circlepath")
        case .failed:      return (tr("업데이트 실패 — 다시 시도"), "exclamationmark.triangle")
        case .idle:        return (trf("v%@로 업데이트", latestRelease?.version ?? ""), "arrow.down.circle.fill")
        }
    }

    /// 새 버전을 받아 바꿔 끼우고 다시 띄운다. 개발 빌드면 다운로드 페이지를 연다.
    func installUpdate() {
        guard let r = latestRelease else { return }
        guard UpdateInstaller.canReplaceCurrent, r.dmgURL != nil else {
            NSWorkspace.shared.open(r.tagURL)
            return
        }
        guard installStatus != .downloading, installStatus != .installing else { return }
        installStatus = .downloading
        Task {
            do {
                let staged = try await UpdateInstaller.prepare(r)
                installStatus = .installing
                UpdateInstaller.replaceAndRelaunch(with: staged)
            } catch let f as UpdateInstaller.Failure {
                installStatus = .failed(f.message)
            } catch {
                installStatus = .failed(tr("업데이트하지 못했습니다"))
            }
        }
    }

    func checkUpdate() async {
        updateStatus = .checking
        // 너무 빨리 끝나면 눌렀는지 모르므로 잠깐은 "확인 중"을 보여준다.
        async let minDelay: Void = { try? await Task.sleep(nanoseconds: 600_000_000) }()
        let r = await ReleaseChecker.fetchLatest()
        _ = await minDelay
        guard let r else {
            updateStatus = .failed
            return
        }
        if ReleaseChecker.isNewer(r.version, than: ReleaseChecker.currentVersion()) {
            latestRelease = r
            updateStatus = .idle
        } else {
            latestRelease = nil
            updateStatus = .upToDate(Date())
        }
    }
}
