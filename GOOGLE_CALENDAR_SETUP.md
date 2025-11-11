# Google Calendar Integration Setup Guide

This guide will help you complete the Google Calendar integration for your Our App.

## Overview

The foundation for Google Calendar sync has been implemented, but requires external setup and SDK installation to function. Follow these steps to complete the integration.

## What's Been Implemented

✅ **Settings View** - New tab with Google Calendar integration UI
✅ **Google Calendar Manager** - Architecture for OAuth and sync operations
✅ **Updated Calendar Model** - Support for tracking synced events
✅ **Sync UI** - Interface to enable/manage synchronization

## What You Need to Complete

### Step 1: Add Google Sign-In SDK

1. Open your project in Xcode
2. Go to **File → Add Package Dependencies**
3. Add the following package:
   ```
   https://github.com/google/GoogleSignIn-iOS
   ```
4. Select version: **7.0.0 or later**
5. Add to target: **OurApp**

**Note:** This implementation uses URLSession for direct REST API calls to Google Calendar, so you don't need the GoogleAPIClientForREST library.

### Step 2: Set Up Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com)

2. **Create or Select Project:**
   - Click "Select a project" → "New Project"
   - Name it (e.g., "Our App")
   - Click "Create"

3. **Enable APIs:**
   - Go to "APIs & Services" → "Library"
   - Search for and enable:
     - **Google Calendar API**
     - **Google Sign-In API**

4. **Create OAuth 2.0 Credentials:**
   - Go to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "OAuth client ID"
   - Application type: **iOS**
   - Name: "Our App iOS"
   - Bundle ID: Enter your app's bundle identifier (found in Xcode → Target → General → Bundle Identifier)
   - Click "Create"

5. **Copy Your Client ID:**
   - Copy your **Client ID** (format: `XXXXXXXXXX-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com`)
   - You'll need this for Step 3 and Step 4

### Step 3: Configure Xcode Project

1. **Add URL Scheme:**
   - Open `Info.plist`
   - Add new row: **URL types** (Array)
   - Inside that, add Item 0 (Dictionary)
   - Add key: **URL Schemes** (Array)
   - Add Item 0 (String): Your reversed client ID
     ```
     Example: com.googleusercontent.apps.XXXXXXXXXX-XXXXXXXXXXX
     ```

   Or add this XML to Info.plist:
   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array>
         <string>com.googleusercontent.apps.YOUR-CLIENT-ID-HERE</string>
       </array>
     </dict>
   </array>
   ```

### Step 4: Add Your Client ID to the Code

1. Open `GoogleCalendarManager.swift`
2. Find the `signIn()` method (around line 92)
3. Replace `"YOUR_CLIENT_ID"` with your actual Client ID:
   ```swift
   let clientID = "XXXXXXXXXX-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com"
   ```

### Step 5: Verify App Delegate Integration

The app delegate has already been updated for you. You can verify:

1. Open `OurAppApp.swift`
2. Confirm it has the Google Sign-In import and URL handler:
   ```swift
   import SwiftUI
   import FirebaseCore
   import GoogleSignIn

   @main
   struct OurAppApp: App {
       // ... initialization code ...

       var body: some Scene {
           WindowGroup {
               ContentView()
                   .onOpenURL { url in
                       GIDSignIn.sharedInstance.handle(url)
                   }
           }
       }
   }
   ```

### Step 6: Test the Integration

## Testing the Integration

1. Build and run the app
2. Go to **Settings** tab (new gear icon)
3. Tap "Connect Google Calendar"
4. Sign in with Google account
5. Grant calendar permissions
6. Try "Sync Now" to test synchronization

## Features

### Automatic Sync
- Toggle "Auto-sync" to enable automatic background synchronization
- Syncs whenever you add/edit/delete events

### Sync Options
- **Sync Upcoming Events** - Sync future events to Google Calendar
- **Sync Past Events** - Include past events (memories) in sync

### Manual Sync
- Tap "Sync Now" to immediately synchronize
- Shows last sync timestamp

## Architecture

### Data Flow
```
Local Firebase ←→ GoogleCalendarManager ←→ Google Calendar API
```

### Event Tracking
- `googleCalendarId` - Stores Google Calendar event ID
- `lastSyncedAt` - Tracks last sync time
- Enables bidirectional sync and conflict resolution

## Troubleshooting

### "Failed to connect" Error
- Verify OAuth credentials are correct
- Check URL scheme matches reversed client ID
- Ensure GoogleService-Info.plist is in project

### Events Not Syncing
- Verify Calendar API is enabled in Google Cloud
- Check internet connection
- Try signing out and back in

### Build Errors
- Ensure Google packages are properly added via SPM
- Clean build folder (Cmd+Shift+K)
- Delete derived data

## Security Notes

- OAuth tokens are securely stored by Google Sign-In SDK
- Never commit `GoogleService-Info.plist` with real credentials to public repos
- Use environment-specific configurations for production

## Next Steps

After completing setup:
1. Test sign-in flow
2. Test event sync (create, update, delete)
3. Verify bidirectional sync works
4. Test conflict resolution
5. Add error handling for edge cases

## Resources

- [Google Sign-In iOS Documentation](https://developers.google.com/identity/sign-in/ios)
- [Google Calendar API Documentation](https://developers.google.com/calendar/api/guides/overview)
- [OAuth 2.0 for Mobile Apps](https://developers.google.com/identity/protocols/oauth2/native-app)

## Need Help?

If you encounter issues:
1. Check Google Cloud Console for API errors
2. Review Xcode console logs
3. Verify all setup steps completed
4. Check Google Calendar API quotas

---

**Note:** This is a complex integration that requires careful setup. Take your time with each step and test thoroughly before deploying to users.
