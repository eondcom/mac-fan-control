import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 온도 카드 3개
            HStack(spacing: 12) {
                tempCard(title: "CPU 온도",  temp: state.thermal.cpuTemp,     accent: .orange)
                tempCard(title: "GPU 온도",  temp: state.thermal.gpuTemp,     accent: .blue)
                tempCard(title: "배터리 온도", temp: state.thermal.batteryTemp, accent: .green)
            }

            // 팬 + 전원 카드
            HStack(spacing: 12) {
                fanCard()
                powerCard()
            }

            Spacer()

            HStack {
                Spacer()
                Button {
                    state.refreshAll()
                } label: {
                    Label("새로고침", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding()
    }

    // MARK: temp card

    private func tempCard(title: String, temp: Double?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(accent)
            if let t = temp {
                Text(String(format: "%.1f°C", t))
                    .font(.system(size: 28, weight: .bold))
                if let lvl = TempLevel.from(temp) {
                    Text(lvl.label)
                        .font(.caption)
                        .foregroundStyle(lvl.color)
                }
            } else {
                Text("N/A")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: fan card

    private func fanCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("팬 상태")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            row(label: "현재 속도",
                value: state.thermal.fanRPM.map { "\($0.formatted()) rpm" } ?? "N/A",
                color: FanLevel.from(state.thermal.fanRPM)?.color ?? .secondary)

            if let mn = state.thermal.fanMin, let mx = state.thermal.fanMax {
                row(label: "속도 범위",
                    value: "\(mn.formatted()) ~ \(mx.formatted()) rpm",
                    color: .secondary)
            } else {
                row(label: "속도 범위", value: "N/A", color: .secondary)
            }

            row(label: "제어 모드",
                value: state.thermal.fanManual ? "🔧 수동" : "🔄 자동",
                color: state.thermal.fanManual ? .yellow : .green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func row(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            Text(value)
                .foregroundStyle(color)
                .fontWeight(.medium)
            Spacer()
        }
        .font(.callout)
    }

    // MARK: power card

    private func powerCard() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("전원 모드")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(state.power == .low ? "🌙 절전" : "⚡ 기본")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(state.power == .low ? Color.blue : Color.green)

            HStack {
                Button {
                    state.setPowerMode(.low)
                } label: {
                    Text("🌙 절전")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(state.power == .low ? .blue : .secondary)

                Button {
                    state.setPowerMode(.normal)
                } label: {
                    Text("⚡ 기본")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(state.power == .normal ? .green : .secondary)
            }

            Text("* 모드 변경 시 시스템 암호가 필요합니다.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
