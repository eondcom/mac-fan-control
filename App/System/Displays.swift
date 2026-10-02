import Foundation
import CoreGraphics
import AppKit

/// 화면 하나 — 연결된 모니터 정보
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    /// 내장 화면을 꺼둔 상태 (연결은 돼 있지만 그리지 않음)
    let isDisabled: Bool
    let current: DisplayModeInfo?
    let modes: [DisplayModeInfo]
    /// 패널 원래 픽셀 폭 — 배율과 부하를 따지는 기준
    let nativeWidth: Int
}

/// 해상도 하나 — "보이는 크기"와 실제로 그리는 픽셀
struct DisplayModeInfo: Identifiable, Equatable {
    /// 보이는 크기마다 하나만 두므로 크기를 id로 쓴다 (ioDisplayModeID는 HiDPI·일반이 겹친다).
    var id: String { "\(width)x\(height)" }
    let modeID: Int32
    /// 보이는 크기 (UI 기준)
    let width: Int
    let height: Int
    /// 실제로 그리는 픽셀
    let pixelWidth: Int
    let pixelHeight: Int
    let refresh: Double

    var label: String { "\(width) × \(height)" }

    /// 원본 대비 글자 크기 — 3840 패널에서 2560이면 150%
    func scalePercent(native: Int) -> Int {
        Int((Double(native) / Double(max(width, 1)) * 100).rounded())
    }

    func load(native: Int) -> DisplayLoad {
        if pixelWidth > native { return .heavy }
        if pixelWidth < native { return .blurry }
        return .light
    }
}

/// 해상도 설정이 그래픽에 주는 부담
enum DisplayLoad {
    /// 패널 픽셀 그대로 (1배·2배) — 가볍고 선명
    case light
    /// 더 크게 그린 뒤 줄여서 보냄 — Intel GPU에 무거움
    case heavy
    /// 작게 그려서 모니터가 키움 — 가볍지만 흐림
    case blurry
}

enum DisplayService {

    // MARK: 목록

    static func list() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }

        let mainID = CGMainDisplayID()
        var result: [DisplayInfo] = []
        for id in ids.prefix(Int(count)) {
            // 미러링 중인 보조 화면은 따로 보여주지 않는다.
            if CGDisplayIsInMirrorSet(id) != 0, CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay { continue }
            let modes = availableModes(id)
            let native = modes.filter { $0.pixelWidth == $0.width }.map(\.pixelWidth).max()
                ?? Int(CGDisplayPixelsWide(id))
            result.append(DisplayInfo(
                id: id,
                name: name(of: id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: id == mainID,
                isDisabled: CGDisplayIsActive(id) == 0,
                current: CGDisplayCopyDisplayMode(id).map(info),
                modes: modes,
                nativeWidth: native))
        }
        // 주 화면 → 외장 → 내장 순
        return result.sorted {
            if $0.isMain != $1.isMain { return $0.isMain }
            return !$0.isBuiltin && $1.isBuiltin
        }
    }

    private static func name(of id: CGDirectDisplayID) -> String {
        if let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }) {
            return screen.localizedName
        }
        return CGDisplayIsBuiltin(id) != 0 ? tr("내장 디스플레이") : tr("외장 모니터")
    }

    /// 데스크톱에 쓸 수 있는 해상도 — 보이는 크기마다 하나, 지금 주사율 우선
    private static func availableModes(_ id: CGDirectDisplayID) -> [DisplayModeInfo] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { return [] }
        let currentRefresh = CGDisplayCopyDisplayMode(id)?.refreshRate ?? 0

        var best: [String: CGDisplayMode] = [:]
        for m in all where m.isUsableForDesktopGUI() {
            let key = "\(m.width)x\(m.height)"
            guard let prev = best[key] else { best[key] = m; continue }
            // 같은 크기면 HiDPI(픽셀 많은 쪽) → 지금 주사율에 가까운 쪽
            if m.pixelWidth != prev.pixelWidth {
                if m.pixelWidth > prev.pixelWidth { best[key] = m }
            } else if abs(m.refreshRate - currentRefresh) < abs(prev.refreshRate - currentRefresh) {
                best[key] = m
            }
        }
        return best.values.map(info).sorted { $0.width > $1.width }
    }

    private static func info(_ m: CGDisplayMode) -> DisplayModeInfo {
        DisplayModeInfo(modeID: m.ioDisplayModeID, width: m.width, height: m.height,
                        pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight, refresh: m.refreshRate)
    }

    // MARK: 해상도 바꾸기

    /// 시스템 설정의 디스플레이 해상도 변경과 같다 (재부팅 후에도 유지).
    @discardableResult
    static func setMode(_ mode: DisplayModeInfo, on id: CGDirectDisplayID) -> Bool {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode],
              let target = all.first(where: {
                  $0.ioDisplayModeID == mode.modeID && $0.width == mode.width && $0.height == mode.height
                      && $0.pixelWidth == mode.pixelWidth && $0.refreshRate == mode.refresh
              }) else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        guard CGConfigureDisplayWithDisplayMode(config, id, target, nil) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .permanently) == .success
    }

    // MARK: 화면 켜기·끄기

    /// 비공개 API — 화면을 연결된 채로 끈다. BetterDisplay의 "연결 해제"와 같은 방식.
    private typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

    private static let configureEnabled: ConfigureEnabledFn? = {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        ]
        for path in paths {
            guard let handle = dlopen(path, RTLD_LAZY),
                  let sym = dlsym(handle, "CGSConfigureDisplayEnabled") else { continue }
            return unsafeBitCast(sym, to: ConfigureEnabledFn.self)
        }
        return nil
    }()

    static var canToggle: Bool { configureEnabled != nil }

    /// 로그아웃·재부팅하면 다시 켜지도록 이번 세션에만 적용한다.
    @discardableResult
    static func setEnabled(_ enabled: Bool, _ id: CGDirectDisplayID) -> Bool {
        guard let fn = configureEnabled else { return false }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        guard fn(config, id, enabled) == .success else {
            CGCancelDisplayConfiguration(config)
            return false
        }
        return CGCompleteDisplayConfiguration(config, .forSession) == .success
    }

    // MARK: WindowServer 부하

    /// 화면을 그리는 WindowServer의 CPU 사용률 (%)
    static func windowServerCPU() -> Double? {
        let out = Shell.run("/bin/ps", ["-Ac", "-o", "pcpu=,comm="])
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2, parts[1].trimmingCharacters(in: .whitespaces) == "WindowServer" {
                return Double(parts[0])
            }
        }
        return nil
    }
}

