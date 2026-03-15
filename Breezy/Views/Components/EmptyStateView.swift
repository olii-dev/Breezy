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
        case noInternet
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
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .blur(radius: 30)
                
                iconView
                    .font(.system(size: 60))
                    .foregroundStyle(iconGradient)
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
                                .fill(iconGradient)
                                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        )
                }
                .padding(.top, 16)
            }
            
            Spacer()
        }
    }
    
    @ViewBuilder
    private var iconView: some View {
        switch state {
        case .loading:
            Image(systemName: "cloud.sun.fill")
        case .noLocation:
            Image(systemName: "location.slash.fill")
        case .noInternet:
            Image(systemName: "wifi.slash")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
        case .noData:
            Image(systemName: "cloud.drizzle.fill")
        }
    }
    
    private var iconGradient: LinearGradient {
        switch state {
        case .loading:
            return LinearGradient(
                colors: [Color.blue, Color.cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .noLocation:
            return LinearGradient(
                colors: [Color.orange, Color.red],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .noInternet:
            return LinearGradient(
                colors: [Color.gray, Color.gray.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .error:
            return LinearGradient(
                colors: [Color.red, Color.orange],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .noData:
            return LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    private var title: String {
        switch state {
        case .loading: return "Loading Weather"
        case .noLocation: return "Location Required"
        case .noInternet: return "No Internet"
        case .error: return "Something Went Wrong"
        case .noData: return "No Data Available"
        }
    }
    
    private var message: String {
        switch state {
        case .loading: return "Fetching the latest forecast..."
        case .noLocation: return "Breezy needs your location to provide accurate weather for your area."
        case .noInternet: return "Check your connection and pull to refresh."
        case .error(let msg): return msg
        case .noData: return "We couldn't find weather data for this location."
        }
    }
    
    private var buttonTitle: String? {
        switch state {
        case .loading: return nil
        case .noLocation: return "Enable Location"
        case .noInternet: return "Try Again"
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
        case (.noInternet, .noInternet): return true
        case (.noData, .noData): return true
        case (.error(let a), .error(let b)): return a == b
        default: return false
        }
    }
}

#Preview {
    ZStack {
        Color.blue.opacity(0.2).ignoresSafeArea()
        EmptyStateView(state: .noInternet, action: {})
    }
}
