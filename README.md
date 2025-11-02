# Us 💜 - Your Personal Couple's App

A beautiful iOS app designed to help couples stay connected through shared voice messages, photos, and calendar events.

## Features

### 🎤 Voice Messages
- Record sweet voice messages for each other
- Play and listen to messages anytime
- Beautiful waveform animation while recording
- Syncs across both devices in real-time

### 📸 Photo Gallery
- Share photos of your favorite moments together
- Grid layout for easy browsing
- Both partners can add photos that sync instantly
- Full-screen photo viewing with captions

### 📅 Shared Calendar
- Add dates, plans, and special events
- Mark special occasions with a 💜
- Both can add and view upcoming plans
- Never miss an important date again

## Setup Instructions

### Prerequisites
- Xcode 15.0 or later
- iOS 17.0 or later
- An Apple Developer Account
- A Firebase account (free)

### Firebase Setup

1. **Create a Firebase Project**
   - Go to [Firebase Console](https://console.firebase.google.com)
   - Click "Add Project"
   - Enter a project name (e.g., "OurApp")
   - Disable Google Analytics (optional)
   - Click "Create Project"

2. **Add iOS App to Firebase**
   - Click the iOS icon to add an iOS app
   - Bundle ID: `com.yourname.ourapp` (or customize it)
   - App nickname: "Us"
   - Click "Register App"
   - Download the `GoogleService-Info.plist` file
   - Replace the placeholder file at `OurApp/OurApp/GoogleService-Info.plist`

3. **Enable Firestore Database**
   - In Firebase Console, go to "Build" > "Firestore Database"
   - Click "Create database"
   - Start in **production mode**
   - Choose a location close to you
   - Click "Enable"

4. **Set Up Firestore Security Rules**
   - In Firestore, click the "Rules" tab
   - Replace the rules with:

   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       // Allow anyone to read and write (since it's just you two)
       // For production, you'd want to add authentication
       match /{document=**} {
         allow read, write: if true;
       }
     }
   }
   ```

   - Click "Publish"

5. **Enable Firebase Storage**
   - Go to "Build" > "Storage"
   - Click "Get started"
   - Start in **production mode**
   - Click "Done"

6. **Set Up Storage Security Rules**
   - In Storage, click the "Rules" tab
   - Replace the rules with:

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

   - Click "Publish"

### Xcode Setup

1. **Open the Project**
   ```bash
   cd OurApp
   open OurApp.xcodeproj
   ```

2. **Update Bundle Identifier**
   - Select the project in Xcode
   - Under "Signing & Capabilities"
   - Change the Bundle Identifier if needed
   - Make sure it matches what you registered in Firebase

3. **Add Firebase Dependencies**
   - In Xcode, go to File > Add Package Dependencies
   - Enter: `https://github.com/firebase/firebase-ios-sdk`
   - Select version 10.18.0 or later
   - Add these packages:
     - FirebaseFirestore
     - FirebaseStorage
     - FirebaseAuth

4. **Configure Signing**
   - Select your team under "Signing & Capabilities"
   - Enable "Automatically manage signing"

5. **Build and Run**
   - Select your device or simulator
   - Click the Play button or press ⌘R
   - Grant microphone and photo permissions when prompted

## Customization

### Change the Color Theme
The app is currently themed in light purple. To change the accent color:

1. Open `ContentView.swift`
2. Find the line: `.accentColor(Color(red: 0.8, green: 0.7, blue: 1.0))`
3. Adjust the RGB values (0.0 to 1.0 range)

### Change the App Name
1. Open `Info.plist`
2. Change the `CFBundleDisplayName` value
3. Or edit in Xcode under the project settings

### Customize User Names
Currently, items show "You" as the creator. To show actual names:

1. Add a simple user selection on first launch
2. Store the user's name in UserDefaults
3. Pass it to the Firebase upload functions

## Adding Authentication (Optional but Recommended)

For better security, you should add Firebase Authentication:

1. Enable Authentication in Firebase Console
2. Add anonymous authentication or email/password
3. Update Firestore and Storage rules to:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

4. Add authentication code to `OurAppApp.swift`

## Usage Tips

### For You (Recording Voice Messages)
1. Tap the Voice Notes tab
2. Tap the + button
3. Record your message
4. Give it a cute title
5. Tap Save

### For Her (Listening to Messages)
1. Open the Voice Notes tab
2. Tap play on any message
3. Listen to your sweet words! 💜

### Adding Photos
1. Tap the Our Photos tab
2. Tap the + button
3. Select a photo from your library
4. It instantly syncs to both phones!

### Planning Dates
1. Tap the Our Plans tab
2. Tap the + button
3. Add date details
4. Toggle "Special Event" for important dates
5. Both of you will see it!

## Troubleshooting

### Firebase Connection Issues
- Make sure `GoogleService-Info.plist` is properly added to your project
- Check that Firestore and Storage are enabled in Firebase Console
- Verify your Firebase rules allow access

### Microphone Not Working
- Go to Settings > Privacy > Microphone
- Make sure the app has permission

### Photos Not Uploading
- Check your internet connection
- Verify Storage rules in Firebase Console
- Check photo format (JPG, PNG should work)

### App Won't Build
- Make sure all Firebase packages are properly installed
- Clean build folder (Shift+Cmd+K)
- Update to latest Firebase SDK version

## Architecture

- **SwiftUI** for the user interface
- **Firebase Firestore** for real-time data sync
- **Firebase Storage** for media files (photos & audio)
- **AVFoundation** for audio recording and playback
- **PhotosUI** for photo selection

## Privacy & Security

⚠️ **Important**: The default setup allows open read/write access to your Firebase database. This is fine for a private app just for you two, but:

- Don't share your Firebase credentials
- Don't share the app with others
- Consider adding authentication for better security
- Keep your `GoogleService-Info.plist` private

## Future Enhancements

Ideas to make it even better:
- Push notifications for new messages/photos
- In-app messaging/chat
- Location sharing for dates
- Countdown timers for special events
- Dark mode support
- Customizable themes
- Video messages
- Shared to-do lists

## License

This is a personal project created with love 💜

Enjoy your special app together!
