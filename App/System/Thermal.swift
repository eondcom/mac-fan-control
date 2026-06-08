import Foundation

struct ThermalReading {
    var cpuTemp: Double?
    var gpuTemp: Double?
    var batteryTemp: Double?
    var fanRPM: Int?
    var fanMin: Int?
    var fanMax: Int?
    var fanManual: Bool
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

    /// 팬 0/1 모두 수동 + 목표 RPM 설정.
    @discardableResult
    static func setFanSpeed(rpm: Int) -> Bool {
        var any = false
        for (modeKey, tgKey) in [(SMCKeys.fan0Mode, SMCKeys.fan0Target),
                                  (SMCKeys.fan1Mode, SMCKeys.fan1Target)] {
            if SMC.shared.writeUInt8(modeKey, value: 1) {
                // 우선 FLT 시도, 실패 시 FPE2
                if SMC.shared.writeFloat(tgKey, value: Float(rpm)) ||
                   SMC.shared.writeFPE2(tgKey, rpm: Double(rpm)) {
                    any = true
                }
            }
        }
        return any
    }

    /// 팬 자동 모드 복구.
    @discardableResult
    static func resetFanAuto() -> Bool {
        let a = SMC.shared.writeUInt8(SMCKeys.fan0Mode, value: 0)
        let b = SMC.shared.writeUInt8(SMCKeys.fan1Mode, value: 0)
        return a || b
    }
}
