# Apple Watch App Setup Instructions

## Steps to Add Watch App to Xcode Project

1. **Open Xcode** and open the Breezy project

2. **Add Watch App Target:**
   - File → New → Target
   - Select "watchOS" → "App"
   - In the dialog that appears:
     - **Product Name:** `BreezyWatch Watch App` (or just `BreezyWatch`)
     - **Team:** Select your team (e.g., "Idearium Pty Ltd")
     - **Organization Identifier:** Should match your iOS app's organization identifier (likely `com.breezy.weather` - check your iOS app's bundle identifier to confirm)
     - **Bundle Identifier:** Should auto-populate as `com.breezy.weather.watchkitapp` (Xcode will add `.watchkitapp` to your org identifier)
       - ⚠️ If it shows something like `com.breezy.weather.watchkitapp.Breezy`, that's incorrect - it should just be `com.breezy.weather.watchkitapp`
     - **Watch App Type:** Select **"Watch App for Existing iOS App"** ✓ (This is correct!)
     - **Existing iOS App:** Select **"Breezy"** from the dropdown ✓ (This is correct!)
     - **Testing System:** Leave as "None" (or select if you want testing)
   - Click **"Finish"**
   
   **Note:** If the Bundle Identifier looks wrong, you can manually edit it to be `com.breezy.weather.watchkitapp` (without any extra suffixes)

3. **Configure App Group:**
   - Select the Watch App target in the project navigator
   - Go to "Signing & Capabilities" tab
   - Click "+ Capability"
   - Add "App Groups"
   - Check the box and add `group.com.breezy.weather` (same as iOS app)
   - Make sure it matches the iOS app's App Group exactly

4. **Add Files to Target:**
   - Drag all files from the `BreezyWatch Watch App/` folder into the Watch App target in Xcode
   - Make sure they're added to the correct target (the Watch App target, not the iOS app)
   - Verify `BreezyWatchApp.swift` is set as the main entry point (should have `@main` attribute)

5. **Configure Entitlements:**
   - The `BreezyWatch.entitlements` file should be automatically linked
   - If not, go to Build Settings → Code Signing Entitlements and set it to `BreezyWatch.entitlements`
   - Verify App Group is configured in both iOS and Watch targets

6. **Build and Run:**
   - Select the Watch App scheme from the scheme dropdown
   - Select a paired Apple Watch or Watch simulator as the run destination
   - Build and run (⌘R)

## Features

- **Main View:** Shows current weather, temperature, condition, and next 3 hours
- **Pull to Refresh:** Swipe down to refresh weather data
- **Complications:** Multiple complication styles supported
- **Data Sharing:** Uses App Group to share data with iOS app

## Notes

- The Watch app reads weather data from the same App Group as widgets
- Weather data is updated when the iOS app fetches new data
- Complications update automatically when weather data changes

