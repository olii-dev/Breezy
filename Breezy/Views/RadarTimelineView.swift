//
//  RadarTimelineView.swift
//  Breezy
//
//  Time scrubbing control for radar animation
//

import SwiftUI

struct RadarTimelineView: View {
    @Binding var currentTimeOffset: Int // Minutes from now
    @Binding var isPlaying: Bool
    let pastRange: Int = 180 // 3 hours
    let futureRange: Int = 120 // 2 hours
    
    var body: some View {
        VStack(spacing: 8) {
            // Time labels
            HStack {
                Text(timeLabel(for: -pastRange))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
                
                Text("Now")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                
                Spacer()
                
                Text(timeLabel(for: futureRange))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))
            }
            
            // Timeline slider
            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 6)
                
                // Past section
                GeometryReader { geometry in
                    let totalRange = pastRange + futureRange
                    let pastWidth = (CGFloat(pastRange) / CGFloat(totalRange)) * geometry.size.width
                    
                    Capsule()
                        .fill(Color.white.opacity(0.4))
                        .frame(width: pastWidth, height: 6)
                    
                    // Current time marker
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2, height: 12)
                        .offset(x: pastWidth - 1, y: -3)
                }
                .frame(height: 6)
                
                // Slider
                Slider(
                    value: Binding(
                        get: { Double(currentTimeOffset + pastRange) },
                        set: { currentTimeOffset = Int($0) - pastRange }
                    ),
                    in: 0...Double(pastRange + futureRange),
                    step: 10
                )
                .accentColor(.white)
            }
            .frame(height: 32)
            
            // Current time display
            Text(currentTimeLabel)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
        .padding(.horizontal)
    }
    
    private func timeLabel(for offset: Int) -> String {
        let hours = abs(offset) / 60
        if offset < 0 {
            return "-\(hours)h"
        } else if offset > 0 {
            return "+\(hours)h"
        } else {
            return "Now"
        }
    }
    
    private var currentTimeLabel: String {
        if currentTimeOffset == 0 {
            return "Current Time"
        }
        let absMinutes = abs(currentTimeOffset)
        let hours = absMinutes / 60
        let mins = absMinutes % 60
        
        var label = ""
        if hours > 0 {
            label += "\(hours)h"
        }
        if mins > 0 {
            label += (hours > 0 ? " " : "") + "\(mins)m"
        }
        
        return currentTimeOffset < 0 ? "\(label) ago" : "in \(label)"
    }
}

/// Play/Pause control button
struct RadarPlayButton: View {
    @Binding var isPlaying: Bool
    
    var body: some View {
        Button {
            withAnimation {
                isPlaying.toggle()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 50, height: 50)
                
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .foregroundColor(.white)
            }
        }
    }
}
