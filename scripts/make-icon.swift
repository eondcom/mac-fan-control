// 앱 아이콘 생성 — swiftc -O -o /tmp/make-icon scripts/make-icon.swift && /tmp/make-icon App/Resources/Assets.xcassets/AppIcon.appiconset
import SwiftUI
import AppKit

// macOS 아이콘 그리드: 1024 캔버스, 824 squircle, 아래로 살짝 그림자
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.60, blue: 1.0),
                                              Color(red: 0.0, green: 0.435, blue: 0.933),
                                              Color(red: 0.0, green: 0.33, blue: 0.78)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(0.22), .clear],
                                             startPoint: .top, endPoint: .center))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 12)

            Image(systemName: "fan.fill")
                .font(.system(size: 470, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
        }
        .frame(width: 1024, height: 1024)
    }
}

let out = CommandLine.arguments[1]
MainActor.assumeIsolated {
    for (px, name) in [(16,"16x16"),(32,"16x16@2x"),(32,"32x32"),(64,"32x32@2x"),(128,"128x128"),
                       (256,"128x128@2x"),(256,"256x256"),(512,"256x256@2x"),(512,"512x512"),(1024,"512x512@2x")] {
        let r = ImageRenderer(content: AppIconView())
        r.scale = CGFloat(px) / 1024
        guard let cg = r.cgImage else { fatalError("render failed") }
        let rep = NSBitmapImageRep(cgImage: cg)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
    }
}
