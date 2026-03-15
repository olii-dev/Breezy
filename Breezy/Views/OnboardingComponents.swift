import SwiftUI

struct ThemeMockupView: View {
    @State private var selectedThemeIndex = 0
    let themes: [(Color, Color, String)] = [
        (DesignSystem.softBlue, DesignSystem.skyBlue, "Blue Skies"),
        (DesignSystem.lavender, DesignSystem.softPink, "Sunset"),
        (DesignSystem.mintGreen, Color.teal.opacity(0.3), "Ocean")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [themes[selectedThemeIndex].0, themes[selectedThemeIndex].1],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 320)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                
                VStack(spacing: 15) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.3))
                        .frame(width: 160, height: 60)
                    
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.3))
                            .frame(width: 74, height: 74)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.3))
                            .frame(width: 74, height: 74)
                    }
                    
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.white.opacity(0.3))
                        .frame(width: 160, height: 80)
                }
            }
            
            HStack(spacing: 12) {
                ForEach(0..<themes.count, id: \.self) { index in
                    Circle()
                        .fill(themes[index].0)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: selectedThemeIndex == index ? 3 : 0)
                        )
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2).repeatForever()) {
                                if index == 0 { // Just a dummy trigger for animation demo
                                    // Normally we'd use a timer to cycle themes
                                }
                            }
                        }
                }
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                withAnimation {
                    selectedThemeIndex = (selectedThemeIndex + 1) % themes.count
                }
            }
        }
    }
}

struct WidgetMockupView: View {
    @AppStorage("Breezy.glassOpacity") private var glassOpacity: Double = 0.35

    var body: some View {
        ZStack {
            // Background Grid
            VStack(spacing: 12) {
                ForEach(0..<3) { _ in
                    HStack(spacing: 12) {
                        ForEach(0..<2) { _ in
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.white.opacity(0.15))
                                .frame(width: 100, height: 100)
                        }
                    }
                }
            }
            .blur(radius: 1)
            
            // Active Widget
            RoundedRectangle(cornerRadius: 24)
                .fill(.ultraThinMaterial.opacity(glassOpacity))
                .frame(width: 160, height: 160)
                .overlay(
                    VStack(spacing: 12) {
                        Image(systemName: "wind")
                            .font(.system(size: 40))
                            .foregroundColor(DesignSystem.skyBlue)
                        Text("Wind Gauge")
                            .font(.caption.bold())
                        RoundedRectangle(cornerRadius: 4)
                            .fill(DesignSystem.skyBlue.opacity(0.3))
                            .frame(width: 80, height: 8)
                    }
                )
                .rotationEffect(.degrees(-5))
                .offset(y: -20)
                .shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 10)
        }
    }
}

struct AstroMockupView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                // Horizon
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 100))
                    path.addLine(to: CGPoint(x: 200, y: 100))
                }
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                
                // Sun Path Arc
                Path { path in
                    path.addArc(center: CGPoint(x: 100, y: 100), radius: 80, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                }
                .stroke(
                    LinearGradient(colors: [.orange, .yellow, .orange.opacity(0.3)], startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 8])
                )
                
                // Sun
                Circle()
                    .fill(
                        RadialGradient(colors: [.yellow, .orange], center: .center, startRadius: 0, endRadius: 15)
                    )
                    .frame(width: 30, height: 30)
                    .offset(x: 40, y: -68) // Positioned on the arc
                    .shadow(color: .orange.opacity(0.5), radius: 10)
            }
            .frame(width: 200, height: 120)
            
            HStack(spacing: 30) {
                VStack {
                    Image(systemName: "sunrise.fill")
                        .foregroundColor(.orange)
                    Text("06:42")
                        .font(.caption2.monospacedDigit())
                }
                VStack {
                    Image(systemName: "sunset.fill")
                        .foregroundColor(.orange)
                    Text("18:15")
                        .font(.caption2.monospacedDigit())
                }
            }
            .foregroundColor(.white)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(.black.opacity(0.2))
        )
    }
}

struct TimeMachineMockupView: View {
    @AppStorage("Breezy.typography") private var typographyRaw: String = WeatherFont.system.rawValue

    private var typographyDesign: Font.Design {
        WeatherFont(rawValue: typographyRaw)?.design ?? .default
    }

    var body: some View {
        VStack(spacing: 30) {
            HStack(spacing: 20) {
                // Comparison Card 1
                VStack(spacing: 12) {
                    Text("JUL 12, 2021")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.yellow)
                    
                    Text("24°")
                        .font(.system(size: 24, weight: .bold, design: typographyDesign))
                        .foregroundColor(.white)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.1)))
                
                Image(systemName: "arrow.left.and.right")
                    .foregroundColor(DesignSystem.lavender)
                    .font(.headline)
                
                // Comparison Card 2
                VStack(spacing: 12) {
                    Text("JUL 12, 2024")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Image(systemName: "cloud.rain.fill")
                        .font(.system(size: 30))
                        .foregroundColor(DesignSystem.softBlue)
                    
                    Text("18°")
                        .font(.system(size: 24, weight: .bold, design: typographyDesign))
                        .foregroundColor(.white)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.1)))
            }
            
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Compare Historical Data")
                    .font(.system(.subheadline, design: typographyDesign).weight(.semibold))
            }
            .foregroundColor(DesignSystem.lavender)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(DesignSystem.lavender.opacity(0.15)))
        }
    }
}
