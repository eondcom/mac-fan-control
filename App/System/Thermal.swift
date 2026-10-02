import Foundation

struct ThermalReading: Equatable {
    var cpuTemp: Double?
    var gpuTemp: Double?
    var batteryTemp: Double?
    var fanRPM: Int?
    var fanMin: Int?
    var fanMax: Int?
    var fanManual: Bool

    /// 온도 0.5°C · 팬 50rpm 단위 — 잔떨림마다 화면 전체를 다시 그리지 않도록
    var smoothed: ThermalReading {
        func half(_ v: Double?) -> Double? { v.map { ($0 * 2).rounded() / 2 } }
        func step(_ v: Int?) -> Int? { v.map { Int((Double($0) / 50).rounded()) * 50 } }
        var r = self
        r.cpuTemp = half(cpuTemp)
        r.gpuTemp = half(gpuTemp)
        r.batteryTemp = half(batteryTemp)
        r.fanRPM = step(fanRPM)
        return r
    }
}

enum Thermal {

    static func read() -> ThermalReading {
        var r = ThermalReading(fanManual: false)

        // CPU 온도 — 후보 순회
        for key in SMCKeys.cpuTempCandidates {
            if let v = SMC.shared.read(key)?.asDouble, v > 0, v < 120 {
                r.cpuTemp = v
                break
            }
        }
        if let v = SMC.shared.read(SMCKeys.gpuTemp)?.asDouble, v > 0, v < 120 {
            r.gpuTemp = v
        }
        if let v = SMC.shared.read(SMCKeys.batteryTemp)?.asDouble, v > 0, v < 80 {
            r.batteryTemp = v
        }

        if let v = SMC.shared.read(SMCKeys.fan0Current)?.asDouble, v > 0 {
            r.fanRPM = Int(v)
        }
        if let v = SMC.shared.read(SMCKeys.fan0Min)?.asDouble, v > 0 {
            r.fanMin = Int(v)
        }
        if let v = SMC.shared.read(SMCKeys.fan0Max)?.asDouble, v > 0 {
            r.fanMax = Int(v)
        }
        if let mode = SMC.shared.read(SMCKeys.fan0Mode)?.asUInt8, mode != 0 {
            r.fanManual = true
        }
        return r
    }

    /// 팬 0/1 모두 수동 + 목표 RPM 설정. root 헬퍼가 없으면 직접 시도한다(root로 실행 중일 때만 성공).
    @discardableResult
    static func setFanSpeed(rpm: Int) -> Bool {
        if FanHelper.isReady { return FanHelper.setFanSpeed(rpm: rpm) }
        var any = false
        for (modeKey, tgKey) in [(SMCKeys.fan0Mode, SMCKeys.fan0Target),
                                  (SMCKeys.fan1Mode, SMCKeys.fan1Target)] {
            if SMC.shared.writeUInt8(modeKey, value: 1),
               SMC.shared.writeRPM(tgKey, rpm: Double(rpm)) {
                any = true
            }
        }
        return any
    }

    /// 팬 자동 모드 복구.
    @discardableResult
    static func resetFanAuto() -> Bool {
        if FanHelper.isReady { return FanHelper.resetAuto() }
        let a = SMC.shared.writeUInt8(SMCKeys.fan0Mode, value: 0)
        let b = SMC.shared.writeUInt8(SMCKeys.fan1Mode, value: 0)
        return a || b
    }
}
