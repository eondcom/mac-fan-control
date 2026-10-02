import Foundation
import AppKit
import CoreGraphics

/// Sidecar로 연결할 수 있는 아이패드 하나
struct SidecarDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let connected: Bool
    fileprivate let object: NSObject

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.connected == b.connected && a.name == b.name }
}

/// macOS 내장 Sidecar — 비공개 SidecarCore를 런타임에 불러 쓴다.
/// 같은 Apple ID·Handoff·Wi-Fi·블루투스가 켜진 아이패드만 잡힌다. macOS 업데이트로 바뀔 수 있다.
enum SidecarService {

    private static let manager: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_LAZY) != nil,
              let cls = NSClassFromString("SidecarDisplayManager") as? NSObject.Type,
              cls.responds(to: NSSelectorFromString("sharedManager")),
              let m = cls.perform(NSSelectorFromString("sharedManager"))?.takeUnretainedValue() as? NSObject
        else { return nil }
        return m
    }()

    static var isAvailable: Bool { manager != nil }

    static func devices() -> [SidecarDevice] {
        guard let m = manager else { return [] }
        let all = m.value(forKey: "devices") as? [NSObject] ?? []
        let connected = Set((m.value(forKey: "connectedDevices") as? [NSObject] ?? []).map(identifier))
        return all.map {
            SidecarDevice(id: identifier($0), name: ($0.value(forKey: "name") as? String) ?? tr("아이패드"),
                          connected: connected.contains(identifier($0)), object: $0)
        }
    }

    private static func identifier(_ d: NSObject) -> String {
        (d.value(forKey: "identifier") as? NSUUID)?.uuidString
            ?? (d.value(forKey: "identifier") as? String)
            ?? (d.value(forKey: "name") as? String ?? "")
    }

    private typealias Call = @convention(c) (NSObject, Selector, NSObject, @escaping @convention(block) (NSError?) -> Void) -> Void

    /// 연결·해제 — 끝나면 메인 스레드에서 오류(없으면 nil)를 돌려준다.
    static func setConnected(_ on: Bool, _ device: SidecarDevice, done: @escaping (String?) -> Void) {
        let sel = NSSelectorFromString(on ? "connectToDevice:completion:" : "disconnectFromDevice:completion:")
        guard let m = manager, m.responds(to: sel) else { done(tr("Sidecar를 쓸 수 없습니다")); return }
        let fn = unsafeBitCast(m.method(for: sel), to: Call.self)
        fn(m, sel, device.object) { err in
            DispatchQueue.main.async { done(err?.localizedDescription) }
        }
    }
}

/// OpenDisplay — 아이폰·아이패드·안드로이드를 Wi-Fi/USB 확장 모니터로 쓰는 별도 오픈소스 앱 (GPL, 코드는 가져오지 않고 실행만 한다)
enum OpenDisplayApp {
    static let bundleID = "com.peetzweg.opensidecar.mac"
    static let releasesURL = URL(string: "https://github.com/peetzweg/opendisplay/releases/latest")!
    static let androidURL = URL(string: "https://github.com/josepacelli/opendisplay-android")!

    static var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    static var isInstalled: Bool { appURL != nil }
    static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    static func open() {
        guard let url = appURL else { NSWorkspace.shared.open(releasesURL); return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}

extension DisplayService {
    /// 미러링 — master를 주면 그 화면과 같게, nil이면 확장으로 되돌린다. 시스템 설정의 미러링과 같다.
    @discardableResult
    static func setMirror(_ id: CGDirectDisplayID, of master: CGDirectDisplayID?) -> Bool {
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        guard CGConfigureDisplayMirrorOfDisplay(config, id, master ?? kCGNullDirectDisplay) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }
}
