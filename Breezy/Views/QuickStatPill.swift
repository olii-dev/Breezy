//
//  QuickStatPill.swift
//  Breezy
//

import SwiftUI

// MARK: - Quick Stat Pill

struct QuickStatPill: View {
    let icon: String
    let emoji: String
    let label: String
    let value: String
    let useEmoji: Bool
    let textColor: Color
    
    var body: some View {
        VStack(spacing: 6) {
            if useEmoji {
                Text(emoji)
                    .font(.title3)
            } else {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(textColor.opacity(0.9))
            }
            
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundColor(textColor.opacity(0.7))
            
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundColor(textColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.spacingS)
        .softGlassCard(padding: 6, cornerRadius: DesignSystem.radiusS)
    }
}
