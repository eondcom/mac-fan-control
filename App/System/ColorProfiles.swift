import Foundation
import ColorSync
import CoreGraphics

/// ICC 프로필 하나를 읽은 결과
struct ColorProfileInfo: Identifiable, Equatable {
    let url: URL
    let name: String
    /// 'mntr' 모니터용 · 'spac' 색 공간 등
    let deviceClass: String
    /// CIE xy 색도 삼각형 넓이 — 프로필이 말하는 색 영역의 크기
    let gamutArea: Double?
    /// 감마가 1.0(선형)이면 화면용으로 쓰면 명암이 밋밋해진다.
    let isLinear: Bool
    var id: URL { url }
}

/// 프로필 후보 — 왜 이 프로필을 쓰는지
enum ProfileRole {
    /// 이 모니터가 알려준 패널 색 정보로 만든 프로필
    case native
    case sRGB
    case displayP3
    case adobeRGB
    /// 지금 쓰고 있지만 위 목록에 없는 것
    case other
}

struct ProfileCandidate: Identifiable {
    let profile: ColorProfileInfo
    let role: ProfileRole
    var id: URL { profile.id }
}

/// 지금 프로필이 패널과 맞는지
enum ProfileFit: Equatable {
    case good
    /// 프로필이 패널보다 좁음 → 패널이 색을 그대로 키워서 형광빛
    case tooNarrow
    /// 프로필이 패널보다 넓음 → 색을 줄여 보내서 바래 보임
    case tooWide
    /// 선형 감마 — 어둡고 밝은 곳 차이가 밋밋함
    case linear
    /// 모니터용 프로필이 아님
    case notDisplay
    case unknown
}

enum ColorProfileService {

    private static let systemDir = URL(fileURLWithPath: "/System/Library/ColorSync/Profiles")
    private static let displaysDir = URL(fileURLWithPath: "/Library/ColorSync/Profiles/Displays")

    static let sRGBArea: Double = {
        read(systemDir.appendingPathComponent("sRGB Profile.icc"))?.gamutArea ?? 0.109
    }()

    // MARK: 읽기

    static func read(_ url: URL) -> ColorProfileInfo? {
        guard let p = ColorSyncProfileCreateWithURL(url as CFURL, nil)?.takeRetainedValue() else { return nil }
        let name = (ColorSyncProfileCopyDescriptionString(p)?.takeRetainedValue() as String?)
            ?? url.deletingPathExtension().lastPathComponent
        var cls = ""
        if let h = ColorSyncProfileCopyHeader(p)?.takeRetainedValue() as Data?, h.count >= 16 {
            cls = String(bytes: h[12..<16], encoding: .ascii) ?? ""
            // 헤더가 기기 바이트 순서로 올 때가 있다 ('rtnm' → 'mntr')
            if !["mntr", "scnr", "prtr", "spac", "abst", "link", "nmcl"].contains(cls) {
                cls = String(cls.reversed())
            }
        }
        return ColorProfileInfo(url: url, name: name, deviceClass: cls,
                                gamutArea: gamutArea(p), isLinear: isLinear(p))
    }

