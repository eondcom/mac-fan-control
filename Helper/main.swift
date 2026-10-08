import Foundation

// MacFanControl SMC 헬퍼 — root(setuid)로 설치되어 팬 키만 쓴다.
//   version        헬퍼 버전 출력
//   auto           모든 팬을 시스템 자동으로
//   set <rpm>      모든 팬을 수동 + 목표 rpm (각 팬의 최소~최대로 자름)
//   lowpower <0|1> macOS 저전력 모드 끄기·켜기 (pmset lowpowermode)
//   daemon <enable|disable> <label>  /Library/LaunchDaemons 항목 켜기·끄기 (Apple 항목 제외)
// 다른 SMC 키·pmset 설정·launchd 항목은 쓸 수 없다.

let helperVersion = "4"

func fail(_ msg: String, _ code: Int32 = 1) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(code)
}

let args = CommandLine.arguments.dropFirst()
guard let cmd = args.first else { fail("usage: version | auto | set <rpm>", 64) }

if cmd == "version" {
    print(helperVersion)
    exit(0)
}

/// root로 명령 하나 실행하고 종료 코드를 돌려준다.
func runAsRoot(_ path: String, _ arguments: [String]) -> Int32 {
    guard setuid(0) == 0 else { fail("setuid failed", 2) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = arguments
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

// 시스템 백그라운드 항목 — /Library/LaunchDaemons 에 실제로 있는 항목만, Apple 항목은 거부
if cmd == "daemon" {
    let a = Array(args)
    guard a.count == 3, a[1] == "enable" || a[1] == "disable" else { fail("usage: daemon <enable|disable> <label>", 64) }
    let label = a[2]
    guard label.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
          !label.hasPrefix("com.apple.") else { fail("invalid label", 64) }
    let dir = URL(fileURLWithPath: "/Library/LaunchDaemons")
    let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
    guard let plist = files.first(where: { url in
        guard url.pathExtension == "plist", let data = try? Data(contentsOf: url),
              let d = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return d["Label"] as? String == label
    }) else { fail("no such daemon", 65) }
    if a[1] == "disable" {
        guard runAsRoot("/bin/launchctl", ["disable", "system/\(label)"]) == 0 else { exit(3) }
        _ = runAsRoot("/bin/launchctl", ["bootout", "system/\(label)"])
    } else {
        guard runAsRoot("/bin/launchctl", ["enable", "system/\(label)"]) == 0 else { exit(3) }
        _ = runAsRoot("/bin/launchctl", ["bootstrap", "system", plist.path])
    }
    exit(0)
}

// 저전력 모드 — 암호 없이 자동 전환하려고 헬퍼가 pmset을 대신 부른다. 값은 0·1만 받는다.
if cmd == "lowpower" {
    guard args.count == 2, let v = args.last, v == "0" || v == "1" else { fail("usage: lowpower <0|1>", 64) }
    // setuid 헬퍼는 실제 사용자 ID가 그대로라 pmset이 거부한다 — root로 맞춘다.
    guard setuid(0) == 0 else { fail("setuid failed", 2) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    p.arguments = ["-a", "lowpowermode", v]
    do { try p.run() } catch { fail("pmset failed", 3) }
    p.waitUntilExit()
    exit(p.terminationStatus == 0 ? 0 : 3)
}

guard SMC.shared.open() else { fail("SMC open failed", 2) }

let count = min(max(Int(SMC.shared.read(SMCKeys.fanCount)?.asDouble ?? 1), 1), 4)

switch (cmd, args.count) {
case ("auto", 1):
    var ok = false
    for i in 0..<count where SMC.shared.writeUInt8("F\(i)Md", value: 0) { ok = true }
    // Apple Silicon: 강제 모드 해제 (키가 없으면 무시)
    _ = SMC.shared.writeUInt8("Ftst", value: 0)
    exit(ok ? 0 : 3)

case ("set", 2):
    guard let raw = Int(args[args.startIndex + 1]), (500...10_000).contains(raw) else {
        fail("rpm must be an integer in 500...10000", 64)
    }
    // Apple Silicon: Ftst=1 로 잠금을 푼 뒤 SMC 가 받아들일 때까지 수동 모드 쓰기가 몇 초 실패한다.
    let unlocking = SMC.shared.writeUInt8("Ftst", value: 1)
    var ok = false
    for i in 0..<count {
        let lo = Int(SMC.shared.read("F\(i)Mn")?.asDouble ?? 0)
        let hi = Int(SMC.shared.read("F\(i)Mx")?.asDouble ?? 0)
        guard hi > lo else { continue }
        let rpm = min(max(raw, lo), hi)
        var manual = SMC.shared.writeUInt8("F\(i)Md", value: 1)
        var tries = 0
        while !manual, unlocking, tries < 30 {
            usleep(100_000)
            tries += 1
            manual = SMC.shared.writeUInt8("F\(i)Md", value: 1)
        }
        if manual, SMC.shared.writeRPM("F\(i)Tg", rpm: Double(rpm)) {
            ok = true
        }
    }
    exit(ok ? 0 : 3)

default:
    fail("usage: version | auto | set <rpm> | lowpower <0|1> | daemon <enable|disable> <label>", 64)
}
