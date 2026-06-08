import Foundation
import Combine
import SwiftUI

@MainActor
final class AppState: ObservableObject {

    // 실시간 데이터
    @Published var thermal = ThermalReading(fanManual: false)
    @Published var power: PowerMode = .normal
    @Published var battery = BatteryInfo(isCharging: false, isCharged: false)

    // 사용자 설정 (UserDefaults)
    @AppStorage("mb_show_temp") var mbShowTemp: Bool = true
    @AppStorage("mb_show_fan")  var mbShowFan:  Bool = true
    @AppStorage("start_hidden") var startHidden: Bool = false

    // 업데이트
    @Published var latestRelease: ReleaseInfo?

    private var timers: [Timer] = []

    init() {
        refreshAll()
    }

    func startTimers() {
        stopTimers()
        // 온도/팬: 5초
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshThermal() }
        })
        // 배터리 빠른 상태: 1초
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBatteryQuick() }
        })
        // 배터리 상세: 60초
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshBatteryFull() }
        })
        // 업데이트 체크: 시작 3초 후
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
        power = PowerModeService.current()
        refreshBatteryFull()
    }

    func refreshThermal() {
        thermal = Thermal.read()
    }

    func refreshBatteryQuick() {
        let q = BatteryService.quickStatus()
        battery.isCharging    = q.isCharging
        battery.isCharged     = q.isCharged
        battery.timeRemaining = q.timeRemaining
    }

    func refreshBatteryFull() {
        Task.detached {
            let info = BatteryService.full()
            await MainActor.run { [weak self] in
                self?.battery = info
            }
        }
    }

    // MARK: actions

    func setPowerMode(_ mode: PowerMode) {
        Task.detached {
            let ok = PowerModeService.set(mode)
            if ok {
                await MainActor.run { [weak self] in
                    self?.power = mode
                }
            }
        }
    }

    func applyFan(rpm: Int) {
        Task.detached {
            _ = Thermal.setFanSpeed(rpm: rpm)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { [weak self] in
                self?.refreshThermal()
            }
        }
    }

    func resetFanAuto() {
        Task.detached {
            _ = Thermal.resetFanAuto()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { [weak self] in
                self?.refreshThermal()
            }
        }
    }

    // MARK: update

    func checkUpdate() async {
        guard let r = await ReleaseChecker.fetchLatest() else { return }
        let local = ReleaseChecker.currentVersion()
        if ReleaseChecker.isNewer(r.version, than: local) {
            self.latestRelease = r
        }
    }
}
