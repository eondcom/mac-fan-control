import Foundation
import IOKit

// MARK: - 4-char code helpers

extension String {
    var fourCharCode: UInt32 {
        var result: UInt32 = 0
        let bytes = Array(utf8.prefix(4))
        let padded = bytes + Array(repeating: UInt8(0x20), count: max(0, 4 - bytes.count))
        for b in padded.prefix(4) {
            result = (result << 8) | UInt32(b)
        }
        return result
    }
}

extension UInt32 {
    var asFourCharString: String {
        let b0 = UInt8((self >> 24) & 0xFF)
        let b1 = UInt8((self >> 16) & 0xFF)
        let b2 = UInt8((self >> 8)  & 0xFF)
        let b3 = UInt8(self & 0xFF)
        return String(bytes: [b0, b1, b2, b3], encoding: .ascii) ?? ""
    }
}

// MARK: - SMC driver structs (must match AppleSMC kext layout)

private struct SMCKeyData_vers_t {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData_t {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo_t {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData_t {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers_t()
    var pLimitData = SMCKeyData_pLimitData_t()
    var keyInfo = SMCKeyData_keyInfo_t()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0,
        0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0)
}

private let kSMCReadKey: UInt8  = 5
private let kSMCWriteKey: UInt8 = 6
private let kSMCGetKeyInfo: UInt8 = 9

enum SMCError: Error {
    case driverNotFound
    case openFailed(kern_return_t)
    case callFailed(kern_return_t)
    case keyError(UInt8)
}

// MARK: - SMC value

struct SMCValue {
    let key: String
    let dataType: String
    let bytes: [UInt8]

    /// FLT (32-bit IEEE 754 little-endian)
    var asFloat: Float? {
        guard dataType.trimmingCharacters(in: .whitespaces) == "flt", bytes.count >= 4 else { return nil }
        return bytes.prefix(4).withUnsafeBufferPointer {
            $0.baseAddress!.withMemoryRebound(to: Float.self, capacity: 1) { $0.pointee }
        }
    }

    /// SP78 (Q8.8 signed fixed-point)
    var asSP78: Double? {
        guard dataType == "sp78", bytes.count >= 2 else { return nil }
        let raw = (Int16(bytes[0]) << 8) | Int16(bytes[1])
        return Double(raw) / 256.0
    }

    /// FPE2 (Q14.2 unsigned fixed-point — fan RPM on some Macs)
    var asFPE2: Double? {
        guard dataType == "fpe2", bytes.count >= 2 else { return nil }
        let raw = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        return Double(raw) / 4.0
    }

    var asUInt8: UInt8? { bytes.first }

    var asUInt16: UInt16? {
        guard bytes.count >= 2 else { return nil }
        return (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
    }

    /// Numeric value, trying type-appropriate decoding.
    var asDouble: Double? {
        switch dataType.trimmingCharacters(in: .whitespaces) {
        case "flt":   return asFloat.map { Double($0) }
        case "sp78":  return asSP78
        case "fpe2":  return asFPE2
        case "ui8":   return asUInt8.map { Double($0) }
        case "ui16":  return asUInt16.map { Double($0) }
        default:      return nil
        }
    }
}

// MARK: - SMC

final class SMC {
    static let shared = SMC()

    private var connection: io_connect_t = 0
    private var opened = false

    private init() {}

    deinit { close() }

    @discardableResult
    func open() -> Bool {
        if opened { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        opened = (result == kIOReturnSuccess)
        return opened
    }

    func close() {
        if opened {
            IOServiceClose(connection)
            opened = false
        }
    }

    // MARK: read

    func read(_ keyString: String) -> SMCValue? {
        guard open() else { return nil }
        let keyCode = keyString.fourCharCode

        var info = SMCKeyData_t()
        info.key = keyCode
        info.data8 = kSMCGetKeyInfo
        guard let infoOut = call(input: info) else { return nil }
        if infoOut.result != 0 { return nil }

        let size = infoOut.keyInfo.dataSize
        var read = SMCKeyData_t()
        read.key = keyCode
        read.keyInfo.dataSize = size
        read.data8 = kSMCReadKey
        guard let readOut = call(input: read) else { return nil }
        if readOut.result != 0 { return nil }

        let typeStr = infoOut.keyInfo.dataType.asFourCharString
        let bytes = bytesFromTuple(readOut.bytes, length: Int(min(size, 32)))
        return SMCValue(key: keyString, dataType: typeStr, bytes: bytes)
    }

    // MARK: write

    @discardableResult
    func writeUInt8(_ keyString: String, value: UInt8) -> Bool {
        return write(keyString, dataType: "ui8 ", bytes: [value])
    }

    @discardableResult
    func writeFloat(_ keyString: String, value: Float) -> Bool {
        var v = value
        let bytes = withUnsafeBytes(of: &v) { Array($0) }
        return write(keyString, dataType: "flt ", bytes: bytes)
    }

    @discardableResult
    func writeFPE2(_ keyString: String, rpm: Double) -> Bool {
        // rpm × 4, big-endian 16-bit
        let raw = UInt16(max(0, min(rpm * 4, Double(UInt16.max))))
        let hi = UInt8((raw >> 8) & 0xFF)
        let lo = UInt8(raw & 0xFF)
        return write(keyString, dataType: "fpe2", bytes: [hi, lo])
    }

    private func write(_ keyString: String, dataType: String, bytes: [UInt8]) -> Bool {
        guard open() else { return false }
        var input = SMCKeyData_t()
        input.key = keyString.fourCharCode
        input.data8 = kSMCWriteKey
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.keyInfo.dataType = dataType.fourCharCode

        // copy into byte tuple
        var b = input.bytes
        withUnsafeMutableBytes(of: &b) { dst in
            for (i, v) in bytes.prefix(32).enumerated() {
                dst[i] = v
            }
        }
        input.bytes = b

        guard let out = call(input: input) else { return false }
        return out.result == 0
    }

    // MARK: low-level call

    private func call(input: SMCKeyData_t) -> SMCKeyData_t? {
        var inStruct = input
        var outStruct = SMCKeyData_t()
        let inSize = MemoryLayout<SMCKeyData_t>.stride
        var outSize = MemoryLayout<SMCKeyData_t>.stride

        let result = IOConnectCallStructMethod(connection,
                                               2, // kSMCHandleYPCEvent
                                               &inStruct, inSize,
                                               &outStruct, &outSize)
        guard result == kIOReturnSuccess else { return nil }
        return outStruct
    }

    private func bytesFromTuple(
        _ tuple: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                  UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8),
        length: Int
    ) -> [UInt8] {
        var t = tuple
        return withUnsafeBytes(of: &t) { ptr in
            Array(ptr.prefix(length))
        }
    }
}
