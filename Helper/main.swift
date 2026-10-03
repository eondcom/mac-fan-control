import Foundation

// MacFanControl SMC 헬퍼 — root(setuid)로 설치되어 팬 키만 쓴다.
//   version        헬퍼 버전 출력
//   auto           모든 팬을 시스템 자동으로
//   set <rpm>      모든 팬을 수동 + 목표 rpm (각 팬의 최소~최대로 자름)
//   lowpower <0|1> macOS 저전력 모드 끄기·켜기 (pmset lowpowermode)
// 다른 SMC 키·pmset 설정은 쓸 수 없다.

let helperVersion = "2"

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
    _ = SMC.shared.writeUInt8("Ftst", value: 1)
    var ok = false
    for i in 0..<count {
        let lo = Int(SMC.shared.read("F\(i)Mn")?.asDouble ?? 0)
        let hi = Int(SMC.shared.read("F\(i)Mx")?.asDouble ?? 0)
        guard hi > lo else { continue }
        let rpm = min(max(raw, lo), hi)
        if SMC.shared.writeUInt8("F\(i)Md", value: 1),
           SMC.shared.writeRPM("F\(i)Tg", rpm: Double(rpm)) {
            ok = true
        }
    }
    exit(ok ? 0 : 3)

default:
    fail("usage: version | auto | set <rpm> | lowpower <0|1>", 64)
}
