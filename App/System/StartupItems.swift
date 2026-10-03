import Foundation
import AppKit

/// 시작 프로그램 — 로그인 항목과 launchd 항목(LaunchAgents·LaunchDaemons)
///
/// 시스템 설정 → 일반 → 로그인 항목은 경로를 보여주지 않고 삭제도 안 된다. 여기서는 파일 경로·실행 파일·상태를 보여주고,
/// 내 계정 항목은 끄기·켜기·삭제, 모든 사용자·시스템 항목은 끄기·켜기만 한다(시스템 항목은 도우미가 처리).

enum LaunchScope: String, CaseIterable, Identifiable {
    /// ~/Library/LaunchAgents — 내 계정, 로그인하면 실행
    case userAgent
    /// /Library/LaunchAgents — 모든 사용자, 로그인하면 실행
    case globalAgent
    /// /Library/LaunchDaemons — 시스템, 켜자마자 root로 실행
    case daemon

    var id: String { rawValue }

    var directory: URL {
        switch self {
        case .userAgent:   return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        case .globalAgent: return URL(fileURLWithPath: "/Library/LaunchAgents")
        case .daemon:      return URL(fileURLWithPath: "/Library/LaunchDaemons")
        }
    }

    var title: String {
        switch self {
        case .userAgent:   return tr("내 계정 백그라운드 항목")
        case .globalAgent: return tr("모든 사용자 백그라운드 항목")
        case .daemon:      return tr("시스템 백그라운드 항목")
        }
    }

    var caption: String {
        switch self {
        case .userAgent:   return tr("로그인하면 내 권한으로 실행됩니다 · ~/Library/LaunchAgents")
        case .globalAgent: return tr("누가 로그인하든 실행됩니다 · /Library/LaunchAgents")
        case .daemon:      return tr("맥이 켜지면 관리자 권한으로 실행됩니다 · /Library/LaunchDaemons")
        }
    }

    /// 삭제는 내 계정 항목만 — 나머지는 관리자 권한이 필요하고 지우면 앱이 망가질 수 있다.
    var canDelete: Bool { self == .userAgent }

    /// launchctl 도메인
    var domain: String {
        self == .daemon ? "system" : "gui/\(getuid())"
    }
}

struct LaunchItem: Identifiable, Equatable {
    let label: String
    let plist: URL
    let scope: LaunchScope
    /// 실제로 실행하는 파일
    let program: String?
    /// 실행 명령 전체 (스크립트를 셸로 돌리는 항목은 인자에 진짜 내용이 있다)
    let command: String?
    /// Label 이 없는 빈 파일 — launchd 가 무시한다 (Google Keystone 이 지우는 대신 비워 둔다)
    var isEmpty: Bool { label.isEmpty }
    let runAtLoad: Bool
    let keepAlive: Bool
    /// launchctl disable 로 꺼 둔 상태
    var disabled: Bool
    /// 지금 launchd에 올라가 있음
    var loaded: Bool

    var id: String { plist.path }

    /// 실행 파일이 들어 있는 앱 — 이름·아이콘을 보여주려고
    var appURL: URL? {
        guard let p = program, let r = p.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(p[..<r.lowerBound]) + ".app")
    }

    var displayName: String {
        if let a = appURL { return FileManager.default.displayName(atPath: a.path).replacingOccurrences(of: ".app", with: "") }
        return isEmpty ? plist.deletingPathExtension().lastPathComponent : label
    }
}

struct LoginItem: Identifiable, Equatable {
    let name: String
    let path: String?
    var id: String { name + (path ?? "") }
}

enum StartupService {

    // MARK: launchd 항목

