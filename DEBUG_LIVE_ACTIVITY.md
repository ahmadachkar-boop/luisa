# Debug Live Activity "unsupportedTarget" Error

Run through this checklist step-by-step to fix the error.

## Step 1: Verify Widget Extension Exists

1. In Xcode, look at the **Project Navigator** (left sidebar)
2. You should see a folder called `OurAppWidgets` (or whatever you named it)
3. If you DON'T see this folder, you need to create the Widget Extension:
   - File → New → Target → Widget Extension

**If you don't have the Widget Extension, STOP and create it first!**

## Step 2: Check Target Membership (CRITICAL!)

### For EventActivityAttributes.swift:

1. Select `EventActivityAttributes.swift` in Project Navigator
2. Open File Inspector (⌥⌘1)
3. Scroll to **Target Membership**
4. **Verify BOTH are checked:**
   - ☑️ OurApp
   - ☑️ OurAppWidgets

### For EventLiveActivity.swift:

1. Select `EventLiveActivity.swift` in Project Navigator
2. Open File Inspector (⌥⌘1)
3. Scroll to **Target Membership**
4. **Verify BOTH are checked:**
   - ☑️ OurApp
   - ☑️ OurAppWidgets

**If either file is missing a checkmark, CHECK IT NOW and rebuild!**

## Step 3: Verify Widget Bundle Configuration

1. In the `OurAppWidgets` folder, find the main Swift file (usually `OurAppWidgets.swift`)
2. It should look EXACTLY like this:

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

3. **Important checks:**
   - There should be only ONE `@main` in the entire file
   - There should be only ONE `struct OurAppWidgetsBundle`
   - The body should reference `EventLiveActivity()`

**If your file looks different, fix it to match the above!**

## Step 4: Check Info.plist

1. Open `OurApp/Info.plist` (the main app's Info.plist)
2. Verify it contains:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

3. If it's missing, add it

## Step 5: Clean Build

After making any changes:

1. **Product → Clean Build Folder** (⌘⇧K)
2. **Product → Build** (⌘B)
3. Fix any compilation errors
4. **Run** on a physical iPhone 14 Pro or newer

## Step 6: Check Console Logs

After running the app with the updated debug code:

1. Open the **Console** app on your Mac
2. Connect your iPhone
3. Filter by your app name
4. Look for the debug output that starts with "🔍 Live Activity Debug:"
5. Share the complete output

The debug output will tell us:
- If activities are enabled
- The exact error code
- Specific guidance on what's wrong

## Step 7: Verify Device Requirements

Make sure:
- ✅ Device is iPhone 14 Pro, 15 Pro, or newer (has Dynamic Island hardware)
- ✅ iOS version is 16.1 or later
- ✅ Running on a REAL device (not simulator)

## Step 8: Verify Bundle Identifiers

1. Select your project in Project Navigator
2. Select **OurApp** target
3. Note the **Bundle Identifier** (e.g., `com.yourname.OurApp`)
4. Select **OurAppWidgets** target
5. The Bundle Identifier should be: `com.yourname.OurApp.OurAppWidgets` (parent + extension name)

**They MUST follow this pattern!**

## Common Issues and Fixes

### Issue: "EventLiveActivity not found"
**Fix:** EventLiveActivity.swift is not in the OurAppWidgets target. Go to Step 2.

### Issue: "Widget extension not found"
**Fix:** You didn't create the Widget Extension target. Go to Step 1.

### Issue: "Activities not enabled"
**Fix:** Check Settings → Your App → Live Activities is enabled

### Issue: "Multiple @main attributes"
**Fix:** You have two @main declarations in OurAppWidgets.swift. Keep only one. Go to Step 3.

## Still Not Working?

Run the app with the updated debug code and share:

1. The complete console output starting with "🔍 Live Activity Debug:"
2. Your iOS version
3. Your iPhone model
4. Screenshots of:
   - Target Membership for EventActivityAttributes.swift
   - Target Membership for EventLiveActivity.swift
   - Your OurAppWidgets.swift file contents
