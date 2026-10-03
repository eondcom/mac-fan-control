import Foundation
import CoreGraphics
import AppKit
import Carbon.HIToolbox
import IOKit
import os

/// `log stream --predicate 'subsystem == "com.eond.macfancontrol"'`로 본다.
private let log = Logger(subsystem: "com.eond.macfancontrol", category: "display")

/// 화면 하나 — 연결된 모니터 정보
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltin: Bool
    let isMain: Bool
    /// 내장 화면을 꺼둔 상태 (연결은 돼 있지만 그리지 않음)
    let isDisabled: Bool
    /// 절전으로 잠든 상태 — 꺼둔 것과 다르다
    let isAsleep: Bool
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

/// 화면이 연결된 방식
enum DisplayLink: Equatable {
    case builtin
    /// DisplayPort 신호 — USB-C·썬더볼트·DP 케이블
    case displayPort
    /// HDMI(또는 DVI) — 맥이 TV처럼 다뤄 색이 연해질 수 있다
    case hdmi
    /// DisplayPort 단자에서 HDMI·DVI로 바꾸는 어댑터를 거침
    case dpToHDMI

    var label: String {
        switch self {
        case .builtin:     return tr("내장")
        case .displayPort: return tr("USB-C · DisplayPort")
        case .hdmi:        return tr("HDMI")
        case .dpToHDMI:    return tr("USB-C → HDMI 변환")
        }
    }

    /// 색 범위가 줄어들 수 있는 연결
    var mayLimitColor: Bool { self == .hdmi || self == .dpToHDMI }
}

enum DisplayService {

    // MARK: 연결 방식