    private static func xyz(_ p: ColorSyncProfile, _ tag: String) -> (Double, Double)? {
        guard let d = ColorSyncProfileCopyTag(p, tag as CFString)?.takeRetainedValue() as Data?,
              d.count >= 20 else { return nil }
        func s15(_ o: Int) -> Double {
            let v = d[d.startIndex + o ..< d.startIndex + o + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            return Double(Int32(bitPattern: v)) / 65536
        }
        let (x, y, z) = (s15(8), s15(12), s15(16))
        let sum = x + y + z
        guard sum > 0 else { return nil }
        return (x / sum, y / sum)
    }

    private static func gamutArea(_ p: ColorSyncProfile) -> Double? {
        guard let r = xyz(p, "rXYZ"), let g = xyz(p, "gXYZ"), let b = xyz(p, "bXYZ") else { return nil }
        return abs((g.0 - r.0) * (b.1 - r.1) - (b.0 - r.0) * (g.1 - r.1)) / 2
    }

    private static func isLinear(_ p: ColorSyncProfile) -> Bool {
        guard let d = ColorSyncProfileCopyTag(p, "rTRC" as CFString)?.takeRetainedValue() as Data?,
              d.count >= 12, String(bytes: d.prefix(4), encoding: .ascii) == "curv" else { return false }
        let b = Array(d)
        let count = Int(b[8]) << 24 | Int(b[9]) << 16 | Int(b[10]) << 8 | Int(b[11])
        if count == 0 { return true }
        if count == 1, b.count >= 14 {
            let gamma = Double(Int(b[12]) << 8 | Int(b[13])) / 256
            return gamma < 1.2
        }
        return false
    }

    // MARK: 화면별

    private static func uuid(_ id: CGDirectDisplayID) -> CFUUID? {
        CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
    }

    /// 화면에 지금 적용된 프로필
    static func current(for id: CGDirectDisplayID) -> ColorProfileInfo? {
        guard let u = uuid(id),
              let info = ColorSyncDeviceCopyDeviceInfo(kColorSyncDisplayDeviceClass.takeUnretainedValue(), u)?
                .takeRetainedValue() as? [String: Any] else { return nil }
        let defaultKey = kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String
        let factory = info[kColorSyncFactoryProfiles.takeUnretainedValue() as String] as? [String: Any]
        let profileID = factory?[defaultKey] as? String ?? defaultKey

        // 사용자가 고른 프로필이 있으면 그것, 없으면 기본 프로필
        if let custom = info[kColorSyncCustomProfiles.takeUnretainedValue() as String] as? [String: Any],
           let url = (custom[profileID] ?? custom.values.first).flatMap(asURL) {
            return read(url)
        }
        if let entry = factory?[profileID] as? [String: Any],
           let url = entry[kColorSyncDeviceProfileURL.takeUnretainedValue() as String].flatMap(asURL) {
            return read(url)
        }
        return nil
    }

    private static func asURL(_ v: Any) -> URL? {
        if let u = v as? URL { return u }
        if let s = v as? String { return URL(string: s) }
        return nil
    }

    /// 이 모니터에 쓸 만한 프로필 — 추천 순서대로
    static func candidates(for id: CGDirectDisplayID) -> [ProfileCandidate] {
        var list: [ProfileCandidate] = []
        if let u = uuid(id), let key = CFUUIDCreateString(nil, u) as String?,
           let files = try? FileManager.default.contentsOfDirectory(at: displaysDir, includingPropertiesForKeys: nil),
           let file = files.first(where: { $0.lastPathComponent.uppercased().contains(key.uppercased()) }),
           let p = read(file) {
            list.append(ProfileCandidate(profile: p, role: .native))
        }
        let standard: [(String, ProfileRole)] = [
            ("sRGB Profile.icc", .sRGB),
            ("Display P3.icc", .displayP3),
            ("AdobeRGB1998.icc", .adobeRGB),
        ]
        for (file, role) in standard {
            if let p = read(systemDir.appendingPathComponent(file)) {
                list.append(ProfileCandidate(profile: p, role: role))
            }
        }
        if let cur = current(for: id), !list.contains(where: { $0.profile.url.standardizedFileURL == cur.url.standardizedFileURL }) {
            list.append(ProfileCandidate(profile: cur, role: .other))
        }
        return list
    }

    /// 패널 색 영역(기본 프로필)과 비교해 지금 프로필이 맞는지 본다.
    static func fit(_ p: ColorProfileInfo, native: ColorProfileInfo?) -> ProfileFit {
        if !["mntr", "spac"].contains(p.deviceClass) { return .notDisplay }
        if p.isLinear { return .linear }
        guard let a = p.gamutArea, let n = native?.gamutArea, n > 0 else {
            return p.deviceClass == "mntr" ? .good : .unknown
        }
        let ratio = a / n
        if ratio < 0.88 { return .tooNarrow }
        if ratio > 1.12 { return .tooWide }
        return .good
    }

    // MARK: 적용

    /// 시스템 설정 → 디스플레이 → 색상 프로파일 선택과 같다.
    @discardableResult
    static func apply(_ url: URL, to id: CGDirectDisplayID) -> Bool {
        guard let u = uuid(id) else { return false }
        let dict: [String: Any] = [
            kColorSyncDeviceDefaultProfileID.takeUnretainedValue() as String: url,
            kColorSyncProfileUserScope.takeUnretainedValue() as String: kCFPreferencesCurrentUser as String,
        ]
        return ColorSyncDeviceSetCustomProfiles(kColorSyncDisplayDeviceClass.takeUnretainedValue(), u, dict as CFDictionary)
    }
}
