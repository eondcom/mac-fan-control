import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("대시보드", systemImage: "gauge") }
            FanControlView()
                .tabItem { Label("팬 제어", systemImage: "fan") }
            BatteryView()
                .tabItem { Label("배터리", systemImage: "battery.100") }
            SettingsView()
                .tabItem { Label("설정", systemImage: "gear") }
        }
        .padding()
        .frame(minWidth: 720, minHeight: 480)
    }
}

// MARK: - 공용 색상 유틸

enum TempLevel {
    case stable, normal, caution, hot

    static func from(_ temp: Double?) -> TempLevel? {
        guard let t = temp else { return nil }
        if t < 60 { return .stable }
        if t < 75 { return .normal }
        if t < 85 { return .caution }
        return .hot
    }

    var color: Color {
        switch self {
        case .stable:  return .green
        case .normal:  return .yellow
        case .caution: return .orange
        case .hot:     return .red
        }
    }

    var label: String {
        switch self {
        case .stable:  return "안정"
        case .normal:  return "적정"
        case .caution: return "주의"
        case .hot:     return "위험"
        }
    }
}

enum FanLevel {
    case low, mid, high

    static func from(_ rpm: Int?) -> FanLevel? {
        guard let r = rpm else { return nil }
        if r < 2000 { return .low }
        if r < 4000 { return .mid }
        return .high
    }

    var color: Color {
        switch self {
        case .low:  return .blue
        case .mid:  return .green
        case .high: return .red
        }
    }

    var label: String {
        switch self {
        case .low:  return "최소"
        case .mid:  return "기본"
        case .high: return "고속"
        }
    }
}
