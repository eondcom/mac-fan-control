import Foundation
import AppKit

/// 업데이트 설치 진행 상태
enum UpdateInstallStatus: Equatable {
    case idle
    case downloading
    case installing
    case failed(String)
}

/// 릴리스 DMG를 받아 지금 앱을 바꿔 끼우고 다시 띄운다.
/// 순서: 받기 → DMG 붙이기 → 새 앱 확인(번들 ID·버전·CPU) → 임시 폴더로 복사 → 앱 종료 후 교체·재실행
enum UpdateInstaller {

    enum Failure: Error {
        case download, mount, invalidApp, notReplaceable, copy

        var message: String {
            switch self {
            case .download:       return tr("내려받지 못했습니다")
            case .mount:          return tr("DMG를 열지 못했습니다")
            case .invalidApp:     return tr("받은 파일이 올바른 앱이 아닙니다")
            case .notReplaceable: return tr("이 위치의 앱은 자동으로 바꿀 수 없습니다")
            case .copy:           return tr("새 앱을 준비하지 못했습니다")
            }
        }
    }

    /// Xcode에서 띄운 개발 빌드는 바꾸지 않는다.
    static var canReplaceCurrent: Bool {
        !Bundle.main.bundlePath.contains("/DerivedData/")
    }

    /// 새 앱을 임시 폴더에 준비하고 그 경로를 돌려준다.
    static func prepare(_ release: ReleaseInfo) async throws -> URL {
        guard canReplaceCurrent else { throw Failure.notReplaceable }
        guard let dmgURL = release.dmgURL else { throw Failure.download }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacFanControl-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let dmg = work.appendingPathComponent("MacFanControl.dmg")
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: dmgURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
            try FileManager.default.moveItem(at: tmp, to: dmg)
        } catch let f as Failure {
            throw f
        } catch {
            throw Failure.download
        }

        let mount = work.appendingPathComponent("mnt", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        guard Shell.runReturningStatus("/usr/bin/hdiutil",
                                       ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                                        "-mountpoint", mount.path]) == 0 else { throw Failure.mount }
        defer { _ = Shell.runReturningStatus("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"]) }

        let mountedApp = mount.appendingPathComponent("MacFanControl.app")
        guard isValid(mountedApp, expectedVersion: release.version) else { throw Failure.invalidApp }

        let staged = work.appendingPathComponent("MacFanControl.app")
        guard Shell.runReturningStatus("/usr/bin/ditto", [mountedApp.path, staged.path]) == 0 else { throw Failure.copy }
        // 서명이 없는 앱이라 격리 표시가 붙으면 처음 실행 때 막힌다.
        _ = Shell.runReturningStatus("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])
        return staged
    }

    /// 번들 ID·버전이 맞고, 이 맥의 CPU에서 돌 수 있는지
    private static func isValid(_ app: URL, expectedVersion: String) -> Bool {
        guard let b = Bundle(url: app),
              b.bundleIdentifier == Bundle.main.bundleIdentifier,
              (b.infoDictionary?["CFBundleShortVersionString"] as? String) == expectedVersion,
              let exe = b.executableURL else { return false }
        #if arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "arm64"
        #endif
        return Shell.runReturningStatus("/usr/bin/lipo", [exe.path, "-verify_arch", arch]) == 0
    }

    /// 이 앱이 끝나기를 기다렸다가 바꿔 끼우고 다시 띄운다. 쓰기 권한이 없으면 관리자 암호를 묻는다.
    static func replaceAndRelaunch(with staged: URL) {
        let target = Bundle.main.bundleURL
        let q = { (p: String) in "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        // 새 앱을 옆에 다 복사한 뒤에야 옛 앱을 지운다 — 중간에 실패해도 앱이 사라지지 않게.
        let next = target.path + ".new"
        let swap = "rm -rf \(q(next)) && /usr/bin/ditto \(q(staged.path)) \(q(next))"
            + " && rm -rf \(q(target.path)) && mv \(q(next)) \(q(target.path))"
        let parent = target.deletingLastPathComponent().path
        let needsAdmin = !FileManager.default.isWritableFile(atPath: parent)
            || !FileManager.default.isWritableFile(atPath: target.path)
        let swapCmd: String
        if needsAdmin {
            let esc = swap.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            swapCmd = "/usr/bin/osascript -e \(q("do shell script \"\(esc)\" with administrator privileges"))"
        } else {
            swapCmd = swap
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        \(swapCmd)
        /usr/bin/open \(q(target.path))
        rm -rf \(q(staged.deletingLastPathComponent().path))
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        try? p.run()
        NSApp.terminate(nil)
    }
}