    static func launchItems() -> [LaunchItem] {
        let userDisabled = disabledLabels(domain: LaunchScope.userAgent.domain)
        let systemDisabled = disabledLabels(domain: "system")
        let loadedUser = loadedUserLabels()
        // 시스템 항목은 일반 권한으로 launchctl 에서 안 보인다 — 실행 중인 프로세스 경로로 판단
        let runningPaths = Set(Shell.run("/bin/ps", ["-axo", "comm="]).split(separator: "\n").map(String.init))

        var result: [LaunchItem] = []
        for scope in LaunchScope.allCases {
            let files = (try? FileManager.default.contentsOfDirectory(at: scope.directory, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.pathExtension == "plist" {
                guard let data = try? Data(contentsOf: url),
                      let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
                let label = dict["Label"] as? String ?? ""
                let args = dict["ProgramArguments"] as? [String]
                let program = (dict["Program"] as? String) ?? args?.first
                let joined = args?.joined(separator: " ") ?? ""
                let command = joined.isEmpty ? program : joined
                let keepAlive: Bool = {
                    if let b = dict["KeepAlive"] as? Bool { return b }
                    return dict["KeepAlive"] is [String: Any]
                }()
                let disabled = scope == .daemon ? systemDisabled.contains(label)
                                                : userDisabled.contains(label) || (dict["Disabled"] as? Bool ?? false)
                let loaded = label.isEmpty ? false
                    : scope == .daemon ? program.map(runningPaths.contains) ?? false
                    : loadedUser.contains(label)
                result.append(LaunchItem(label: label, plist: url, scope: scope, program: program, command: command,
                                         runAtLoad: dict["RunAtLoad"] as? Bool ?? false, keepAlive: keepAlive,
                                         disabled: disabled, loaded: loaded))
            }
        }
        return result.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// `launchctl print-disabled` — "label" => disabled (옛 형식은 => true)
    private static func disabledLabels(domain: String) -> Set<String> {
        let out = Shell.run("/bin/launchctl", ["print-disabled", domain])
        var set = Set<String>()
        for line in out.split(separator: "\n") {
            let parts = line.components(separatedBy: "=>")
            guard parts.count == 2 else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard value == "disabled" || value == "true" else { continue }
            set.insert(parts[0].trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")))
        }
        return set
    }

    /// 내 도메인에 올라간 항목 — `launchctl list` 세 번째 열
    private static func loadedUserLabels() -> Set<String> {
        let out = Shell.run("/bin/launchctl", ["list"])
        return Set(out.split(separator: "\n").dropFirst().compactMap { line in
            line.split(separator: "\t").last.map(String.init)
        })
    }

    // MARK: 끄기·켜기·삭제

    /// 끄면 다시 로그인해도 실행되지 않고, 지금 돌고 있는 것도 멈춘다.
    static func setEnabled(_ enabled: Bool, _ item: LaunchItem) -> Bool {
        if item.scope == .daemon {
            return Shell.runReturningStatus(FanHelper.installedPath, ["daemon", enabled ? "enable" : "disable", item.label]) == 0
        }
        let target = "\(item.scope.domain)/\(item.label)"
        if enabled {
            guard Shell.runReturningStatus("/bin/launchctl", ["enable", target]) == 0 else { return false }
            // 이미 올라가 있으면 실패하지만 상관없다.
            _ = Shell.runReturningStatus("/bin/launchctl", ["bootstrap", item.scope.domain, item.plist.path])
            return true
        } else {
            guard Shell.runReturningStatus("/bin/launchctl", ["disable", target]) == 0 else { return false }
            _ = Shell.runReturningStatus("/bin/launchctl", ["bootout", target])
            return true
        }
    }

    /// 내 계정 항목만 — 멈추고 plist를 휴지통으로 (휴지통에서 되살릴 수 있다)
    static func delete(_ item: LaunchItem) -> Bool {
        guard item.scope.canDelete else { return false }
        _ = Shell.runReturningStatus("/bin/launchctl", ["bootout", "\(item.scope.domain)/\(item.label)"])
        return (try? FileManager.default.trashItem(at: item.plist, resultingItemURL: nil)) != nil
    }

    // MARK: 로그인 항목 — System Events (처음 한 번 자동화 권한을 묻는다)

    static func loginItems() -> (items: [LoginItem], error: String?) {
        let script = """
        tell application "System Events"
            set out to ""
            repeat with i in every login item
                set p to ""
                try
                    set p to path of i
                end try
                set out to out & (name of i) & tab & p & linefeed
            end repeat
            return out
        end tell
        """
        var err: NSDictionary?
        guard let result = NSAppleScript(source: script)?.executeAndReturnError(&err).stringValue else {
            let code = err?[NSAppleScript.errorNumber] as? Int
            return ([], code == -1743 ? tr("자동화 권한이 필요합니다 — 시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 System Events를 허용하세요")
                                     : tr("로그인 항목을 읽지 못했습니다"))
        }
        let items = result.split(separator: "\n").compactMap { line -> LoginItem? in
            let f = line.components(separatedBy: "\t")
            guard let name = f.first, !name.isEmpty else { return nil }
            let path = f.count > 1 && !f[1].isEmpty && f[1] != "missing value" ? f[1] : nil
            return LoginItem(name: name, path: path)
        }
        return (items, nil)
    }

    static func removeLoginItem(_ item: LoginItem) -> Bool {
        let name = item.name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"System Events\" to delete login item \"\(name)\"")?.executeAndReturnError(&err)
        return err == nil
    }

    /// 시스템 설정의 로그인 항목 화면
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
}

// MARK: - 상태

@MainActor
final class StartupState: ObservableObject {
    @Published private(set) var launchItems: [LaunchItem] = []
    @Published private(set) var loginItems: [LoginItem] = []
    @Published private(set) var loginError: String?
    @Published private(set) var loading = false
    @Published var lastError: String?

    func refresh() {
        loading = true
        Task.detached {
            let items = StartupService.launchItems()
            let login = StartupService.loginItems()
            await MainActor.run {
                self.launchItems = items
                self.loginItems = login.items
                self.loginError = login.error
                self.loading = false
            }
        }
    }

    func items(_ scope: LaunchScope) -> [LaunchItem] {
        launchItems.filter { $0.scope == scope }
    }

    func toggle(_ item: LaunchItem) {
        if item.scope == .daemon, !FanHelper.isReady {
            lastError = tr("시스템 항목을 바꾸려면 팬 제어 도우미를 먼저 설치하세요 (팬 제어 탭)")
            return
        }
        let enable = item.disabled
        Task.detached {
            let ok = StartupService.setEnabled(enable, item)
            await MainActor.run {
                self.lastError = ok ? nil : trf("%@을(를) 바꾸지 못했습니다", item.displayName)
                self.refresh()
            }
        }
    }

    func delete(_ item: LaunchItem) {
        lastError = StartupService.delete(item) ? nil : trf("%@을(를) 지우지 못했습니다", item.displayName)
        refresh()
    }

    func removeLoginItem(_ item: LoginItem) {
        Task.detached {
            let ok = StartupService.removeLoginItem(item)
            await MainActor.run {
                self.lastError = ok ? nil : trf("%@을(를) 로그인 항목에서 빼지 못했습니다", item.name)
                self.refresh()
            }
        }
    }
}
