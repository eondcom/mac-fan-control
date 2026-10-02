import AppKit
import SwiftUI

/// 화면 배율 — 대시보드·메뉴바 패널의 글자와 칸 크기를 함께 키운다.
enum UIZoom {
    static let key = "ui_zoom"
    static let steps: [CGFloat] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]

    static var current: CGFloat {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? CGFloat(v) : 1
    }

    static var canZoomIn: Bool { current < steps.last! - 0.001 }
    static var canZoomOut: Bool { current > steps.first! + 0.001 }

    static func set(_ v: CGFloat) { UserDefaults.standard.set(Double(v), forKey: key) }
    static func zoomIn()  { if let n = steps.first(where: { $0 > current + 0.001 }) { set(n) } }
    static func zoomOut() { if let n = steps.last(where: { $0 < current - 0.001 }) { set(n) } }
    static func reset()   { set(1) }

    private static var monitor: Any?

    /// 메뉴바 앱이라 메뉴 단축키가 없으므로 키 입력을 직접 받는다.
    /// 자판이 한글이어도 같은 키로 동작하도록 키 코드로 본다.
    static func installShortcuts() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting([.shift, .numericPad, .function, .capsLock])
            guard mods == .command else { return e }
            switch e.keyCode {
            case 24, 69: zoomIn()   // = · 키패드 +
            case 27, 78: zoomOut()  // - · 키패드 -
            case 29, 82: reset()    // 0 · 키패드 0
            case 15: NotificationCenter.default.post(name: .refreshEverything, object: nil) // R
            default: return e
            }
            return nil
        }
    }
}

extension Notification.Name {
    /// ⌘R · 사이드바 버튼 — 온도·배터리·화면·성능을 한 번에 다시 읽는다.
    static let refreshEverything = Notification.Name("refreshEverything")
}

/// 배율이 바뀌면 안쪽 화면을 다시 그린다.
struct ZoomReader<Content: View>: View {
    @AppStorage(UIZoom.key) private var zoom: Double = 1
    @ViewBuilder var content: (Double) -> Content

    var body: some View { content(zoom) }
}
