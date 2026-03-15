# How to Run & Verify Watch Sync

Follow this exact order to ensure the Simulator environment is clean and connected.

## 1. Clean Slate (Recommended)
1.  **Close the Simulator** completely if it's lagging.
2.  In Xcode, go to `Product` > `Clean Build Folder` (Cmd+Shift+K).

## 2. Launch Watch App FIRST
1.  Select the **Breezy Watch Watch App** scheme in Xcode.
2.  Press Run (**Cmd+R**).
3.  Wait for the Watch Simulator to launch and show the weather/loading spinner.
4.  **KEEP THIS WINDOW OPEN AND AWAKE.** (Don't let it go to sleep or lock).

## 3. Launch iPhone App SECOND
1.  Select the **Breezy** (iOS) scheme in Xcode.
2.  Press Run (**Cmd+R**).
3.  Wait for the iPhone app to launch.

## 4. Verify in Logs (Bottom Right of Xcode)
Look for these lines in order:

1.  `⌚️ WATCH: Activation complete.`
2.  `📱 PHONE: Activation complete.`
3.  `📱 PHONE-VM: Session Active callback received. Syncing context.`
4.  **`📱 PHONE: Attempting sync... Reachable: true`**
5.  **`⌚️ WATCH: Received INSTANT message...`**

## 5. Test Live Sync
1.  On iPhone: Go to **Settings** -> **Design Studio**.
2.  Change **Theme** to "Cotton Candy" (or any other).
3.  **Result:** The Watch background should change color INSTANTLY (within 0.5s).

> **Note:** If `Reachable` is `false`, it means the Watch Simulator thinks it's disconnected or sleeping. Click on the Watch Simulator window to wake it up, and try changing a setting on the iPhone again.
