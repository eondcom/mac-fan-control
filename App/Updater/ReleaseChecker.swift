import Foundation

/// 업데이트 확인 결과 — 눌렀을 때 무슨 일이 있었는지 보여주기 위해
enum UpdateCheckStatus: Equatable {
    case idle
    case checking
    case upToDate(Date)
    case failed
}

struct ReleaseInfo {
    let version: String
    let dmgURL: URL?
    let tagURL: URL
}

enum ReleaseChecker {

    static let apiURL = URL(string: "https://api.github.com/repos/eondcom/mac-fan-control/releases/latest")!

    static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    static func parseVersion(_ s: String) -> [Int] {
        s.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
         .split(separator: ".")
         .compactMap { Int($0) }
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = parseVersion(remote)
        let l = parseVersion(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    static func fetchLatest() async -> ReleaseInfo? {
        var req = URLRequest(url: apiURL, timeoutInterval: 6)
        req.addValue("MacFanControl/\(currentVersion())", forHTTPHeaderField: "User-Agent")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            // 404(릴리스 없음)·403(요청 한도) 등은 실패로 본다.
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else { return nil }
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "v "))
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmg = assets.compactMap { $0["browser_download_url"] as? String }
                            .first { $0.hasSuffix(".dmg") }
                            .flatMap(URL.init(string:))
            let tagURL = URL(string: "https://github.com/eondcom/mac-fan-control/releases/tag/v\(version)")!
            return ReleaseInfo(version: version, dmgURL: dmg, tagURL: tagURL)
        } catch {
            return nil
        }
    }
}