// MARK: - 화면 상태

@MainActor
final class DisplayState: ObservableObject {

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var windowServerCPU: Double?
    @Published private(set) var lastError: String?

    /// 외장 모니터가 연결되면 내장 화면을 자동으로 끈다.
    @Published var autoBuiltinOff: Bool = UserDefaults.standard.bool(forKey: "display_auto_builtin_off") {
        didSet {
            UserDefaults.standard.set(autoBuiltinOff, forKey: "display_auto_builtin_off")
            if autoBuiltinOff { applyAutoOff() }
        }
    }

    private var pendingRefresh: DispatchWorkItem?
    private var loadTimer: Timer?
    private var externalCount = 0

    init() {
        refresh()
        externalCount = activeExternalCount
        applyAutoOff()

        let me = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, info in
            guard let info, !flags.contains(.beginConfigurationFlag) else { return }
            let state = Unmanaged<DisplayState>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in state.scheduleRefresh() }
        }, me)

        // 앱이 꺼진 뒤 내장 화면이 꺼진 채 남지 않도록 다시 켠다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in
            for d in DisplayService.list() where d.isBuiltin && d.isDisabled {
                DisplayService.setEnabled(true, d.id)
            }
        }
    }

    var builtin: DisplayInfo? { displays.first(where: \.isBuiltin) }

    private var activeExternalCount: Int {
        displays.filter { !$0.isBuiltin && !$0.isDisabled }.count
    }

    /// 화면별 색상 프로필 — 지금 쓰는 것과 후보
    @Published private(set) var profiles: [CGDirectDisplayID: (current: ColorProfileInfo?, candidates: [ProfileCandidate])] = [:]

    func refresh() {
        displays = DisplayService.list()
        var map: [CGDirectDisplayID: (current: ColorProfileInfo?, candidates: [ProfileCandidate])] = [:]
        for d in displays where !d.isDisabled {
            map[d.id] = (ColorProfileService.current(for: d.id), ColorProfileService.candidates(for: d.id))
        }
        profiles = map
    }

    func applyProfile(_ p: ColorProfileInfo, to display: DisplayInfo) {
        lastError = ColorProfileService.apply(p.url, to: display.id) ? nil : tr("색상 프로필을 바꾸지 못했습니다")
        refreshAfterChange()
    }

    /// 화면 구성이 바뀌면 콜백이 여러 번 오므로 모아서 한 번만 처리한다.
    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.afterReconfigure() }
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func afterReconfigure() {
        refresh()
        let count = activeExternalCount

        // 안전장치: 켜진 화면이 하나도 없으면 내장 화면을 되살린다.
        if count == 0, let b = builtin, b.isDisabled {
            DisplayService.setEnabled(true, b.id)
            refresh()
        } else if count > externalCount {
            // 외장 모니터가 새로 연결됐을 때만 자동으로 끈다 — 직접 켠 내장 화면은 그대로 둔다.
            applyAutoOff()
        }
        externalCount = activeExternalCount
    }

    private func applyAutoOff() {
        guard autoBuiltinOff, activeExternalCount > 0, let b = builtin, !b.isDisabled else { return }
        setBuiltin(enabled: false)
    }

    func setBuiltin(enabled: Bool) {
        guard let b = builtin else { return }
        if !enabled && activeExternalCount == 0 {
            lastError = tr("외장 모니터가 없어 내장 화면을 끌 수 없습니다")
            return
        }
        lastError = DisplayService.setEnabled(enabled, b.id) ? nil : tr("화면 설정을 바꾸지 못했습니다")
        refreshAfterChange()
    }

    func setMode(_ mode: DisplayModeInfo, on display: DisplayInfo) {
        lastError = DisplayService.setMode(mode, on: display.id) ? nil : tr("해상도를 바꾸지 못했습니다")
        refreshAfterChange()
    }

    /// 바꾼 직후에는 이전 상태가 읽히므로 화면 전환이 끝날 때까지 몇 번 더 읽는다.
    private func refreshAfterChange() {
        refresh()
        for delay in [0.5, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    // MARK: WindowServer 부하 — 탭을 보고 있을 때만 잰다

    func startLoadMonitor() {
        stopLoadMonitor()
        sampleLoad()
        loadTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleLoad() }
        }
    }

    func stopLoadMonitor() {
        loadTimer?.invalidate()
        loadTimer = nil
    }

    private func sampleLoad() {
        Task.detached { [weak self] in
            let v = DisplayService.windowServerCPU()
            await MainActor.run { self?.windowServerCPU = v }
        }
    }
}
