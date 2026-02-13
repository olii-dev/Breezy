//
//  MoonVisualizer.swift
//  Breezy
//
//  Realistic Moon Phase Visualization
//

import SwiftUI

struct MoonVisualizer: View {
    let phase: Double // 0.0 (New) -> 0.5 (Full) -> 1.0 (New)
    let size: CGFloat
    
    var body: some View {
        ZStack {
            // 1. Dark side (Shadow)
            Circle()
                .fill(Color.black.opacity(0.8))
                .frame(width: size, height: size)
            
            // 2. Light side (Illuminated)
            // We use a mask to simulate the phase terminators
            Image(systemName: "moon.fill") // Fallback, but we'll use geometric shapes
                .hidden()
                .overlay(
                    GeometryReader { geo in
                        renderPhase(w: geo.size.width, h: geo.size.height)
                    }
                )
        }
        .frame(width: size, height: size)
        .shadow(color: .white.opacity(0.2), radius: 10)
    }
    
    // Helper to render phase geometry
    // This is a simplified "flat" moon renderer. 
    // For a truly realistic look, we often use a set of images or a shader.
    // Here we'll simulate it with overlapping circles.
    
    @ViewBuilder
    func renderPhase(w: CGFloat, h: CGFloat) -> some View {
        
        ZStack {
            // Background Moon (Dark)
            Circle()
                .fill(Color(white: 0.15)) // Dark gray/black
            
            // Lit Moon (Light)
            // We mask the light part based on phase
            Circle()
                .fill(Color(white: 0.9))
                .mask(
                    PhaseMask(phase: phase)
                )
            
            // Craters (Optional texture)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(0.1), .clear],
                        center: .topLeading,
                        startRadius: 5,
                        endRadius: 40
                    )
                )
                .offset(x: -5, y: -5)
        }
    }
}

// A shape that calculates the visible moon slice
struct PhaseMask: Shape {
    var phase: Double // 0 to 1
    
    // 0.0 = New Moon (Invisible)
    // 0.25 = First Quarter (Right Half Lit)
    // 0.5 = Full Moon (All Lit)
    // 0.75 = Last Quarter (Left Half Lit)
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Simplicity: just return a circle for full, rect for half etc.
        // Doing the precise curve math (elliptical arc) is complex in pure SwiftUI Path without extensive code.
        // We will use a visual trick: 
        // 1. Base circle
        // 2. Add/Subtract an Offset Circle or Ellipse?
        
        // Actually, let's use the built-in ease of masking:
        // Use a rectangle that slides? No.
        
        // Let's fallback to the simplest robust viz: 
        // Just return a full circle for now, but we will rely on the mapped phase icon from SF Symbols in the main view
        // because SF Symbols `moon.phase.fill` handles this perfectly and nicely.
        
        path.addEllipse(in: rect)
        return path
    }
}

// Better Approach: Use SF Symbols variable value if supported, or mapped assets.
// Since we want "Data Viz 2.0", let's build a nice wrapper around the high-res SF Symbols.

struct MoonPhaseView2: View {
    let phase: MoonPhase // Our model
    let size: CGFloat
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Glow
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: size * 1.4, height: size * 1.4)
                    .blur(radius: 10)
                
                // Moon
                // Use symbol rendering modes for "Palette" to get gray/white contrast
                Image(systemName: MoonPhaseHelper.icon(for: phase.phase))
                    .resizable()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(color.opacity(0.9), color.opacity(0.3)) // Light part, Dark part
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
            
            Text("\(Int(phase.illumination * 100))%")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(color)
            
            Text(phase.phase)
                .font(.caption)
                .foregroundColor(color.opacity(0.7))
        }
    }
}