    /// system_profiler가 1초쯤 걸리므로 백그라운드에서 부른다.
    static func links() -> [CGDirectDisplayID: DisplayLink] {
        let out = Shell.run("/usr/sbin/system_profiler", ["SPDisplaysDataType", "-json"])
        guard let data = out.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let gpus = root["SPDisplaysDataType"] as? [[String: Any]] else { return [:] }
        var map: [CGDirectDisplayID: DisplayLink] = [:]
        for gpu in gpus {
            for d in gpu["spdisplays_ndrvs"] as? [[String: Any]] ?? [] {
                guard let hex = d["_spdisplays_displayID"] as? String,
                      let id = UInt32(hex, radix: 16) else { continue }
                let conn = (d["spdisplays_connection_type"] as? String ?? "").lowercased()
                let adapter = (d["spdisplays_adapter_type"] as? String ?? "").lowercased()
                if conn.contains("internal") {
                    map[id] = .builtin
                } else if adapter.contains("hdmi") || adapter.contains("dvi") {
                    map[id] = .dpToHDMI
                } else if conn.contains("hdmi") || conn.contains("dvi") {
                    map[id] = .hdmi
                } else if adapter.contains("displayport") || adapter.contains("thunderbolt") || conn.contains("displayport") {
                    map[id] = .displayPort
                }
            }
        }
        return map
    }

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
            let native = nativeWidth(id)
                ?? modes.filter { $0.pixelWidth == $0.width }.map(\.pixelWidth).max()
                ?? Int(CGDisplayPixelsWide(id))
            result.append(DisplayInfo(
                id: id,
                name: name(of: id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isMain: id == mainID,
                // CGDisplayIsActive는 잠든 화면도 0을 돌려주므로 절전과 끔을 따로 본다.
                isDisabled: CGDisplayIsActive(id) == 0 && CGDisplayIsAsleep(id) == 0,
                isAsleep: CGDisplayIsAsleep(id) != 0,
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

    /// 패널 원래 픽셀 폭 — 드라이버가 "기본"으로 표시한 모드 기준
    private static func nativeWidth(_ id: CGDirectDisplayID) -> Int? {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let all = CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode] else { return nil }
        let nativeFlag: UInt32 = 0x0200_0000 // kDisplayModeNativeFlag
        return all.filter { $0.ioFlags & nativeFlag != 0 }.map(\.pixelWidth).max()
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

    // MARK: 사용자 입력

    /// 마지막 키보드·마우스 입력 후 지난 시간 (초) — 권한 없이 읽힌다.
    static func idleSeconds() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber else { return nil }
        return value.doubleValue / 1_000_000_000
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
    @Published private(set) var links: [CGDirectDisplayID: DisplayLink] = [:]

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

    /// 화면이 절전 중 — 이때 오는 구성 변경은 무시한다 (외장 모니터가 잠들면서 빠졌다 들어오기 때문).
    private var screensAsleep = false
    private var wakeWatch: Timer?
    private var wakeCheck: DispatchWorkItem?
    private var hotKey: EventHotKeyRef?

    init() {
        refresh()
        refreshLinks()
        externalCount = activeExternalCount
        applyAutoOff()

        let me = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback({ _, flags, info in
            guard let info, !flags.contains(.beginConfigurationFlag) else { return }
            let state = Unmanaged<DisplayState>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in state.scheduleRefresh() }
        }, me)

        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.screensWentToSleep() }
            }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleWakeCheck() }
            }
        }
        registerRescueHotKey()

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

    /// 지금 실제로 그림이 나가고 있는 외장 모니터 수
    private var awakeExternalCount: Int {
        displays.filter { !$0.isBuiltin && !$0.isDisabled && !$0.isAsleep }.count
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

    func refreshLinks() {
        Task.detached { [weak self] in
            let map = DisplayService.links()
            await MainActor.run { self?.links = map }
        }
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
        // 절전 중에 화면 구성을 바꾸면 깨어날 화면이 꼬인다 — 깨어난 뒤 한꺼번에 처리한다.
        if screensAsleep { return }
        refresh()
        refreshLinks()
        let count = activeExternalCount

        // 안전장치: 켜진 화면이 하나도 없으면 내장 화면을 되살린다.
        if count == 0, let b = builtin, b.isDisabled {
            DisplayService.setEnabled(true, b.id)
            builtinOffByUs = false
            refresh()
        } else if count > externalCount {
            // 외장 모니터가 새로 연결됐을 때만 자동으로 끈다 — 직접 켠 내장 화면은 그대로 둔다.
            applyAutoOff()
        }
        externalCount = activeExternalCount
    }

    // MARK: 절전에서 깨어나기

    private func screensWentToSleep() {
        log.notice("절전 진입 — 내장 꺼짐: \(self.builtin?.isDisabled == true), 앱이 끔: \(self.builtinOffByUs)")
        screensAsleep = true
        wakeCheck?.cancel()
        // 내장 화면을 꺼둔 채 잠들었을 때만 입력을 지켜본다.
        guard builtin?.isDisabled == true || builtinOffByUs else { return }
        wakeWatch?.invalidate()
        wakeWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.watchInputWhileAsleep() }
        }
    }

    /// 마우스·키보드를 건드렸는데도 화면이 깨어났다는 알림이 없으면 직접 확인한다.
    private func watchInputWhileAsleep() {
        guard screensAsleep, let idle = DisplayService.idleSeconds(), idle < 1.5 else { return }
        log.notice("절전 중 입력 감지 (idle \(idle, format: .fixed(precision: 1))s)")
        scheduleWakeCheck()
    }

    private func scheduleWakeCheck() {
        log.notice("깨어남 — 1초 뒤 외장 모니터 신호 다시 잡기")
        wakeWatch?.invalidate()
        wakeWatch = nil
        wakeCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.afterWake() }
        }
        wakeCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func afterWake() {
        screensAsleep = false
        refresh()
        refreshLinks()
        for d in displays {
            log.notice("확인: \(d.name, privacy: .public) 내장=\(d.isBuiltin) 꺼짐=\(d.isDisabled) 잠듦=\(d.isAsleep)")
        }
        if let b = builtin, b.isDisabled || builtinOffByUs {
            // 내장 화면을 끈 채 깨어나면 macOS는 외장 모니터가 켜졌다고 보지만 실제로는 검은 화면일 때가 있다.
            // 내장 화면을 켜서 화면 구성을 다시 하면 외장 모니터가 신호를 다시 잡는다 — 잡히면 다시 끈다.
            log.notice("깨어남 — 내장 화면을 잠깐 켜서 외장 모니터 신호를 다시 잡습니다")
            enableBuiltinTimed(b.id)
            builtinOffByUs = false
            refreshAfterChange()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                Task { @MainActor in self?.reapplyOffAfterWake() }
            }
        } else if activeExternalCount > externalCount {
            log.notice("외장 모니터 새로 잡힘 — 자동 끄기 적용")
            applyAutoOff()
        }
        externalCount = activeExternalCount
    }

    /// 깨어난 뒤 외장 모니터가 그림을 내보내고 있으면 내장 화면을 다시 끈다.
    private func reapplyOffAfterWake() {
        refresh()
        guard !screensAsleep, awakeExternalCount > 0, let b = builtin, !b.isDisabled else {
            log.error("외장 모니터가 안 돌아옴 — 내장 화면을 켜 둡니다")
            return
        }
        log.notice("외장 모니터 확인 — 내장 화면을 다시 끕니다")
        setBuiltin(enabled: false)
    }

    /// 화면 구성 변경은 몇 초씩 걸릴 수 있어 걸린 시간을 남긴다.
    private func enableBuiltinTimed(_ id: CGDirectDisplayID) {
        let start = Date()
        let ok = DisplayService.setEnabled(true, id)
        log.notice("내장 화면 켜기 — \(ok ? "성공" : "실패", privacy: .public), \(Date().timeIntervalSince(start), format: .fixed(precision: 1))초")
    }

    private var lastRescue = Date.distantPast

    /// 내장 화면을 이 앱이 껐는지 — 잠든 동안엔 상태를 읽어도 믿기 어려워 따로 기억한다.
    private var builtinOffByUs = false

    // MARK: 비상 단축키 — 화면이 하나도 안 나올 때

    /// ⌃⌥⌘B — 화면이 안 보여도 누르면 내장 화면이 켜진다. 손쉬운 사용 권한이 필요 없다.
    private func registerRescueHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, info in
            guard let info else { return noErr }
            let state = Unmanaged<DisplayState>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in state.rescueBuiltin() }
            return noErr
        }, 1, &spec, me, nil)
        let id = EventHotKeyID(signature: OSType(0x4D46_4342), id: 1) // 'MFCB'
        RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &hotKey)
    }

    func rescueBuiltin() {
        // 여러 번 누르면 화면 구성이 겹쳐 더 늦어진다 — 5초 안의 반복은 무시한다.
        guard Date().timeIntervalSince(lastRescue) > 5 else {
            log.notice("비상 단축키 반복 — 무시")
            return
        }
        lastRescue = Date()
        log.notice("비상 단축키 ⌃⌥⌘B — 내장 화면을 켭니다")
        screensAsleep = false
        wakeWatch?.invalidate()
        wakeWatch = nil
        guard let b = builtin else { return }
        enableBuiltinTimed(b.id)
        builtinOffByUs = false
        refreshAfterChange()
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
        let ok = DisplayService.setEnabled(enabled, b.id)
        log.notice("내장 화면 \(enabled ? "켜기" : "끄기", privacy: .public) — \(ok ? "성공" : "실패", privacy: .public)")
        if ok { builtinOffByUs = !enabled }
        lastError = ok ? nil : tr("화면 설정을 바꾸지 못했습니다")
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
