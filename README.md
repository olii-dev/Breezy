# Breezy - Beautiful Weather App

A modern, elegant weather app for iOS, watchOS, and widgets that provides accurate forecasts powered by Apple WeatherKit.

## Features

### Core Features
- **Real-time Weather Data** - Powered by Apple WeatherKit for accurate forecasts
- **Beautiful UI** - Dynamic gradient backgrounds that adapt to weather conditions
- **Interactive Hourly Charts** - Smooth, scrubable charts with detailed hourly forecasts
- **7-Day Forecast** - Detailed daily forecast with expandable day views
- **Weather Metrics** - UV index, air quality, humidity, wind speed/direction, visibility, and more
- **Sun & Moon Data** - Sunrise/sunset times and moon phase information

### Smart Features
- **Location Services** - Automatic location detection with manual city search
- **Favourites** - Save your favorite locations for quick access
- **Recently Viewed** - Quick access to recently checked locations
- **Smart Caching** - Configurable cache duration to reduce API calls
- **Rain Detection** - Contextual alerts when rain is imminent

### Notifications
- **Daily Forecast** - Scheduled notifications at your preferred time
- **Severe Weather Alerts** - Immediate alerts for dangerous conditions
- **Rain Alerts** - Get notified when rain is expected in the next few hours
- **UV Index Alerts** - Warnings when UV index exceeds your threshold
- **Location-Based** - Automatic weather updates when you change locations

### Customization
- **Temperature Units** - Switch between Celsius and Fahrenheit
- **Appearance** - Light, Dark, or Auto mode
- **Icon Style** - Choose between emoji or SF Symbols
- **Notification Settings** - Fully customizable alert preferences

### Extensions
- **iOS Widgets** - Home screen and lock screen widgets
- **Apple Watch App** - Full-featured weather app for Apple Watch
- **Watch Complications** - Quick glance weather on your watch face
- **Watch Widgets** - Weather widgets on watchOS

## Requirements

- **Xcode 15.0+**
- **iOS 17.0+** for main app
- **watchOS 10.0+** for Watch app
- **Apple Developer Account** with WeatherKit entitlement
- **App Group** configured for widget data sharing

## Setup

### 1. WeatherKit Configuration

WeatherKit requires an Apple Developer Program membership and proper configuration:

1. Sign in to [Apple Developer Portal](https://developer.apple.com)
2. Go to **Certificates, Identifiers & Profiles**
3. Create an **App ID** (if not exists):
   - Bundle ID: `com.breezy.weather`
   - Enable **WeatherKit** capability
4. Create/update your **Provisioning Profile** with WeatherKit enabled

### 2. App Groups Configuration

The app uses App Groups to share data between the main app, widgets, and watch app:

1. In Apple Developer Portal, create an **App Group**:
   - Identifier: `group.com.breezy.weather`
2. Enable this App Group for:
   - Main app (`com.breezy.weather`)
   - Widget extension
   - Watch app

### 3. Project Configuration

1. Clone the repository
2. Open `Breezy.xcodeproj` in Xcode
3. Update the following in **Signing & Capabilities**:
   - Select your Development Team
   - Verify WeatherKit is enabled
   - Verify App Groups contains `group.com.breezy.weather`
4. Repeat for all targets (Main app, Widgets, Watch app)

### 4. Build and Run

```bash
# Open the project
open Breezy.xcodeproj

# Build from command line (optional)
xcodebuild -project Breezy.xcodeproj -scheme Breezy -configuration Debug build
```

## Project Structure

```
Breezy/
├── Breezy/                          # Main iOS app
│   ├── BreezyApp.swift              # App entry point
│   ├── Models/                      # Data models
│   │   ├── WeatherInfo.swift        # Main weather data model
│   │   ├── DailyForecast.swift      # Daily forecast model
│   │   ├── HourlyForecast.swift     # Hourly forecast model
│   │   ├── LocationData.swift       # Location model
│   │   ├── WeatherMetrics.swift     # Weather metrics model
│   │   ├── NotificationSettings.swift
│   │   └── AppSettings.swift
│   ├── Views/                       # SwiftUI views
│   │   ├── ContentView.swift        # Main weather view
│   │   ├── OnboardingView.swift     # First-run tutorial
│   │   ├── SettingsView.swift       # Settings screen
│   │   ├── LocationPickerView.swift # Location search
│   │   └── DailyForecastDetailView.swift
│   ├── ViewModels/                  # View models
│   │   └── WeatherViewModel.swift   # Main weather logic
│   ├── Services/                    # Business logic
│   │   ├── LocationHelper.swift     # Location services
│   │   └── NotificationManager.swift # Notification handling
│   ├── Stores/                      # Data persistence
│   │   ├── WeatherCache.swift       # Weather data cache
│   │   ├── FavouritesStore.swift    # Saved locations
│   │   ├── RecentlyViewedStore.swift
│   │   └── WidgetDataStore.swift    # Widget data sharing
│   └── Utilities/                   # Helper utilities
│       ├── DesignSystem.swift       # UI constants
│       ├── WeatherTheme.swift       # Dynamic theming
│       ├── WeatherIconHelper.swift  # Icon mapping
│       ├── DateFormatterHelper.swift
│       ├── UVIndexHelper.swift
│       ├── AirQualityHelper.swift
│       ├── MoonPhaseHelper.swift
│       └── WindDirectionHelper.swift
├── BreezyWidget/                    # iOS widget extension
├── Breezy Watch Watch App/          # watchOS app
└── BreezyWatchWidgetExtension/      # watchOS widget extension
```

## App Architecture

### Data Flow
1. **LocationHelper** - Requests user location or geocodes manual search
2. **WeatherViewModel** - Fetches weather data from WeatherKit
3. **WeatherCache** - Stores data with configurable expiration
4. **WidgetDataStore** - Shares minimal data with widgets via App Group
5. **NotificationManager** - Schedules alerts based on weather conditions

### Key Technologies
- **SwiftUI** - Modern declarative UI framework
- **WeatherKit** - Apple's weather data service
- **Core Location** - Location services
- **User Notifications** - Weather alerts
- **WidgetKit** - Home and lock screen widgets
- **SwiftData** - Lightweight data persistence
- **Charts** - Interactive weather charts

## Privacy

Breezy respects user privacy:
- Location data is used **only** for weather forecasts
- No data is sent to third-party servers
- Weather data comes directly from Apple WeatherKit
- All data stays on device or in your iCloud (via SwiftData)

## Version

**Current Version:** 1.0

## License

This is a personal project. See the repository license for details.

## Attribution

Weather data provided by Apple Weather. See [legal attribution](https://weather-data.apple.com/legal-attribution) for data sources.

---

Built with ❤️ using SwiftUI and WeatherKit
