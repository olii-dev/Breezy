//
//  EmptyStateView.swift
//  Breezy
//
//  Reusable view for Empty, Error, and Loading states
//

import SwiftUI

struct EmptyStateView: View {
    enum StateType {
        case loading
        case noLocation
        case error(String)
        case noData
    }
    
    let state: StateType
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                
                Image(systemName: iconName)
                    .font(.system(size: 60))
                    .foregroundColor(.primary.opacity(0.8))
                    .symbolEffect(.pulse, isActive: state == .loading)
            }
            .padding(.bottom, 8)
            
            VStack(spacing: 12) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if let action = action, buttonTitle != nil {
                Button(action: {
                    HapticsManager.shared.impact(style: .medium)
                    action()
                }) {
                    Text(buttonTitle!)
                        .font(.headline)
                        .foregroundColor(colorScheme == .light ? .white : .black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(
                            Capsule()
                                .fill(Color.primary)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        )
                }
                .padding(.top, 16)
            }
            
            Spacer()
        }
    }
    
    private var iconName: String {
        switch state {
        case .loading: return "cloud.sun.fill"
        case .noLocation: return "location.slash.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .noData: return "cloud.drizzle.fill"
        }
    }
    
    private var title: String {
        switch state {
        case .loading: return "Loading Weather"
        case .noLocation: return "Location Required"
        case .error: return "Something Went Wrong"
        case .noData: return "No Data Available"
        }
    }
    
    private var message: String {
        switch state {
        case .loading: return "Fetching the latest forecast..."
        case .noLocation: return "Breezy needs your location to provide accurate weather for your area."
        case .error(let msg): return msg
        case .noData: return "We couldn't find weather data for this location."
        }
    }
    
    private var buttonTitle: String? {
        switch state {
        case .loading: return nil
        case .noLocation: return "Enable Location"
        case .error: return "Try Again"
        case .noData: return "Search Location"
        }
    }
}

extension EmptyStateView.StateType: Equatable {
    static func == (lhs: EmptyStateView.StateType, rhs: EmptyStateView.StateType) -> Bool {
        switch (lhs, rhs) {
        case (.loading, .loading): return true
        case (.noLocation, .noLocation): return true
        case (.noData, .noData): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

#Preview {
    ZStack {
        Color.blue.opacity(0.2).ignoresSafeArea()
        EmptyStateView(state: .noLocation, action: {})
    }
}
