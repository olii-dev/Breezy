//
//  OnboardingView.swift
//  Breezy
//
//  Guided first-run onboarding flow
//

import SwiftUI
import MapKit
import UserNotifications
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case explore
        case style
        case location
        case alerts

        var title: String {
            switch self {
            case .welcome: return "Welcome"
            case .explore: return "Explore Breezy"
            case .style: return "Pick Your Look"
            case .location: return "Choose a Starting Place"
            case .alerts: return "Alerts and Handoff"
            }
        }
    }

    private enum LocationChoice {
        case current
        case manual
    }

    @Binding var isPresented: Bool
    @ObservedObject var viewModel: WeatherViewModel
    @ObservedObject var locationHelper: LocationHelper
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var searchService = LocationSearchService()

    @State private var currentStep: Step = .welcome
    @State private var selectedLocation: LocationData?
    @State private var selectedLocationChoice: LocationChoice?
    @State private var draftNotificationSettings = UserDefaults.standard.notificationSettings
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isRequestingLocation = false
    @State private var isFinishing = false
    @State private var showManualSearch = false
    @State private var shakeError = false
    @FocusState private var searchFieldFocused: Bool
    @AppStorage("Breezy.typography") private var typographyRaw: String = WeatherFont.system.rawValue

    private var typographyDesign: Font.Design {
        WeatherFont(rawValue: typographyRaw)?.design ?? .default
    }

    private var primaryButtonTitle: String {
        switch currentStep {
        case .welcome:
            return "Start Setup"
        case .explore:
            return "Show Me the Style"
        case .style:
            return "Set My Location"
        case .location:
            return "Continue"
        case .alerts:
            if isFinishing {
                return "Finishing..."
            }
            if notificationStatus == .authorized || notificationStatus == .denied {
                return "Start"
            }
            return "Enable & Start"
        }
    }

    private var secondaryButtonTitle: String? {
        currentStep == .alerts && notificationStatus != .authorized ? "Start Without Notifications" : nil
    }

    private var primaryActionDisabled: Bool {
        switch currentStep {
        case .location:
            return selectedLocation == nil || isRequestingLocation
        case .alerts:
            return isFinishing
        default:
            return false
        }
    }

    var body: some View {
        let theme = viewModel.currentTheme(colorScheme: colorScheme)

        ZStack {
            AnimatedGradientBackground(colors: [theme.topColor, theme.bottomColor])
                .ignoresSafeArea()

            VStack(spacing: 0) {
                onboardingHeader(theme: theme)

                // Fixed, responsive content - avoid vertical scrolling on onboarding pages
                VStack {
                    stepContent(theme: theme)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 20)
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar(theme: theme)
        }
        .task {
            await refreshNotificationStatus()
        }
    }

    @ViewBuilder
    private func stepContent(theme: WeatherTheme) -> some View {
        VStack(spacing: 18) {
            // eyebrow removed — keep the header clean

            Text(currentStep.title)
                .font(.system(size: 34, weight: .bold, design: typographyDesign))
                .foregroundColor(theme.textColor)
                .multilineTextAlignment(.center)

            Text(stepDescription)
                .font(.body)
                .foregroundColor(theme.textColor.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .padding(.horizontal, 10)
        }
        .padding(.top, 8)

        Group {
            switch currentStep {
            case .welcome:
                welcomeStep(theme: theme)
            case .explore:
                exploreStep(theme: theme)
            case .style:
                styleStep(theme: theme)
            case .location:
                locationStep(theme: theme)
            case .alerts:
                alertsStep(theme: theme)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private var stepDescription: String {
        switch currentStep {
        case .welcome:
            return "Deeper forecasts, powerful widgets, and full customisation."
        case .explore:
            return "Build widgets, explore past weather, and customise nearly every detail."
        case .style:
            return "Pick the style you want for Breezy."
        case .location:
            return "Choose how Breezy should start: use your current location or pick a city manually."
        case .alerts:
            return "Pick what you want to be notified about."
        }
    }

    private func onboardingHeader(theme: WeatherTheme) -> some View {
        VStack(spacing: 14) {
            HStack {
                if currentStep != .welcome {
                    Button {
                        HapticsManager.shared.impact(style: .light)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                            currentStep = Step(rawValue: max(currentStep.rawValue - 1, 0)) ?? .welcome
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(theme.textColor)
                            .frame(width: 40, height: 40)
                            .background(.ultraThinMaterial.opacity(viewModel.glassOpacity), in: Circle())
                    }
                } else {
                    Color.clear.frame(width: 40, height: 40)
                }

                Spacer()

                Text("\(currentStep.rawValue + 1) of \(Step.allCases.count)")
                    .font(FontScale.footnote.weight(.semibold))
                    .foregroundColor(theme.textColor.opacity(0.82))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial.opacity(viewModel.glassOpacity), in: Capsule())

                Spacer()

                Color.clear.frame(width: 40, height: 40)
            }

            HStack(spacing: 8) {
                ForEach(Step.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStep.rawValue ? theme.textColor : theme.textColor.opacity(0.18))
                        .frame(height: 6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func actionBar(theme: WeatherTheme) -> some View {
        VStack(spacing: 12) {
            Button {
                HapticsManager.shared.impact(style: .medium)
                handlePrimaryAction()
            } label: {
                HStack(spacing: 10) {
                    if isFinishing {
                        ProgressView()
                            .tint(colorScheme == .light ? .white : .black)
                    }

                    Text(primaryButtonTitle)
                        .font(.headline.weight(.semibold))
                }
                .foregroundColor(colorScheme == .light ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.radiusL)
                        .fill(theme.textColor)
                        .shadow(color: Color.black.opacity(0.2), radius: 12, x: 0, y: 6)
                )
            }
            .disabled(primaryActionDisabled)
            .opacity(primaryActionDisabled ? 0.55 : 1)

            if let secondaryButtonTitle {
                Button(secondaryButtonTitle) {
                    HapticsManager.shared.impact(style: .light)
                    Task {
                        await finalizeOnboarding(requestNotifications: false)
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.textColor.opacity(0.75))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 18)
        .background(
            LinearGradient(
                colors: [Color.clear, theme.bottomColor.opacity(theme.isDark ? 0.92 : 0.84)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func handlePrimaryAction() {
        switch currentStep {
        case .welcome, .explore, .style, .location:
            advanceStep()
        case .alerts:
            Task {
                await finalizeOnboarding(requestNotifications: notificationStatus == .notDetermined)
            }
        }
    }

    private func advanceStep() {
        guard let nextStep = Step(rawValue: min(currentStep.rawValue + 1, Step.allCases.count - 1)) else { return }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            currentStep = nextStep
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationStatus = settings.authorizationStatus
    }

    private func persistLocationChoice() {
        switch selectedLocationChoice {
        case .current:
            viewModel.shouldFollowGPS = true
            UserDefaults.standard.set(true, forKey: "Breezy.useGPSLocation")
            UserDefaults.standard.removeObject(forKey: "Breezy.selectedLocation")
        case .manual:
            guard let selectedLocation else { return }
            viewModel.shouldFollowGPS = false
            UserDefaults.standard.set(false, forKey: "Breezy.useGPSLocation")
            if let encoded = try? JSONEncoder().encode(selectedLocation) {
                UserDefaults.standard.set(encoded, forKey: "Breezy.selectedLocation")
            }
            RecentlyViewedStore.add(selectedLocation)
        case nil:
            break
        }
    }

    private func persistNotificationPreferences() {
        UserDefaults.standard.notificationSettings = draftNotificationSettings
        NotificationManager.shared.updateSettings(
            draftNotificationSettings,
            weather: viewModel.weather,
            temperatureUnit: viewModel.temperatureUnit
        )
    }

    private func finalizeOnboarding(requestNotifications: Bool) async {
        isFinishing = true
        persistLocationChoice()
        persistNotificationPreferences()

        if requestNotifications {
            let granted = await NotificationManager.shared.requestAuthorization()
            await refreshNotificationStatus()
            if granted || notificationStatus == .authorized {
                NotificationManager.shared.registerNotificationCategories()
            }
        } else if notificationStatus == .authorized {
            NotificationManager.shared.registerNotificationCategories()
        }

        UserDefaults.standard.set(true, forKey: "Breezy.HasCompletedOnboarding")
        isPresented = false
        isFinishing = false
    }

    private func requestCurrentLocation() {
        Task {
            isRequestingLocation = true
            viewModel.error = nil
            selectedLocation = nil
            do {
                let location = try await locationHelper.requestLocationAndGetData()
                selectedLocation = location
                selectedLocationChoice = .current
                showManualSearch = false
                // Apply immediately: follow GPS and fetch weather so the app is populated before finishing
                viewModel.shouldFollowGPS = true
                await viewModel.fetchWeather(for: location, saveToCache: true)
            } catch {
                showManualSearch = true
                selectedLocationChoice = nil
            }
            isRequestingLocation = false
        }
    }

    private func selectManualLocation(_ completion: MKLocalSearchCompletion) {
        Task {
            do {
                let location = try await searchService.getCoordinates(for: completion)
                selectedLocation = location
                selectedLocationChoice = .manual
                // Apply immediately: switch off GPS and fetch weather for the chosen city
                viewModel.shouldFollowGPS = false
                searchService.searchQuery = ""
                searchFieldFocused = false
                await viewModel.fetchWeather(for: location, saveToCache: true)
            } catch {
                viewModel.error = "Could not load location details."
            }
        }
    }

    private func previewTheme(for preset: WeatherTheme.PresetTheme) -> WeatherTheme {
        switch viewModel.appearanceMode {
        case .light:
            return preset.light
        case .dark:
            return preset.dark
        case .auto:
            return colorScheme == .dark ? preset.dark : preset.light
        }
    }

    private var activeThemeSummary: String {
        switch viewModel.themeMode {
        case .auto:
            return "Weather Reactive"
        case .preset:
            return viewModel.selectedPresetThemeName
        case .custom:
            return "Custom"
        }
    }

    private var locationSummary: String {
        switch selectedLocationChoice {
        case .current:
            return selectedLocation?.city ?? "Current Location"
        case .manual:
            return selectedLocation?.city ?? "Chosen City"
        case nil:
            return "Not set"
        }
    }

    private var notificationSummary: String {
        switch notificationStatus {
        case .authorized:
            return "Ready to send alerts"
        case .denied:
            return "Permission denied, preferences saved"
        default:
            return "Asks on finish"
        }
    }

    @ViewBuilder
    private func welcomeStep(theme: WeatherTheme) -> some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 30)
                    .fill(
                        LinearGradient(
                            colors: [Color.orange, Color.pink, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 170)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                VStack(spacing: 14) {
                    Image(systemName: "cloud.sun.rain.fill")
                        .font(.system(size: 46, weight: .light))
                        .foregroundColor(.white)

                    Text("Breezy")
                        .font(.system(size: 36, weight: .black, design: typographyDesign))
                        .foregroundColor(.white)
                }
            }

            HStack(spacing: 12) {
                onboardingStatCard(title: "Widgets", detail: "Build your own", icon: "square.grid.2x2.fill", theme: theme)
                onboardingStatCard(title: "Radar", detail: "Map-first", icon: "tornado", theme: theme)
                onboardingStatCard(title: "History", detail: "Time Machine", icon: "clock.arrow.circlepath", theme: theme)
            }

            HStack(spacing: 12) {
                onboardingStatCard(title: "Customise", detail: "Change anything", icon: "slider.horizontal.3", theme: theme)
                onboardingStatCard(title: "Font", detail: "Pick a font", icon: "textformat", theme: theme)
                onboardingStatCard(title: "Alerts", detail: "Notifications", icon: "bell.fill", theme: theme) 
            }
        }
    }

    @ViewBuilder
    private func exploreStep(theme: WeatherTheme) -> some View {
        VStack(spacing: 14) {
            featureShowcaseCard(
                title: "Widget Gallery",
                subtitle: "Build dashboards you control.",
                icon: "square.grid.2x2.fill",
                accent: .blue,
                theme: theme
            )

            featureShowcaseCard(
                title: "Time Machine",
                subtitle: "Explore past weather.",
                icon: "clock.arrow.circlepath",
                accent: .purple,
                theme: theme
            )

            featureShowcaseCard(
                title: "Full-Screen Radar",
                subtitle: "Map view for precipitation & layers.",
                icon: "tornado",
                accent: .teal,
                theme: theme
            )

            featureShowcaseCard(
                title: "Deep Daily Detail",
                subtitle: "Fine-grained daily data, configurable.",
                icon: "chart.line.uptrend.xyaxis",
                accent: .orange,
                theme: theme
            )
        }
    }

    @ViewBuilder
    private func styleStep(theme: WeatherTheme) -> some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Appearance")
                    .font(FontScale.headline)
                    .foregroundColor(theme.textColor)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 10) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button {
                            HapticsManager.shared.selectionChanged()
                            viewModel.appearanceMode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(viewModel.appearanceMode == mode ? (theme.isDark ? .black : .white) : theme.textColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(theme.textColor)
                                            .opacity(viewModel.appearanceMode == mode ? 1 : 0)

                                        RoundedRectangle(cornerRadius: 14)
                                            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                                            .opacity(viewModel.appearanceMode == mode ? 0 : 1)
                                    }
                                )
                        }
                    }
                }
            }
            .padding(18)
            .background(onboardingCardBackground(theme: theme))

            VStack(alignment: .leading, spacing: 14) {
                Text("Theme Style")
                    .font(FontScale.headline)
                    .foregroundColor(theme.textColor)
                    .accessibilityAddTraits(.isHeader)

                Button {
                    HapticsManager.shared.selectionChanged()
                    viewModel.themeMode = .auto
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(LinearGradient(colors: [.blue, .cyan, .mint], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 72, height: 72)
                            .overlay(Image(systemName: "cloud.sun.fill").font(.system(size: 28)).foregroundColor(.white))

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Weather Reactive")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(theme.textColor)
                            Text("Shifts with the forecast.")
                                .font(.caption)
                                .foregroundColor(theme.textColor.opacity(0.72))
                        }

                        Spacer()

                        if viewModel.themeMode == .auto {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(theme.textColor)
                        }
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(viewModel.themeMode == .auto ? theme.textColor.opacity(0.9) : theme.textColor.opacity(0.14), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(WeatherTheme.presets, id: \.name) { preset in
                            let preview = previewTheme(for: preset)

                            Button {
                                HapticsManager.shared.selectionChanged()
                                viewModel.selectedPresetThemeName = preset.name
                                viewModel.themeMode = .preset
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(LinearGradient(colors: [preview.topColor, preview.bottomColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 146, height: 126)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 20)
                                                .stroke(viewModel.themeMode == .preset && viewModel.selectedPresetThemeName == preset.name ? theme.textColor : Color.white.opacity(0.18), lineWidth: 2)
                                        )
                                        .overlay(alignment: .topTrailing) {
                                            if viewModel.themeMode == .preset && viewModel.selectedPresetThemeName == preset.name {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundColor(preview.textColor)
                                                    .padding(10)
                                            }
                                        }

                                    Text(preset.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(theme.textColor)
                                }
                            }
                            .buttonStyle(.plain)
                            .scaleEffect(viewModel.selectedPresetThemeName == preset.name && viewModel.themeMode == .preset ? ScaleConstants.selectionScale : 1.0)
                            .animation(AnimationConstants.standardSpring, value: viewModel.selectedPresetThemeName)
                            .animation(AnimationConstants.standardSpring, value: viewModel.themeMode)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .contentMargins(16, for: .scrollContent)
            }
            .padding(18)
            .background(onboardingCardBackground(theme: theme))
        }
    }

    @ViewBuilder
    private func locationStep(theme: WeatherTheme) -> some View {
        VStack(spacing: 18) {
            Button {
                HapticsManager.shared.impact(style: .light)
                requestCurrentLocation()
            } label: {
                ZStack {
                    locationChoiceCard(
                        title: isRequestingLocation ? "Checking your location..." : "Use Current Location",
                        subtitle: "Best for forecasts that follow you automatically.",
                        icon: "location.fill",
                        accent: .blue,
                        isSelected: selectedLocationChoice == .current,
                        theme: theme
                    )
                    .opacity(isRequestingLocation ? 0.5 : 1.0)
                    
                    if isRequestingLocation {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(selectedLocationChoice == .current ? 1.02 : 1.0)
            .animation(AnimationConstants.standardSpring, value: selectedLocationChoice)
            .animation(Animation.easeOut(duration: AnimationConstants.quick), value: isRequestingLocation)

            VStack(spacing: 12) {
                Button {
                    HapticsManager.shared.impact(style: .light)
                    withAnimation(AnimationConstants.standardSpring) {
                        showManualSearch = true
                        selectedLocationChoice = .manual
                        selectedLocation = nil
                    }
                    searchFieldFocused = true
                } label: {
                    locationChoiceCard(
                        title: "Search Manually",
                        subtitle: "Great if you track another city or do not want GPS.",
                        icon: "magnifyingglass",
                        accent: .purple,
                        isSelected: selectedLocationChoice == .manual || showManualSearch,
                        theme: theme
                    )
                }
                .buttonStyle(.plain)
                .scaleEffect(selectedLocationChoice == .manual || showManualSearch ? 1.02 : 1.0)
                .animation(AnimationConstants.standardSpring, value: selectedLocationChoice)
                .animation(AnimationConstants.standardSpring, value: showManualSearch)

                if showManualSearch {
                    manualLocationSearch(theme: theme)
                }
            }

            if let selectedLocation {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ready to start with")
                        .font(.caption.weight(.bold))
                        .foregroundColor(theme.textColor.opacity(0.64))

                    HStack(spacing: 12) {
                        Image(systemName: selectedLocationChoice == .current ? "location.fill" : "mappin.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(theme.textColor)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(selectedLocation.city)
                                .font(.headline)
                                .foregroundColor(theme.textColor)
                            Text(selectedLocation.coordinateString)
                                .font(.caption)
                                .foregroundColor(theme.textColor.opacity(0.68))
                        }

                        Spacer()
                    }
                }
                .padding(16)
                .background(onboardingCardBackground(theme: theme))
            }

            Group {
                if let errorText = locationHelper.locationError, selectedLocation == nil {
                    shakeableContent(if: shakeError) {
                        Text(errorText)
                            .font(FontScale.caption)
                            .foregroundColor(theme.textColor.opacity(0.74))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                            .transition(.opacity)
                            .id(errorText)
                    }
                }
            }
            .onChange(of: locationHelper) { _, _ in
                shakeError = false
            }
        }
    }

    @ViewBuilder
    private func manualLocationSearch(theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(theme.textColor.opacity(0.68))

                TextField("Search city or postcode", text: $searchService.searchQuery)
                    .focused($searchFieldFocused)
                    .foregroundColor(theme.textColor)

                if !searchService.searchQuery.isEmpty {
                    Button {
                        HapticsManager.shared.impact(style: .light)
                        searchService.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(theme.textColor.opacity(0.62))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(theme.textColor.opacity(0.12), lineWidth: 0.5)
                    )
            )

            if !searchService.completions.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(searchService.completions.prefix(5)), id: \.self) { completion in
                        Button {
                            HapticsManager.shared.impact(style: .light)
                            selectManualLocation(completion)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(theme.textColor.opacity(0.76))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(theme.textColor)
                                        .multilineTextAlignment(.leading)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundColor(theme.textColor.opacity(0.68))
                                    }
                                }

                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color.white.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !searchService.searchQuery.isEmpty {
                Text(searchStatusText)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.7))
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(onboardingCardBackground(theme: theme))
    }

    private var searchStatusText: String {
        switch searchService.status {
        case .idle:
            return "Start typing to find a city."
        case .searching:
            return "Searching..."
        case .noResults:
            return "No results yet. Try a nearby city or postcode."
        case .error(let message):
            return message
        }
    }

    @ViewBuilder
    private func alertsStep(theme: WeatherTheme) -> some View {
        VStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Starter Alerts")
                    .font(.headline)
                    .foregroundColor(theme.textColor)

                onboardingToggleRow(
                    title: "Daily Forecast",
                    subtitle: "Daily forecast.",
                    icon: "sunrise.fill",
                    accent: .orange,
                    isOn: Binding(
                        get: { draftNotificationSettings.dailyForecastEnabled },
                        set: { draftNotificationSettings.dailyForecastEnabled = $0 }
                    ),
                    theme: theme
                )

                onboardingToggleRow(
                    title: "Severe Weather",
                    subtitle: "Critical alerts.",
                    icon: "exclamationmark.triangle.fill",
                    accent: .red,
                    isOn: Binding(
                        get: { draftNotificationSettings.severeWeatherEnabled },
                        set: { draftNotificationSettings.severeWeatherEnabled = $0 }
                    ),
                    theme: theme
                )

                onboardingToggleRow(
                    title: "Rain Alerts",
                    subtitle: "Rain heads-up.",
                    icon: "cloud.rain.fill",
                    accent: .blue,
                    isOn: Binding(
                        get: { draftNotificationSettings.rainAlertsEnabled },
                        set: { draftNotificationSettings.rainAlertsEnabled = $0 }
                    ),
                    theme: theme
                )

                onboardingToggleRow(
                    title: "UV Alerts",
                    subtitle: "UV exposure.",
                    icon: "sun.max.fill",
                    accent: .yellow,
                    isOn: Binding(
                        get: { draftNotificationSettings.uvAlertsEnabled },
                        set: { draftNotificationSettings.uvAlertsEnabled = $0 }
                    ),
                    theme: theme
                )
            }
            .padding(18)
            .background(onboardingCardBackground(theme: theme))

            // Inform users they can change these later in Settings
            Text("You can change any of these choices later in Settings.")
                .font(.caption)
                .foregroundColor(theme.textColor.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, 6)

            // Setup summary removed to reduce density per request

            if notificationStatus == .denied {
                Text("Notifications are currently denied at the system level, so Breezy cannot show the permission prompt again right now. Your alert choices are still saved.")
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.74))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
    }

    private func onboardingCardBackground(theme: WeatherTheme) -> some View {
        RoundedRectangle(cornerRadius: 24)
            .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(theme.textColor.opacity(0.12), lineWidth: 0.6)
            )
    }

    private func onboardingStatCard(title: String, detail: String, icon: String, theme: WeatherTheme) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(theme.textColor)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.textColor)

            Text(detail)
                .font(.caption)
                .foregroundColor(theme.textColor.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(onboardingCardBackground(theme: theme))
    }

    private func featureShowcaseCard(title: String, subtitle: String, icon: String, accent: Color, theme: WeatherTheme) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(accent.opacity(0.24))
                    .frame(width: 58, height: 58)
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(theme.textColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.72))
            }

            Spacer()
        }
        .padding(16)
        .background(onboardingCardBackground(theme: theme))
    }

    private func locationChoiceCard(title: String, subtitle: String, icon: String, accent: Color, isSelected: Bool, theme: WeatherTheme) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.24))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.72))
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(theme.textColor)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(viewModel.glassOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(isSelected ? theme.textColor.opacity(0.88) : theme.textColor.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func onboardingToggleRow(title: String, subtitle: String, icon: String, accent: Color, isOn: Binding<Bool>, theme: WeatherTheme) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(accent.opacity(0.22))
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(theme.textColor)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(theme.textColor.opacity(0.68))
            }

            Spacer()

            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(accent)
                .onChange(of: isOn.wrappedValue) { oldValue, newValue in
                    HapticsManager.shared.impact(style: .light)
                }
                .accessibilityHint("Double tap to enable or disable \(title)")
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func summaryRow(title: String, value: String, icon: String, theme: WeatherTheme) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.textColor.opacity(0.76))
                .frame(width: 24)

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(theme.textColor.opacity(0.78))

            Spacer()

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(theme.textColor)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct StaggeredAnimationModifier: ViewModifier {
    let index: Int
    @State private var isVisible = false
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 20)
            .animation(
                Animation.easeOut(duration: 0.4)
                    .delay(Double(index) * StaggerDelay.step),
                value: isVisible
            )
            .onAppear {
                isVisible = true
            }
    }
}

struct ShakeModifier: ViewModifier {
    @State private var offset: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: 0.05).repeatCount(6, autoreverses: true)) {
                    offset = 10
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    offset = 0
                }
            }
    }
}

@ViewBuilder
private func shakeableContent(if shouldShake: Bool, @ViewBuilder content: () -> some View) -> some View {
    if shouldShake {
        content().shake()
    } else {
        content()
    }
}

extension View {
    func staggeredAnimation(index: Int) -> some View {
        modifier(StaggeredAnimationModifier(index: index))
    }
    
    func shake() -> some View {
        modifier(ShakeModifier())
    }
}

#Preview {
    OnboardingView(
        isPresented: .constant(true),
        viewModel: WeatherViewModel(),
        locationHelper: LocationHelper()
    )
}
