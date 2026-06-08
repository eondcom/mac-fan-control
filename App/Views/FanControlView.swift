import SwiftUI

struct FanControlView: View {
    @EnvironmentObject var state: AppState
    @State private var customRPM: Double = 2500

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("팬 속도 프리셋")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                presetButton(label: "🔇 저속",   rpm: 1200, color: .blue)
                presetButton(label: "🔁 일반",   rpm: 2500, color: .green)
                presetButton(label: "🚀 고성능", rpm: 4500, color: .red)
            }

            Button {
                state.resetFanAuto()
            } label: {
                Label("자동 모드로 복구 (macOS 기본)", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(state.thermal.fanManual ? .blue : .secondary)

            Divider().padding(.vertical, 4)

            // 커스텀 슬라이더
            HStack {
                Text("커스텀 RPM")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(customRPM).formatted()) rpm")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }

            Slider(value: $customRPM, in: 1200...6000, step: 100)

            Button {
                state.applyFan(rpm: Int(customRPM))
            } label: {
                Text("적용")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
        .onAppear {
            if let current = state.thermal.fanRPM {
                customRPM = max(1200, min(6000, Double(current)))
            }
        }
    }

    private func presetButton(label: String, rpm: Int, color: Color) -> some View {
        Button {
            customRPM = Double(rpm)
            state.applyFan(rpm: rpm)
        } label: {
            VStack(spacing: 4) {
                Text(label).font(.title3).bold()
                Text("\(rpm.formatted()) rpm").font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }
}
