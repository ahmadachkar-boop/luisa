# Quick Setup Guide 💜

This is a step-by-step guide to get your app running!

## Step 1: Install Xcode (if you haven't already)

1. Open the App Store on your Mac
2. Search for "Xcode"
3. Click "Get" or "Install"
4. Wait for it to download (it's large, ~10GB)

## Step 2: Set Up Firebase (Free!)

### 2.1 Create Firebase Project

1. Go to https://console.firebase.google.com
2. Click "Add project"
3. Name it something cute like "OurApp" or "UsTwo"
4. You can disable Google Analytics (we don't need it)
5. Click "Create project"

### 2.2 Add iOS App

1. In your Firebase project, click the iOS icon (⚙️)
2. For **iOS bundle ID**, enter: `com.yourname.ourapp`
   - You can change "yourname" to your actual name
   - Remember this! You'll need it later
3. App nickname: "Us" (or whatever you want)
4. Click "Register app"

### 2.3 Download Configuration File

1. Click "Download GoogleService-Info.plist"
2. Keep this file handy - you'll need it in a moment!

### 2.4 Enable Firestore Database

1. In Firebase Console, click "Build" in the left sidebar
2. Click "Firestore Database"
3. Click "Create database"
4. Choose "Start in **production mode**" (don't worry, we'll make it secure)
5. Choose a location close to you
6. Click "Enable"

### 2.5 Configure Firestore Rules

1. Click the "Rules" tab
2. Delete everything and paste this:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

3. Click "Publish"

⚠️ Note: This allows anyone with your Firebase URL to access your data. Since this is just for you two and you're not sharing the Firebase credentials, it's fine. For better security, add authentication later!

### 2.6 Enable Firebase Storage

1. Click "Build" > "Storage"
2. Click "Get started"
3. Choose "Start in **production mode**"
4. Click "Next"
5. Choose the same location as Firestore
6. Click "Done"

### 2.7 Configure Storage Rules

1. Click the "Rules" tab
2. Delete everything and paste this:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if true;
    }
  }
}
```

3. Click "Publish"

## Step 3: Open the Project in Xcode

1. Navigate to the `OurApp` folder
2. Double-click `OurApp.xcodeproj`
3. Xcode should open automatically

## Step 4: Add Your Firebase Configuration

1. In Xcode, look at the left sidebar (Project Navigator)
2. Find `GoogleService-Info.plist` under the OurApp folder
3. Delete the placeholder file
4. Drag your downloaded `GoogleService-Info.plist` into the same location
5. Make sure "Copy items if needed" is checked
6. Click "Finish"

## Step 5: Add Firebase SDK

1. In Xcode, go to **File** > **Add Package Dependencies...**
2. In the search box at the top right, paste: `https://github.com/firebase/firebase-ios-sdk`
3. Click "Add Package"
4. Select these packages:
   - ✅ FirebaseFirestore
   - ✅ FirebaseStorage
   - ✅ FirebaseAuth (optional, for future use)
5. Click "Add Package"
6. Wait for it to download

## Step 6: Configure Project Settings

1. Click on "OurApp" at the very top of the left sidebar (the blue icon)
2. Make sure "OurApp" is selected under TARGETS
3. Click the "Signing & Capabilities" tab

### Update Bundle Identifier
1. Under "Bundle Identifier", change it to match what you entered in Firebase
   - Example: `com.yourname.ourapp`
2. Make sure it matches EXACTLY

### Set Up Signing
1. Under "Team", click the dropdown
2. Select your Apple ID
   - If you don't see your Apple ID, click "Add an Account..." and sign in
3. Make sure "Automatically manage signing" is checked

## Step 7: Run the App!

### On Simulator (Easiest)
1. At the top of Xcode, click the device dropdown (it might say "My Mac")
2. Select any iPhone simulator (e.g., "iPhone 15 Pro")
3. Click the ▶️ Play button (or press ⌘R)
4. Wait for the simulator to launch and the app to install

### On Your Actual iPhone
1. Connect your iPhone to your Mac with a cable
2. Unlock your iPhone
3. If prompted, tap "Trust This Computer"
4. In Xcode, select your iPhone from the device dropdown
5. Click the ▶️ Play button
6. On your iPhone, go to Settings > General > VPN & Device Management
7. Tap on your Apple ID and tap "Trust"
8. Go back and launch the app!

## Step 8: Grant Permissions

When you first run the app:
1. It will ask for **Microphone** permission
   - Tap "OK" or "Allow"
   - This is needed for voice messages
2. When you try to add a photo, it will ask for **Photos** permission
   - Tap "OK" or "Allow"
   - This is needed for the photo gallery

## Step 9: Test It Out!

### Test Voice Messages
1. Tap the "Voice Notes" tab (microphone icon)
2. Tap the + button
3. Tap the red record button
4. Say something sweet!
5. Tap the button again to stop
6. Enter a title
7. Tap "Save Recording"
8. Tap play to hear it back!

### Test Photos
1. Tap the "Our Photos" tab (heart icon)
2. Tap the + button
3. Select a photo
4. It should appear in the grid!

### Test Calendar
1. Tap the "Our Plans" tab (calendar icon)
2. Tap the + button
3. Add an upcoming date
4. Toggle "Special Event" for something important
5. Tap "Save"

## Step 10: Install on Your Girlfriend's Phone

### Option 1: Using Xcode (Easiest)
1. Connect her iPhone to your Mac
2. In Xcode, select her iPhone from the device list
3. Click ▶️ to run
4. Follow the same "Trust" steps from Step 7

### Option 2: Using TestFlight (Better for Long-term)
1. In Xcode, go to Product > Archive
2. Once archived, click "Distribute App"
3. Select "TestFlight & App Store"
4. Follow the prompts to upload to TestFlight
5. In App Store Connect, add her as a tester
6. She'll receive an email to install via TestFlight

### Option 3: App Store (Most Professional)
1. Complete the TestFlight setup
2. Create an App Store listing
3. Submit for review
4. Once approved, she can download it like any app!

## Troubleshooting

### "Signing for 'OurApp' requires a development team"
- Make sure you've selected your Apple ID under Team in Step 6

### "Failed to register bundle identifier"
- The bundle ID might already be taken
- Try changing it to something unique like `com.yourname.ourappcute`
- Remember to update it in Firebase too!

### "GoogleService-Info.plist not found"
- Make sure you replaced the placeholder file in Step 4
- Check that it's included in the target (right-click file > Show File Inspector > Target Membership)

### Voice recording isn't working
- Make sure you granted microphone permission
- Go to Settings > Privacy & Security > Microphone > OurApp > Enable

### Photos aren't uploading
- Check your internet connection
- Make sure Firebase Storage is enabled
- Check that you granted photo library permission

### App crashes on launch
- Check that GoogleService-Info.plist is properly configured
- Make sure all Firebase packages are installed
- Try cleaning the build (Product > Clean Build Folder)

### Data isn't syncing between phones
- Both phones need internet connection
- Check Firebase Console to see if data is being written
- Make sure Firestore rules are set to allow access

## Need Help?

If you get stuck:
1. Check the README.md for more detailed information
2. Google the error message - Stack Overflow is your friend!
3. Check Firebase Console logs
4. Make sure all steps were followed exactly

## Customization Ideas

Once everything is working:
- Change the color theme in `ContentView.swift`
- Update the app icon
- Add more features!
- Make it even cuter with custom messages and emojis

Have fun with your app! 💜
