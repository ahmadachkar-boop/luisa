# Dynamic Island Setup Guide

This guide will help you set up the Live Activities feature to display your upcoming events in the iOS Dynamic Island.

## Requirements

- iOS 16.1 or later
- iPhone 14 Pro, iPhone 14 Pro Max, iPhone 15 Pro, or iPhone 15 Pro Max (devices with Dynamic Island)
- Xcode 14.1 or later

## Step-by-Step Setup in Xcode

### 1. Create a Widget Extension Target

1. Open your project in **Xcode**
2. Go to **File → New → Target**
3. In the template chooser:
   - Select **iOS** at the top
   - Scroll down to find **Widget Extension**
   - Click **Next**
4. Configure your widget:
   - **Product Name**: `OurAppWidgets` (or your preferred name)
   - **Team**: Select your development team
   - **Include Configuration Intent**: **UNCHECK this box** (we don't need it)
   - Click **Finish**
5. When prompted "Activate 'OurAppWidgets' scheme?", click **Activate**

### 2. Add Files to Widget Extension Target

**CRITICAL STEP** - This is the most common cause of the "unsupportedTarget" error!

The following files MUST be added to your Widget Extension target:

1. **EventActivityAttributes.swift** - Must be in BOTH targets
2. **EventLiveActivity.swift** - Must be in BOTH targets
3. **LiveActivityManager.swift** - Only needs to be in main app target

#### How to add files to the Widget Extension:

1. In Xcode's **Project Navigator** (left sidebar), locate these files:
   - `EventActivityAttributes.swift`
   - `EventLiveActivity.swift`

2. **For EventActivityAttributes.swift**:
   - Click on the file
   - Open **File Inspector** (View → Inspectors → Show File Inspector, or right sidebar first tab)
   - Find **Target Membership** section
   - ✅ Check **OurApp** (should already be checked)
   - ✅ Check **OurAppWidgets** (THIS IS CRITICAL!)

3. **For EventLiveActivity.swift**:
   - Click on the file
   - Open **File Inspector**
   - Find **Target Membership** section
   - ✅ Check **OurApp** (should already be checked)
   - ✅ Check **OurAppWidgets** (THIS IS CRITICAL!)

4. **Verify the checkmarks**:
   - Both files should have TWO checkmarks ✅✅
   - One for OurApp, one for OurAppWidgets

**Screenshot guidance**: You should see both checkboxes selected for each file!

### 3. Configure App Groups (Optional but Recommended)

If you want to share data between your main app and the widget extension:

1. Select your **project** in the Project Navigator
2. Select the **main app target** (OurApp)
3. Go to **Signing & Capabilities** tab
4. Click **+ Capability** and add **App Groups**
5. Click the **+** button and create: `group.com.yourcompany.ourapp`
6. Repeat steps 2-5 for the **OurAppWidgets** target

### 4. Update Widget Bundle File

After creating the widget extension, Xcode creates a file like `OurAppWidgets.swift`. You need to register your Live Activity widget:

1. Open `OurAppWidgets.swift` (or similar name in your widget extension folder)
2. Replace its contents with:

```swift
import WidgetKit
import SwiftUI

@main
struct OurAppWidgetsBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            EventLiveActivity()
        }
    }
}
```

### 5. Build and Run

1. **Select your main app target** (not the widget extension) from the scheme selector
2. **Build** the project (Cmd + B) to check for errors
3. **Run** on a device with Dynamic Island (iPhone 14 Pro or newer)
   - **Note**: The simulator doesn't fully support Dynamic Island testing

### 6. Testing the Live Activity

Once running on a device:

1. Open the app and navigate to the Calendar page
2. Make sure you have at least one upcoming event
3. The Live Activity should automatically start and appear in the Dynamic Island
4. Tap the Dynamic Island to expand it and see full details
5. Swipe left/right in the expanded view to navigate between events (if you have multiple)
6. Tap the Dynamic Island when compact to open the event in the app

## Troubleshooting

### Error: "unsupportedTarget" or "Failed to start Live Activity"

This is the #1 most common error! It means the files aren't properly added to the Widget Extension.

**Fix:**

1. **Open Xcode File Inspector** for these files:
   - `EventActivityAttributes.swift`
   - `EventLiveActivity.swift`

2. **For EACH file above:**
   - Select the file in Project Navigator
   - Open File Inspector (⌥⌘1 or View → Inspectors → File)
   - Scroll to **Target Membership**
   - **BOTH boxes must be checked:**
     - ✅ OurApp
     - ✅ OurAppWidgets (or whatever you named your widget extension)

3. **After fixing:**
   - Clean build folder: **Product → Clean Build Folder** (⌘⇧K)
   - Rebuild: **Product → Build** (⌘B)
   - Run on device

**Still not working?** Make sure you created the Widget Extension target (Step 1 above).

### Live Activity Not Appearing

1. **Check device**: Make sure you're using iPhone 14 Pro or newer
2. **Check iOS version**: Must be iOS 16.1 or later
3. **Check Info.plist**: Verify `NSSupportsLiveActivities` is set to `YES`
4. **Check target membership**: Ensure EventActivityAttributes.swift and EventLiveActivity.swift are in BOTH targets
5. **Rebuild**: Clean build folder (Cmd + Shift + K) then rebuild (Cmd + B)

### Compilation Errors

If you get errors about missing modules:

1. Make sure `EventLiveActivity.swift` is added to the **OurAppWidgets** target
2. Make sure `EventActivityAttributes.swift` is added to **both** the main app and widget targets
3. Clean and rebuild

### Widget Not Updating

- Live Activities update automatically when the app calls `updateLiveActivity()`
- This happens when:
  - The view appears
  - The upcoming events list changes
  - You can also manually trigger updates

## Features

Your Dynamic Island Live Activity shows:

- **Compact State**: Event icon (left) and countdown (right)
- **Expanded State**:
  - Event name and icon (left)
  - Countdown and date (right)
  - Navigation buttons to switch between events
  - Event counter (showing "Event 2 of 5")
- **Tap to Open**: Tapping opens the full event detail in your app
- **Auto-Update**: Countdown updates automatically

## Managing Live Activities

The Live Activity will:
- **Start** automatically when you open the Calendar page (if you have upcoming events)
- **Update** automatically when events change
- **Persist** even when you close the app
- **Dismiss** manually by long-pressing and selecting "Remove"

You can also programmatically end it by calling:
```swift
LiveActivityManager.shared.endLiveActivity()
```

## Next Steps

After setup, you can customize:
- Colors and styling in `EventLiveActivity.swift`
- Update frequency in `LiveActivityManager.swift`
- Add more interactive buttons or controls
- Customize the expanded view layout

Enjoy your Dynamic Island integration! 🎉
