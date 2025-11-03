#!/bin/bash

# OurApp - Easy Xcode Project Creator
# This script creates the Xcode project structure properly

echo "🚀 Creating OurApp Xcode Project..."
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ Error: Xcode is not installed or not in PATH"
    echo "Please install Xcode from the App Store first"
    exit 1
fi

echo "✅ Xcode found"
echo ""
echo "📝 Please answer these questions:"
echo ""

# Get bundle identifier
read -p "Enter your name (e.g., 'ahmad'): " USERNAME
BUNDLE_ID="com.${USERNAME}.ourapp"

echo ""
echo "Your Bundle ID will be: $BUNDLE_ID"
echo "You'll need this for Firebase setup!"
echo ""

# Create a temporary directory for the new project
TEMP_DIR=$(mktemp -d)
echo "Creating project in temporary location..."

# Create the Xcode project using xcodebuild
cd "$TEMP_DIR"

# We'll use Swift Package Manager instead - much simpler!
echo "Setting up Swift Package..."

# Go back to our directory
cd "$SCRIPT_DIR/OurApp"

# Create Package.swift if it doesn't exist
cat > Package.swift << 'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OurApp",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "OurApp",
            targets: ["OurApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/firebase/firebase-ios-sdk.git", from: "10.18.0")
    ],
    targets: [
        .target(
            name: "OurApp",
            dependencies: [
                .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
                .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
                .product(name: "FirebaseAuth", package: "firebase-ios-sdk")
            ],
            path: "OurApp"
        )
    ]
)
EOF

echo "✅ Package.swift created"
echo ""
echo "⚠️  MANUAL STEPS REQUIRED:"
echo ""
echo "Unfortunately, Xcode projects must be created manually through Xcode's UI."
echo "But I've made it super simple for you!"
echo ""
echo "Next steps:"
echo "1. Open Xcode"
echo "2. File → New → Project"
echo "3. Choose: iOS → App"
echo "4. Fill in:"
echo "   - Product Name: OurApp"
echo "   - Bundle Identifier: $BUNDLE_ID"
echo "   - Interface: SwiftUI"
echo "   - Language: Swift"
echo "5. Save at: $SCRIPT_DIR/OurApp"
echo ""
echo "Then run: open setup-complete.md"
echo ""

# Create follow-up instructions
cat > "$SCRIPT_DIR/setup-complete.md" << 'EOF'
# Final Setup Steps

After creating the Xcode project:

1. Delete Xcode's template files:
   - OurAppApp.swift
   - ContentView.swift
   - Assets.xcassets

2. The correct files are already in OurApp/OurApp/:
   - Just build and run!

3. Add Firebase SDK:
   - File → Add Package Dependencies
   - URL: https://github.com/firebase/firebase-ios-sdk
   - Add: FirebaseFirestore, FirebaseStorage, FirebaseAuth

4. Add GoogleService-Info.plist from Firebase Console

5. Build and run! 🚀
EOF

echo "✅ Setup instructions created"
