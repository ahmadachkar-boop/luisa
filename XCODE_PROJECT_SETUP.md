# Creating the Xcode Project - Step by Step 🎯

The source files are ready, but we need to create the Xcode project properly. Follow these steps exactly:

## Step 1: Create New Xcode Project

1. Open **Xcode** on your Mac
2. Click **"Create New Project"** (or File → New → Project)
3. Under **iOS**, select **"App"**
4. Click **"Next"**

## Step 2: Configure Your App

Fill in these details:

- **Product Name**: `OurApp`
- **Team**: Select your Apple ID
- **Organization Identifier**: `com.yourname` (or use your actual name, like `com.ahmad`)
- **Bundle Identifier**: This will auto-fill as `com.yourname.OurApp` - **remember this!**
- **Interface**: Select **SwiftUI** (very important!)
- **Language**: Swift
- **Storage**: None
- **Include Tests**: Uncheck both boxes (we don't need them)

Click **"Next"**

## Step 3: Choose Save Location

1. Navigate to: `/Users/ahmadachkar/luisa/`
2. You'll see there's already an `OurApp` folder - **that's okay!**
3. Name it `OurApp` (Xcode will merge with the existing folder)
4. Make sure **"Create Git repository"** is UNCHECKED (we already have one)
5. Click **"Create"**

## Step 4: Delete Template Files

Xcode created some template files we don't need. In the left sidebar (Project Navigator):

1. Right-click `OurAppApp.swift` → Delete → **"Move to Trash"**
2. Right-click `ContentView.swift` → Delete → **"Move to Trash"**
3. Right-click `Assets.xcassets` → Delete → **"Move to Trash"**

## Step 5: Add Our Files

Now we'll add the files I created for you:

1. In Finder, navigate to `/Users/ahmadachkar/luisa/OurApp/OurApp/`
2. You should see all the Swift files (OurAppApp.swift, ContentView.swift, etc.)
3. Drag ALL these files into Xcode's Project Navigator (the left sidebar)
   - OurAppApp.swift
   - ContentView.swift
   - Models.swift
   - FirebaseManager.swift
   - VoiceMessagesView.swift
   - PhotoGalleryView.swift
   - CalendarView.swift
   - Assets.xcassets (folder)
   - Info.plist

4. When prompted:
   - ✅ Check **"Copy items if needed"**
   - ✅ Make sure **"OurApp" target is selected**
   - Click **"Finish"**

## Step 6: Add Firebase SDK

1. In Xcode, go to **File** → **Add Package Dependencies...**
2. In the search box (top right), paste:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```
3. Click **"Add Package"**
4. Wait for it to load, then select these packages:
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage
   - ✅ FirebaseAuth
5. Click **"Add Package"**
6. Wait for it to download (may take a minute)

## Step 7: Update Info.plist Settings

1. Click on the blue **"OurApp"** project icon at the top of the left sidebar
2. Select **"OurApp"** under TARGETS
3. Click the **"Info"** tab
4. You should see the microphone and photo permissions already there from our Info.plist
5. If not, click the **+** button and add:
   - **Privacy - Microphone Usage Description**: `We need access to your microphone to record voice messages for your loved one 💜`
   - **Privacy - Photo Library Usage Description**: `We need access to your photos to add memories to your shared gallery 📸`

## Step 8: Configure Bundle Identifier

1. Still in project settings, click **"Signing & Capabilities"** tab
2. Under **Bundle Identifier**, it should show `com.yourname.OurApp`
3. **Important**: Remember this exact Bundle ID for Firebase setup!
4. Select your **Team** (your Apple ID)
5. Make sure **"Automatically manage signing"** is checked

## Step 9: Set Up Firebase

Now follow the Firebase setup from SETUP_GUIDE.md starting at "Step 2: Set Up Firebase"

**Critical**: When you create your iOS app in Firebase, use the EXACT Bundle ID from Step 8!

## Step 10: Add GoogleService-Info.plist

1. After downloading `GoogleService-Info.plist` from Firebase
2. Drag it into Xcode's Project Navigator
3. Make sure:
   - ✅ **"Copy items if needed"** is checked
   - ✅ **"OurApp" target** is selected
4. Click **"Finish"**

## Step 11: Add Widget Extension (IMPORTANT!)

For the countdown widget to appear on the home screen, you must add it as a separate target:

### 11.1: Create Widget Extension Target

1. In Xcode, go to **File** → **New** → **Target...**
2. Search for **"Widget Extension"** and select it
3. Click **Next**
4. Configure the widget:
   - **Product Name**: `OurAppWidget`
   - **Team**: Same as your main app
   - **Bundle Identifier**: Will auto-fill (e.g., `com.yourname.OurApp.OurAppWidget`)
   - **Include Live Activity**: Uncheck this
   - **Include Configuration App Intent**: Uncheck this
5. Click **Finish**
6. If prompted to activate the scheme, click **Activate**

### 11.2: Delete Template Widget Files

Xcode creates template files we don't need:

1. In the left sidebar, expand the new **OurAppWidget** folder
2. Delete ALL the template Swift files Xcode created (OurAppWidget.swift, etc.)
3. Keep the **Assets.xcassets** folder

### 11.3: Add Our Widget Files

1. From `/OurApp/OurAppWidget/` folder, drag these files into the OurAppWidget target:
   - `CountdownWidget.swift`
   - `Info.plist`
   - `OurAppWidget.entitlements`
2. When prompted:
   - Check **"Copy items if needed"**
   - Make sure **"OurAppWidget" target** is selected
   - Click **Finish**

### 11.4: Configure Widget Info.plist

1. Click on the blue **OurApp** project icon
2. Select **OurAppWidget** under TARGETS
3. Click **Build Settings** tab
4. Search for "Info.plist"
5. Set **Info.plist File** to: `OurAppWidget/Info.plist`

### 11.5: Add App Group Capability (CRITICAL!)

Both the main app AND widget need the same App Group to share data:

**For Main App:**
1. Select **OurApp** target → **Signing & Capabilities**
2. Click **+ Capability** → **App Groups**
3. Click **+** and add: `group.com.ourapp`

**For Widget:**
1. Select **OurAppWidget** target → **Signing & Capabilities**
2. Click **+ Capability** → **App Groups**
3. Click **+** and add the SAME group: `group.com.ourapp`

### 11.6: Set Widget Entitlements

1. Select **OurAppWidget** target
2. Click **Build Settings** tab
3. Search for "Code Signing Entitlements"
4. Set to: `OurAppWidget/OurAppWidget.entitlements`

## Step 12: Build and Run!

1. Select a simulator from the device dropdown (e.g., "iPhone 15 Pro")
2. Click the ▶️ Play button (or press Cmd+R)
3. Wait for it to build and launch!

---

## Troubleshooting

### "No such module 'FirebaseFirestore'"
- Make sure you completed Step 6 (Add Firebase SDK)
- Try cleaning the build: **Product** → **Clean Build Folder** (Shift+Cmd+K)
- Restart Xcode

### "Multiple commands produce 'OurApp.app'"
- You might have duplicate files
- Check that you deleted the template files in Step 4

### Still not working?
- Create a completely fresh project in a different location
- Then manually copy over just the Swift files (not the whole folder)

### Widget Not Appearing in Widget Gallery?
- Make sure you completed Step 11 (Add Widget Extension)
- Verify both app and widget have the SAME App Group: `group.com.ourapp`
- Check that the widget target has `Info.plist` with `NSExtensionPointIdentifier: com.apple.widgetkit-extension`
- Clean build folder: **Product** → **Clean Build Folder**
- Delete the app from simulator/device and reinstall
- Make sure the widget scheme is embedded in the main app (check "Embed in Application" in widget target settings)

---

Once you get it running, check out SETUP_GUIDE.md for the complete Firebase configuration!
